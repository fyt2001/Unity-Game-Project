--[[
=============================================================================
SampleBagView.lua - 背包窗口视图层示例（对齐 H02：继承 UIView 组件容器）
=============================================================================
Module:     Framework/UI/Sample/SampleBagView
Version:    4.0.0
Author:     Framework Team
Status:     Sample (示例代码)
Target:     Unity + XLua

Description:
	SampleBagView 是背包窗口的视图层示例，演示如何绑定 UI 控件并
	将用户交互委托给 Controller。视图层只负责 UI 展示，不包含业务逻辑。

	生命周期回调：
		- OnCreate: 绑定 UI 控件
		- OnOpen: 根据参数更新视觉状态
		- OnRefresh: 刷新物品列表展示
		- OnDestroy: 解绑控件引用

	按钮事件绑定示例（生产项目中通过 Unity 组件绑定）：
		self:RegisterButton("CloseBtn", function() self:OnCloseClicked() end)

Dependencies:
	- BaseClass（OOP 系统，对齐 H02）
	- UIView（视图基类 / 组件容器）

Usage:
	由 UIManager 通过 UIWindowFactory 自动创建，无需手动实例化。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local SampleBagView = BaseClass("SampleBagView", UIView)
local base = UIView

-- =============================================================================
-- 生命周期回调
-- =============================================================================

---窗口创建时绑定 UI 控件
function SampleBagView:OnCreate()
	base.OnCreate(self)
	self.bound = true
	self.lastBagId = nil
	self.lastItems = nil
	-- 示例：绑定关闭按钮
	-- self:RegisterButton("CloseBtn", function() self:OnCloseClicked() end)
	-- 示例：绑定物品列表
	-- self.itemList = self:GetComponent("ScrollRect/Content", "Transform")
end

---窗口打开时更新视觉状态
function SampleBagView:OnOpen(bagId)
	self.lastBagId = bagId
end

---窗口刷新时更新物品列表展示
function SampleBagView:OnRefresh(items)
	self.lastItems = items
end

---窗口销毁时解绑控件引用
function SampleBagView:OnDestroy()
	self.bound = false
	self.lastBagId = nil
	self.lastItems = nil
	base.OnDestroy(self)
end

-- =============================================================================
-- 公共 API：控件交互
-- =============================================================================

---示例：关闭按钮点击处理
function SampleBagView:OnCloseClicked()
	local controller = self:GetController()
	if controller and controller.OnCloseClicked then
		controller:OnCloseClicked()
	end
end

---示例：物品点击处理
function SampleBagView:OnItemClicked(itemId)
	local controller = self:GetController()
	if controller and controller.OnItemClicked then
		controller:OnItemClicked(itemId)
	end
end

return SampleBagView
