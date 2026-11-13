--[[
=============================================================================
FlyingSwordView.lua - 环绕飞剑表现层（美术资产驱动）
=============================================================================
Module:     Game/Battle/View/FlyingSwordView

Description:
	把「环绕玩家旋转的飞剑」画出来。由 WeaponSystem 每帧驱动
	（见 WeaponSystem:_updateFlyingSword），伤害结算仍在 WeaponSystem:_attackOrbit，
	本模块只负责表现，两者解耦。

	视觉资产（美术做，代码不拼几何）：
		VFX/FlyingSword/FlyingSword.prefab
		- 剑模型：KayKit Adventurers Pack 的 sword_1handed.fbx（CC0，见同目录
		  SOURCE.txt），缩放 0.4 / 剑尖朝 +Z / knight 渐变贴图 + 青色自发光
		- 剑光：TrailRenderer（Legacy Shaders/Particles/Additive + 工程内
		  t_trail01 贴图）—— 随剑移动自动拖尾，无需代码逐帧铺点
		prefab 缺失时静默不显示（与 VFXManager 的静默跳过同策略），不影响战斗。

	生命周期：
		无自建 tick —— 由 WeaponSystem:Update 每帧调用 Update()。
		count 归零（武器被移除 / 战斗结束）→ 自动 Hide 并销毁。
		WeaponSystem:Destroy 也会显式调 Hide()，覆盖「战斗结束后不再有
		每帧 Update」的情况，避免剑体残留在场景里。
=============================================================================
]]

local UnityEngine = CS.UnityEngine
local BattleLayers = require "Game.Battle.BattleLayers"

local FlyingSwordView = {}

-- =============================================================================
-- 可调参数
-- =============================================================================

local ORBIT_SPEED  = 2.2                      -- 环绕角速度（弧度/秒）
local SWORD_HEIGHT = BattleLayers.Projectile  -- 与子弹同层（0.6）
local MIN_RADIUS   = 0.8                      -- 环绕半径下限，避免贴脸转
local PREFAB_PATH  = "VFX/FlyingSword/FlyingSword"

-- =============================================================================
-- 内部状态
-- =============================================================================

---@type UnityEngine.GameObject|nil 飞剑预制体（懒加载缓存）
local _prefab = nil
---@type UnityEngine.GameObject[] 已实例化的飞剑
local _swords = {}
local _angle = 0

-- =============================================================================
-- 资源加载 / 构建 / 销毁
-- =============================================================================

---加载飞剑预制体（懒加载 + 缓存；失败静默返回 nil）
---@return UnityEngine.GameObject|nil
local function loadPrefab()
	if _prefab ~= nil then return _prefab end
	local ok, go = pcall(function()
		return UnityEngine.Resources.Load(PREFAB_PATH)
	end)
	if ok and go then
		_prefab = go
		return _prefab
	end
	return nil
end

---实例化一把飞剑
---@return UnityEngine.GameObject|nil
local function makeSword()
	local prefab = loadPrefab()
	if not prefab then return nil end
	local go = nil
	local ok = pcall(function()
		go = UnityEngine.Object.Instantiate(prefab)
	end)
	if not ok or not go then return nil end
	go.name = "FlyingSword"
	return go
end

---收起并销毁全部飞剑（幂等）
function FlyingSwordView.Hide()
	for i = 1, #_swords do
		local go = _swords[i]
		if go then
			pcall(function() UnityEngine.Object.Destroy(go) end)
		end
	end
	_swords = {}
	_angle = 0
end

-- =============================================================================
-- 每帧驱动
-- =============================================================================

---@param dt number 帧间隔（秒）
---@param cx number 环绕中心（玩家逻辑 X）
---@param cy number 环绕中心（玩家逻辑 Y）
---@param count number 飞剑数量；<= 0 表示应收起
---@param radius number|nil 环绕半径
function FlyingSwordView.Update(dt, cx, cy, count, radius)
	count = math.max(0, math.floor(count or 0))
	if count <= 0 then
		FlyingSwordView.Hide()
		return
	end

	radius = math.max(MIN_RADIUS, radius or 1.6)

	-- 剑数变化：补齐（prefab 缺失时放弃本次补齐，下帧再试）
	while #_swords < count do
		local go = makeSword()
		if not go then break end
		_swords[#_swords + 1] = go
	end
	-- 剑数变化：裁掉多余的
	while #_swords > count do
		local go = table.remove(_swords)
		if go then pcall(function() UnityEngine.Object.Destroy(go) end) end
	end
	if #_swords == 0 then return end

	_angle = (_angle + ORBIT_SPEED * (dt or 0)) % (math.pi * 2)

	local step = math.pi * 2 / #_swords
	for i = 1, #_swords do
		local a = _angle + (i - 1) * step
		local wx = (cx or 0) + math.cos(a) * radius
		local wy = (cy or 0) + math.sin(a) * radius
		local pos = UnityEngine.Vector3(wx, SWORD_HEIGHT, wy)

		-- 剑尖朝切线方向（绕圈飞行的观感）。逻辑平面上位置对角度求导即切线：
		--   d/da (cos a, sin a) = (-sin a, cos a)
		-- 逻辑 (x, y) 落在 Unity 的 (x, *, z) 平面，故 forward 取 (tx, 0, ty)。
		local tx, ty = -math.sin(a), math.cos(a)

		pcall(function()
			local go = _swords[i]
			go.transform.position = pos
			go.transform.rotation = UnityEngine.Quaternion.LookRotation(
				UnityEngine.Vector3(tx, 0, ty), UnityEngine.Vector3(0, 1, 0))
		end)
	end
end

return FlyingSwordView
