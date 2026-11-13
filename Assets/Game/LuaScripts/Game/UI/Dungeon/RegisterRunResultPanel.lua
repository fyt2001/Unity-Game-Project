--[[
=============================================================================
RegisterRunResultPanel.lua - 结算面板注册
=============================================================================
Module:     Game/UI/Dungeon/RegisterRunResultPanel

Description:
	把 RunResultPanel 注册到 UIManager。

	Prefab 路径: UI/Dungeon/RunResultPanel
	（以 FloorEventPopup.prefab 为骨架复制，结构：
	  root(800x560, RectTransform/Canvas/GraphicRaycaster/CanvasRenderer/Image)
	    + m_Title / m_Subtitle (TMP)
	    + m_FloorText / m_KillText / m_TimeText / m_GoldText / m_ItemText / m_FragText (TMP)
	    + m_LootLostText (TMP, 默认隐藏)
	    + m_ConfirmBtn (Image + Button + TMP)
	  TMP 已预置 LiberationSans SDF 字体）

	注意：本 prefab 未登记 UIComponentBinder 绑定项，
	View 用 FindGameObject + GetComponent 取组件，因此无需 Inspector 补绑定。

	对应总序 P2-1（结算面板 RunResultView）。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterRunResultPanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("RunResultPanel", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = false,

		prefab = "UI/Dungeon/RunResultPanel",

		model = "Game.UI.Dungeon.UIRunResultModel",
		view = "Game.UI.Dungeon.UIRunResultView",
		controller = "Game.UI.Dungeon.UIRunResultController",
	})
end

return RegisterRunResultPanel
