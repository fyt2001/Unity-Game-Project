--[[
=============================================================================
UIWindow.lua
=============================================================================
Module:     Framework/UI/Core/UIWindow
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIWindow 是所有 UI 界面的唯一基类，负责单个逻辑窗口的生命周期编排。
    它是 MVC 三件套（UIView、UIController、UIModel）的容器和生命周期管理者。

    UIWindow 拥有：
        - 生命周期状态（UIState）
        - MVC 引用（View、Controller、Model）
        - 打开参数
        - 焦点/可见性标志
        - 所属 Zone 引用
        - 运行时 GameObject 引用
        - 用户自定义数据

    UIWindow 不拥有：
        - Prefab 加载（由 UIResourceLoader 负责）
        - 层级选择（由 UILayerManager 负责）
        - 焦点调度（由 UIZoneManager 负责）
        - 缓存策略（由 UIWindowCache 负责）
        - 堆栈排序（由 UIWindowStack 负责）
        - 业务逻辑（由 UIController 负责）

Lifecycle:
    None -> Loading -> Loaded -> Creating -> Created -> Opening -> Opened
    -> Focused -> Hidden -> Closing -> Closed -> Destroying -> Destroyed

Dependencies:
    - UIState (状态机)
    - Class (类系统)
    - Logger (日志系统)

Usage:
    Business code must NOT call UIWindow methods directly.
    Use UIManager:Open / UIManager:Close / UIManager:Refresh instead.
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local Logger = require "Framework.UI.Utils.Logger"
local UIState = require "Framework.UI.Core.UIState"

local UIWindow = Class.Define("UIWindow")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化 Window 的不可变元数据和运行时引用
---子类重写 Ctor 时必须调用父类 Ctor
---@param name string Window 唯一名称，由 UIWindowFactory 传入
---@param config table Window 静态配置，来自 UIWindowConfig
function UIWindow:Ctor(name, config)
    -- 不可变元数据
    self.name = name
    self.config = config

    -- 生命周期状态
    self.state = UIState.None

    -- MVC 引用
    self.view = nil
    self.controller = nil
    self.model = nil

    -- Unity 运行时引用
    self.gameObject = nil
    self.transform = nil

    -- Zone 与层级
    self.ownerZone = nil
    self.layerName = config and config.layer or nil

    -- 运行时参数
    self.openParams = nil
    self.closeReason = nil

    -- 状态标志
    self.created = false
    self.focused = false
    self.visible = false

    -- 异步加载令牌
    self.loadingToken = nil

    -- 用户自定义数据（业务层可自由扩展）
    self.userData = {}
end

-- =============================================================================
-- 公共 API：基本信息
-- =============================================================================

---返回 Window 唯一名称
---@return string name
function UIWindow:GetName()
    return self.name
end

---返回 Window 静态配置表
---@return table config
function UIWindow:GetConfig()
    return self.config
end

---返回当前层级名称
---@return string|nil layerName
function UIWindow:GetLayerName()
    return self.layerName
end

---返回打开时传入的参数
---@return table|nil openParams
function UIWindow:GetOpenParams()
    return self.openParams
end

---返回关闭原因
---@return string|nil reason
function UIWindow:GetCloseReason()
    return self.closeReason
end

---返回用户自定义数据表
---@return table userData
function UIWindow:GetUserData()
    return self.userData
end

-- =============================================================================
-- 公共 API：生命周期状态
-- =============================================================================

---返回当前生命周期状态值
---@return number state UIState 枚举值
function UIWindow:GetState()
    return self.state
end

---返回当前生命周期状态的可读名称
---@return string name
function UIWindow:GetStateName()
    return UIState.GetName(self.state)
end

---变更生命周期状态，内部会验证转换合法性
---非法转换将抛出错误，附带窗口名称和状态信息
---@param nextState number 目标 UIState 枚举值
function UIWindow:SetState(nextState)
    UIState.AssertTransition(self.state, nextState, self.name)
    local previous = self.state
    self.state = nextState
    Logger.Debug(string.format(
        "[Window] %s: %s -> %s",
        self.name,
        UIState.GetName(previous),
        UIState.GetName(nextState)
    ))
end

-- =============================================================================
-- 公共 API：生命周期状态判断
-- 所有状态判断委托给 UIState 模块，禁止直接比较状态数值
-- =============================================================================

---判断是否正在加载资源
---@return boolean result
function UIWindow:IsLoading()
    return UIState.IsLoading(self.state)
end

---判断资源是否已加载完成
---@return boolean result
function UIWindow:IsLoaded()
    return UIState.IsLoaded(self.state)
end

---判断是否正在创建
---@return boolean result
function UIWindow:IsCreating()
    return UIState.IsCreating(self.state)
end

---判断是否创建完成
---@return boolean result
function UIWindow:IsCreated()
    return UIState.IsCreated(self.state)
end

---判断是否正在打开动画
---@return boolean result
function UIWindow:IsOpening()
    return UIState.IsOpening(self.state)
end

---判断是否已打开（Opened 或 Focused）
---@return boolean result
function UIWindow:IsOpened()
    return UIState.IsOpened(self.state)
end

---判断是否获得焦点
---@return boolean result
function UIWindow:IsFocused()
    return UIState.IsFocused(self.state)
end

---判断是否被隐藏
---@return boolean result
function UIWindow:IsHidden()
    return UIState.IsHidden(self.state)
end

---判断是否正在关闭动画
---@return boolean result
function UIWindow:IsClosing()
    return UIState.IsClosing(self.state)
end

---判断是否已关闭
---@return boolean result
function UIWindow:IsClosed()
    return UIState.IsClosed(self.state)
end

---判断是否正在销毁
---@return boolean result
function UIWindow:IsDestroying()
    return UIState.IsDestroying(self.state)
end

---判断是否已销毁
---@return boolean result
function UIWindow:IsDestroyed()
    return UIState.IsDestroyed(self.state)
end

---判断是否处于活跃状态
---@return boolean result
function UIWindow:IsActive()
    return UIState.IsActive(self.state)
end

---判断是否处于过渡状态
---@return boolean result
function UIWindow:IsTransitioning()
    return UIState.IsTransitioning(self.state)
end

---判断是否可见
---@return boolean result
function UIWindow:IsVisible()
    return UIState.IsVisible(self.state)
end

-- =============================================================================
-- 公共 API：Unity 对象绑定
-- =============================================================================

---绑定 Unity GameObject 引用（资源加载完成后由 UIManager 调用）
---@param gameObject any Unity GameObject 或适配器对象
function UIWindow:AttachGameObject(gameObject)
    self.gameObject = gameObject
    if gameObject then
        self.transform = gameObject.transform
    else
        self.transform = nil
    end
end

---返回绑定的 Unity GameObject
---@return any|nil gameObject
function UIWindow:GetGameObject()
    return self.gameObject
end

---返回绑定的 Unity Transform
---@return any|nil transform
function UIWindow:GetTransform()
    return self.transform
end

-- =============================================================================
-- 公共 API：MVC 绑定
-- =============================================================================

---绑定 MVC 实例（由 UIWindowFactory 在创建时调用）
---同时建立 View 和 Controller 之间的双向引用
---@param view table UIView 实例
---@param controller table UIController 实例
---@param model table UIModel 实例
function UIWindow:BindMVC(view, controller, model)
    self.view = view
    self.controller = controller
    self.model = model

    -- 建立 View-Controller 双向绑定
    if self.view and self.view.BindController then
        self.view:BindController(controller)
    end
    if self.controller and self.controller.BindView then
        self.controller:BindView(view)
    end
end

---返回 View 实例
---@return table|nil view
function UIWindow:GetView()
    return self.view
end

---返回 Controller 实例
---@return table|nil controller
function UIWindow:GetController()
    return self.controller
end

---返回 Model 实例
---@return table|nil model
function UIWindow:GetModel()
    return self.model
end

-- =============================================================================
-- 公共 API：Zone 管理
-- =============================================================================

---设置所属 Zone
---@param zone table|nil Zone 实例
function UIWindow:SetOwnerZone(zone)
    self.ownerZone = zone
end

---返回所属 Zone
---@return table|nil zone
function UIWindow:GetOwnerZone()
    return self.ownerZone
end

-- =============================================================================
-- 生命周期阶段：Loading（异步加载）
-- =============================================================================

---标记资源加载开始，进入 Loading 状态
---由 UIManager 在发起异步加载时调用
---@param token table UIManager 创建的可取消加载令牌
function UIWindow:BeginLoading(token)
    self.loadingToken = token
    self:SetState(UIState.Loading)
end

---标记资源加载完成，进入 Loaded 状态
---由 UIManager 在资源回调中调用
function UIWindow:CompleteLoading()
    self.loadingToken = nil
    self:SetState(UIState.Loaded)
end

---取消正在进行的异步加载
---由 UIManager 在关闭加载中的窗口时调用
function UIWindow:CancelLoading()
    if self.loadingToken then
        self.loadingToken.cancelled = true
        self.loadingToken = nil
    end
end

-- =============================================================================
-- 生命周期阶段：Create（创建）
-- =============================================================================

---执行一次性的 MVC 创建回调
---依次调用 Model.OnCreate -> View.OnCreate -> Controller.OnCreate
---created 标志防止重复创建
function UIWindow:Create()
    if self.created then
        Logger.Warn(string.format("[Window] %s already created, skip", self.name))
        return
    end
    self:SetState(UIState.Creating)

    -- 按 Model -> View -> Controller 顺序调用，确保数据层先初始化
    if self.model and self.model.OnCreate then
        self.model:OnCreate()
    end
    if self.view and self.view.OnCreate then
        self.view:OnCreate()
    end
    if self.controller and self.controller.OnCreate then
        self.controller:OnCreate()
    end

    self.created = true
    self:SetState(UIState.Created)
end

-- =============================================================================
-- 生命周期阶段：Open（打开）
-- =============================================================================

---打开 Window 并传递参数给 MVC 组件
---依次调用 Model.OnOpen -> View.OnOpen -> Controller.OnOpen
---@param ... any 打开参数，由业务层传入
function UIWindow:Open(...)
    self.openParams = table.pack(...)
    self:SetState(UIState.Opening)
    self.visible = true

    -- 按 Model -> View -> Controller 顺序调用
    if self.model and self.model.OnOpen then
        self.model:OnOpen(...)
    end
    if self.view and self.view.OnOpen then
        self.view:OnOpen(...)
    end
    if self.controller and self.controller.OnOpen then
        self.controller:OnOpen(...)
    end

    self:SetState(UIState.Opened)
end

-- =============================================================================
-- 生命周期阶段：Refresh（刷新）
-- =============================================================================

---刷新已打开的 Window，传递新参数给 MVC 组件
---与 Open 不同，Refresh 不改变状态，仅在已打开窗口上更新数据
---@param ... any 刷新参数
function UIWindow:Refresh(...)
    if not self:IsOpened() then
        Logger.Warn(string.format(
            "[Window] %s is not opened, cannot refresh. Current state: %s",
            self.name,
            self:GetStateName()
        ))
        return
    end

    -- 按 Model -> View -> Controller 顺序调用
    if self.model and self.model.OnRefresh then
        self.model:OnRefresh(...)
    end
    if self.view and self.view.OnRefresh then
        self.view:OnRefresh(...)
    end
    if self.controller and self.controller.OnRefresh then
        self.controller:OnRefresh(...)
    end
end

-- =============================================================================
-- 生命周期阶段：Focus / Blur（焦点）
-- =============================================================================

---给予 Window 输入焦点
---只有 Opened 或 Hidden 状态的 Window 可以获取焦点
---已销毁的 Window 调用此方法无效果
function UIWindow:Focus()
    if UIState.IsDestroyed(self.state) then
        return
    end
    if self.state == UIState.Focused then
        return
    end
    if not (self.state == UIState.Opened or self.state == UIState.Hidden) then
        Logger.Warn(string.format(
            "[Window] %s cannot focus from state %s",
            self.name,
            self:GetStateName()
        ))
        return
    end

    -- Hidden 状态需要先恢复到 Opened
    if self.state == UIState.Hidden then
        self:SetState(UIState.Opening)
        self:SetState(UIState.Opened)
    end

    self:SetState(UIState.Focused)
    self.focused = true

    if self.view and self.view.OnFocus then
        self.view:OnFocus()
    end
end

---移除 Window 输入焦点，但不关闭 Window
---只有 Focused 状态的 Window 可以失去焦点
function UIWindow:Blur()
    if self.state ~= UIState.Focused then
        return
    end
    self.focused = false
    self:SetState(UIState.Hidden)

    if self.view and self.view.OnBlur then
        self.view:OnBlur()
    end
end

-- =============================================================================
-- 生命周期阶段：Hide（隐藏）
-- =============================================================================

---隐藏 Window，保持其存活以便后续重新显示
---Focused 或 Opened 状态的 Window 可被隐藏
---已销毁或已隐藏的 Window 调用此方法无效果
function UIWindow:Hide()
    if UIState.IsDestroyed(self.state) or self.state == UIState.Hidden then
        return
    end
    if self.state == UIState.Focused or self.state == UIState.Opened then
        self:SetState(UIState.Hidden)
    end
    self.visible = false
    self.focused = false

    if self.view and self.view.OnHide then
        self.view:OnHide()
    end
end

-- =============================================================================
-- 生命周期阶段：Close（关闭）
-- =============================================================================

---关闭 Window，释放活跃的订阅和计时器
---Loading 中的 Window 直接进入 Closed 状态
---Hidden 中的 Window 需要先 Closing -> Closed
---Created 中的 Window 需要先 Opening -> Opened -> Closing -> Closed
---@param reason string|nil 关闭原因，用于日志和分析
function UIWindow:Close(reason)
    if UIState.IsClosed(self.state) or self.state == UIState.Destroying then
        return
    end

    self.closeReason = reason

    -- Loading 状态：直接关闭，无需经过完整流程
    if self.state == UIState.Loading then
        self:CancelLoading()
        if self.controller and self.controller.OnClose then
            self.controller:OnClose()
        end
        if self.view and self.view.OnClose then
            self.view:OnClose()
        end
        if self.model and self.model.OnClose then
            self.model:OnClose()
        end
        self.visible = false
        self.focused = false
        self:SetState(UIState.Closed)
        return
    end

    -- 根据当前状态确定关闭路径
    if self.state == UIState.Hidden then
        self:SetState(UIState.Closing)
    elseif self.state == UIState.Opened or self.state == UIState.Focused or self.state == UIState.Opening then
        self:SetState(UIState.Closing)
    elseif self.state == UIState.Created then
        -- Created 状态需要先经过 Opened 再 Closing
        self:SetState(UIState.Opening)
        self:SetState(UIState.Opened)
        self:SetState(UIState.Closing)
    else
        self:SetState(UIState.Closing)
    end

    -- 通知 MVC 组件关闭
    if self.controller and self.controller.OnClose then
        self.controller:OnClose()
    end
    if self.view and self.view.OnClose then
        self.view:OnClose()
    end
    if self.model and self.model.OnClose then
        self.model:OnClose()
    end

    self.visible = false
    self.focused = false
    self:SetState(UIState.Closed)
end

-- =============================================================================
-- 生命周期阶段：Destroy（销毁）
-- =============================================================================

---销毁 Window，释放所有 MVC 引用和运行时对象
---如果 Window 尚未关闭，会先执行 Close 流程
---销毁后所有引用置空，Window 不可再使用
function UIWindow:Destroy()
    if UIState.IsDestroyed(self.state) then
        return
    end

    -- 确保先关闭
    if not UIState.IsClosed(self.state) then
        self:Close("Destroy")
    end

    self:SetState(UIState.Destroying)

    -- 按 Controller -> View -> Model 顺序销毁
    if self.controller and self.controller.OnDestroy then
        self.controller:OnDestroy()
    end
    if self.view and self.view.OnDestroy then
        self.view:OnDestroy()
    end
    if self.model and self.model.OnDestroy then
        self.model:OnDestroy()
    end

    -- 释放所有引用
    self.view = nil
    self.controller = nil
    self.model = nil
    self.gameObject = nil
    self.transform = nil
    self.ownerZone = nil
    self.loadingToken = nil
    self.openParams = nil
    self.closeReason = nil
    self.userData = nil
    self.config = nil

    self:SetState(UIState.Destroyed)
end

-- =============================================================================
-- 公共 API：调试
-- =============================================================================

---返回 Window 状态的调试快照
---@return string snapshot
function UIWindow:Snapshot()
    return string.format(
        "%s state=%s layer=%s zone=%s focused=%s visible=%s created=%s",
        self.name,
        self:GetStateName(),
        tostring(self.layerName),
        self.ownerZone and self.ownerZone:GetName() or "nil",
        tostring(self.focused),
        tostring(self.visible),
        tostring(self.created)
    )
end

return UIWindow