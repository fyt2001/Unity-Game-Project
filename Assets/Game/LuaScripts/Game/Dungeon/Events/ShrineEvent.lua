--[[
=============================================================================
ShrineEvent.lua - 祭坛事件
=============================================================================
Module:     Game/Dungeon/Events/ShrineEvent

行为（附录 K）：
	祈祷 → 回复 20% 最大生命
	强化 → 随机已拥有 Mod 的 rank+1（依赖 ModInventory，P6）

【自适应选项】GetOptions 会检查是否拥有 mod，没有则不返回「强化」选项，
	避免出现点了没反应的死选项。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"

local ShrineEvent = Class.Define("ShrineEvent")

local PRAY_HEAL_RATIO = 0.20

function ShrineEvent:Ctor()
	self.runData = nil
	self.ctx = nil
	self._done = false
end

function ShrineEvent:Enter(runData, ctx)
	self.runData = runData
	self.ctx = ctx
	self._done = false
	Logger.Info("ShrineEvent", "A shrine of the buried ones")
end

---弹窗展示文案（标题/正文），供 FloorEventPopup 显示
function ShrineEvent:GetDisplay()
	return {
		title = "祭坛",
		body = "埋骨者的祭坛静默矗立，似乎在等待献祭或祈祷。",
	}
end

---是否拥有【可升级】的 Mod（P6 接 ModInventory）
-- 注意是「可升级」而不是「拥有」：全都满级时提供该选项会变成点了没反应的死选项。
function ShrineEvent:_hasMods()
	if SaveData.IsOnline() then return false end
	local ModInventory = require "Game.Mod.ModInventory"
	for _, m in ipairs(ModInventory.GetAll()) do
		if ModInventory.CanUpgrade(m) then return true end
	end
	return false
end

function ShrineEvent:GetOptions()
	local opts = {
		{ id = "pray", text = "祈祷（回复 20% 生命）", enabled = not self._done },
	}

	-- 仅在真的拥有 mod 时才提供「强化」，避免死选项
	if self:_hasMods() then
		opts[#opts + 1] = { id = "fortify", text = "强化一件 Mod（等级+1）", enabled = not self._done }
	end

	opts[#opts + 1] = { id = "leave", text = "离开", enabled = true }
	return opts
end

function ShrineEvent:Select(optionId)
	if optionId == "fortify" and SaveData.IsOnline() then return false, "online_authority" end
	if self._done then return end

	if optionId == "pray" then
		self._done = true
		local pc = self.ctx and self.ctx.playerController
		if pc then
			pc:Heal(pc.maxHp * PRAY_HEAL_RATIO)
			Logger.Info("ShrineEvent", "Pray: hp now %d/%d", pc.hp, pc.maxHp)
		else
			Logger.Warn("ShrineEvent", "Pray skipped: no playerController")
		end
	elseif optionId == "fortify" then
		self._done = true
		local ModInventory = require "Game.Mod.ModInventory"
		local up = ModInventory.UpgradeRandom()
		if up then
			Logger.Info("ShrineEvent", "Fortify: mod uid=%d -> rank %d", up.uid, up.rank)
		else
			Logger.Info("ShrineEvent", "Fortify: no upgradable mod")
		end
	end
end

function ShrineEvent:Exit()
	self.runData = nil
	self.ctx = nil
end

return ShrineEvent
