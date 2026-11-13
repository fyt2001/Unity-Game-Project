--[[
=============================================================================
RegisterLevelUpPopup.lua - 升级三选一弹窗注册
=============================================================================
Module:     Game/UI/Dungeon/RegisterLevelUpPopup

Description:
	把 LevelUpPopup 注册到 UIManager。

	Prefab 路径: UI/Dungeon/LevelUpPopup
	（以 FloorEventPopup.prefab 为骨架复制，结构：
	  root
	    + m_Title / m_Subtitle (TMP)
	    + m_OptionBtn0 ~ m_OptionBtn2 (Image + Button + TMP)
	  Button 与 TMP 均从骨架继承，TMP 字体已预置 LiberationSans SDF）

	注意：本 prefab 未登记 UIComponentBinder 绑定项，
	View 用 FindGameObject + GetComponent 取组件，因此无需 Inspector 补绑定。

	CacheOnClose：连升多级时会连续多次打开同一个面板，
	缓存可避免每级都重新加载 prefab。

	对应总序 P2-2（升级三选一弹窗 LevelUpPopup）。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterLevelUpPopup(uiManager)
	assert(uiManager, "UIManager instance is required")
	assert(uiManager.RegisterWindow, "UIManager must have RegisterWindow method")

	uiManager:RegisterWindow("LevelUpPopup", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = false,

		prefab = "UI/Dungeon/LevelUpPopup",

		model = "Game.UI.Dungeon.UILevelUpModel",
		view = "Game.UI.Dungeon.UILevelUpView",
		controller = "Game.UI.Dungeon.UILevelUpController",
	})
end

return RegisterLevelUpPopup
