--[[
=============================================================================
TrapEvent.lua - 陷阱事件
=============================================================================
Module:     Game/Dungeon/Events/TrapEvent

行为（附录 K）：
	【进入即生效】立即扣血——陷阱不给玩家「选择躲开」的机会，
	符合贪婪洞窟的突发惩罚感。Select("continue") 只是确认继续。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"

local TrapEvent = Class.Define("TrapEvent")

local DMG_MIN = 10
local DMG_MAX = 30

function TrapEvent:Ctor()
	self.runData = nil
	self.ctx = nil
end

function TrapEvent:Enter(runData, ctx)
	self.runData = runData
	self.ctx = ctx

	local pc = ctx and ctx.playerController
	if pc then
		local dmg = math.random(DMG_MIN, DMG_MAX)
		pc:TakeDamage(dmg)
		Logger.Info("TrapEvent", "Trap! -%d hp (now %d/%d)", dmg, pc.hp, pc.maxHp)
	else
		Logger.Warn("TrapEvent", "No playerController, damage skipped")
	end
end

---弹窗展示文案（标题/正文），供 FloorEventPopup 显示
function TrapEvent:GetDisplay()
	return {
		title = "陷阱",
		body = "你踩中了隐藏的机关，已受到伤害！",
	}
end

function TrapEvent:GetOptions()
	return {
		{ id = "continue", text = "继续", enabled = true },
	}
end

function TrapEvent:Select(optionId)
	-- 伤害已在 Enter 结算，这里无需再处理
end

function TrapEvent:Exit()
	self.runData = nil
	self.ctx = nil
end

return TrapEvent
