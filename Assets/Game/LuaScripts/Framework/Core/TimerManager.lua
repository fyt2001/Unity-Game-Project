--[[
=============================================================================
TimerManager.lua
=============================================================================
Module:     Framework/Core/TimerManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    统一定时器管理器。提供延迟定时器和循环定时器。
    所有定时器通过 Update 驱动（依赖 Unity Time.deltaTime）。
    支持时间缩放（scale）和时间缩放无关（unscale）两种模式。

Usage:
    local TimerManager = require "Framework.Core.TimerManager"
    local tm = TimerManager.GetInstance()
    
    -- 延迟1秒执行
    local id = tm:AddDelay(1000, function() print("fired") end)
    
    -- 每2秒循环执行
    local id2 = tm:AddLoop(2000, function() print("tick") end)
    
    -- 取消
    tm:Remove(id)
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Singleton = require "Framework.Core.Singleton"

local TimerManager = Class.Define("TimerManager")
Class.Extend(TimerManager, Singleton)

local TimerState = {
    Idle = 0,
    Running = 1,
    Paused = 2,
    Dead = 3,
}

function TimerManager:Ctor()
    self._timers = {}       -- { [id] = timerData }
    self._idCounter = 0
    self._paused = false
    self._scale = 1.0
end

---每帧更新（由 UpdateManager 驱动）
---@param dt number 帧间隔（毫秒）
function TimerManager:Update(dt)
    if self._paused then return end

    local scaledDt = dt * self._scale
    local toRemove = {}

    for id, timer in pairs(self._timers) do
        if timer.state == TimerState.Running then
            timer.elapsed = timer.elapsed + scaledDt
            if timer.elapsed >= timer.interval then
                timer.elapsed = timer.elapsed - timer.interval
                if timer.callback then
                    timer.callback()
                end
                if timer.repeatCount > 0 then
                    timer.repeatCount = timer.repeatCount - 1
                    if timer.repeatCount == 0 then
                        toRemove[#toRemove + 1] = id
                    end
                elseif timer.repeatCount < 0 then
                    -- 无限循环，不处理
                else
                    -- 单次
                    toRemove[#toRemove + 1] = id
                end
            end
        end
    end

    for _, id in ipairs(toRemove) do
        self._timers[id] = nil
    end

    -- 清理标记为 Dead 的定时器（由 Remove 方法标记，不在遍历期间删表）
    for id, timer in pairs(self._timers) do
        if timer.state == TimerState.Dead then
            self._timers[id] = nil
        end
    end
end

---添加延迟定时器（执行一次）
---@param interval number 延迟时间（毫秒）
---@param callback function 回调函数
---@return number timerId
function TimerManager:AddDelay(interval, callback)
    return self:_addTimer(interval, callback, 0)
end

---添加循环定时器
---@param interval number 间隔时间（毫秒）
---@param callback function 回调函数
---@param repeatCount number|nil 重复次数，nil或-1表示无限循环
---@return number timerId
function TimerManager:AddLoop(interval, callback, repeatCount)
    return self:_addTimer(interval, callback, repeatCount or -1)
end

---内部添加定时器
function TimerManager:_addTimer(interval, callback, repeatCount)
    self._idCounter = self._idCounter + 1
    local id = self._idCounter
    self._timers[id] = {
        interval = interval,
        elapsed = 0,
        callback = callback,
        repeatCount = repeatCount,
        state = TimerState.Running,
    }
    return id
end

---移除定时器
---@param timerId number|nil
function TimerManager:Remove(timerId)
    if timerId and self._timers[timerId] then
        self._timers[timerId].state = TimerState.Dead
    end
end

---暂停所有定时器
function TimerManager:Pause()
    self._paused = true
end

---恢复所有定时器
function TimerManager:Resume()
    self._paused = false
end

---设置时间缩放
---@param scale number
function TimerManager:SetScale(scale)
    self._scale = scale or 1.0
end

---清除所有定时器
function TimerManager:ClearAll()
    self._timers = {}
end

function TimerManager:Delete()
    self:ClearAll()
end

return TimerManager