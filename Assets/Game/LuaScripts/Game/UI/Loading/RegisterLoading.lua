--[[
=============================================================================
RegisterLoading.lua - Loading 窗口注册
=============================================================================
Module:     Game/UI/Loading/RegisterLoading
Version:    2.0.0
Description:
    将 Loading 窗口注册到 UIManager（Prefab 模式）。
    Prefab 路径: UI/Loading/LoadingPanel（需在 Unity 中创建）

    Prefab 结构：
        LoadingPanel (root, include UIComponentBinder)
        ├── m_SliderBar    (Slider)
        ├── m_LoadingDesc  (Text)
        └── m_VersionText  (Text, optional)
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterLoading(uiManager)
    assert(uiManager, "UIManager instance is required")

    uiManager:RegisterWindow("Loading", {
        -- 基础配置
        layer = "Loading",
        windowType = UIEnums.WindowType.Loading,
        cachePolicy = UIEnums.CachePolicy.NeverDestroy,
        zonePolicy = UIEnums.ZonePolicy.IgnoreFocus,
        openMode = UIEnums.OpenMode.SingleTop,
        fullscreen = true,

        -- Prefab 路径
        prefab = "UI/Loading/LoadingPanel",

        -- MVC 模块路径
        model = "Game.UI.Loading.LoadingModel",
        view = "Game.UI.Loading.LoadingView",
        controller = "Game.UI.Loading.LoadingController",
    })
end

return RegisterLoading
