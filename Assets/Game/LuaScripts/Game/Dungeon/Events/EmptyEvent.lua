--[[
=============================================================================
EmptyEvent.lua - 空事件
=============================================================================
Module:     Game/Dungeon/Events/EmptyEvent

行为（附录 K）：
	只有一段氛围文本，无奖惩。用于稀释事件密度，
	让「有奖励」的事件显得更珍贵。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"

local EmptyEvent = Class.Define("EmptyEvent")

function EmptyEvent:Ctor()
	self.runData = nil
	self.ctx = nil
end

function EmptyEvent:Enter(runData, ctx)
	self.runData = runData
	self.ctx = ctx
	Logger.Info("EmptyEvent", "Nothing but cold stone and the smell of old earth")
end

---弹窗展示文案（标题/正文），供 FloorEventPopup 显示
function EmptyEvent:GetDisplay()
	return {
		title = "空荡的石室",
		body = "只有冰冷的石头和陈土的腥味，什么都没有发生。",
	}
end

function EmptyEvent:GetOptions()
	return {
		{ id = "continue", text = "继续", enabled = true },
	}
end

function EmptyEvent:Select(optionId)
	-- 无效果
end

function EmptyEvent:Exit()
	self.runData = nil
	self.ctx = nil
end

return EmptyEvent
