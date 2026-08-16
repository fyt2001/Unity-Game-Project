--[[
=============================================================================
Framework.lua
=============================================================================
Module:     Framework/Framework
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    Framework 统一入口。游戏代码通过此模块访问所有框架服务。
    这是 Game 层唯一的 Framework 依赖入口。

    提供：
        - Core 模块引用（Class, Singleton, EventManager, TimerManager, 
          UpdateManager, ObjectPool, CoroutineManager）
        - UI 框架入口（UIFramework）
        - 配置注册辅助方法

    设计原则：
        - 单一入口：Game 层只依赖 Framework
        - 内部模块可替换
        - 版本管理

Usage:
    local FW = require "Framework.Framework"
    
    -- 核心服务
    local eventMgr = FW.Event.GetInstance()
    local timerMgr = FW.Timer.GetInstance()
    
    -- UI 服务
    local uiManager = FW.UI.Create()
    uiManager:Open("Bag", bagId)
=============================================================================
]]

local Framework = {}

-- 版本
Framework.Version = "3.0.0"

-- =============================================================================
-- Core 模块
-- =============================================================================

Framework.Class = require "Framework.Core.Class"
Framework.Singleton = require "Framework.Core.Singleton"
Framework.EventManager = require "Framework.Core.EventManager"
Framework.TimerManager = require "Framework.Core.TimerManager"
Framework.UpdateManager = require "Framework.Core.UpdateManager"
Framework.ObjectPool = require "Framework.Core.ObjectPool"

-- =============================================================================
-- UI 模块
-- =============================================================================

Framework.UI = require "Framework.UI.UIFramework"

-- =============================================================================
-- 快捷访问（单例）
-- =============================================================================

---获取 EventManager 单例
function Framework.Event()
    return Framework.EventManager:GetInstance()
end

---获取 TimerManager 单例
function Framework.Timer()
    return Framework.TimerManager:GetInstance()
end

---获取 UpdateManager 单例
function Framework.Update()
    return Framework.UpdateManager:GetInstance()
end

---创建 UIManager 实例
---@param options table|nil
function Framework.CreateUIManager(options)
    return Framework.UI.Create(options)
end

return Framework
