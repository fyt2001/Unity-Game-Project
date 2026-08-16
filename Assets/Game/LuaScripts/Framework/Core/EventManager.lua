--[[
=============================================================================
EventManager.lua
=============================================================================
Module:     Framework/Core/EventManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    全局事件系统，提供发布-订阅模式，用于模块间解耦通信。
    特性：
        - 基于链表的监听器管理，支持遍历中增删
        - 引用计数锁机制，防止回调中修改列表崩溃
        - 支持带 TargetName 的定向广播
        - 返回句柄用于精确移除

Usage:
    local EventManager = require "Framework.Core.EventManager"
    local em = EventManager.GetInstance()
    
    local handle = em:AddListener("OnEnemyKilled", function(enemyId)
        print("Killed:", enemyId)
    end)
    em:Broadcast("OnEnemyKilled", 1001)
    em:RemoveListener(handle)
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Singleton = require "Framework.Core.Singleton"

local EventManager = Class.Define("EventManager")
Class.Extend(EventManager, Singleton)

function EventManager:Ctor()
    self._listeners = {}    -- { [eventName] = { {callback, target, handle}, ... } }
    self._handleCounter = 0
    self._lockCount = 0     -- 引用计数锁
    self._pendingOps = {}   -- 锁期间暂存的操作
end

---添加事件监听
---@param eventName string 事件名
---@param callback function 回调函数
---@param target any|nil 可选的目标对象（用于批量移除）
---@return number handle 监听器句柄
function EventManager:AddListener(eventName, callback, target)
    if not eventName or not callback then
        return 0
    end
    if not self._listeners[eventName] then
        self._listeners[eventName] = {}
    end

    self._handleCounter = self._handleCounter + 1
    local handle = self._handleCounter

    local entry = {
        callback = callback,
        target = target,
        handle = handle,
    }

    if self._lockCount > 0 then
        table.insert(self._pendingOps, { type = "add", eventName = eventName, entry = entry })
    else
        table.insert(self._listeners[eventName], entry)
    end

    return handle
end

---移除事件监听（通过句柄）
---@param handle number 监听器句柄
---@return boolean removed
function EventManager:RemoveListener(handle)
    if not handle or handle <= 0 then
        return false
    end

    if self._lockCount > 0 then
        table.insert(self._pendingOps, { type = "removeByHandle", handle = handle })
        return true
    end

    for eventName, list in pairs(self._listeners) do
        for i = #list, 1, -1 do
            if list[i].handle == handle then
                table.remove(list, i)
                if #list == 0 then
                    self._listeners[eventName] = nil
                end
                return true
            end
        end
    end
    return false
end

---移除某对象的所有监听
---@param target any 目标对象
function EventManager:RemoveListenerByTarget(target)
    if not target then return end

    if self._lockCount > 0 then
        table.insert(self._pendingOps, { type = "removeByTarget", target = target })
        return
    end

    for eventName, list in pairs(self._listeners) do
        for i = #list, 1, -1 do
            if list[i].target == target then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            self._listeners[eventName] = nil
        end
    end
end

---广播事件
---@param eventName string 事件名
---@param ... any 事件参数
function EventManager:Broadcast(eventName, ...)
    local list = self._listeners[eventName]
    if not list then return end

    self:_enterLock()
    for i = 1, #list do
        local entry = list[i]
        if entry and entry.callback then
            entry.callback(...)
        end
    end
    self:_exitLock()
end

---进入锁（防止回调中修改列表）
function EventManager:_enterLock()
    self._lockCount = self._lockCount + 1
end

---退出锁，执行暂存操作
function EventManager:_exitLock()
    self._lockCount = self._lockCount - 1
    if self._lockCount > 0 then return end

    -- 执行暂存的操作
    local ops = self._pendingOps
    self._pendingOps = {}
    for _, op in ipairs(ops) do
        if op.type == "add" then
            if not self._listeners[op.eventName] then
                self._listeners[op.eventName] = {}
            end
            table.insert(self._listeners[op.eventName], op.entry)
        elseif op.type == "removeByHandle" then
            self:RemoveListener(op.handle)
        elseif op.type == "removeByTarget" then
            self:RemoveListenerByTarget(op.target)
        end
    end
end

---清除所有监听
function EventManager:ClearAll()
    self._listeners = {}
    self._pendingOps = {}
    self._lockCount = 0
end

function EventManager:Delete()
    self:ClearAll()
end

return EventManager
