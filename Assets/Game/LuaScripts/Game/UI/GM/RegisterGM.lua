--[[
=============================================================================
RegisterGM.lua - GM 调试面板注册（S2：参数沿用现网，未擅自改动）
=============================================================================
Module:     Game.UI.GM.RegisterGM

注册参数（与 S1 之前现网一致，本次不改）：
  layer       = "Popup"
  windowType  = UIEnums.WindowType.Popup
  cachePolicy = UIEnums.CachePolicy.CacheOnClose
  zonePolicy  = UIEnums.ZonePolicy.Default
  openMode    = UIEnums.OpenMode.SingleTop
  fullscreen  = false
  prefab      = "UI/GM/GMPanel"
  model / view / controller = Game.UI.GM.UIGMModel / UIGMView / UIGMController

注意：UIEnums.OpenMode 只有 Stack / Replace / SingleTop / RefreshIfOpen，
      没有 Single 成员（写错会 nil 索引），故沿用 SingleTop。
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"
local GMConfig = require "Game.GM.GMConfig"

local function RegisterGM(uiManager)
	assert(uiManager, "UIManager instance is required")
	if not GMConfig.IsDev() then return end

	uiManager:RegisterWindow("GM", {
		layer = "Popup",
		windowType = UIEnums.WindowType.Popup,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Default,
		openMode = UIEnums.OpenMode.SingleTop,
		fullscreen = false,

		prefab = "UI/GM/GMPanel",

		model = "Game.UI.GM.UIGMModel",
		view = "Game.UI.GM.UIGMView",
		controller = "Game.UI.GM.UIGMController",
	})
end

return RegisterGM
