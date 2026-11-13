--[[
=============================================================================
UIController.lua
=============================================================================
Module:     Framework/UI/Core/UIController
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
	UIController 是所有 UI 控制器的基类，负责处理用户意图和业务逻辑。
	它接收来自 View 的用户输入事件，更新 Model 数据，并通过游戏服务
	发送网络请求或触发游戏逻辑。

	Controller 禁止：
		- 直接实例化资源或 Prefab
		- 管理层级（Layer）
		- 管理焦点（Focus）
		- 直接操作 Unity GameObject

Dependencies:
	- Class (类系统)

Lifecycle Callbacks:
	OnCreate()      - 一次性初始化
	OnOpen(...)     - 打开时注册事件、订阅数据
	OnRefresh(...)  - 数据刷新时更新业务状态
	OnClose()       - 关闭时取消订阅、保存状态
	OnDestroy()     - 销毁前释放所有引用

Usage:
	local SampleBagController = Class.Define("SampleBagController")
	Class.Extend(SampleBagController, UIController)   -- 继承必须显式两步
	function SampleBagController:OnItemClicked(itemId)
		self.model:SetSelectedItem(itemId)
	end
=============================================================================
]]

local Class = require "Framework.Core.Class"

local UIController = Class.Define("UIController")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化 Controller 依赖
---子类重写 Ctor 时必须调用父类 Ctor
---@param model table Model 实例，由 UIWindowFactory 创建
function UIController:Ctor(model)
	self.model = model
	self.view = nil
	self.isCreated = false
end

-- =============================================================================
-- 公共 API：绑定与访问
-- =============================================================================

---绑定 View（由 UIWindow:BindMVC 在创建时调用）
---@param view table View 实例
function UIController:BindView(view)
	self.view = view
end

---获取绑定的 View
---@return table|nil view
function UIController:GetView()
	return self.view
end

---获取绑定的 Model
---@return table|nil model
function UIController:GetModel()
	return self.model
end

-- =============================================================================
-- 生命周期回调
-- 子类重写这些方法以实现具体业务逻辑
-- =============================================================================

---一次性创建回调：注册事件监听、初始化业务状态
---在此方法中订阅游戏事件、初始化业务数据
function UIController:OnCreate()
	self.isCreated = true
end

---打开回调：处理打开参数，启动业务逻辑
---在此方法中根据打开参数请求数据、注册网络回调
---@param ... any 打开参数
function UIController:OnOpen(...)
end

---刷新回调：处理数据刷新请求
---在此方法中根据新的刷新参数更新业务状态
---@param ... any 刷新参数
function UIController:OnRefresh(...)
end

---关闭回调：取消订阅、保存状态
---在此方法中取消所有事件订阅和网络请求
function UIController:OnClose()
end

---销毁回调：释放所有引用
---必须在此方法中释放所有外部引用
function UIController:OnDestroy()
	-- 基类统一注销：凡是订阅时以 self 作为 target（AddListener(event, cb, self)），
	-- 在此自动按对象批量移除，子类无需手动维护 _eventHandles / 循环 RemoveListener。
	local ok, EventManager = pcall(require, "Framework.Core.EventManager")
	if ok and EventManager then
		pcall(function()
			local em = EventManager:GetInstance()
			if em then em:RemoveListenerByTarget(self) end
		end)
	end
	self.view = nil
	self.model = nil
	self.isCreated = false
end

return UIController