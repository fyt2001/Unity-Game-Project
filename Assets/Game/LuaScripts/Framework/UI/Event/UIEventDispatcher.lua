--[[
=============================================================================
UIEventDispatcher.lua
=============================================================================
Module:     Framework/UI/Event/UIEventDispatcher
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIEventDispatcher 是框架的事件中枢，负责在不同层级之间传递事件。
    它提供类型安全的事件注册、分发和移除，支持窗口级事件、全局事件和
    自定义事件。

    事件类型：
        - WindowOpened: 窗口打开完成
        - WindowClosed: 窗口关闭完成
        - WindowRefreshed: 窗口刷新
        - WindowFocused: 窗口获得焦点
        - WindowBlurred: 窗口失去焦点
        - WindowDestroyed: 窗口销毁
        - SceneChanged: 场景切换

    特性：
        - 类型安全的事件注册
        - 支持多个回调
        - 支持一次性订阅
        - 防止回调中修改监听器列表导致的问题

Dependencies:
    - Class (类系统)
    - TableUtil (表工具)

Usage:
    local dispatcher = UIEventDispatcher.New()
    dispatcher:On("WindowOpened", function(window) ... end)
    dispatcher:Dispatch("WindowOpened", window)
    dispatcher:Off("WindowOpened", callback)
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local TableUtil = require "Framework.UI.Utils.TableUtil"

local UIEventDispatcher = Class.Define("UIEventDispatcher")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化事件监听器表
function UIEventDispatcher:Ctor()
    self.listeners = {}
    self.dispatching = false
    self.pendingRemoves = {}
end

-- =============================================================================
-- 私有方法：安全分发
-- =============================================================================

---标记监听器在分发完成后移除
---防止在分发过程中修改监听器列表导致的问题
---@param eventName string 事件名
---@param callback fun() 回调函数
function UIEventDispatcher:MarkForRemove(eventName, callback)
    self.pendingRemoves[#self.pendingRemoves + 1] = { eventName, callback }
end

---处理待移除的监听器
function UIEventDispatcher:ProcessPendingRemoves()
    if #self.pendingRemoves == 0 then
        return
    end
    for _, entry in ipairs(self.pendingRemoves) do
        self:RemoveListener(entry[1], entry[2])
    end
    self.pendingRemoves = {}
end

---直接移除监听器（不经过 pending 队列）
---@param eventName string 事件名
---@param callback fun() 回调函数
function UIEventDispatcher:RemoveListener(eventName, callback)
    local list = self.listeners[eventName]
    if not list then
        return
    end
    TableUtil.RemoveValue(list, callback)
    if #list == 0 then
        self.listeners[eventName] = nil
    end
end

-- =============================================================================
-- 公共 API：注册
-- =============================================================================

---注册监听器（多次触发）
---@param eventName string 事件名
---@param callback fun(...) 回调函数
function UIEventDispatcher:On(eventName, callback)
    assert(type(eventName) == "string", "eventName must be a string")
    assert(type(callback) == "function", "callback must be a function")

    if not self.listeners[eventName] then
        self.listeners[eventName] = {}
    end
    self.listeners[eventName][#self.listeners[eventName] + 1] = callback
end

---注册一次性监听器（触发后自动移除）
---@param eventName string 事件名
---@param callback fun(...) 回调函数
function UIEventDispatcher:Once(eventName, callback)
    local dispatcher = self
    local function wrapper(...)
        dispatcher:Off(eventName, wrapper)
        callback(...)
    end
    self:On(eventName, wrapper)
end

-- =============================================================================
-- 公共 API：移除
-- =============================================================================

---移除监听器
---如果在分发过程中调用，标记为待移除状态
---@param eventName string 事件名
---@param callback fun() 回调函数
function UIEventDispatcher:Off(eventName, callback)
    if self.dispatching then
        self:MarkForRemove(eventName, callback)
    else
        self:RemoveListener(eventName, callback)
    end
end

---移除指定事件的所有监听器
---@param eventName string 事件名
function UIEventDispatcher:OffAll(eventName)
    self.listeners[eventName] = nil
end

---清空所有事件的所有监听器
function UIEventDispatcher:Clear()
    self.listeners = {}
    self.pendingRemoves = {}
end

-- =============================================================================
-- 公共 API：分发
-- =============================================================================

---分发事件
---安全分发方式：遍历监听器列表的快照，防止分发过程中修改列表
---@param eventName string 事件名
---@param ... 事件参数
function UIEventDispatcher:Dispatch(eventName, ...)
    local list = self.listeners[eventName]
    if not list then
        return
    end

    self.dispatching = true

    -- 遍历快照，避免回调中修改监听器列表
    local snapshot = {}
    for _, callback in ipairs(list) do
        snapshot[#snapshot + 1] = callback
    end

    for _, callback in ipairs(snapshot) do
        local ok, err = pcall(callback, ...)
        if not ok then
            error(string.format(
                "Error dispatching event '%s': %s",
                eventName,
                tostring(err)
            ), 2)
        end
    end

    self.dispatching = false
    self:ProcessPendingRemoves()
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---返回指定事件的监听器数量
---@param eventName string 事件名
---@return number count
function UIEventDispatcher:GetListenerCount(eventName)
    local list = self.listeners[eventName]
    return list and #list or 0
end

---判断事件是否有监听器
---@param eventName string 事件名
---@return boolean hasListeners
function UIEventDispatcher:HasListeners(eventName)
    return self.listeners[eventName] ~= nil and #self.listeners[eventName] > 0
end

return UIEventDispatcher