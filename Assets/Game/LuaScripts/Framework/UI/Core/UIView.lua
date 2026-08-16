--[[
=============================================================================
UIView.lua
=============================================================================
Module:     Framework/UI/Core/UIView
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIView 是所有 UI 视图的基类，负责 UI 组件绑定和用户输入转发。
    它了解 Unity Widget 和视觉节点，但禁止发送网络请求、修改全局游戏数据
    或控制层级。

    业务 View 继承 UIView，在 OnCreate 中绑定 UI 组件（Button、Text、Image 等），
    在 OnRefresh 中更新 UI 显示，用户交互通过 Controller 转发处理。

Dependencies:
    - Class (类系统)

Lifecycle Callbacks:
    OnCreate()      - 一次性绑定 UI 组件
    OnOpen(...)     - 打开时初始化 UI 状态
    OnRefresh(...)  - 数据刷新时更新 UI 显示
    OnFocus()       - 获得输入焦点时
    OnBlur()        - 失去输入焦点时
    OnHide()        - 被隐藏时
    OnClose()       - 关闭前清理
    OnDestroy()     - 销毁前释放引用

Usage:
    local SampleBagView = Class.Define("SampleBagView", UIView)
    function SampleBagView:OnCreate()
        -- 绑定 UI 组件
        self.closeButton = self.gameObject:Find("CloseButton")
    end
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"

local UIView = Class.Define("UIView")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化 View 标识和 Unity 引用
---子类重写 Ctor 时必须调用父类 Ctor
---@param windowName string 所属 Window 名称
---@param gameObject any Unity GameObject 或适配器对象
function UIView:Ctor(windowName, gameObject)
    self.windowName = windowName
    self.gameObject = gameObject
    self.controller = nil
    self.visible = true
    self.isCreated = false
end

-- =============================================================================
-- 公共 API：绑定
-- =============================================================================

---绑定 Controller（由 UIWindow:BindMVC 在创建时调用）
---@param controller table Controller 实例
function UIView:BindController(controller)
    self.controller = controller
end

---获取绑定的 Controller
---@return table|nil controller
function UIView:GetController()
    return self.controller
end

---获取绑定的 GameObject
---@return any|nil gameObject
function UIView:GetGameObject()
    return self.gameObject
end

---获取 Transform
---@return any|nil transform
function UIView:GetTransform()
    return self.gameObject and self.gameObject.transform or nil
end

---获取所属 Window 名称
---@return string windowName
function UIView:GetWindowName()
    return self.windowName
end

-- =============================================================================
-- 公共 API：可见性
-- =============================================================================

---设置 View 的可见性
---@param visible boolean 是否可见
function UIView:SetVisible(visible)
    self.visible = visible
    if self.gameObject and self.gameObject.SetActive then
        self.gameObject:SetActive(visible)
    end
end

---返回 View 是否可见
---@return boolean visible
function UIView:IsVisible()
    return self.visible
end

-- =============================================================================
-- 生命周期回调
-- 子类重写这些方法以实现具体 UI 逻辑
-- =============================================================================

---一次性创建回调：绑定 UI 组件、注册 UI 事件
---在此方法中查找并缓存 Widget 引用（Button、Text、Image 等）
---禁止在此方法中发送网络请求或修改全局数据
function UIView:OnCreate()
    self.isCreated = true
end

---打开回调：初始化 UI 状态
---在此方法中根据打开参数设置 UI 初始状态
---@param ... any 打开参数
function UIView:OnOpen(...)
end

---刷新回调：更新 UI 显示
---在此方法中根据最新的 Model 数据更新 UI 组件
---@param ... any 刷新参数
function UIView:OnRefresh(...)
end

---焦点回调：当 View 获得输入焦点时调用
---可在此方法中启用输入监听、显示焦点指示器等
function UIView:OnFocus()
end

---失焦回调：当 View 失去输入焦点时调用
---可在此方法中禁用输入监听、隐藏焦点指示器等
function UIView:OnBlur()
end

---隐藏回调：当 View 被隐藏时调用
---可在此方法中暂停动画、关闭音效等
function UIView:OnHide()
end

---关闭回调：在关闭动画之前调用
---可在此方法中保存临时状态、取消订阅等
function UIView:OnClose()
end

---销毁回调：在释放引用之前调用
---必须在此方法中释放所有 Widget 引用和事件订阅
function UIView:OnDestroy()
    self.controller = nil
    self.gameObject = nil
    self.isCreated = false
end

return UIView