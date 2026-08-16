--[[
=============================================================================
UIIgnoreFocusZone.lua
=============================================================================
Module:     Framework/UI/Zone/UIIgnoreFocusZone
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIIgnoreFocusZone 是信息覆盖层的 Zone 实现，用于可见但不抢占输入焦点的窗口。
    这些窗口通常作为信息提示层，用户可以看到但不能交互。

    典型场景：
        - 伤害数字飘字
        - 战斗提示信息
        - 系统公告覆盖层
        - 无交互的纯展示窗口

    行为：
        - CanFocus: 始终返回 false（不抢占焦点）
        - Focus: 显示所有窗口但不改变输入焦点
        - 与 UIKeepZone 的区别：信息覆盖层更偏向临时性展示

Dependencies:
    - Class (类系统)
    - UIZone (基础 Zone)

Usage:
    由 UIZoneManager 自动管理，业务代码无需直接操作。
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local UIZone = require "Framework.UI.Zone.UIZone"

local UIIgnoreFocusZone = Class.Define("UIIgnoreFocusZone")
Class.Extend(UIIgnoreFocusZone, UIZone)

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化忽略焦点 Zone
function UIIgnoreFocusZone:Ctor()
    UIZone.Ctor(self, "IgnoreFocusZone")
end

-- =============================================================================
-- 公共 API：焦点策略
-- =============================================================================

---忽略焦点 Zone 不抢占焦点
---始终返回 false，确保 NormalZone 可以正常获得焦点
---@return boolean focusable 始终为 false
function UIIgnoreFocusZone:CanFocus()
    return false
end

---显示信息覆盖层但不改变输入焦点
---所有窗口都获得焦点（显示），便于用户看到信息但不影响操作
function UIIgnoreFocusZone:Focus()
    self.focused = true
    for _, window in ipairs(self.windows) do
        if window:IsOpened() or window:IsHidden() then
            window:Focus()
        end
    end
end

---隐藏信息覆盖层
function UIIgnoreFocusZone:Blur()
    self.focused = false
    for _, window in ipairs(self.windows) do
        if window:IsOpened() then
            window:Hide()
        end
    end
end

return UIIgnoreFocusZone