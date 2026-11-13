--[[
=============================================================================
RegisterExtractConfirmPopup.lua - 撤离二次确认弹窗注册
=============================================================================
Module:     Game/UI/Battle/RegisterExtractConfirmPopup
Version:    1.0.0
Description:
	P2-4「撤离/死亡二次确认 + 暂停」：把 ExtractConfirmPopup 注册到 UIManager。

	Prefab 路径: UI/Battle/ExtractConfirmPopup（由 FloorEventPopup 派生）

	核心设计（与 PausePanel 一致）：
		- layer = "Popup"：盖在 BattleHudPanel（Normal 层）之上
		- fullscreen = true：模态期间吃满屏 Raycast
		- cachePolicy = CacheOnClose：复用实例
		- openMode = SingleTop：与其余战斗面板一致
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterExtractConfirmPopup(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("ExtractConfirmPopup", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = true,

		prefab = "UI/Battle/ExtractConfirmPopup",

		model = "Game.UI.Battle.UIExtractConfirmModel",
		view = "Game.UI.Battle.UIExtractConfirmView",
		controller = "Game.UI.Battle.UIExtractConfirmController",
	})
end

return RegisterExtractConfirmPopup
