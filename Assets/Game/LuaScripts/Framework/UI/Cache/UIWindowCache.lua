--[[
=============================================================================
UIWindowCache.lua
=============================================================================
Module:     Framework/UI/Cache/UIWindowCache
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIWindowCache 按名称缓存 UIWindow 逻辑实例。
    它缓存的是逻辑窗口对象，不是原始 Prefab 资源；资源缓存由 UIResourceLoader 负责。

    缓存策略由 UIWindowConfig 中的 cachePolicy 决定：
        - DestroyOnClose: 关闭后立即销毁
        - CacheOnClose: 关闭后缓存逻辑窗口
        - NeverDestroy: 永久缓存
        - DestroyOnSceneChange: 场景切换时销毁

Dependencies:
    - Class (类系统)
    - TableUtil (表工具)

Usage:
    local cache = UIWindowCache.New()
    cache:Put(window)
    local w = cache:Get("Bag")
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local TableUtil = require "Framework.UI.Utils.TableUtil"

local UIWindowCache = Class.Define("UIWindowCache")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化缓存表
function UIWindowCache:Ctor()
    self.windows = {}
end

-- =============================================================================
-- 公共 API：缓存操作
-- =============================================================================

---存储窗口到缓存（按名称索引）
---如果同名窗口已存在则覆盖
---@param window table UIWindow 实例
function UIWindowCache:Put(window)
    assert(window ~= nil, "cannot cache nil window")
    assert(window.GetName, "window must have GetName method")
    self.windows[window:GetName()] = window
end

---获取缓存中的窗口
---@param name string 窗口名称
---@return table|nil window 缓存的窗口实例，不存在返回 nil
function UIWindowCache:Get(name)
    return self.windows[name]
end

---判断窗口是否在缓存中
---@param name string 窗口名称
---@return boolean exists
function UIWindowCache:Has(name)
    return self.windows[name] ~= nil
end

---从缓存中移除窗口（不销毁）
---@param name string 窗口名称
---@return table|nil window 被移除的窗口实例
function UIWindowCache:Remove(name)
    local window = self.windows[name]
    self.windows[name] = nil
    return window
end

---返回所有缓存窗口的数组
---@return table windows 窗口数组
function UIWindowCache:GetAll()
    local result = {}
    for _, window in pairs(self.windows) do
        result[#result + 1] = window
    end
    return result
end

---返回缓存中窗口数量
---@return number count
function UIWindowCache:Count()
    return TableUtil.Count(self.windows)
end

-- =============================================================================
-- 公共 API：批量操作
-- =============================================================================

---销毁并移除所有缓存窗口
---遍历所有缓存窗口，逐一销毁
function UIWindowCache:Clear()
    for name, window in pairs(self.windows) do
        if window and not window:IsDestroyed() then
            window:Destroy()
        end
        self.windows[name] = nil
    end
end

---按缓存策略清理窗口
---@param policy string 缓存策略名称
---@return number count 被清理的窗口数量
function UIWindowCache:ClearByPolicy(policy)
    local count = 0
    for name, window in pairs(self.windows) do
        if window:GetConfig().cachePolicy == policy then
            if not window:IsDestroyed() then
                window:Destroy()
            end
            self.windows[name] = nil
            count = count + 1
        end
    end
    return count
end

---按条件过滤窗口
---@param predicate fun(window:table):boolean 过滤函数
---@return table windows 符合条件的窗口数组
function UIWindowCache:Filter(predicate)
    local result = {}
    for _, window in pairs(self.windows) do
        if predicate(window) then
            result[#result + 1] = window
        end
    end
    return result
end

return UIWindowCache