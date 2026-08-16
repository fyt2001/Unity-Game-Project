--[[
=============================================================================
RegisterSample.lua
=============================================================================
Module:     Framework/UI/Sample/RegisterSample
Version:    3.0.0
Author:     Framework Team
Status:     Sample (示例代码)
Target:     Unity + XLua

Description:
    RegisterSample 是示例窗口注册脚本，演示如何将窗口配置注册到
    UIManager 中。生产项目中通常由配置管线自动生成。

    注册内容：
        - SampleBag: 背包窗口示例（Normal 层、CacheOnClose 缓存、SingleTop 打开模式）

Dependencies:
    - UIFramework (框架入口)
    - UIEnums (枚举定义)

Usage:
    local RegisterSample = require "Framework.UI.Sample.RegisterSample"
    RegisterSample(uiManager)
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

---注册示例窗口配置到 UIManager
---@param uiManager table UIManager 实例
local function RegisterSample(uiManager)
    assert(uiManager, "UIManager instance is required")
    assert(uiManager.RegisterConfig, "UIManager must have RegisterConfig method")

    -- 注册背包窗口
    uiManager:RegisterConfig("SampleBag", {
        asset = "UI/SampleBag",
        layer = "Normal",
        openingLayer = "Normal",
        windowType = UIEnums.WindowType.Normal,
        cachePolicy = UIEnums.CachePolicy.CacheOnClose,
        zonePolicy = UIEnums.ZonePolicy.Normal,
        openMode = UIEnums.OpenMode.SingleTop,
        model = "Framework.UI.Sample.SampleBagModel",
        view = "Framework.UI.Sample.SampleBagView",
        controller = "Framework.UI.Sample.SampleBagController",
        fullscreen = true,
        blockInput = true,
    })
end

return RegisterSample