--[[
=============================================================================
UIHomeModel.lua - 主界面数据模型（主城菜单）

	P2-3「战斗 HUD 归位」：HP / Exp / 战斗统计已迁到 Game/UI/Battle/
	UIBattleHudModel。本 Model 只保留主城真正会显示的玩家信息与货币。
=============================================================================
Module:     Game/UI/Home/UIHomeModel
Version:    2.0.0
Description:
	主界面数据模型，包含：
		- 玩家信息（名称、等级）
		- 货币（金币、宝石）

	核心设计（腾讯大厂级）：
		- 展示数据快照，金币只读采样 SaveData
		- 姓名与等级仅为传入展示信息，非持久化账号数据
		- 默认值防御：所有 Setter 对 nil 做兜底
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"
local SaveData = require "Game.Save.SaveData"

local UIHomeModel = Class.Define("UIHomeModel")
Class.Extend(UIHomeModel, UIModel)

function UIHomeModel:Ctor(windowName)
	self.super:Ctor(windowName)

	self.playerName = "旅人"
	self.playerLevel = 1
	self.gold = 0
	self.diamond = 0
end

function UIHomeModel:SetPlayerInfo(name, level)
	self.playerName = name or "旅人"
	self.playerLevel = level or 1
end

-- Display snapshot only; SaveData owns currency and persistence.
function UIHomeModel:RefreshCurrency()
	local inventory = SaveData.Get().inventory or {}
	local gold = inventory.gold or 0
	local changed = self.gold ~= gold
	self.gold = gold
	return changed
end

function UIHomeModel:SetCurrency(gold, diamond)
	self.gold = gold or 0
	self.diamond = diamond or 0
end

function UIHomeModel:GetPlayerName() return self.playerName end
function UIHomeModel:GetPlayerLevel() return self.playerLevel end
function UIHomeModel:GetGold() return self.gold end
function UIHomeModel:GetDiamond() return self.diamond end
return UIHomeModel
