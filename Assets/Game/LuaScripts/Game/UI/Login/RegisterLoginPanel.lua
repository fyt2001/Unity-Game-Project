--[[
=============================================================================
RegisterLoginPanel.lua - 登录面板注册
=============================================================================
Module:     Game/UI/Login/RegisterLoginPanel
Version:    1.0.0
Description:
    将 LoginPanel 窗口注册到 UIManager。
    Prefab 路径: UI/Login/LoginPanel（需在 Unity Assets/Resources 下创建）

    Prefab 结构（建议）：
        LoginPanel (root)
        ├── Background (Image)
        ├── LoginForm
        │   ├── Input_Account (InputField)
        │   ├── Input_Password (InputField)
        │   └── Btn_Login (Button)
        └── Btn_Exit (Button)
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterLoginPanel(uiManager)
    assert(uiManager, "UIManager instance is required")

    uiManager:RegisterWindow("LoginPanel", {
        -- 基础配置
        layer = "Normal",
        windowType = UIEnums.WindowType.Normal,
        cachePolicy = UIEnums.CachePolicy.CacheOnClose,
        zonePolicy = UIEnums.ZonePolicy.Default,
        openMode = UIEnums.OpenMode.SingleTop,
        fullscreen = false,

        -- Prefab 路径（需在 Unity Assets/Resources 下创建）
        prefab = "UI/Login/LoginPanel",

        -- MVC 模块路径
        model = "Game.UI.Login.LoginModel",
        view = "Game.UI.Login.LoginView",
        controller = "Game.UI.Login.LoginController",
    })
end

return RegisterLoginPanel