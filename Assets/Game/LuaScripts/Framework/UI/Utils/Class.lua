--[[
=============================================================================
Class.lua
=============================================================================
Module:     Framework/UI/Utils/Class
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    Class 是 Lua 的轻量级 OOP 系统，提供类定义、继承和实例化支持。
    设计为最小化开销，无外部依赖，兼容 XLua 和标准 Lua 5.1+。

    特性：
        - Define(className): 定义新类，返回类表
        - Extend(baseClass): 创建基类的子类
        - New(...): 创建类实例，调用 Ctor 构造函数
        - Super: 调用父类方法

    用法示例：
        local Class = require "UI.Utils.Class"

        local Animal = Class.Define("Animal")
        function Animal:Ctor(name) self.name = name end
        function Animal:Speak() print(self.name) end

        local Dog = Class.Define("Dog")
        Class.Extend(Dog, Animal)
        function Dog:Speak() print(self.name .. " barks") end

        local dog = Dog.New("Rex")
        dog:Speak() -- "Rex barks"

Dependencies:
    无外部依赖

Known Issues:
    - 不支持多重继承，仅支持单继承链
    - Super 使用调用栈深度，在闭包中调用需谨慎
=============================================================================
]]

local Class = {}

-- =============================================================================
-- 公共 API：定义类
-- =============================================================================

---定义新类
---创建类表，设置 __index，绑定 New 方法
---@param name string 类名，用于调试和日志
---@return table class 类表
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

-- =============================================================================
-- 公共 API：继承
-- =============================================================================

---建立继承关系
---设置 metatable 链，使派生类可以访问基类方法
---@param derived table 派生类
---@param base table 基类
function Class.Extend(derived, base)
    -- 拷贝基类方法到派生类
    for key, value in pairs(base) do
        if derived[key] == nil then
            derived[key] = value
        end
    end

    -- 设置 metatable 链
    derived.__base = base
    setmetatable(derived, {
        __index = base.__index,
        __call = base.__call,
    })

    -- 覆盖 New 方法
    derived.New = function(...)
        return Class.New(derived, ...)
    end
end

-- =============================================================================
-- 公共 API：创建实例
-- =============================================================================

---创建类实例
---分配空表，设置 metatable，调用 Ctor 构造函数
---@param class table 类表
---@param ... 传递给 Ctor 的参数
---@return table instance 类实例
function Class.New(class, ...)
    local instance = {}
    setmetatable(instance, class)
    if instance.Ctor then
        instance:Ctor(...)
    end
    return instance
end

-- =============================================================================
-- 公共 API：Super 调用
-- =============================================================================

---调用父类方法
---通过调用栈深度确定当前类，从而找到其父类
---@param ... 传递给父类方法的参数
---@return any 父类方法的返回值
function Class.Super(...)
    -- 从调用栈中获取当前类
    local info = debug.getinfo(2, "f")
    local current = info.func

    -- 获取当前类的父类
    local base = current.__base
    if not base then
        error("Super called but no base class found", 2)
    end

    -- 调用父类方法
    local methodName = current.__methodName
    if methodName then
        local baseMethod = base[methodName]
        if baseMethod then
            return baseMethod(...)
        end
    end

    error("Super called but base method not found", 2)
end

-- =============================================================================
-- 公共 API：类型查询
-- =============================================================================

---判断实例是否属于某个类（或其子类）
---检查 metatable 链
---@param instance table 类实例
---@param class table 类表
---@return boolean isInstanceOf
function Class.IsInstanceOf(instance, class)
    if not instance then
        return false
    end
    local mt = getmetatable(instance)
    while mt do
        if mt == class then
            return true
        end
        mt = mt.__base
    end
    return false
end

---获取实例的类名
---@param instance table 类实例
---@return string|nil className
function Class.GetClassName(instance)
    if not instance then
        return nil
    end
    local mt = getmetatable(instance)
    return mt and mt.__className
end

return Class