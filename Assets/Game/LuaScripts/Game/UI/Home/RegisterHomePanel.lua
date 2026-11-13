--[[
=============================================================================
RegisterHomePanel.lua - 主界面面板注册（俯视角战斗 HUD + 摇杆）
=============================================================================
Module:     Game/UI/Home/RegisterHomePanel
Version:    2.0.0
Description:
	将 HomePanel 窗口注册到 UIManager。
	HomePanel 是主界面的 HUD 层，包含：
		- TopBar：玩家名、等级、金币、宝石
		- CenterArea：奖杯
		- BottomBar：摇杆（VirtualJoystick）、商店按钮、配装按钮

	Prefab 路径: UI/Home/HomePanel（AssetBundle: ui/homepanel.asset）

	Prefab 结构：
		HomePanel (root, RectTransform 全屏)
		├── TopBar
		│   ├── m_PlayerName (Text)
		│   ├── m_Level (Text)
		│   ├── m_Gold (Text)
		│   └── m_Gem (Text)
		├── CenterArea
		│   └── m_Trophy (Text)          # 战斗按钮已下线，玩法入口改为场景洞口
		├── BottomBar
		│   ├── JoystickArea
		│   │   ├── m_JoystickBg (Image, VirtualJoystick)
		│   │   │   └── Handle (Image)
		│   └── m_ShopBtn (Button)
		└── m_HpBar (Slider)
			├── Fill
			└── m_HpText (Text)

	核心设计（腾讯大厂级）：
		- fullscreen = true：HomePanel 覆盖全屏，作为战斗 HUD
		- layer = "Normal"：挂载到 NormalLayer Canvas
		- cachePolicy = CacheOnClose：关闭时缓存，避免重复加载
		- zonePolicy = Default：参与焦点管理
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterHomePanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("HomePanel", {
		layer = "Normal",
		windowType = UIEnums.WindowType.Normal,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = true,

		prefab = "UI/Home/HomePanel",

		model = "Game.UI.Home.UIHomeModel",
		view = "Game.UI.Home.UIHomeView",
		controller = "Game.UI.Home.UIHomeController",
	})
end

return RegisterHomePanel