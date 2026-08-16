--[[
=============================================================================
UpdateManager.lua
=============================================================================
Module:     Framework/Core/UpdateManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    帧更新管理器，驱动所有需要每帧更新的模块（Timer、Battle等）。
    提供 Update / LateUpdate / FixedUpdate 三种更新回调注册。

Usage:
    local UpdateManager = require "Framework.Core.UpdateManager"
    local um = UpdateManager.GetInstance()
    
    um:AddUpdate(function(dt) ... end, self)       -- 注册
    um:RemoveUpdateByTarget(self)                    -- 批量移除
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Singleton = require "Framework.Core.Singleton"

local UpdateManager = Class.Define("UpdateManager")
Class.Extend(UpdateManager, Singleton)

function UpdateManager:Ctor()
    self._updates = {}          -- { {callback, target} }
    self._lateUpdates = {}
    self._fixedUpdates = {}
end

---注册 Update 回调
---@param callback function(dt) dt为秒
---@param target any 目标对象（用于批量移除）
function UpdateManager:AddUpdate(callback, target)
    table.insert(self._updates, { callback = callback, target = target })
end

---注册 LateUpdate 回调
---@param callback function(dt)
---@param target any
function UpdateManager:AddLateUpdate(callback, target)
    table.insert(self._lateUpdates, { callback = callback, target = target })
end

---注册 FixedUpdate 回调
---@param callback function(dt)
---@param target any
function UpdateManager:AddFixedUpdate(callback, target)
    table.insert(self._fixedUpdates, { callback = callback, target = target })
end

---移除某对象的所有更新回调
---@param target any
function UpdateManager:RemoveUpdateByTarget(target)
    self:_removeByTarget(self._updates, target)
    self:_removeByTarget(self._lateUpdates, target)
    self:_removeByTarget(self._fixedUpdates, target)
end

function UpdateManager:_removeByTarget(list, target)
    for i = #list, 1, -1 do
        if list[i].target == target then
            table.remove(list, i)
        end
    end
end

---每帧调用（由 C# 层驱动）
---@param dt number 秒
function UpdateManager:OnUpdate(dt)
    for i = 1, #self._updates do
        local entry = self._updates[i]
        if entry.callback then
            entry.callback(dt)
        end
    end
end

---每帧调用（由 C# 层驱动）
---@param dt number 秒
function UpdateManager:OnLateUpdate(dt)
    for i = 1, #self._lateUpdates do
        local entry = self._lateUpdates[i]
        if entry.callback then
            entry.callback(dt)
        end
    end
end

---固定帧调用（由 C# 层驱动）
---@param dt number 秒
function UpdateManager:OnFixedUpdate(dt)
    for i = 1, #self._fixedUpdates do
        local entry = self._fixedUpdates[i]
        if entry.callback then
            entry.callback(dt)
        end
    end
end

---清空所有
function UpdateManager:ClearAll()
    self._updates = {}
    self._lateUpdates = {}
    self._fixedUpdates = {}
end

function UpdateManager:Delete()
    self:ClearAll()
end

return UpdateManager
