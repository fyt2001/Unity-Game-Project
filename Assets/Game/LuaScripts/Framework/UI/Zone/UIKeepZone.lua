--[[
=============================================================================
UIKeepZone.lua
=============================================================================
Module:     Framework/UI/Zone/UIKeepZone
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIKeepZone 是常驻窗口的 Zone 实现，用于始终可见但不抢占焦点的窗口。
    这些窗口通常显示在屏幕边缘或作为覆盖层，不影响正常 UI 交互。

    典型场景：
        - HUD（血量、法力、小地图）
        - 调试面板（FPS、内存监控）
        - 全局加载提示
        - 网络状态提示

    行为：
        - CanFocus: 始终返回 false（不抢占焦点）
        - Focus: 显示所有窗口但不改变输入焦点
        - 窗口始终可见，不受 NormalZone 焦点切换影响

Dependencies:
    - Class (类系统)
    - UIZone (基础 Zone)

Usage:
    由 UIZoneManager 自动管理，业务代码无需直接操作。
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local UIZone = require "Framework.UI.Zone.UIZone"

local UIKeepZone = Class.Define("UIKeepZone")
Class.Extend(UIKeepZone, UIZone)

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化常驻 Zone
function UIKeepZone:Ctor()
    UIZone.Ctor(self, "KeepZone")
end

-- =============================================================================
-- 公共 API：焦点策略
-- =============================================================================

---常驻 Zone 不抢占焦点
---始终返回 false，确保 NormalZone 可以正常获得焦点
---@return boolean focusable 始终为 false
function UIKeepZone:CanFocus()
    return false
end

---显示常驻窗口但不改变输入焦点
---所有窗口都获得焦点（显示），但不影响正常 UI 交互
function UIKeepZone:Focus()
    self.focused = true
    for _, window in ipairs(self.windows) do
        if window:IsOpened() or window:IsHidden() then
            window:Focus()
        end
    end
end

---隐藏常驻窗口
function UIKeepZone:Blur()
    self.focused = false
    for _, window in ipairs(self.windows) do
        if window:IsOpened() then
            window:Hide()
        end
    end
end

return UIKeepZone