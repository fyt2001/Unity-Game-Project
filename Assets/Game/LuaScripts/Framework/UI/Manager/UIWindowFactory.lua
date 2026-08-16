--[[
=============================================================================
UIWindowFactory.lua
=============================================================================
Module:     Framework/UI/Manager/UIWindowFactory
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIWindowFactory 负责创建 UIWindow 实例及其 MVC 组件。
    工厂不打开、关闭、缓存或聚焦窗口，只负责实例化和绑定。

    创建流程：
        1. 创建 UIWindow 实例
        2. 从配置中解析 MVC 类路径
        3. 实例化 Model -> Controller -> View
        4. 绑定 Unity GameObject 到 Window
        5. 绑定 MVC 到 Window（建立双向引用）

Dependencies:
    - Class (类系统)
    - UIWindow (窗口基类)
    - UIView (视图基类)
    - UIController (控制器基类)
    - UIModel (模型基类)
    - UIResourceLoader (资源加载器)

Usage:
    local factory = UIWindowFactory.New(resourceLoader)
    local window = factory:CreateWindow("Bag", config)
    factory:CreateMVC(window, gameObject)
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local UIWindow = require "Framework.UI.Core.UIWindow"
local UIView = require "Framework.UI.Core.UIView"
local UIController = require "Framework.UI.Core.UIController"
local UIModel = require "Framework.UI.Core.UIModel"

local UIWindowFactory = Class.Define("UIWindowFactory")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化工厂依赖
---@param resourceLoader table UIResourceLoader 实例
function UIWindowFactory:Ctor(resourceLoader)
    self.resourceLoader = resourceLoader
end

-- =============================================================================
-- 私有方法：类解析
-- =============================================================================

---从配置中解析类路径，返回对应的类表
---如果未配置路径或路径为空，使用默认基类
---@param modulePath string|nil Lua 模块路径
---@param fallback table 默认基类
---@return table class 类表
local function ResolveClass(modulePath, fallback)
    if not modulePath or modulePath == "" then
        return fallback
    end
    local ok, result = pcall(require, modulePath)
    if not ok then
        error(string.format(
            "Failed to require UI module: %s\n%s",
            tostring(modulePath),
            tostring(result)
        ), 3)
    end
    return result
end

-- =============================================================================
-- 公共 API：创建窗口
-- =============================================================================

---创建空窗口实例（不包含 MVC）
---@param name string 窗口名称
---@param config table 窗口配置
---@return table window UIWindow 实例
function UIWindowFactory:CreateWindow(name, config)
    return UIWindow.New(name, config)
end

---创建 MVC 实例并绑定到窗口
---创建顺序：Model -> Controller -> View
---确保数据层先于展示层初始化
---@param window table UIWindow 实例
---@param gameObject any Unity GameObject
function UIWindowFactory:CreateMVC(window, gameObject)
    local config = window:GetConfig()

    -- 解析类
    local ModelClass = ResolveClass(config.model, UIModel)
    local ControllerClass = ResolveClass(config.controller, UIController)
    local ViewClass = ResolveClass(config.view, UIView)

    -- 创建 MVC 实例
    local model = ModelClass.New(window:GetName())
    local controller = ControllerClass.New(model)
    local view = ViewClass.New(window:GetName(), gameObject)

    -- 绑定到窗口
    window:AttachGameObject(gameObject)
    window:BindMVC(view, controller, model)
end

-- =============================================================================
-- 公共 API：销毁
-- =============================================================================

---销毁窗口的运行时 GameObject
---通过资源加载器释放 Unity 侧的实例
---@param window table UIWindow 实例
function UIWindowFactory:DestroyRuntimeObject(window)
    if window:GetGameObject() then
        self.resourceLoader:DestroyInstance(window:GetGameObject())
    end
end

return UIWindowFactory