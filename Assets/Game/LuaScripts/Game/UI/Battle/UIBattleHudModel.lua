--[[
=============================================================================
UIBattleHudModel.lua - 战斗 HUD 数据模型
=============================================================================
Module:     Game/UI/Battle/UIBattleHudModel
Version:    1.0.0
Description:
	P2-3「战斗 HUD 归位」的产物。

	【搬迁前是什么样】
		这批字段原先寄存在 UIHomeModel（主城 Model）里，由 UIHomeController
		每 0.5s 从 BattleManager 采样写入。也就是说：**主城的 Model 被战斗数据
		污染**，且 `SetExp` 写进去之后没有任何 UI 读它（UIHomeView:SetExp 是空实现，
		prefab 里也没有经验条节点）。

	【现在】
		连同采样逻辑一并回到战斗层，主城 Model 只剩玩家信息与货币。

	【承载内容（严格照搬现状，不新增）】
		- 等级 level
		- HP / maxHp
		- exp / expToNext（已接上 View 侧 m_ExpBar 经验条）

	核心设计：
		- 纯数据容器，不含任何业务逻辑
		- Setter 对 nil 做兜底
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UIBattleHudModel = Class.Define("UIBattleHudModel")
Class.Extend(UIBattleHudModel, UIModel)

function UIBattleHudModel:Ctor(windowName)
	self.super:Ctor(windowName)

	self.level = 1
	self.hp = 100
	self.maxHp = 100
	self.exp = 0
	self.expToNext = 100
end

function UIBattleHudModel:SetLevel(level)
	self.level = level or self.level
end

function UIBattleHudModel:SetHp(hp, maxHp)
	self.hp = hp or 0
	self.maxHp = maxHp or self.maxHp
end

---写入经验。View 侧已有 m_ExpBar 控件（BattleHudPanel.prefab，HP 条正上方），
---由 UIBattleHudController:_sampleBattleData 采样时一并刷新。
function UIBattleHudModel:SetExp(exp, expToNext)
	self.exp = exp or 0
	self.expToNext = expToNext or self.expToNext
end

function UIBattleHudModel:GetLevel() return self.level end
function UIBattleHudModel:GetHp() return self.hp end
function UIBattleHudModel:GetMaxHp() return self.maxHp end
function UIBattleHudModel:GetExp() return self.exp end
function UIBattleHudModel:GetExpToNext() return self.expToNext end

return UIBattleHudModel
