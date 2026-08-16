--[[
=============================================================================
UIModel.lua
=============================================================================
Module:     Framework/UI/Core/UIModel
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIModel 是所有 UI 数据模型的基类，负责管理 UI 显示数据和游戏数据订阅。
    Model 是 UI 层的数据抽象，隔离了游戏数据和 UI 显示逻辑。

    Model 禁止：
        - 依赖 View 或 Unity 对象
        - 直接操作 UI 组件
        - 发送网络请求
        - 管理层级或焦点

Dependencies:
    - Class (类系统)

Lifecycle Callbacks:
    OnCreate()      - 一次性初始化数据结构
    OnOpen(...)     - 打开时根据参数初始化数据
    OnRefresh(...)  - 数据刷新时更新模型数据
    OnClose()       - 关闭时清理临时数据
    OnDestroy()     - 销毁前释放所有引用

Usage:
    local SampleBagModel = Class.Define("SampleBagModel", UIModel)
    function SampleBagModel:OnOpen(bagId)
        self.bagId = bagId
        self.items = GameDataService:GetBagItems(bagId)
    end
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"

local UIModel = Class.Define("UIModel")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化 Model 标识和生命周期标志
---子类重写 Ctor 时必须调用父类 Ctor
---@param windowName string 所属 Window 名称
function UIModel:Ctor(windowName)
    self.windowName = windowName
    self.active = false
    self.isCreated = false
end

-- =============================================================================
-- 公共 API：访问
-- =============================================================================

---获取所属 Window 名称
---@return string windowName
function UIModel:GetWindowName()
    return self.windowName
end

---返回 Model 是否处于活跃状态
---@return boolean active
function UIModel:IsActive()
    return self.active
end

-- =============================================================================
-- 生命周期回调
-- 子类重写这些方法以实现具体数据管理
-- =============================================================================

---一次性创建回调：初始化数据结构
---在此方法中初始化列表、字典等数据容器
function UIModel:OnCreate()
    self.isCreated = true
end

---打开回调：根据打开参数初始化数据
---在此方法中根据参数从游戏服务获取数据
---@param ... any 打开参数
function UIModel:OnOpen(...)
    self.active = true
end

---刷新回调：更新模型数据
---在此方法中根据新的刷新参数更新数据
---@param ... any 刷新参数
function UIModel:OnRefresh(...)
end

---关闭回调：清理临时数据
---在此方法中清理 UI 专用的临时数据，但保留可缓存数据
function UIModel:OnClose()
    self.active = false
end

---销毁回调：释放所有数据引用
---必须在此方法中释放所有外部数据引用
function UIModel:OnDestroy()
    self.active = false
    self.isCreated = false
end

return UIModel