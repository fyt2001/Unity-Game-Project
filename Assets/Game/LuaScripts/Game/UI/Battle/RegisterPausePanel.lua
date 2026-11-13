--[[
=============================================================================
RegisterPausePanel.lua - 暂停菜单注册
=============================================================================
Module:     Game/UI/Battle/RegisterPausePanel
Version:    1.0.0
Description:
	P2-4「撤离/死亡二次确认 + 暂停」：把 PausePanel 注册到 UIManager。

	Prefab 路径: UI/Battle/PausePanel（由 FloorEventPopup 派生）

	核心设计：
		- layer = "Popup"：盖在 BattleHudPanel（Normal 层）之上
		- fullscreen = true：吃掉 Raycast，暂停时不会再误触摇杆/HUD 按钮
		- cachePolicy = CacheOnClose：频繁开关，复用实例
		- openMode = SingleTop：与 BattleHudPanel 一致，避免开出两个 Clone

	注意：本 prefab 继承自 FloorEventPopup 的 UIComponentBinder 绑定项，
	其中大部分已随节点删除而悬空。View 不用 AutoBind，改走
	FindGameObject + GetComponent（UIBaseContainer.AutoBind 有 null 防护）。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterPausePanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("PausePanel", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = true,

		prefab = "UI/Battle/PausePanel",

		model = "Game.UI.Battle.UIPauseModel",
		view = "Game.UI.Battle.UIPauseView",
		controller = "Game.UI.Battle.UIPauseController",
	})
end

return RegisterPausePanel
