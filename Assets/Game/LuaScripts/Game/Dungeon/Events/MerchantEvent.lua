--[[
=============================================================================
MerchantEvent.lua - 商人事件
=============================================================================
Module:     Game/Dungeon/Events/MerchantEvent

行为（附录 K）：
	花局内金币购买回城卷轴（scroll.current+1）
	购买 Mod → 依赖 SaveData/ModInventory（P6），暂不提供

【注意】局内金币来自 RunData.loot.gold，未撤离前未入账，死亡即失。
	卷轴当前直接改 RunData.scroll；P4 的 ItemSystem 建成后收敛为统一入口。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"
local MetaSystem = require "Game.Save.MetaSystem"
local SaveData = require "Game.Save.SaveData"

local MerchantEvent = Class.Define("MerchantEvent")

local SCROLL_PRICE = 150
local MOD_PRICE = 300

---实际售价（受 Meta 天赋 M04「商谊」折扣影响）
function MerchantEvent:_price()
	local discount = MetaSystem.GetShopDiscount()
	return math.floor(SCROLL_PRICE * (1 - discount))
end

function MerchantEvent:Ctor()
	self.runData = nil
	self.ctx = nil
end

function MerchantEvent:Enter(runData, ctx)
	self.runData = runData
	self.ctx = ctx
	Logger.Info("MerchantEvent", "A hooded merchant offers his wares")
end

---弹窗展示文案（标题/正文），供 FloorEventPopup 显示
function MerchantEvent:GetDisplay()
	return {
		title = "商人",
		body = "一名兜帽商人向你兜售货物，是否交易？",
	}
end

function MerchantEvent:GetOptions()
	local rd = self.runData
	local gold = (rd and rd.loot and rd.loot.gold) or 0
	local sys = self.ctx and self.ctx.itemSystem

	-- 剩余容量：优先问 ItemSystem，没有则兜底读 RunData
	local hasRoom
	if sys then
		hasRoom = sys:GetScrollCount() < sys:GetScrollMax()
	else
		local sc = (rd and rd.scroll) or {}
		hasRoom = (sc.current or 0) < (sc.max or 0)
	end

	-- 金币不足或卷轴包已满 → enabled=false（供 UI 置灰；
	-- 无 UI 自动选第一项时也不会误买）
	local price = self:_price()
	local canBuy = (gold >= price) and hasRoom

	local modPrice = self:_modPrice()

	return {
		{ id = "buy_scroll", text = string.format("购买回城卷轴（%d 金币）", price), enabled = canBuy },
		-- P6：买 Mod（随机一张，直接进永久背包）
		{ id = "buy_mod", text = string.format("购买 Mod（%d 金币）", modPrice),
			enabled = not SaveData.IsOnline() and gold >= modPrice },
		{ id = "leave", text = "离开", enabled = true },
	}
end

---Mod 售价（同样受 M04 商谊折扣影响）
function MerchantEvent:_modPrice()
	return math.floor(MOD_PRICE * (1 - MetaSystem.GetShopDiscount()))
end

function MerchantEvent:Select(optionId)
	if optionId == "buy_mod" then
		return self:_buyMod()
	end

	if optionId ~= "buy_scroll" then return end
	if not self.runData then return end

	local loot = self.runData.loot
	local price = self:_price()
	if loot.gold < price then
		Logger.Info("MerchantEvent", "Not enough gold (%d < %d)", loot.gold, price)
		return
	end

	local sys = self.ctx and self.ctx.itemSystem
	if sys then
		-- P4：卷轴改动统一走 ItemSystem（不再直接改 RunData.scroll）
		if not sys:AddScroll(1) then
			Logger.Info("MerchantEvent", "Scroll bag full, purchase failed")
			return
		end
	else
		-- 兜底：正常流程不会发生（RollFloorEvent 总会带上 itemSystem）
		local sc = self.runData.scroll
		if (sc.current or 0) >= (sc.max or 0) then
			Logger.Info("MerchantEvent", "Scroll bag full (%d/%d)", sc.current, sc.max)
			return
		end
		sc.current = sc.current + 1
	end

	loot.gold = loot.gold - price
	Logger.Info("MerchantEvent", "Bought scroll for %d, gold left %d", price, loot.gold)
end

---购买 Mod（P6）：随机一张，直接进永久背包（SaveData.inventory.mods）
function MerchantEvent:_buyMod()
	if SaveData.IsOnline() then return false, "online_authority" end
	if not self.runData then return end

	local loot = self.runData.loot
	local price = self:_modPrice()
	if loot.gold < price then
		Logger.Info("MerchantEvent", "Not enough gold for mod (%d < %d)", loot.gold, price)
		return
	end

	local ModInventory = require "Game.Mod.ModInventory"
	local got = ModInventory.GrantRandom(nil)
	if not got then
		Logger.Warn("MerchantEvent", "Mod grant failed, purchase cancelled")
		return
	end
	-- P3-1 起【不再自动装配】：买到的 Mod 只进背包，等主城配装面板自己装
	loot.gold = loot.gold - price
	Logger.Info("MerchantEvent", "Bought mod uid=%d (id=%d) for %d, gold left %d",
		got.uid, got.id, price, loot.gold)
end

function MerchantEvent:Exit()
	self.runData = nil
	self.ctx = nil
end

return MerchantEvent
