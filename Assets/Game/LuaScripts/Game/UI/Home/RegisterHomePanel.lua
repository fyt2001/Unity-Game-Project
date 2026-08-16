--[[
=============================================================================
RegisterHomePanel.lua - 主城面板注册
=============================================================================
Module:     Game/UI/Home/RegisterHomePanel
Version:    1.0.0
Description:
    将 HomePanel 窗口注册到 UIManager。
    Prefab 路径: UI/Home/HomePanel（需在 Unity Assets/Resources 下创建）

    Prefab 结构（建议）：
        HomePanel (root)
        ├── Header
        │   ├── Avatar (Image)
        │   ├── Name (Text)
        │   └── Level (Text)
        ├── MenuButtons
        │   ├── Btn_Battle (Button)
        │   ├── Btn_Bag (Button)
        │   ├── Btn_Shop (Button)
        │   └── Btn_Settings (Button)
        └── Footer
            └── ResourceBar
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterHomePanel(uiManager)
    assert(uiManager, "UIManager instance is required")

    uiManager:RegisterWindow("HomePanel", {
        -- 基础配置
        layer = "Normal",
        windowType = UIEnums.WindowType.Normal,
        cachePolicy = UIEnums.CachePolicy.CacheOnClose,
        zonePolicy = UIEnums.ZonePolicy.Default,
        openMode = UIEnums.OpenMode.SingleTop,
        fullscreen = false,

        -- Prefab 路径（需在 Unity Assets/Resources 下创建）
        prefab = "UI/Home/HomePanel",

        -- MVC 模块路径
        model = "Game.UI.Home.HomeModel",
        view = "Game.UI.Home.HomeView",
        controller = "Game.UI.Home.HomeController",
    })
end

return RegisterHomePanel