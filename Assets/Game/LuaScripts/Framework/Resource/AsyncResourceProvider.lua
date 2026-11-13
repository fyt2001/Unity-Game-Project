--[[
=============================================================================
AsyncResourceProvider.lua - 异步资源加载 + 实例池 + 生命周期
=============================================================================
Module:     Framework/Resource/AsyncResourceProvider

Description:
	资源加载的统一入口：异步加载 → 实例池复用 → 空闲自动卸载。
	设计对齐旧项目 Framework/Resource/GameObjectPool（AssetBundle 版），
	这里底层换成 Resources.LoadAsync，并保留其三层结构：

		资源层  _cache[path]        prefab 缓存（异步加载后缓存）
		实例层  _pools[path]        { caches = 空闲实例, usings = 在用实例 }
		生命周期 keep 计时          空闲超时自动销毁实例并清缓存

	与 UIResourceLoader 的 Provider 契约一致（LoadAsync / Release /
	Instantiate / DestroyInstance），可直接注入 UIResourceLoader。

生命周期（keep）：
	nil / >0  空闲 keep 毫秒后自动卸载（默认 DEFAULT_KEEP = 30s）
	-1        常驻：永不卸载（高频资源，如通用受击特效）
	0         用完即卸：一旦 usings 清空立刻释放

Usage:
	local p = AsyncResourceProvider.New()
	p:LoadAsync("VFX/Hit_Enemy", function(asset) ... end)
	p:TryGet("VFX/Hit_Enemy")                       -- 同步取，未就绪返回 nil
	p:Get("VFX/Hit_Enemy", function(inst) ... end)  -- 异步取（池命中则同步回调）
	p:Recycle("VFX/Hit_Enemy", inst)                -- 回收而非销毁
	p:SetKeep("VFX/Hit_Enemy", -1)                  -- 设常驻
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UpdateManager = require "Framework.Core.UpdateManager"
local TimerManager = require "Framework.Core.TimerManager"
local Logger = require "Framework.UI.Utils.Logger"

local UnityEngine = CS.UnityEngine

local AsyncResourceProvider = Class.Define("AsyncResourceProvider")

---默认空闲保留时间（毫秒）：对齐旧项目 GameObjectPool 的 DEFAULT_KEEP
local DEFAULT_KEEP = 30 * 1000
---巡检间隔（毫秒）：清理「已被外部销毁却仍在记账」的实例
local CHECK_INTERVAL = 30 * 1000

function AsyncResourceProvider:Ctor()
	self._cache = {}      -- path -> prefab asset
	self._pending = {}    -- path -> 在途加载请求
	self._list = {}       -- 轮询列表
	self._pools = {}      -- path -> { caches, usings, keep, timer }
	self._instToPath = {} -- 实例 -> path（回收校验用）
	self._tickId = nil
	self._cacheRoot = nil
	self._checkTimer = nil
end

-- =============================================================================
-- 私有：基础设施
-- =============================================================================

---隐藏的节点，用于挂载空闲实例（对齐旧项目 GameObjectCacheRoot）
function AsyncResourceProvider:_ensureCacheRoot()
	if self._cacheRoot then return self._cacheRoot end

	local ok, go = pcall(function()
		local existing = UnityEngine.GameObject.Find("AsyncCacheRoot")
		if existing then return existing end
		local root = UnityEngine.GameObject("AsyncCacheRoot")
		UnityEngine.Object.DontDestroyOnLoad(root)
		root:SetActive(false)
		return root
	end)

	if ok and go then self._cacheRoot = go.transform end
	return self._cacheRoot
end

function AsyncResourceProvider:_ensureTick()
	if self._tickId then return end
	local ok, id = pcall(function()
		return UpdateManager:GetInstance():AddUpdate(function() self:_poll() end, self)
	end)
	if ok then
		self._tickId = id
	else
		Logger.Warn("AsyncResourceProvider", "register UpdateManager failed: %s", tostring(id))
	end
end

function AsyncResourceProvider:IsAlive(obj)
	if obj == nil then return false end
	-- 已 Destroy 的 Unity Object 访问属性会抛异常，用属性探针判断
	return pcall(function() return obj.transform ~= nil end)
end

-- =============================================================================
-- 私有：在途请求轮询
-- =============================================================================

function AsyncResourceProvider:_poll()
	for i = #self._list, 1, -1 do
		local entry = self._list[i]
		local ok, done = pcall(function() return entry.req.isDone end)
		-- 读取失败也按完成处理：否则这条请求会永远卡在轮询列表里
		if not ok or done then
			table.remove(self._list, i)
			self:_finish(entry)
		end
	end

	if #self._list == 0 and self._tickId then
		pcall(function() UpdateManager:GetInstance():RemoveUpdate(self._tickId) end)
		self._tickId = nil
	end
end

function AsyncResourceProvider:_finish(entry)
	local asset = nil
	pcall(function() asset = entry.req.asset end)

	if asset ~= nil then
		self._cache[entry.path] = asset
	end
	self._pending[entry.path] = nil

	for _, item in ipairs(entry.callbacks) do
		if not (item.token and item.token.cancelled) then
			pcall(function() item.cb(asset, item.token) end)
		end
	end
end

-- =============================================================================
-- 私有：实例池
-- =============================================================================

function AsyncResourceProvider:_poolOf(path)
	local p = self._pools[path]
	if not p then
		p = { caches = {}, usings = {}, keep = nil, timer = nil }
		self._pools[path] = p
	end
	return p
end

---从空闲实例中取一个（无则新建）
function AsyncResourceProvider:_takeInstance(path, prefab)
	local pool = self:_poolOf(path)

	while #pool.caches > 0 do
		local inst = table.remove(pool.caches)
		if self:IsAlive(inst) then
			pool.usings[#pool.usings + 1] = inst
			self._instToPath[inst] = path
			return inst
		end
		-- 池中实例已被外部销毁，直接丢弃
		self._instToPath[inst] = nil
	end

	local inst = nil
	pcall(function() inst = UnityEngine.Object.Instantiate(prefab) end)
	if inst then
		pool.usings[#pool.usings + 1] = inst
		self._instToPath[inst] = path
	end
	return inst
end

---空闲检查：usings 清零后按 keep 策略安排释放
function AsyncResourceProvider:_checkIdle(path)
	local pool = self._pools[path]
	if not pool or #pool.usings > 0 then return end

	if pool.timer then return end

	local keep = pool.keep
	if keep == nil then keep = DEFAULT_KEEP end

	-- 常驻：永不释放
	if keep < 0 then return end

	if keep == 0 then
		self:_releasePool(path)
		return
	end

	local ok = pcall(function()
		pool.timer = TimerManager:GetInstance():AddDelay(keep, function()
			pool.timer = nil
			self:_releasePool(path)
		end)
	end)
	if not ok then pool.timer = nil end
end

---销毁空闲实例并清掉 prefab 缓存（不主动 UnloadAsset，避免误伤共享资源）
function AsyncResourceProvider:_releasePool(path)
	local pool = self._pools[path]
	if not pool then return end

	for _, inst in ipairs(pool.caches) do
		if self:IsAlive(inst) then
			pcall(function() UnityEngine.Object.Destroy(inst) end)
		end
		self._instToPath[inst] = nil
	end

	-- 仍有在用实例（例如巡检期间被取走）→ 只清空闲队列，保留池
	if #pool.usings > 0 then
		pool.caches = {}
		return
	end

	self._pools[path] = nil
	self._cache[path] = nil
end

---定期巡检：剔除已被外部销毁的实例并触发空闲检查
function AsyncResourceProvider:_startCheckTimer()
	if self._checkTimer then return end
	local ok, id = pcall(function()
		return TimerManager:GetInstance():AddLoop(CHECK_INTERVAL, function()
			self:_checkInvalidUsings()
		end)
	end)
	if ok then self._checkTimer = id end
end

function AsyncResourceProvider:_checkInvalidUsings()
	for path, pool in pairs(self._pools) do
		for i = #pool.usings, 1, -1 do
			local inst = pool.usings[i]
			if not self:IsAlive(inst) then
				self._instToPath[inst] = nil
				table.remove(pool.usings, i)
			end
		end
		self:_checkIdle(path)
	end
end

-- =============================================================================
-- 公共 API：资源加载
-- =============================================================================

---异步加载资源（缓存命中时同步回调）
---@param path string Resources 下路径
---@param onComplete fun(asset:any, token:table|nil)|nil 完成回调，asset 可能为 nil
---@param token table|nil 可取消令牌
---@return table|nil token 原样返回
function AsyncResourceProvider:LoadAsync(path, onComplete, token)
	if type(path) ~= "string" or path == "" then
		Logger.Warn("AsyncResourceProvider", "invalid path: %s", tostring(path))
		return token
	end
	onComplete = onComplete or function() end
	self:_startCheckTimer()

	if self._cache[path] then
		onComplete(self._cache[path], token)
		return token
	end

	-- 在途：合并回调，不重复发起
	local entry = self._pending[path]
	if entry then
		entry.callbacks[#entry.callbacks + 1] = { cb = onComplete, token = token }
		return token
	end

	local req = nil
	local ok, err = pcall(function() req = UnityEngine.Resources.LoadAsync(path) end)
	if not ok or req == nil then
		Logger.Warn("AsyncResourceProvider", "LoadAsync failed: %s (%s)", path, tostring(err))
		onComplete(nil, token)
		return token
	end

	entry = {
		path = path,
		req = req,
		callbacks = { { cb = onComplete, token = token } },
	}
	self._pending[path] = entry
	self._list[#self._list + 1] = entry
	self:_ensureTick()

	return token
end

---批量预加载
---@param paths string[] 路径数组
---@param onAll fun()|nil 全部完成回调
function AsyncResourceProvider:Preload(paths, onAll)
	local remain = 0
	for _, p in ipairs(paths or {}) do
		if type(p) == "string" and p ~= "" and not self._cache[p] then
			remain = remain + 1
		end
	end

	if remain == 0 then
		if onAll then onAll() end
		return
	end

	for _, p in ipairs(paths) do
		if type(p) == "string" and p ~= "" and not self._cache[p] then
			self:LoadAsync(p, function()
				remain = remain - 1
				if remain <= 0 and onAll then onAll() end
			end)
		end
	end
end

---是否已完成加载并缓存
function AsyncResourceProvider:IsLoaded(path)
	return self._cache[path] ~= nil
end

---取已缓存的 prefab（不触发加载）
function AsyncResourceProvider:GetAsset(path)
	return self._cache[path]
end

-- =============================================================================
-- 公共 API：实例获取 / 回收（对齐 GameObjectPool）
-- =============================================================================

---同步取一个实例；资源未就绪返回 nil（调用方应自行触发加载或跳过）
---@return any|nil inst
function AsyncResourceProvider:TryGet(path)
	local prefab = self._cache[path]
	if not prefab then return nil end
	return self:_takeInstance(path, prefab)
end

---异步取一个实例：资源/池命中则同步回调，否则先加载
---@param path string
---@param onGet fun(inst:any)
function AsyncResourceProvider:Get(path, onGet)
	local inst = self:TryGet(path)
	if inst then
		if onGet then onGet(inst) end
		return
	end

	self:LoadAsync(path, function(asset)
		if asset == nil then
			if onGet then onGet(nil) end
			return
		end
		if onGet then onGet(self:_takeInstance(path, asset)) end
	end)
end

---回收实例（停用后放回空闲队列，而不是销毁）
---@return boolean ok 是否成功回收
function AsyncResourceProvider:Recycle(path, inst)
	if not self:IsAlive(inst) then return false end

	local realPath = path or self._instToPath[inst]
	if not realPath then return false end

	local pool = self._pools[realPath]
	if not pool then return false end

	for i = #pool.usings, 1, -1 do
		if pool.usings[i] == inst then
			table.remove(pool.usings, i)
			break
		end
	end

	pcall(function()
		inst:SetActive(false)
		local root = self:_ensureCacheRoot()
		if root then inst.transform:SetParent(root, false) end
	end)

	pool.caches[#pool.caches + 1] = inst
	self:_checkIdle(realPath)
	return true
end

---设置某路径的保留策略（nil=默认 / -1=常驻 / 0=用完即卸 / >0=毫秒）
function AsyncResourceProvider:SetKeep(path, keep)
	local pool = self:_poolOf(path)
	pool.keep = keep
	if keep == 0 then self:_checkIdle(path) end
end

---释放某个路径：销毁实例 + 清缓存
function AsyncResourceProvider:Unload(path)
	self:_releasePool(path)
end

---清理全部（切场景 / 战斗结束时调用）
function AsyncResourceProvider:Cleanup()
	for path in pairs(self._pools) do
		self:_releasePool(path)
	end
	self._pools = {}
	self._cache = {}
	self._instToPath = {}
end

-- =============================================================================
-- 公共 API：Provider 契约（供 UIResourceLoader 使用）
-- =============================================================================

function AsyncResourceProvider:Instantiate(asset)
	if not asset then return nil end
	return UnityEngine.Object.Instantiate(asset)
end

function AsyncResourceProvider:DestroyInstance(gameObject)
	if not gameObject then return end
	UnityEngine.Object.Destroy(gameObject)
end

---释放单个资源的缓存记录
function AsyncResourceProvider:Release(path)
	self._cache[path] = nil
end

function AsyncResourceProvider:ClearCache()
	self._cache = {}
end

return AsyncResourceProvider
