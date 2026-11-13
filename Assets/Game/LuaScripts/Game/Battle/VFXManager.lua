--[[
=============================================================================
VFXManager.lua - 特效实例化助手
=============================================================================
Module:     Game/Battle/VFXManager

Description:
	极轻量的特效生成器：从 Resources 加载预制体并在世界坐标生成。

	坐标约定（与 BulletView/EnemyView 一致）：
		逻辑坐标 (x, y) → Unity 世界坐标 Vector3(x, height, y)
		子弹/飞行层 height ≈ 0.6，地面命中 height ≈ 0.5

	设计要点：
		- 全部 pcall 包裹：预制体不存在 / 路径为空时【静默跳过】，
		  不会因缺少美术资源而中断战斗逻辑（美术接入前也不会报错）。
		- 不强制 lifetime：由预制体自身的 ParticleSystem.StopAction 决定销毁；
		  若需在固定时长后强制销毁，传 lifetime（秒）即可。
=============================================================================
]]

local UnityEngine = CS.UnityEngine
local UpdateManager = require "Framework.Core.UpdateManager"
local BattleLayers = require "Game.Battle.BattleLayers"
local Logger = require "Framework.UI.Utils.Logger"
local AsyncResourceProvider = require "Framework.Resource.AsyncResourceProvider"
local VFXConfig = require "Game.Battle.VFXConfig"

local VFXManager = {}

---默认生成高度（统一分层常量，勿在此硬编码具体数值）
VFXManager.DefaultHeight = BattleLayers.Projectile

---prefab 缓存与实例池统一由 AsyncResourceProvider 管理，此处不另建缓存
---已确认缺失的路径：直接跳过，不做二次加载尝试
local missingSet = {}

---单个 path 每帧最多生成的数量（超出则丢弃，见 Spawn 同帧节流）
VFXManager.MaxPerFrame = 4
---同帧内判定为「重复命中」的距离平方（0.35 单位）
VFXManager.DedupeRadiusSq = 0.1225

local throttleFrame = -1
local throttleCount = {}
local throttlePoints = {}

---同帧节流：一次群体攻击可能同帧命中几十个目标，全部生成既拖帧率也糊成一片。
-- 策略：① 每个 path 每帧有数量上限 ② 落点与已生成点过近则视为重复，跳过。
---@return boolean true=允许生成
local function passThrottle(path, x, y)
	local frame = CS.UnityEngine.Time.frameCount
	if frame ~= throttleFrame then
		throttleFrame = frame
		throttleCount = {}
		throttlePoints = {}
	end

	local n = throttleCount[path] or 0
	if n >= VFXManager.MaxPerFrame then return false end

	local cx, cy = x or 0, y or 0
	local pts = throttlePoints[path]
	if pts then
		for i = 1, #pts do
			local dx = pts[i].x - cx
			local dy = pts[i].y - cy
			if dx * dx + dy * dy <= VFXManager.DedupeRadiusSq then
				return false
			end
		end
	end

	throttleCount[path] = n + 1
	pts = pts or {}
	pts[#pts + 1] = { x = cx, y = cy }
	throttlePoints[path] = pts
	return true
end

---加载并缓存预制体；不存在或出错返回 nil（并记入黑名单）
---@param path string
---@return UnityEngine.Object|nil
local function loadPrefab(path)
	if missingSet[path] then return false end

	local provider = VFXManager._provider()
	-- 已就绪（热路径，预热后应当 100% 命中）
	if provider:IsLoaded(path) then return true end

	-- 未就绪：交给异步 Provider 加载，本次【不阻塞、不生成】。
	-- 命中瞬间同步 Resources.Load 会卡帧（大特效尤其明显），所以宁可丢这一次
	-- 表现；配合 VFXManager.Preload 预热即可完全避免丢失。
	provider:LoadAsync(path, function(asset)
		if asset == nil and not missingSet[path] then
			Logger.Warn("VFXManager", "prefab missing: %s", tostring(path))
			missingSet[path] = true
		end
	end)
	return false
end

---取异步资源提供者（懒创建）
function VFXManager._provider()
	if not VFXManager._providerInstance then
		VFXManager._providerInstance = AsyncResourceProvider.New()
	end
	return VFXManager._providerInstance
end

---预热特效资源：战斗开始前调用，避免首次命中时来不及加载而丢失表现
---@param paths string[] 路径数组（可用 VFXConfig.AllPaths()）
---@param onComplete fun()|nil 全部完成回调
function VFXManager.Preload(paths, onComplete)
	local provider = VFXManager._provider()

	-- 通用特效（受击 / 死亡 / 脚步尘…）全程高频使用：标为常驻，
	-- 否则一次战斗的空档就可能被空闲策略卸载，下次命中又要重新加载。
	for _, v in pairs(VFXConfig.Common) do
		if type(v) == "string" and v ~= "" then
			provider:SetKeep(v, -1)
		end
	end

	local list = {}
	for _, p in ipairs(paths or {}) do
		if type(p) == "string" and p ~= "" and not provider:IsLoaded(p) and not missingSet[p] then
			list[#list + 1] = p
		end
	end

	if #list == 0 then
		if onComplete then onComplete() end
		return
	end

	provider:Preload(list, onComplete)
end

---未指定 lifetime 时的默认存活秒数（统一纳入回收，便于池化）
VFXManager.DefaultLifetime = 1.0
---活跃实例列表 { obj, path, expiry }，到期后回收到 Provider 的实例池
local activeList = {}

---Unity Object 是否仍有效
-- 已 Destroy 的对象在 Lua 侧仍是 userdata（非 nil），访问其属性会抛异常，
-- 因此用「属性探针」判断：能读到 transform 说明还活着。
local function isAlive(obj)
	if obj == nil then return false end
	return pcall(function() return obj.transform ~= nil end)
end

---清扫已到期 / 已被外部销毁的实例。
-- 不依赖 Update 驱动：每次 Spawn 顺带清扫，活跃列表通常只有几十项，开销可忽略。
-- 回收交给 Provider 的实例池统一管（空闲超时会自动释放，见 SetKeep）。
local function sweepExpired(now)
	local provider = VFXManager._provider()
	for i = #activeList, 1, -1 do
		local e = activeList[i]
		if not isAlive(e.obj) then
			table.remove(activeList, i)
		elseif now >= e.expiry then
			provider:Recycle(e.path, e.obj)
			table.remove(activeList, i)
		end
	end
end

---在逻辑坐标 (x, y) 处生成特效预制体
---@param path string Resources 下路径（不含扩展名），如 "VFX/Fireball_Explosion"
---@param x number 逻辑 X
---@param y number 逻辑 Y
---@param z number|nil 世界高度，缺省 DefaultHeight
---@param lifetime number|nil 存活秒数；nil 取 DefaultLifetime，<=0 表示不自动回收
---@return UnityEngine.Object|nil 生成的 GameObject
function VFXManager.Spawn(path, x, y, z, lifetime, scale)
	if not path or path == "" then return nil end
	VFXManager._ensureTicker()
	z = z or VFXManager.DefaultHeight

	sweepExpired(UnityEngine.Time.time)
	if not passThrottle(path, x, y) then return nil end

	-- 资源未就绪 → 本次跳过（异步加载中，见 loadPrefab）
	if not loadPrefab(path) then return nil end

	if lifetime == nil then lifetime = VFXManager.DefaultLifetime end

	-- 实例取自 Provider 的实例池（命中则复用，不再新建）
	local provider = VFXManager._provider()
	local ok, obj = pcall(function()
		local inst = provider:TryGet(path)
		if inst then
			inst:SetActive(false)
			-- 复用实例可能还挂在隐藏的 CacheRoot 下，先摘出来再用世界坐标定位
			inst.transform:SetParent(nil)
			inst.transform.position = UnityEngine.Vector3(x or 0, z, y or 0)
			inst.transform.localScale = UnityEngine.Vector3.one * (scale or 1)
			local particles = inst:GetComponentsInChildren(typeof(UnityEngine.ParticleSystem), true)
			for i = 0, particles.Length - 1 do
				particles[i]:Stop(false, UnityEngine.ParticleSystemStopBehavior.StopEmittingAndClear)
			end
			local trails = inst:GetComponentsInChildren(typeof(UnityEngine.TrailRenderer), true)
			for i = 0, trails.Length - 1 do trails[i]:Clear() end
			inst:SetActive(true)
			for i = 0, particles.Length - 1 do particles[i]:Play(false) end
		end
		return inst
	end)

	if not ok or obj == nil then return nil end

	-- lifetime <= 0：常驻实例不自动回收（由调用方自行销毁）
	if lifetime > 0 then
		activeList[#activeList + 1] = {
			obj = obj,
			path = path,
			expiry = UnityEngine.Time.time + lifetime,
		}
	end
	return obj
end

---彻底释放：活跃实例与池中实例全部真销毁。
-- 切场景 / 战斗重启时调用，避免池持有跨场景的失效对象。
function VFXManager.ReleaseAll()
	for _, e in ipairs(activeList) do
		if isAlive(e.obj) then
			pcall(function() UnityEngine.Object.Destroy(e.obj) end)
		end
	end
	activeList = {}

	-- 实例池已交给 Provider 统一管，这里走它的 Cleanup
	if VFXManager._providerInstance then
		VFXManager._providerInstance:Cleanup()
	end
end

---手动推进回收（回收到期/失效的实例）
function VFXManager.Update()
	sweepExpired(UnityEngine.Time.time)
end

---注册全局逐帧清扫（首次 Spawn 时懒注册）
-- 与视图基类同理：清扫不该只在「有人生成新特效」时才发生。
-- 战斗结束 / 结算阶段不再创建新特效，若没有这个 tick，
-- 已过期的实例既不会被回收进池也不会被销毁。
function VFXManager._ensureTicker()
	if VFXManager._tickerReady then return end

	local ok, err = pcall(function()
		UpdateManager:GetInstance():AddUpdate(function()
			VFXManager.Update()
		end, VFXManager)
		return true
	end)

	-- 注册失败 = 过期特效永不回收，必须能看见
	if not ok then
		Logger.Warn("VFXManager", "register sweep ticker failed: %s", tostring(err))
	end
	VFXManager._tickerReady = ok
end

---清空预制体缓存（调用 Resources.UnloadUnusedAssets 后必须执行，
-- 否则缓存里持有的是已失效对象）
function VFXManager.ClearCache()
	missingSet = {}
	if VFXManager._providerInstance then
		VFXManager._providerInstance:ClearCache()
	end
	VFXManager.ReleaseAll()
end

return VFXManager
