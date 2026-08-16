--[[
=============================================================================
UIResourceLoader.lua
=============================================================================
Module:     Framework/UI/Resource/UIResourceLoader
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIResourceLoader 是资源加载的外观类，封装了异步加载、实例化、释放和
    预加载操作。默认实现是适配器友好的桩代码，项目可注入 Addressables、
    YooAsset、AssetBundle 或 Resources 等提供者，无需修改 UIManager 或 UIWindow。

    特性：
        - 异步加载与可取消令牌
        - 资源引用计数
        - 资源缓存（避免重复加载）
        - 支持即时回调（缓存命中时同步回调）

Dependencies:
    - Class (类系统)

Usage:
    local loader = UIResourceLoader.New(provider)
    local token = loader:LoadAsync("UI/Bag", function(asset) ... end)
    local go = loader:Instantiate(asset)
    loader:DestroyInstance(go)
    loader:Release("UI/Bag")
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"

local UIResourceLoader = Class.Define("UIResourceLoader")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化资源加载器
---@param provider table|nil 资源提供者，需实现 LoadAsync/Release/Instantiate/Destroy
function UIResourceLoader:Ctor(provider)
    self.provider = provider
    self.refCounts = {}
    self.cache = {}
    self.nextToken = 0
end

-- =============================================================================
-- 私有方法：令牌管理
-- =============================================================================

---创建可取消的加载令牌
---@param path string 资源路径
---@return table token 加载令牌 { id, path, cancelled }
function UIResourceLoader:CreateToken(path)
    self.nextToken = self.nextToken + 1
    return {
        id = self.nextToken,
        path = path,
        cancelled = false,
    }
end

-- =============================================================================
-- 公共 API：取消加载
-- =============================================================================

---取消异步加载令牌
---取消后，回调中应检查 token.cancelled 并跳过处理
---@param token table|nil 加载令牌
function UIResourceLoader:Cancel(token)
    if token then
        token.cancelled = true
    end
end

-- =============================================================================
-- 公共 API：异步加载
-- =============================================================================

---异步加载资源
---如果缓存中存在，则同步回调（不经过异步）
---@param path string 资源路径
---@param onComplete fun(asset:any, token:table) 加载完成回调
---@param existingToken table|nil 可选的外部令牌，用于先标记状态再异步加载
---@return table token 可取消的加载令牌
function UIResourceLoader:LoadAsync(path, onComplete, existingToken)
    assert(type(path) == "string" and path ~= "", "resource path must be a non-empty string")
    assert(type(onComplete) == "function", "onComplete must be a function")

    local token = existingToken or self:CreateToken(path)

    -- 增加引用计数
    self.refCounts[path] = (self.refCounts[path] or 0) + 1

    -- 缓存命中：同步回调
    if self.cache[path] then
        onComplete(self.cache[path], token)
        return token
    end

    -- 使用 Provider 异步加载
    if self.provider and self.provider.LoadAsync then
        self.provider:LoadAsync(path, function(asset)
            if token.cancelled then
                return
            end
            self.cache[path] = asset
            onComplete(asset, token)
        end)
        return token
    end

    -- 无 Provider 时使用桩实现
    local asset = {
        __mockAsset = true,
        path = path,
    }
    self.cache[path] = asset
    onComplete(asset, token)
    return token
end

-- =============================================================================
-- 公共 API：实例化与销毁
-- =============================================================================

---实例化资源为运行时 GameObject
---@param asset any 已加载的资源
---@return any gameObject 运行时对象或提供者返回结果
function UIResourceLoader:Instantiate(asset)
    if self.provider and self.provider.Instantiate then
        return self.provider:Instantiate(asset)
    end
    -- 桩实现：返回兼容 Unity GameObject 接口的模拟对象
    -- transform.Find 返回 nil（模拟未找到子节点），避免调用方崩溃
    return {
        asset = asset,
        name = asset and asset.path or "MockUI",
        transform = {
            Find = function(_, _) return nil end,
        },
        SetActive = function(_, _active) end,
    }
end

---销毁运行时 GameObject
---@param gameObject any 运行时对象
function UIResourceLoader:DestroyInstance(gameObject)
    if self.provider and self.provider.DestroyInstance then
        self.provider:DestroyInstance(gameObject)
    end
end

-- =============================================================================
-- 公共 API：资源释放
-- =============================================================================

---释放资源的一个引用
---引用计数降至 0 时，从缓存中移除并调用 Provider 释放
---@param path string 资源路径
function UIResourceLoader:Release(path)
    if not path then
        return
    end
    local count = (self.refCounts[path] or 0) - 1
    if count <= 0 then
        self.refCounts[path] = nil
        if self.provider and self.provider.Release then
            self.provider:Release(path, self.cache[path])
        end
        self.cache[path] = nil
    else
        self.refCounts[path] = count
    end
end

---返回资源的引用计数
---@param path string 资源路径
---@return number count
function UIResourceLoader:GetRefCount(path)
    return self.refCounts[path] or 0
end

---返回资源是否已缓存
---@param path string 资源路径
---@return boolean cached
function UIResourceLoader:IsCached(path)
    return self.cache[path] ~= nil
end

-- =============================================================================
-- 公共 API：预加载
-- =============================================================================

---预加载资源（不创建窗口实例）
---@param path string 资源路径
---@param onComplete fun(asset:any)|nil 加载完成回调
---@return table token 可取消的加载令牌
function UIResourceLoader:Preload(path, onComplete)
    return self:LoadAsync(path, function(asset)
        if onComplete then
            onComplete(asset)
        end
    end)
end

-- =============================================================================
-- 公共 API：缓存管理
-- =============================================================================

---清空所有资源缓存（不释放引用计数不为 0 的资源）
function UIResourceLoader:ClearCache()
    for path, _ in pairs(self.cache) do
        if (self.refCounts[path] or 0) == 0 then
            self.cache[path] = nil
        end
    end
end

---返回缓存中资源数量
---@return number count
function UIResourceLoader:GetCacheCount()
    local count = 0
    for _ in pairs(self.cache) do
        count = count + 1
    end
    return count
end

return UIResourceLoader