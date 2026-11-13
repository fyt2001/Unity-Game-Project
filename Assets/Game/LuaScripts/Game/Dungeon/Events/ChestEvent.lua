--[[
=============================================================================
ChestEvent.lua - 宝箱事件
=============================================================================
Module:     Game/Dungeon/Events/ChestEvent

行为（附录 K）：
	开箱 → 金币 + 概率材料；mod 掉落依赖 SaveData（P5）/ ModInventory（P6），
	字段与分支已就位，P6 启用。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"

local ChestEvent = Class.Define("ChestEvent")

local MATERIALS = { "bone", "rust", "crystal" }

function ChestEvent:Ctor()
	self.runData = nil
	self.ctx = nil
	self._done = false
end

function ChestEvent:Enter(runData, ctx)
	self.runData = runData
	self.ctx = ctx
	self._done = false
	Logger.Info("ChestEvent", "A chest lies buried in the rubble")
end

---弹窗展示文案（标题/正文），供 FloorEventPopup 显示
function ChestEvent:GetDisplay()
	return {
		title = "宝箱",
		body = "废墟之中埋着一只布满锈痕的宝箱，要打开它吗？",
	}
end

function ChestEvent:GetOptions()
	return {
		{ id = "open",  text = "开箱", enabled = not self._done },
		{ id = "leave", text = "离开", enabled = true },
	}
end

function ChestEvent:Select(optionId)
	if optionId ~= "open" or self._done then return end
	self._done = true
	if not self.runData then return end

	local gold = math.random(50, 150)
	self.runData.loot.gold = self.runData.loot.gold + gold

	if math.random() < 0.5 then
		local mat = MATERIALS[math.random(1, #MATERIALS)]
		table.insert(self.runData.loot.materials, mat)
		Logger.Info("ChestEvent", "Opened: +%d gold, material=%s", gold, mat)
	else
		Logger.Info("ChestEvent", "Opened: +%d gold", gold)
	end

	-- mod 掉落：待 P6（SaveData.inventory.mods）接入后启用
end

function ChestEvent:Exit()
	self.runData = nil
	self.ctx = nil
end

return ChestEvent
