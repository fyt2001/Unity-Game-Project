--[[
=============================================================================
RegisterLoginPanel.lua - 登录面板注册（参考 ShaoNvClient_H02 UIWindowNames / UIConfigMap）
=============================================================================
Module:     Game/UI/Login/RegisterLoginPanel
Version:    2.0.0
Description:
	将 LoginPanel 窗口注册到 UIManager。
	窗口名对齐 H02 的 UIWindowNames.UILogin = "UILogin"。
	Prefab 路径: UI/Login/LoginPanel（位于 Assets/Game/Resources/ 下）

	Prefab 结构（对齐 H02 UILogin.prefab）:
		LoginPanel (root, tag:"UI")
		├── BgRoot
		│   ├── BG_Image
		│   └── Logo
		├── ContentRoot
		│   ├── m_LoginBtn      (Button, tag:"UIEvent")
		│   ├── m_Loading
		│   ├── SvrRoot
		│   │   └── m_SvrSelectBtn -> m_SvrText
		│   ├── m_AppVersionText
		│   ├── m_ResVersionText
		│   ├── m_VersionContent
		│   ├── m_BtnTerms
		│   └── m_BtnPrivacy
		├── PolicyRoot
		└── m_BtnClose

	生成: Unity Editor -> Tools -> Create LoginPanel Prefab
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterLoginPanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("LoginPanel", {
		layer = "Normal",
		windowType = UIEnums.WindowType.Normal,
		-- 登录面板为一次性界面，关闭后必须真正销毁 GameObject（否则只缓存不隐藏，
		-- 面板会一直挂在 UIRoot/Normal 层全屏可见，盖住 HomePanel）。
		cachePolicy = UIEnums.CachePolicy.DestroyOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = true,

		prefab = "UI/Login/LoginPanel",

		model = "Game.UI.Login.UILoginModel",
		view = "Game.UI.Login.UILoginView",
		controller = "Game.UI.Login.UILoginController",
	})
	CS.UnityEngine.Debug.Log("[LoginPanel] RegisterLoginPanel: 窗口已注册 -> LoginPanel")
end

return RegisterLoginPanel