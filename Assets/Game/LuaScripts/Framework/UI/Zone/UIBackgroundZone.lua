--[[
=============================================================================
UIBackgroundZone.lua
=============================================================================
Module:     Framework/UI/Zone/UIBackgroundZone
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIBackgroundZone 是背景窗口的 Zone 实现，确保同一时间只有一个背景窗口可见。
    新背景窗口打开时，旧背景窗口自动隐藏。

    典型场景：
        - 全屏主界面（如主城、战斗界面）
        - 场景背景界面
        - 需要互斥的全屏窗口

    行为：
        - AddWindow: 新窗口添加时隐藏旧背景窗口
        - Focus: 仅显示最新的背景窗口
        - CanFocus: 有背景窗口时返回 true

Dependencies:
    - Class (类系统)
    - UIZone (基础 Zone)

Usage:
    由 UIZoneManager 自动管理，业务代码无需直接操作。
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIZone = require "NewObject.Framework.UI.Zone.UIZone"

local UIBackgroundZone = Class.Define("UIBackgroundZone")
Class.Extend(UIBackgroundZone, UIZone)

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化背景 Zone 状态
function UIBackgroundZone:Ctor()
    UIZone.Ctor(self, "BackgroundZone")
    self.backgroundWindow = nil
end

-- =============================================================================
-- 公共 API：窗口管理
-- =============================================================================

---添加背景窗口，隐藏旧背景窗口
---新背景窗口打开时，旧背景窗口自动隐藏
---@param window table UIWindow 实例
function UIBackgroundZone:AddWindow(window)
    -- 隐藏旧背景窗口
    if self.backgroundWindow and self.backgroundWindow ~= window then
        self.backgroundWindow:Hide()
    end
    self.backgroundWindow = window
    UIZone.AddWindow(self, window)
end

---从 Zone 中移除窗口
---如果移除的是当前背景窗口，清除引用
---@param window table UIWindow 实例
---@return boolean removed
function UIBackgroundZone:RemoveWindow(window)
    if self.backgroundWindow == window then
        self.backgroundWindow = nil
    end
    return UIZone.RemoveWindow(self, window)
end

-- =============================================================================
-- 公共 API：焦点操作
-- =============================================================================

---聚焦背景 Zone，显示最新背景窗口
function UIBackgroundZone:Focus()
    self.focused = true
    if self.backgroundWindow and
        (self.backgroundWindow:IsOpened() or self.backgroundWindow:IsHidden()) then
        self.backgroundWindow:Focus()
    end
end

---失焦背景 Zone，隐藏背景窗口
function UIBackgroundZone:Blur()
    self.focused = false
    if self.backgroundWindow and self.backgroundWindow:IsOpened() then
        self.backgroundWindow:Hide()
    end
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---返回当前背景窗口
---@return table|nil window
function UIBackgroundZone:GetTopWindow()
    return self.backgroundWindow
end

return UIBackgroundZone