--[[
=============================================================================
Singleton.lua
=============================================================================
Module:     Framework/Core/Singleton
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    单例模式基类，所有全局管理器的基础。
    提供懒加载 GetInstance() 和 Delete() 销毁。

Usage:
    local Singleton = require "Framework.Core.Singleton"
    local MyManager = Class.Define("MyManager")
    Class.Extend(MyManager, Singleton)
    
    local inst = MyManager.GetInstance()
=============================================================================
]]

local Class = require "Framework.Core.Class"

local Singleton = Class.Define("Singleton")

function Singleton:Ctor()
    -- 子类在此初始化
end

---获取单例实例（懒加载）
---@return table instance
function Singleton.GetInstance(self)
    if not self._instance then
        self._instance = self.New()
    end
    return self._instance
end

---销毁单例实例
function Singleton.DeleteInstance(self)
    if self._instance then
        if self._instance.Delete then
            self._instance:Delete()
        end
        self._instance = nil
    end
end

return Singleton
