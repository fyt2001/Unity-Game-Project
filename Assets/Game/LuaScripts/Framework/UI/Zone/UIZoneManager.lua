--[[
=============================================================================
UIZoneManager.lua
=============================================================================
Module:     Framework/UI/Zone/UIZoneManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIZoneManager 协调多个 Zone 并确定焦点归属。
    Zone 是窗口的焦点分组容器，决定哪些窗口可以获得输入焦点。

    内置 Zone 类型：
        - BackgroundZone: 背景窗口，新背景隐藏旧背景
        - KeepZone: 常驻窗口（HUD、Debug），不抢占焦点
        - IgnoreFocusZone: 信息覆盖层，可见但不抢占焦点
        - NormalZone: 普通窗口组，最后打开的获得焦点

    焦点优先级：NormalZone > BackgroundZone > KeepZone / IgnoreFocusZone

Dependencies:
    - Class (类系统)
    - UIEnums (枚举)
    - UIZone (基础 Zone)
    - UIBackgroundZone (背景 Zone)
    - UIKeepZone (常驻 Zone)
    - UIIgnoreFocusZone (忽略焦点 Zone)

Usage:
    local zoneMgr = UIZoneManager.New()
    local zone = zoneMgr:AddWindow(window)
    zoneMgr:UpdateFocus()
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIEnums = require "NewObject.Framework.UI.Config.UIEnums"
local UIZone = require "NewObject.Framework.UI.Zone.UIZone"
local UIBackgroundZone = require "NewObject.Framework.UI.Zone.UIBackgroundZone"
local UIKeepZone = require "NewObject.Framework.UI.Zone.UIKeepZone"
local UIIgnoreFocusZone = require "NewObject.Framework.UI.Zone.UIIgnoreFocusZone"

local UIZoneManager = Class.Define("UIZoneManager")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化默认 Zone
function UIZoneManager:Ctor()
    self.backgroundZone = UIBackgroundZone.New()
    self.keepZone = UIKeepZone.New()
    self.ignoreFocusZone = UIIgnoreFocusZone.New()
    self.normalZones = {}
    self.focusZone = nil
end

-- =============================================================================
-- 私有方法：Zone 分配
-- =============================================================================

---根据窗口配置返回对应的 Zone
---@param config table 窗口配置
---@return table zone Zone 实例
function UIZoneManager:GetZoneForConfig(config)
    if config.zonePolicy == UIEnums.ZonePolicy.Background then
        return self.backgroundZone
    end
    if config.zonePolicy == UIEnums.ZonePolicy.Keep then
        return self.keepZone
    end
    if config.zonePolicy == UIEnums.ZonePolicy.IgnoreFocus then
        return self.ignoreFocusZone
    end
    -- 默认：创建独立 NormalZone
    local zone = UIZone.New(config.name .. "Zone")
    self.normalZones[#self.normalZones + 1] = zone
    return zone
end

-- =============================================================================
-- 公共 API：窗口管理
-- =============================================================================

---将窗口添加到其策略对应的 Zone
---@param window table UIWindow 实例
---@return table zone 所属 Zone
function UIZoneManager:AddWindow(window)
    local zone = self:GetZoneForConfig(window:GetConfig())
    zone:AddWindow(window)
    self:UpdateFocus()
    return zone
end

---从 Zone 中移除窗口
---如果 Zone 变为空且不是内置 Zone，则清理该 Zone
---@param window table UIWindow 实例
function UIZoneManager:RemoveWindow(window)
    local zone = window:GetOwnerZone()
    if zone then
        zone:RemoveWindow(window)
    end

    -- 清理空 NormalZone
    for index = #self.normalZones, 1, -1 do
        if not self.normalZones[index]:IsValid() then
            table.remove(self.normalZones, index)
        end
    end

    self:UpdateFocus()
end

-- =============================================================================
-- 公共 API：焦点管理
-- =============================================================================

---重新计算焦点分配
---KeepZone 和 IgnoreFocusZone 始终显示其窗口但不抢占焦点
---NormalZone 从后往前找到第一个可聚焦的 Zone
---如果没有 NormalZone 可聚焦，BackgroundZone 获得焦点
function UIZoneManager:UpdateFocus()
    -- KeepZone 和 IgnoreFocusZone 始终显示但不抢占焦点
    self.keepZone:Focus()
    self.ignoreFocusZone:Focus()

    -- 寻找可聚焦的 NormalZone
    local nextFocus = nil
    for index = #self.normalZones, 1, -1 do
        local zone = self.normalZones[index]
        if zone:CanFocus() then
            nextFocus = zone
            break
        end
    end

    -- 没有 NormalZone 时，BackgroundZone 获得焦点
    if not nextFocus and self.backgroundZone:CanFocus() then
        nextFocus = self.backgroundZone
    end

    -- 切换焦点
    if self.focusZone and self.focusZone ~= nextFocus then
        self.focusZone:Blur()
    end

    self.focusZone = nextFocus

    if self.focusZone then
        self.focusZone:Focus()
    end
end

---返回当前焦点 Zone 的顶层窗口
---@return table|nil window
function UIZoneManager:GetTopWindow()
    return self.focusZone and self.focusZone:GetTopWindow() or nil
end

---返回当前焦点 Zone
---@return table|nil zone
function UIZoneManager:GetFocusZone()
    return self.focusZone
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---返回所有 NormalZone 的数量
---@return number count
function UIZoneManager:GetNormalZoneCount()
    return #self.normalZones
end

---返回所有 Zone 中的窗口总数
---@return number count
function UIZoneManager:GetTotalWindowCount()
    local count = 0
    count = count + self.backgroundZone:GetWindowCount()
    count = count + self.keepZone:GetWindowCount()
    count = count + self.ignoreFocusZone:GetWindowCount()
    for _, zone in ipairs(self.normalZones) do
        count = count + zone:GetWindowCount()
    end
    return count
end

-- =============================================================================
-- 公共 API：批量操作
-- =============================================================================

---关闭并清除所有 Zone 中的窗口
---@param reason string|nil 关闭原因
function UIZoneManager:CloseAll(reason)
    for index = #self.normalZones, 1, -1 do
        self.normalZones[index]:CloseAll(reason)
        table.remove(self.normalZones, index)
    end
    self.backgroundZone:CloseAll(reason)
    self.ignoreFocusZone:CloseAll(reason)
    self.keepZone:CloseAll(reason)
    self.focusZone = nil
end

return UIZoneManager