--[[
=============================================================================
RegisterFloorEventPopup.lua - 层间事件弹窗注册
=============================================================================
Module:     Game/UI/Dungeon/RegisterFloorEventPopup

Description:
	把 FloorEventPopup 注册到 UIManager。

	Prefab 路径: UI/Dungeon/FloorEventPopup
	（由 MCP 运行时创建，结构：root(Canvas/GraphicRaycaster/Image)
	  + m_EventTitle/m_EventBody(TMP) + m_OptionBtn0~2(Image+Button)）

	注意：本 prefab 未登记 UIComponentBinder 绑定项，
	View 用 FindGameObject + GetComponent 取组件，因此无需 Inspector 补绑定。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterFloorEventPopup(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("FloorEventPopup", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = false,

		prefab = "UI/Dungeon/FloorEventPopup",

		model = "Game.UI.Dungeon.UIFloorEventModel",
		view = "Game.UI.Dungeon.UIFloorEventView",
		controller = "Game.UI.Dungeon.UIFloorEventController",
	})
end

return RegisterFloorEventPopup
