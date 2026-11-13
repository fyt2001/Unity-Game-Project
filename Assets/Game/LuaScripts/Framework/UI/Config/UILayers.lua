--[[
=============================================================================
UILayers.lua
=============================================================================
Module:     Framework/UI/Config/UILayers
Version:    3.1.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
	UILayers 定义 UI 层级配置，决定每个 Canvas 的渲染顺序和层间距。
	层级顺序从低到高：Scene < Background < Normal < Popup < Toast < Guide < Top < Debug

	每个层级定义：
		- name: 层级显示名称
		- order: 基础排序值（用于 Canvas.sortingOrder）
		- planeDistance: 平面距离（控制 3D 空间中的 z 轴偏移）

Dependencies:
	无外部依赖

Usage:
	local layers = require "Framework.UI.Config.UILayers"
	local normalOrder = layers.Normal.order
=============================================================================
]]

local UILayers = {
	Scene = {
		name = "Scene",
		order = 0,
		planeDistance = 1000,
	},

	Background = {
		name = "Background",
		order = 1000,
		planeDistance = 900,
	},

	Normal = {
		name = "Normal",
		order = 3000,
		planeDistance = 700,
	},

	Popup = {
		name = "Popup",
		order = 4000,
		planeDistance = 600,
	},

	Toast = {
		name = "Toast",
		order = 5000,
		planeDistance = 500,
	},

	Guide = {
		name = "Guide",
		order = 5500,
		planeDistance = 450,
	},

	Loading = {
		name = "Loading",
		order = 5800,
		planeDistance = 420,
	},

	Top = {
		name = "Top",
		order = 6000,
		planeDistance = 400,
	},

	Debug = {
		name = "Debug",
		order = 7000,
		planeDistance = 300,
	},
}

---返回所有层级键名列表
---@return table keys 层级键名数组
function UILayers.GetLayerKeys()
	return { "Scene", "Background", "Normal", "Popup", "Toast", "Guide", "Loading", "Top", "Debug" }
end

---返回层级数量
---@return number count
function UILayers.GetLayerCount()
	return 9
end

return UILayers