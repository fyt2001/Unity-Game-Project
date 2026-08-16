--[[
=============================================================================
ResourcesProvider.lua - Unity Resources 资源提供者
=============================================================================
Module:     Game/UI/Provider/ResourcesProvider
Version:    1.0.0
Description:
    基于 Unity Resources API 的资源提供者，实现 UIResourceLoader 所需的
    LoadAsync / Instantiate / Destroy / Release 接口。

    设计要点：
        - 同步加载：Resources.Load 是同步的，包装为异步回调接口
        - 实例化：使用 GameObject.Instantiate 创建运行时实例
        - 销毁：使用 GameObject.Destroy 清理实例
        - 卸载：使用 Resources.UnloadAsset 卸载缓存资源

    用法：
        local provider = ResourcesProvider.New()
        local uiManager = FW.CreateUIManager({ resourceProvider = provider })
=============================================================================
]]

local Class = require "Framework.Core.Class"

local ResourcesProvider = Class.Define("ResourcesProvider")

function ResourcesProvider:Ctor()
    self._assetCache = {}  -- { [path] = asset }
end

-- =============================================================================
-- 公共 API：异步加载
-- =============================================================================

---加载资源（同步 Resources.Load，异步回调）
---@param path string 资源路径（相对于 Resources 目录）
---@param onComplete fun(asset:any, token:table) 完成回调
---@param token table|nil 可取消的加载令牌
function ResourcesProvider:LoadAsync(path, onComplete, token)
    if token and token.cancelled then
        return
    end

    -- 缓存命中
    if self._assetCache[path] then
        if onComplete then
            onComplete(self._assetCache[path], token)
        end
        return
    end

    -- 同步加载 Unity 资源
    -- CS.UnityEngine.Resources.Load 需要 XLua 生成代码
    local asset = CS.UnityEngine.Resources.Load(path)

    if asset then
        self._assetCache[path] = asset
    end

    if onComplete then
        onComplete(asset, token)
    end
end

-- =============================================================================
-- 公共 API：实例化
-- =============================================================================

---实例化资源为运行时 GameObject
---当 Prefab 不存在时，返回兼容的 mock 对象，保证系统平稳运行
---@param asset any Resources.Load 返回的 Object
---@return any gameObject 实例化的 GameObject 或 mock 对象
function ResourcesProvider:Instantiate(asset)
    if not asset then
        -- Prefab 不存在时返回 mock 对象（兼容 UIResourceLoader 桩实现）
        return {
            __mockAsset = true,
            name = "MockUI",
            transform = {
                Find = function(_, _) return nil end,
            },
            SetActive = function(_, _) end,
        }
    end

    -- 桩实现兼容：跳过 mock 对象
    if asset.__mockAsset then
        return {
            asset = asset,
            name = asset.path or "MockUI",
            transform = {
                Find = function(_, _) return nil end,
            },
            SetActive = function(_, _) end,
        }
    end

    -- 使用 Unity Object.Instantiate
    return CS.UnityEngine.Object.Instantiate(asset)
end

-- =============================================================================
-- 公共 API：销毁
-- =============================================================================

---销毁运行时 GameObject
---@param gameObject any 实例化的 GameObject
function ResourcesProvider:DestroyInstance(gameObject)
    if not gameObject then
        return
    end

    -- 跳过 mock 对象
    if gameObject.__mockAsset then
        return
    end

    CS.UnityEngine.Object.Destroy(gameObject)
end

-- =============================================================================
-- 公共 API：释放
-- =============================================================================

---释放缓存的资源
---@param path string 资源路径
---@param asset any 已缓存的资源（可选）
function ResourcesProvider:Release(path, asset)
    local cached = asset or self._assetCache[path]
    if cached then
        CS.UnityEngine.Resources.UnloadAsset(cached)
        self._assetCache[path] = nil
    end
end

---释放所有缓存
function ResourcesProvider:ReleaseAll()
    for path, asset in pairs(self._assetCache) do
        CS.UnityEngine.Resources.UnloadAsset(asset)
    end
    self._assetCache = {}
end

return ResourcesProvider