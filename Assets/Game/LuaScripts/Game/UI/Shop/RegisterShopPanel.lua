--[[
=============================================================================
RegisterShopPanel.lua - 主城商店面板注册（P3-2）
=============================================================================
Module:     Game/UI/Shop/RegisterShopPanel

Description:
	把 ShopPanel 注册到 UIManager。

	Prefab 路径: UI/Home/ShopPanel
	（由 MCP 运行时构建于 2026-10-02，结构见 UIShopView 头部说明。
	 本 prefab 未登记 UIComponentBinder 绑定项，View 走 FindGameObject +
	 GetComponent，因此无需在 Inspector 补绑定。）

	openMode = SingleTop：商店与主城面板是并列关系（叠在之上的 Popup，
	不是替换主城），同时保证同名单例 —— 重复点商店按钮只会刷新数据，
	不会叠出第二个面板。

	【踩过的坑】UIEnums.OpenMode 只有 Stack / Replace / SingleTop / RefreshIfOpen
	四个键，**没有 Single**。写成 Single 会拿到 nil，导致 UIManager:Open 里的
	SingleTop 守卫生效不了（config.openMode == 3 不成立），每次 Open 都新建
	窗口实例。配装面板 RegisterModStationPanel 已踩过，此处不再重复。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

local function RegisterShopPanel(uiManager)
	assert(uiManager, "UIManager instance is required")

	uiManager:RegisterWindow("ShopPanel", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = false,

		prefab = "UI/Home/ShopPanel",

		model = "Game.UI.Shop.UIShopModel",
		view = "Game.UI.Shop.UIShopView",
		controller = "Game.UI.Shop.UIShopController",
	})
end

return RegisterShopPanel
