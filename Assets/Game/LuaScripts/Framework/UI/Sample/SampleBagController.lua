--[[
=============================================================================
SampleBagController.lua
=============================================================================
Module:     Framework/UI/Sample/SampleBagController
Version:    3.0.0
Author:     Framework Team
Status:     Sample (示例代码)
Target:     Unity + XLua

Description:
    SampleBagController 是背包窗口的控制器示例，演示如何处理用户交互、
    更新模型和调用游戏服务。控制器是 MVC 的业务逻辑中枢。

    生命周期回调：
        - OnCreate: 注册事件监听
        - OnOpen: 初始化业务状态
        - OnRefresh: 处理刷新逻辑
        - OnDestroy: 清理事件监听

Dependencies:
    - Class (类系统)
    - UIController (控制器基类)

Usage:
    由 UIManager 通过 UIWindowFactory 自动创建，无需手动实例化。
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local UIController = require "Framework.UI.Core.UIController"

local SampleBagController = Class.Define("SampleBagController")
Class.Extend(SampleBagController, UIController)

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化控制器依赖
---@param model table SampleBagModel 实例
function SampleBagController:Ctor(model)
    UIController.Ctor(self, model)
    self.selectedItemId = nil
end

-- =============================================================================
-- 生命周期回调
-- =============================================================================

---窗口创建时注册事件监听
function SampleBagController:OnCreate()
    -- 示例：注册全局事件
    -- self:RegisterEvent("ItemChanged", self.OnItemChanged)
end

---窗口打开时初始化业务状态
---@param bagId number|nil 背包 ID
function SampleBagController:OnOpen(bagId)
    self.selectedItemId = nil
end

---窗口刷新时更新业务状态
---@param items table|nil 新的物品列表
function SampleBagController:OnRefresh(items)
    self.selectedItemId = nil
end

---窗口销毁时清理事件监听
function SampleBagController:OnDestroy()
    self.selectedItemId = nil
end

-- =============================================================================
-- 公共 API：用户交互处理
-- =============================================================================

---处理物品点击事件
---更新模型中的选中状态
---@param itemId number 物品 ID
function SampleBagController:OnItemClicked(itemId)
    self.selectedItemId = itemId
    local model = self:GetModel()
    if model then
        model:SetSelectedItem(itemId)
    end
end

---处理关闭按钮点击
---委托给窗口关闭
function SampleBagController:OnCloseClicked()
    local window = self:GetWindow()
    if window then
        window:Close("UserClose")
    end
end

---处理物品使用事件
---生产项目中应调用游戏服务
---@param itemId number 物品 ID
function SampleBagController:OnItemUsed(itemId)
    -- 示例：模拟使用物品
    local model = self:GetModel()
    if model then
        model:RemoveItem(itemId)
    end
end

return SampleBagController