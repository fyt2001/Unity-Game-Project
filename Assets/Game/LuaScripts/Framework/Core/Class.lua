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
	
	【canonical】全工程唯一 Class 实现，任何 Lua 模块一律 require "Framework.Core.Class"。
	（历史说明：Framework/UI/Utils/Class.lua 曾为第二份等价实现，已于 P0-1 删除。）

	【能力约定】继承链上的实例自带 `self.super`：它是一个代理表，按 `__index` 转发到
	直接父类的方法，并把 self 绑定为当前实例。子类 Ctor 里写
	`self.super:Ctor(...)` 即可调用父类构造。仅指向**直接**父类，不支持跨级。

Usage:
	local Class = require "Framework.Core.Class"
	local MyClass = Class.Define("MyClass")

	-- 继承必须【显式两步】，不可写成 Class.Define("Child", Parent)：
	local Parent  = Class.Define("Parent")
	local Child   = Class.Define("Child")
	Class.Extend(Child, Parent)
=============================================================================
]]

local Class = {}

function Class.Define(name, base)
	-- 【P2-2 防回归 2026-10-01】显式拒绝第二个参数，把静默坑改成显式失败。
	-- 历史：全工程曾有 3 处代码 + 2 处文档示例写成 Class.Define(name, Base)。
	-- 本函数只取第一个参数，于是 __base 恒为 nil、继承被静默吞掉。实测后果：
	--   Game/UI/Dungeon/UIFloorEventModel.lua   UIModel 方法全为 nil
	--   Game/UI/GM/UIGMModel.lua                 UIModel 方法全为 nil
	--   Game/UI/GM/UIGMController.lua            GetView=nil，:Execute() 抛 nil 调用（活 bug）
	-- 继承请显式两步：Class.Define(name) 然后 Class.Extend(Derived, Base)。
	if base ~= nil then
		error(string.format(
			"Class.Define(%s) 只接受一个参数。继承请写成：Class.Define(%s) + Class.Extend(%s, Base)",
			tostring(name), tostring(name), tostring(name)), 2)
	end

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
	-- 【P0-1 收敛修复 2026-10-01】补回 `self.super`。
	-- 历史：被删的 Framework/UI/Utils/Class.lua 的 New() 会给实例挂 super 代理表；
	-- 本 canonical 实现原先没有。批次2 把 31 处 require 切到本文件后，所有
	-- `self.super:Ctor(...)` 的调用点全部报
	-- "attempt to index a nil value (field 'super')"（实测 Game/UI/Login/UILoginModel.lua:22）。
	-- 收敛的正确语义是并集：canonical 必须保留被收敛方的全部能力。
	local base = class.__base
	if base then
		instance.super = setmetatable({}, {
			__index = function(_, key)
				local method = base[key]
				if type(method) == "function" then
					return function(_, ...)
						return method(instance, ...)
					end
				end
				return method
			end,
		})
	end
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
