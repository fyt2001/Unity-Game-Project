--[[
=============================================================================
ObjectPool.lua
=============================================================================
Module:     Framework/Core/ObjectPool
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    通用 Lua 对象池。用于复用频繁创建/销毁的 Lua table 对象
    （如技能数据、Buff数据、伤害信息等），减少 GC 压力。
    
    支持自动扩容和最大容量限制。

Usage:
    local ObjectPool = require "Framework.Core.ObjectPool"
    local pool = ObjectPool.New(function() return {x=0, y=0} end, function(t) 
        t.x=0; t.y=0  -- reset
    end)
    
    local obj = pool:Get()
    obj.x = 10
    pool:Release(obj)
=============================================================================
]]

local Class = require "Framework.Core.Class"

local ObjectPool = Class.Define("ObjectPool")

---@param createFn function 创建新对象的工厂函数
---@param resetFn function|nil 回收时重置对象的函数
---@param initialSize number|nil 初始容量
---@param maxSize number|nil 最大容量
function ObjectPool:Ctor(createFn, resetFn, initialSize, maxSize)
    self._createFn = createFn
    self._resetFn = resetFn
    self._maxSize = maxSize or 100
    self._pool = {}
    self._activeCount = 0

    -- 预创建
    initialSize = initialSize or 0
    for i = 1, initialSize do
        self._pool[i] = createFn()
    end
end

---从池中获取对象
---@return any
function ObjectPool:Get()
    if #self._pool > 0 then
        local obj = table.remove(self._pool)
        self._activeCount = self._activeCount + 1
        return obj
    end
    -- 池空，创建新对象
    self._activeCount = self._activeCount + 1
    return self._createFn()
end

---回收对象到池
---@param obj any
function ObjectPool:Release(obj)
    if not obj then return end
    self._activeCount = self._activeCount - 1

    if self._maxSize and #self._pool >= self._maxSize then
        return -- 超过最大容量，丢弃
    end

    if self._resetFn then
        self._resetFn(obj)
    end
    table.insert(self._pool, obj)
end

---预分配
---@param count number
function ObjectPool:PreAllocate(count)
    for i = 1, count do
        table.insert(self._pool, self._createFn())
    end
end

---获取池中可用数量
---@return number
function ObjectPool:GetAvailableCount()
    return #self._pool
end

---获取活跃对象数量
---@return number
function ObjectPool:GetActiveCount()
    return self._activeCount
end

---清空池
function ObjectPool:Clear()
    self._pool = {}
    self._activeCount = 0
end

return ObjectPool
