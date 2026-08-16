--[[
=============================================================================
UIEnums.lua
=============================================================================
Module:     Framework/UI/Config/UIEnums
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIEnums 定义 UI 框架的所有枚举值，包括窗口类型、缓存策略、Zone 策略、
    和打开模式。所有枚举值均为数字常量，确保跨模块一致。

    枚举定义：
        - WindowType: 窗口类型（Normal, Popup, Dialog, Toast, Guide, Loading, System）
        - CachePolicy: 缓存策略（DestroyOnClose, CacheOnClose, NeverDestroy, DestroyOnSceneChange）
        - ZonePolicy: Zone 焦点策略（Normal, Background, Keep, IgnoreFocus）
        - OpenMode: 打开模式（Stack, Replace, SingleTop, RefreshIfOpen）

Dependencies:
    无外部依赖

Usage:
    local UIEnums = require "Framework.UI.Config.UIEnums"
    local config = { openMode = UIEnums.OpenMode.SingleTop }
=============================================================================
]]

local UIEnums = {}

-- =============================================================================
-- WindowType: 窗口类型
-- 决定窗口的 UI 行为和样式
-- =============================================================================
UIEnums.WindowType = {
    Normal = 1,
    Popup = 2,
    Dialog = 3,
    Toast = 4,
    Guide = 5,
    Loading = 6,
    System = 7,
}

-- =============================================================================
-- CachePolicy: 缓存策略
-- 决定窗口关闭后缓存的删除行为
-- =============================================================================
UIEnums.CachePolicy = {
    DestroyOnClose = 1,
    CacheOnClose = 2,
    NeverDestroy = 3,
    DestroyOnSceneChange = 4,
}

-- =============================================================================
-- ZonePolicy: Zone 焦点策略
-- 决定窗口与焦点分组的交互方式
-- =============================================================================
UIEnums.ZonePolicy = {
    Normal = 1,
    Background = 2,
    Keep = 3,
    IgnoreFocus = 4,
}

-- =============================================================================
-- OpenMode: 打开模式
-- 决定窗口打开时对现有窗口的处理方式
-- =============================================================================
UIEnums.OpenMode = {
    Stack = 1,
    Replace = 2,
    SingleTop = 3,
    RefreshIfOpen = 4,
}

-- =============================================================================
-- 工具函数：枚举转字符串
-- =============================================================================

---将 WindowType 枚举值转换为可读字符串
---@param value number 枚举值
---@return string name
function UIEnums.GetWindowTypeName(value)
    local map = {
        [UIEnums.WindowType.Normal] = "Normal",
        [UIEnums.WindowType.Popup] = "Popup",
        [UIEnums.WindowType.Dialog] = "Dialog",
        [UIEnums.WindowType.Toast] = "Toast",
        [UIEnums.WindowType.Guide] = "Guide",
        [UIEnums.WindowType.Loading] = "Loading",
        [UIEnums.WindowType.System] = "System",
    }
    return map[value] or "Unknown"
end

---将 CachePolicy 枚举值转换为可读字符串
---@param value number 枚举值
---@return string name
function UIEnums.GetCachePolicyName(value)
    local map = {
        [UIEnums.CachePolicy.DestroyOnClose] = "DestroyOnClose",
        [UIEnums.CachePolicy.CacheOnClose] = "CacheOnClose",
        [UIEnums.CachePolicy.NeverDestroy] = "NeverDestroy",
        [UIEnums.CachePolicy.DestroyOnSceneChange] = "DestroyOnSceneChange",
    }
    return map[value] or "Unknown"
end

---将 ZonePolicy 枚举值转换为可读字符串
---@param value number 枚举值
---@return string name
function UIEnums.GetZonePolicyName(value)
    local map = {
        [UIEnums.ZonePolicy.Normal] = "Normal",
        [UIEnums.ZonePolicy.Background] = "Background",
        [UIEnums.ZonePolicy.Keep] = "Keep",
        [UIEnums.ZonePolicy.IgnoreFocus] = "IgnoreFocus",
    }
    return map[value] or "Unknown"
end

---将 OpenMode 枚举值转换为可读字符串
---@param value number 枚举值
---@return string name
function UIEnums.GetOpenModeName(value)
    local map = {
        [UIEnums.OpenMode.Stack] = "Stack",
        [UIEnums.OpenMode.Replace] = "Replace",
        [UIEnums.OpenMode.SingleTop] = "SingleTop",
        [UIEnums.OpenMode.RefreshIfOpen] = "RefreshIfOpen",
    }
    return map[value] or "Unknown"
end

return UIEnums