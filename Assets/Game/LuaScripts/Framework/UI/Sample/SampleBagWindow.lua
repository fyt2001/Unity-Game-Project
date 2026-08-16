--[[
=============================================================================
SampleBagWindow.lua
=============================================================================
Module:     Framework/UI/Sample/SampleBagWindow
Version:    3.0.0
Author:     Framework Team
Status:     Sample (示例代码)
Target:     Unity + XLua

Description:
    SampleBagWindow 是背包窗口的完整示例，演示如何继承 UIWindow 并
    注册自定义 MVC 配置。生产项目中应替换为具体的 UIWindow 子类。

    MVC 结构：
        - SampleBagView: 绑定 UI 控件（关闭按钮、物品列表）
        - SampleBagController: 处理业务逻辑（物品增删、排序）
        - SampleBagModel: 管理背包数据（物品列表）

    配置示例：
        UIManager:RegisterConfig("Bag", {
            layer = "Normal",
            asset = "UI/Bag/BagWindow",
            view = "NewObject.Framework.UI.Sample.SampleBagView",
            controller = "NewObject.Framework.UI.Sample.SampleBagController",
            model = "NewObject.Framework.UI.Sample.SampleBagModel",
            cachePolicy = UIEnums.CachePolicy.CacheOnClose,
            openMode = UIEnums.OpenMode.SingleTop,
        })

Dependencies:
    - Class (类系统)
    - UIWindow (窗口基类)

Usage:
    通过 UIManager:Open("Bag") 打开窗口，框架自动创建 MVC 实例。
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIWindow = require "NewObject.Framework.UI.Core.UIWindow"

local SampleBagWindow = Class.Define("SampleBagWindow")
Class.Extend(SampleBagWindow, UIWindow)

---可以在构造函数中初始化窗口特有的属性
---@param name string 窗口名称
---@param config table 窗口配置
function SampleBagWindow:Ctor(name, config)
    UIWindow.Ctor(self, name, config)
end

return SampleBagWindow