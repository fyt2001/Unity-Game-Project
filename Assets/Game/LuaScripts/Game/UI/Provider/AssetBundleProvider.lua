--[[
=============================================================================
AssetBundleProvider.lua - AssetBundle 资源提供者（UI 面板）
=============================================================================
Module:     Game/UI/Provider/AssetBundleProvider
Version:    1.0.0

Description:
	基于 AssetBundle 的 UI 资源提供者，实现 UIResourceLoader 所需的
	LoadAsync / Instantiate / DestroyInstance / Release 接口。

	与 ResourcesProvider 的区别：
		ResourcesProvider 走 UnityEngine.Resources.LoadAsync（内置资源区，
		无条件随包、不可热更）；本类走 AssetBundleManager（按需、可热更）。

	bundle 命名规则（与 H02 及本工程既有 ui/*.asset 一致，一面板一 bundle）：
		"UI/Home/ShopPanel"  ->  bundle = "ui/shoppanel.asset", asset = "ShopPanel"
	即：取路径最后一段做 asset 名，bundle 名 = "ui/" .. 名字小写 .. ".asset"。
	标签的赋予由编辑器工具完成（详见 tools/assign_ui_ab_labels.py）。

	驱动方式：
		AssetBundleManager.LoadAssetAsync 返回的 AssetBundleLoadAssetOperation
		是 IEnumerator，不能从 Lua yield；而 AssetBundleManager 只在真机
		（有实例）时由自身 Update() 推进。因此这里与 AsyncResourceProvider 一样，
		注册到 UpdateManager 按帧轮询 op.IsDone()。
		编辑器 Simulation 模式下 op.IsDone() 恒为 true，第一拍即完成。

	泛型桥：
		op.GetAsset<T>() 是泛型方法，Lua 不能直接调用，统一走 C# 侧
		UIAssetBundleHelper（见 Assets/Game/Scripts/Core/UIAssetBundleHelper.cs）。

Usage:
	local provider = AssetBundleProvider.New()
	local uiManager = FW.CreateUIManager({ resourceProvider = provider })
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UpdateManager = require "Framework.Core.UpdateManager"
local Logger = require "Framework.UI.Utils.Logger"

local AssetBundleProvider = Class.Define("AssetBundleProvider")

---bundle 目录前缀与后缀（与 H02 AssetsPackage/UI/Prefabs 的标签约定一致）
local BUNDLE_DIR = "ui/"
local BUNDLE_EXT = ".asset"

---Release 时是否顺带卸载 AssetBundle。
---默认关闭：同一 bundle 可能被多个窗口/实例共享，贸然 UnloadAssetBundle 会让
---已实例化的对象丢资源。UI 面板数量有限（十余个），常驻成本可接受。
local UNLOAD_BUNDLE_ON_RELEASE = false

---把 UI 资源路径解析成 (bundleName, assetName)
---@param path string 形如 "UI/Home/ShopPanel"
---@return string|nil bundleName
---@return string|nil assetName
local function resolveBundle(path)
	local assetName = string.match(path, "([^/]+)$")
	if not assetName or assetName == "" then
		return nil, nil
	end
	return BUNDLE_DIR .. string.lower(assetName) .. BUNDLE_EXT, assetName
end

-- =============================================================================
-- 构造函数
-- =============================================================================

function AssetBundleProvider:Ctor()
	self._cache = {}     -- path -> prefab asset
	self._pending = {}   -- path -> 在途请求
	self._list = {}      -- 轮询列表（数组）
	self._tickId = nil
end

-- =============================================================================
-- 私有：Update 轮询
-- =============================================================================

function AssetBundleProvider:_ensureTick()
	if self._tickId then return end
	local ok, id = pcall(function()
		return UpdateManager:GetInstance():AddUpdate(function() self:_poll() end, self)
	end)
	if ok then
		self._tickId = id
	else
		Logger.Warn("AssetBundleProvider", "register UpdateManager failed: %s", tostring(id))
	end
end

function AssetBundleProvider:_poll()
	for i = #self._list, 1, -1 do
		local entry = self._list[i]
		-- 读取失败也按完成处理：否则这条请求会永远卡在轮询列表里
		local ok, done = pcall(function() return CS.UIAssetBundleHelper.IsDone(entry.op) end)
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

function AssetBundleProvider:_finish(entry)
	local asset = nil
	pcall(function() asset = CS.UIAssetBundleHelper.GetPrefab(entry.op) end)

	if asset ~= nil then
		self._cache[entry.path] = asset
	else
		Logger.Warn(
			"AssetBundleProvider",
			"加载结果为空: path=%s bundle=%s asset=%s（检查 .meta 的 assetBundleName 是否已赋标签）",
			entry.path, tostring(entry.bundle), tostring(entry.assetName))
	end

	self._pending[entry.path] = nil

	for _, item in ipairs(entry.callbacks) do
		if not (item.token and item.token.cancelled) then
			pcall(function() item.cb(asset, item.token) end)
		end
	end
end

-- =============================================================================
-- 公共 API（UIResourceLoader Provider 契约）
-- =============================================================================

---异步加载资源（缓存命中则同步回调）
---@param path string 资源路径，形如 "UI/Home/ShopPanel"
---@param onComplete fun(asset:any, token:table|nil)|nil
---@param token table|nil 可取消令牌
---@return table|nil token 原样返回
function AssetBundleProvider:LoadAsync(path, onComplete, token)
	if self._disposed then return token end
	if type(path) ~= "string" or path == "" then
		Logger.Warn("AssetBundleProvider", "invalid path: %s", tostring(path))
		if onComplete then onComplete(nil, token) end
		return token
	end
	onComplete = onComplete or function() end

	-- 缓存命中：同步回调（与 ResourcesProvider 行为一致）
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

	local bundleName, assetName = resolveBundle(path)
	if not bundleName then
		Logger.Warn("AssetBundleProvider", "无法从路径解析 bundle: %s", tostring(path))
		onComplete(nil, token)
		return token
	end

	local op
	local ok, err = pcall(function()
		op = CS.UIAssetBundleHelper.LoadPrefabAsync(bundleName, assetName)
	end)
	if not ok then
		Logger.Warn("AssetBundleProvider", "LoadPrefabAsync 异常: %s (%s)", path, tostring(err))
		onComplete(nil, token)
		return token
	end
	if op == nil then
		Logger.Warn("AssetBundleProvider", "LoadPrefabAsync 返回 nil: bundle=%s asset=%s", bundleName, assetName)
		onComplete(nil, token)
		return token
	end

	entry = {
		path = path,
		bundle = bundleName,
		assetName = assetName,
		op = op,
		callbacks = { { cb = onComplete, token = token } },
	}
	self._pending[path] = entry
	self._list[#self._list + 1] = entry
	self:_ensureTick()

	return token
end

---实例化资源为运行时 GameObject
function AssetBundleProvider:Instantiate(asset)
	if not asset then
		return nil
	end
	return CS.UnityEngine.Object.Instantiate(asset)
end

---销毁运行时 GameObject
function AssetBundleProvider:DestroyInstance(gameObject)
	if not gameObject then
		return
	end
	CS.UnityEngine.Object.Destroy(gameObject)
end

---释放资源的一个引用（缓存由 UIResourceLoader 侧管理，这里只决定是否卸载 bundle）
function AssetBundleProvider:Release(path, _asset)
	local bundleName = resolveBundle(path)
	if not bundleName then
		return
	end
	if UNLOAD_BUNDLE_ON_RELEASE then
		pcall(function() CS.MyAssetBundles.AssetBundleManager.UnloadAssetBundle(bundleName) end)
	end
	self._cache[path] = nil
end

-- =============================================================================
-- 查询 / 调试
-- =============================================================================

---是否已加载并缓存
function AssetBundleProvider:IsLoaded(path)
	return self._cache[path] ~= nil
end

---取已缓存资源（未加载返回 nil）
function AssetBundleProvider:GetAsset(path)
	return self._cache[path]
end

---当前在途请求数
function AssetBundleProvider:GetPendingCount()
	return #self._list
end

---清空缓存
function AssetBundleProvider:ClearCache()
	self._cache = {}
end

function AssetBundleProvider:Dispose()
	if self._disposed then return end
	self._disposed = true
	if self._tickId then
		UpdateManager:GetInstance():RemoveUpdate(self._tickId)
		self._tickId = nil
	end
	for _, entry in ipairs(self._list) do
		for _, request in ipairs(entry.callbacks) do
			if request.token then request.token.cancelled = true end
		end
	end
	self._list, self._pending, self._cache = {}, {}, {}
end

return AssetBundleProvider
