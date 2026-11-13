--[[
=============================================================================
UIView.lua
=============================================================================
Module:     Framework/UI/Core/UIView
Version:    4.0.0（对齐 ShaoNvClient_H02：UIView 继承 UIBaseContainer 组件容器）
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
	UIView 是所有 UI 视图的基类，继承 H02 的 UIBaseContainer，因此它本身就是一个
	组件容器：在 OnCreate 中使用 self:AddComponent(UIButton/UIText/UIImage/UINode, path)
	绑定子组件，销毁（OnDestroy）时自动遍历 Delete 所有子组件（触发 __delete -> OnDestroy，
	子组件在此清理点击监听等），与 H02 生命周期完全一致。

	View 构造签名对齐 H02 组件容器：__init(holder, var_arg)
		holder = window（窗口容器），var_arg = gameObject（根节点）

Dependencies:
	- BaseClass（OOP 系统，对齐 H02）
	- UIBaseContainer / UIBaseComponent（组件容器 / 组件基类）

Lifecycle Callbacks（由 UIWindow 调用）:
	OnCreate()      - 一次性绑定 UI 组件
	OnOpen(...)     - 打开时初始化 UI 状态
	OnRefresh(...)  - 数据刷新时更新 UI 显示
	OnFocus()       - 获得输入焦点时
	OnBlur()        - 失去输入焦点时
	OnHide()        - 被隐藏时
	OnClose()       - 关闭前清理
	OnDestroy()     - 销毁前释放引用（由 UIBaseContainer 自动 Delete 子组件）
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseContainer = require "Framework.UI.Base.UIBaseContainer"
local Logger = require "Framework.UI.Utils.Logger"

local UIView = BaseClass("UIView", UIBaseContainer)
local base = UIBaseContainer

-- =============================================================================
-- 构造函数（对齐 H02 组件容器 __init(holder, var_arg)）
-- UIBaseComponent.__init 已在 BaseClass 创建链中执行（holder=window, var_arg=gameObject）
-- =============================================================================

---@param window table 所属 UIWindow（作为容器持有者 holder）
---@param gameObject any Unity GameObject 根节点
function UIView:__init(window, gameObject)
	self.windowName = window and window:GetName() or ""
	self.controller = nil
	self.visible = true
	self.isCreated = false
end

-- =============================================================================
-- 公共 API：绑定 / 引用
-- =============================================================================

---绑定 Controller（由 UIWindow:BindMVC 在创建时调用）
function UIView:BindController(controller)
	self.controller = controller
end

function UIView:GetController()
	return self.controller
end

function UIView:GetGameObject()
	return self.gameObject
end

function UIView:GetTransform()
	return self.transform
end

-- =============================================================================
-- 公共 API：动静分离（参考 H02：UIValentineChocolateProgressItem.lua 给 Slider 节点
-- AddComponent(Canvas) + overrideSorting=true，隔离频繁重建元素，避免污染整个窗口合批）
--
-- 原理：在频繁更新的 UI 节点（Slider / 计时文本 / 滚动列表项 / 飘字根）上挂一个
-- 嵌套 Canvas，该子树会作为独立 Canvas 单独合批与重建，父窗口其余静态内容不受影响。
--
-- 本项目无自定义 sorting layer（UI 全在 Default 层，挂在 layer Canvas 之下），为避免分层回归：
--   - 不传 sortingOrder：嵌套 Canvas 继承父级排序，渲染位置不变（最安全，推荐默认）；
--   - 传了 sortingOrder：对齐 H02，设 overrideSorting=true 并用指定排序值（用于需要
--     主动控制层级的场景，注意会进入 Default 层全局排序，值需 > 所在 layer 的 order）。
--
--@param go UnityEngine.GameObject 需要隔离重建的动态节点
--@param sortingOrder number|nil 可选，显式排序值（启用 overrideSorting）
--@return UnityEngine.Canvas|nil canvas
function UIView:AddDynamicCanvas(go, sortingOrder)
	if not go then return nil end
	local canvas = go:AddComponent(typeof(Unity_Canvas))
	if sortingOrder then
		canvas.overrideSorting = true
		canvas.sortingOrder = sortingOrder
	end
	return canvas
end

---查找子节点对应的 GameObject（用于没有组件语义的纯节点）
function UIView:FindGameObject(path)
	if not self.gameObject then return nil end
	local transform = self.gameObject.transform
	if path and path ~= "" then
		transform = transform:Find(path)
	end
	return transform and transform.gameObject or nil
end

function UIView:GetWindowName()
	return self.windowName
end

-- =============================================================================
-- 公共 API：可见性
-- =============================================================================

function UIView:SetVisible(visible)
	self.visible = visible
	if self.gameObject and self.gameObject.SetActive then
		self:SetActive(visible)
	end
end

function UIView:IsVisible()
	return self.visible
end

-- =============================================================================
-- 生命周期回调（子类重写这些实现具体 UI 逻辑）
-- 注意：子类 OnCreate 必须首先调用 base.OnCreate(self) 以解析 transform 并注册容器
-- =============================================================================

function UIView:OnCreate()
	base.OnCreate(self)   -- 基类 UIBaseContainer.OnCreate 已执行 BindLuaUIComp + AutoBind
	self.isCreated = true
end

function UIView:OnOpen(...)
end

function UIView:OnRefresh(...)
end

function UIView:OnFocus()
end

function UIView:OnBlur()
end

function UIView:OnHide()
end

function UIView:OnClose()
end

function UIView:OnDestroy()
	base.OnDestroy(self)
	self.controller = nil
	self.gameObject = nil
	self.isCreated = false
end

return UIView
