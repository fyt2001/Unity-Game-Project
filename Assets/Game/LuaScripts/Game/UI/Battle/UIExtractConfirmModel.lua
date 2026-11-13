--[[
=============================================================================
UIExtractConfirmModel.lua - 撤离二次确认 Model
=============================================================================
Module:     Game/UI/Battle/UIExtractConfirmModel

Description:
	P2-4「撤离/死亡二次确认 + 暂停」的产物。

	为什么要有这个二次确认：
		回城卷轴是本局【唯一稀缺资源】。改动前点 HUD 按钮直接消耗、
		立即结算，一次误触就毁掉一局且没有任何提示（总序 P2-4）。

	Model 只承载【确认那一刻的静态快照】，包括：
		- 卷轴：撤离前持有数 / 消耗数 / 撤离后剩余数
		- 预期收益：撤离能带出的渊获金币与记忆碎片

	数据由 DungeonManager:RequestExtract() 一次性喂入。UI 层不计算、
	不查询 Run 状态，保证「确认框上显示的数字」与「真正结算的数字」
	出自同一个 RunResult.Build —— 只是 outcome 固定为 Extract。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UIExtractConfirmModel = Class.Define("UIExtractConfirmModel")
Class.Extend(UIExtractConfirmModel, UIModel)
local base = UIModel

---@param windowName string 由 UIWindowFactory 传入
function UIExtractConfirmModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self.scrollBefore = 0
	self.scrollCost = 1
	self.gold = 0
	self.fragments = 0
	self.floor = 0
	self.killCount = 0
end

---由 Controller 在打开时填充（快照来自 DungeonManager:BuildExtractPreview()）
---@param data table { scrollBefore, gold, fragments, floor, killCount }
function UIExtractConfirmModel:SetConfirmData(data)
	data = data or {}
	self.scrollBefore = data.scrollBefore or 0
	self.gold = data.gold or 0
	self.fragments = data.fragments or 0
	self.floor = data.floor or 0
	self.killCount = data.killCount or 0
end

---确认框正文：卷轴消耗 + 剩余 + 本局收益
---@return table string[] 每行一条
function UIExtractConfirmModel:GetInfoLines()
	local left = self.scrollBefore - self.scrollCost
	if left < 0 then left = 0 end

	return {
		string.format("消耗回城卷轴 1 张（剩余 %d → %d）", self.scrollBefore, left),
		string.format("撤离后可带出渊获：%d", self.gold),
		string.format("获得记忆碎片：%d", self.fragments),
		string.format("当前进度：第 %d 层 / 击杀 %d", self.floor, self.killCount),
	}
end

return UIExtractConfirmModel
