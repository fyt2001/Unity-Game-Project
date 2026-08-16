--[[
=============================================================================
UIZone.lua
=============================================================================
Module:     Framework/UI/Zone/UIZone
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIZone 是所有 Zone 的基础实现，负责将窗口分组并应用焦点/可见性策略。
    每个 Zone 维护一个窗口列表，Zone 聚焦时顶部窗口获得焦点，其他窗口隐藏。

    特化 Zone 应继承 UIZone 并重写策略方法（CanFocus、Focus、Blur）。

Dependencies:
    - Class (类系统)
    - TableUtil (表工具)

Usage:
    local zone = UIZone.New("ShopZone")
    zone:AddWindow(window)
    zone:Focus()
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local TableUtil = require "NewObject.Framework.UI.Utils.TableUtil"

local UIZone = Class.Define("UIZone")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化 Zone 名称和窗口列表
---@param name string Zone 名称，用于日志
function UIZone:Ctor(name)
    self.name = name or "Zone"
    self.windows = {}
    self.focused = false
end

-- =============================================================================
-- 公共 API：基本信息
-- =============================================================================

---返回 Zone 名称
---@return string name
function UIZone:GetName()
    return self.name
end

---返回 Zone 内窗口数量
---@return number count
function UIZone:GetWindowCount()
    return #self.windows
end

-- =============================================================================
-- 公共 API：窗口管理
-- =============================================================================

---向 Zone 添加窗口
---如果窗口已在 Zone 中，则跳过
---如果 Zone 已聚焦，新窗口自动获得焦点
---@param window table UIWindow 实例
function UIZone:AddWindow(window)
    if TableUtil.IndexOf(self.windows, window) then
        return
    end
    self.windows[#self.windows + 1] = window
    window:SetOwnerZone(self)

    -- 如果 Zone 已聚焦，新窗口自动获得焦点
    if self.focused and (window:IsOpened() or window:IsHidden()) then
        window:Focus()
    elseif window:IsOpened() then
        window:Hide()
    end
end

---从 Zone 中移除窗口
---@param window table UIWindow 实例
---@return boolean removed 是否成功移除
function UIZone:RemoveWindow(window)
    local removed = TableUtil.RemoveValue(self.windows, window)
    if removed then
        window:SetOwnerZone(nil)
    end
    return removed
end

-- =============================================================================
-- 公共 API：状态查询
-- =============================================================================

---判断 Zone 是否有效（至少有一个窗口）
---@return boolean valid
function UIZone:IsValid()
    return #self.windows > 0
end

---判断 Zone 是否可以接收焦点
---默认实现：Zone 有效即可聚焦
---子类可重写以改变行为
---@return boolean focusable
function UIZone:CanFocus()
    return self:IsValid()
end

---判断 Zone 是否已聚焦
---@return boolean focused
function UIZone:IsFocused()
    return self.focused
end

-- =============================================================================
-- 公共 API：焦点操作
-- =============================================================================

---聚焦 Zone，顶部窗口获得焦点，其余窗口隐藏
function UIZone:Focus()
    self.focused = true
    for index, window in ipairs(self.windows) do
        if index == #self.windows and (window:IsOpened() or window:IsHidden()) then
            window:Focus()
        elseif window:IsOpened() then
            window:Hide()
        end
    end
end

---失焦 Zone，隐藏所有窗口
function UIZone:Blur()
    self.focused = false
    for _, window in ipairs(self.windows) do
        if window:IsOpened() then
            window:Hide()
        end
    end
end

-- =============================================================================
-- 公共 API：批量操作
-- =============================================================================

---从顶部到底部关闭所有窗口
---@param reason string|nil 关闭原因
function UIZone:CloseAll(reason)
    for index = #self.windows, 1, -1 do
        local window = self.windows[index]
        self:RemoveWindow(window)
        window:Close(reason or "ZoneCloseAll")
    end
end

---返回 Zone 顶部窗口
---@return table|nil window
function UIZone:GetTopWindow()
    return self.windows[#self.windows]
end

return UIZone