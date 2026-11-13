--[[
=============================================================================
RegisterModStationPanel.lua - 配装面板注册（P3-1）
=============================================================================
Module:     Game/UI/Mod/RegisterModStationPanel

Description:
	把 ModStationPanel 注册到 UIManager。

	Prefab 路径: UI/Home/ModStationPanel
	（由 MCP 运行时构建于 2026-10-02，结构见 UIModStationView 头部说明。
	 本 prefab 未登记 UIComponentBinder 绑定项，View 走 FindGameObject +
	 GetComponent，因此无需在 Inspector 补绑定。）

	openMode = SingleTop：配装面板与主城面板是并列关系，
	不开配装时不影响主城（配装是叠在主城之上的 Popup，不是替换）；
	同时保证同名单例，重复点击只会刷新数据，不会叠出第二个面板。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterModStationPanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("ModStationPanel", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
	-- ⚠ 必须是 SingleTop：UIEnums.OpenMode 只有 Stack / Replace / SingleTop / RefreshIfOpen
	-- 四个键，**没有 Single**。写成 Single 会拿到 nil，
	-- 导致 UIManager:Open 里的 SingleTop 守卫生效不了（config.openMode == 3 不成立），
	-- 于是每次 Open 都新建窗口实例 —— 连点配装按钮会叠出一堆面板。
	-- SingleTop 语义：同名单例，加载中/已开/已隐藏都复用同一实例，只刷新数据。
	openMode = UIEnums.OpenMode.SingleTop,
	fullscreen = false,

		prefab = "UI/Home/ModStationPanel",

		model = "Game.UI.Mod.UIModStationModel",
		view = "Game.UI.Mod.UIModStationView",
		controller = "Game.UI.Mod.UIModStationController",
	})
end

return RegisterModStationPanel
