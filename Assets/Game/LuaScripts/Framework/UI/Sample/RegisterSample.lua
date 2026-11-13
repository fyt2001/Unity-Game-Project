--[[
=============================================================================
RegisterSample.lua
=============================================================================
Module:     Framework/UI/Sample/RegisterSample
Version:    3.0.0
Author:     Framework Team
Status:     Sample (示例代码)
Target:     Unity + XLua

Description:
	RegisterSample 是示例窗口注册脚本，演示如何将窗口配置注册到
	UIManager 中。生产项目中通常由配置管线自动生成。

	注册内容：
		- SampleBag: 背包窗口示例（Popup/Normal 层、CacheOnClose 缓存、SingleTop 打开模式）

	【重要】本样本仅供写法参考，**不可运行**：
		工程内不存在 Resources/UI/SampleBag.prefab，因此即使注册成功也无法 Open。
		需要可运行的活模板请直接看同在 Dungeon 下的：
			Game/UI/Dungeon/RegisterFloorEventPopup.lua
			Game/UI/Dungeon/RegisterRunResultPanel.lua

Dependencies:
	- UIFramework (框架入口)
	- UIEnums (枚举定义)

Usage:
	local RegisterSample = require "Framework.UI.Sample.RegisterSample"
	RegisterSample(uiManager)   -- uiManager 为 UIManager 实例
=============================================================================
]]

local UIEnums = require "Framework.UI.Config.UIEnums"

---注册示例窗口配置到 UIManager
---@param uiManager table UIManager 实例
local function RegisterSample(uiManager)
	assert(uiManager, "UIManager instance is required")
	assert(uiManager.RegisterWindow, "UIManager must have RegisterWindow method")

	-- 注册背包窗口
	uiManager:RegisterWindow("SampleBag", {
		prefab = "UI/SampleBag",
		layer = "Normal",
		openingLayer = "Normal",
		windowType = UIEnums.WindowType.Normal,
		cachePolicy = UIEnums.CachePolicy.CacheOnClose,
		zonePolicy = UIEnums.ZonePolicy.Normal,
		openMode = UIEnums.OpenMode.SingleTop,
		model = "Framework.UI.Sample.SampleBagModel",
		view = "Framework.UI.Sample.SampleBagView",
		controller = "Framework.UI.Sample.SampleBagController",
		fullscreen = true,
		blockInput = true,
	})
end

return RegisterSample