--[[
=============================================================================
RegisterBattleHudPanel.lua - 战斗 HUD 面板注册
=============================================================================
Module:     Game/UI/Battle/RegisterBattleHudPanel
Version:    1.0.0
Description:
	P2-3「战斗 HUD 归位」：把 BattleHudPanel 注册到 UIManager。

	BattleHudPanel 是战斗期间专用的 HUD 层，包含：
		- TopBar/m_Level：等级
		- m_HpBar：HP 条（Slider）+ m_HpText
		- m_ReturnScrollBtn：回城卷轴（仅在战斗中且有卷轴时显示）
		- BottomBar/JoystickArea/m_JoystickBg：摇杆（VirtualJoystick）

	Prefab 路径: UI/Battle/BattleHudPanel
	（由 MCP 运行时以 HomePanel 为骨架复制改造而来）

	注意：本 prefab 上的 UIComponentBinder 绑定项继承自 HomePanel，其中
	m_HpBar_Sld / m_HpText_Txt 之外的大多已随节点删除而悬空。View 不用
	AutoBind，改走 FindGameObject + GetComponent，无需 Inspector 补绑定。
	（UIBaseContainer.AutoBind 有 null 防护，悬空项会被静默跳过。）

	核心设计：
		- layer = "Normal"：挂载到 NormalLayer Canvas
		- cachePolicy = CacheOnClose：关闭时缓存，避免重复加载
		- fullscreen = true：HUD 覆盖全屏，保证摇杆能吃到 Raycast
		- openMode = SingleTop：与 HomePanel 一致，避免开出两个 Clone
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterBattleHudPanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("BattleHudPanel", {
		layer = "Normal",
		windowType = UIEnums.WindowType.Normal,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		-- HUD may finish loading after a modal; it must not steal its focus.
		zonePolicy = UIEnums.ZonePolicy.Keep,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = true,

		prefab = "UI/Battle/BattleHudPanel",

		model = "Game.UI.Battle.UIBattleHudModel",
		view = "Game.UI.Battle.UIBattleHudView",
		controller = "Game.UI.Battle.UIBattleHudController",
	})
end

return RegisterBattleHudPanel
