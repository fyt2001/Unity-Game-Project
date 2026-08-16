--[[
=============================================================================
Class.lua
=============================================================================
Module:     Framework/Core/Class
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    轻量级 Lua OOP 系统，为 Framework 层提供统一的类定义和继承机制。
    
    注意：此模块与 UI/Utils/Class.lua 功能相同，但路径不同。
    Framework/Core 下的模块使用此路径，UI 模块使用 UI/Utils/Class。
    
    两者保持接口兼容，实际使用时按模块所在层级引用对应路径。

Usage:
    local Class = require "Framework.Core.Class"
    local MyClass = Class.Define("MyClass")
=============================================================================
]]

local Class = {}

function Class.Define(name)
    local class = {
        __className = name,
        __base = nil,
    }
    class.__index = class
    class.New = function(...)
        return Class.New(class, ...)
    end
    return class
end

function Class.Extend(derived, base)
    for key, value in pairs(base) do
        if derived[key] == nil then
            derived[key] = value
        end
    end
    derived.__base = base
    setmetatable(derived, {
        __index = base.__index,
        __call = base.__call,
    })
    derived.New = function(...)
        return Class.New(derived, ...)
    end
end

function Class.New(class, ...)
    local instance = {}
    setmetatable(instance, class)
    if instance.Ctor then
        instance:Ctor(...)
    end
    return instance
end

function Class.IsInstanceOf(instance, class)
    if not instance then return false end
    local mt = getmetatable(instance)
    while mt do
        if mt == class then return true end
        mt = mt.__base
    end
    return false
end

function Class.GetClassName(instance)
    if not instance then return nil end
    local mt = getmetatable(instance)
    return mt and mt.__className
end

return Class
