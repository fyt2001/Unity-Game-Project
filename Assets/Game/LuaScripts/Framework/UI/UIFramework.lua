--[[
=============================================================================
UIFramework.lua
=============================================================================
Module:     Framework/UI/UIFramework
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIFramework 是 UI 框架的统一入口模块，游戏代码应通过此模块访问框架
    功能，而不是直接引用内部管理器。

    提供：
        - 框架核心模块引用（Class、Logger、UIEnums 等）
        - UIManager 工厂方法（Create）
        - 配置注册辅助方法

    设计原则：
        - 单一入口：游戏代码只依赖 UIFramework
        - 内部模块可替换：不暴露内部模块路径给游戏代码
        - 版本管理：框架版本号便于追踪兼容性

Dependencies:
    - 所有框架核心模块

Usage:
    local UI = require "NewObject.Framework.UI.UIFramework"
    local uiManager = UI.Create()
    uiManager:RegisterConfig("Bag", { ... })
    uiManager:Open("Bag", bagId)
=============================================================================
]]

local UIFramework = {}

-- =============================================================================
-- 框架版本
-- =============================================================================

UIFramework.Version = "3.0.0"

-- =============================================================================
-- 核心模块引用
-- =============================================================================

UIFramework.Class = require "NewObject.Framework.UI.Utils.Class"
UIFramework.Logger = require "NewObject.Framework.UI.Utils.Logger"
UIFramework.TableUtil = require "NewObject.Framework.UI.Utils.TableUtil"

UIFramework.UIEnums = require "NewObject.Framework.UI.Config.UIEnums"
UIFramework.UILayers = require "NewObject.Framework.UI.Config.UILayers"
UIFramework.UISettings = require "NewObject.Framework.UI.Config.UISettings"

UIFramework.UIState = require "NewObject.Framework.UI.Core.UIState"
UIFramework.UIView = require "NewObject.Framework.UI.Core.UIView"
UIFramework.UIModel = require "NewObject.Framework.UI.Core.UIModel"
UIFramework.UIController = require "NewObject.Framework.UI.Core.UIController"
UIFramework.UIWindow = require "NewObject.Framework.UI.Core.UIWindow"

UIFramework.UIManager = require "NewObject.Framework.UI.Manager.UIManager"

-- =============================================================================
-- 公共 API：工厂方法
-- =============================================================================

---创建 UIManager 实例
---游戏代码应通过此方法创建 UIManager，而不是直接调用 UIManager.New
---@param options table|nil 配置选项 { resourceLoader, animationManager, blockView }
---@return table manager UIManager 实例
function UIFramework.Create(options)
    return UIFramework.UIManager.New(options)
end

return UIFramework