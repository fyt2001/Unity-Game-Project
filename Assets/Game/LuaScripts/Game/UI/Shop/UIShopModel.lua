--[[
=============================================================================
UIShopModel.lua - 主城商店（Shop）Model
=============================================================================
Module:     Game/UI/Shop/UIShopModel

Description:
	主城商店的纯数据层：读永久金币（SaveData.inventory.gold）、算售价、
	执行「金币换一张随机 Mod」。

	【金额真相在存档里】
	余额直接现读 SaveData.inventory.gold，不在 Model 里缓存一份副本 ——
	否则配装面板 / 局内结算改了钱，商店显示的就是旧数。

	【为什么商品是「随机 Mod」】
	用户 2026-10-02 拍板「金币买 Mod」＝金币换随机卡（不做卷轴售卖、
	不做玩家自选卡池）。随机卡的「预览」只能给到池子大小与价格，
	因此商品名显示「随机 Mod ×1（全池 N 种）」而不是假造一张具体卡名。

	【与局内商人的关系】
	局内 MerchantEvent 也卖随机 Mod（MOD_PRICE=300），花的是本次 Run 的
	loot.gold（未撤离会丢）；主城商店花的是永久 gold，价格同一个基准。
	两处各算各的，不互相读取对方的常量。

	【不做自动装配】
	与 P3-1 的配装面板一致：买到的 Mod 只进背包（ModInventory），
	由玩家自己回主城配装面板装 —— 装哪一槽、极性合不合都该玩家决定。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"
local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"
local MetaSystem = require "Game.Save.MetaSystem"
local ModInventory = require "Game.Mod.ModInventory"
local ModConfig = require "Game.Mod.ModConfig"

local UIShopModel = Class.Define("UIShopModel")
Class.Extend(UIShopModel, UIModel)
local base = UIModel

-- 单张基准价；与局内商人 MerchantEvent.MOD_PRICE 对齐（同为「金币换随机 Mod」）
local BASE_PRICE = 300

local BUY_COUNT_5 = 5

-- =============================================================================
-- 模块级纯函数
-- =============================================================================

---实际售价：受 Meta 天赋 M04「商谊」折扣影响（discount=0.10 表示 9 折）
---@param count number 购买张数
---@param discount number MetaSystem.GetShopDiscount() 返回值
local function priceOf(count, discount)
	return math.floor(BASE_PRICE * (count or 1) * (1 - (discount or 0)))
end

local function goldOf()
	local inv = SaveData.Get().inventory or {}
	return (inv.gold or 0)
end

-- =============================================================================
-- 构造函数
-- =============================================================================

---@param windowName string 由 UIWindowFactory 传入
function UIShopModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self._discount = 0
	self._price = BASE_PRICE
	self._price5 = BASE_PRICE * BUY_COUNT_5
	self._gold = 0
	self._itemName = ""
	self._itemDesc = ""
	self._goldText = ""
	self._resultText = ""

	-- 同配装面板：Ctor 末尾自播种，避免「首开时 View 读到空值画出一屏空白」
	self:Refresh()
end

-- =============================================================================
-- 查询
-- =============================================================================

function UIShopModel:GetGold()
	return self._gold
end

---商谊折扣：0 表示没有折扣（未点 M04）
function UIShopModel:GetDiscount()
	return self._discount
end

function UIShopModel:GetPrice()
	return priceOf(1, self:GetDiscount())
end

function UIShopModel:GetPrice5()
	return priceOf(BUY_COUNT_5, self:GetDiscount())
end

---当前金币买不买得起（View 用来置灰按钮，Controller 不用）
function UIShopModel:CanBuy(count)
	if SaveData.IsOnline() then
		local ok, session = pcall(require, "Game.Online.OnlineSession")
		if not ok or self._onlinePending then return false end
		local queried, busy = pcall(session.IsBusy)
		return queried and busy == false and (count == nil or count == 1 or count == 5)
	end
	return goldOf() >= priceOf(count or 1, self:GetDiscount())
end

function UIShopModel:SetPending(pending)
	self._onlinePending = pending == true
end

function UIShopModel:SetResult(text)
	self._resultText = text or ""
	return self
end

-- =============================================================================
-- 购买
-- =============================================================================

---执行购买：扣金币 + 发放随机 Mod + 落盘。
---先扣钱再发放，全发放失败则原额退回（不会出现「钱扣了卡没到」）。
---@param count number|nil 张数，默认 1
---@return boolean ok, string text 结果文案（供 View 显示回执）
function UIShopModel:Buy(count)
	if SaveData.IsOnline() then
		self:SetResult("在线购买由服务器处理")
		return false, "online_authority"
	end
	count = count or 1

	local inv = SaveData.Get().inventory or {}
	local gold = goldOf()
	local price = priceOf(count, self:GetDiscount())

	if gold < price then
		self._resultText = string.format("金币不足：需要 %d，余额 %d", price, gold)
		return false, self._resultText
	end

	inv.gold = gold - price
	SaveData.Commit()

	local names = {}
	local granted = 0
	for _ = 1, count do
		local got = ModInventory.GrantRandom(nil)
		if got then
			local cfg = ModConfig.Get(got.id)
			names[#names + 1] = string.format("%s R%d", cfg and cfg.name or tostring(got.id), got.rank or 1)
			granted = granted + 1
		end
	end

	if granted <= 0 then
		-- 全部发放失败：原额退回
		inv.gold = gold
		SaveData.Commit()
		self._resultText = "发货失败，已全额退款"
		Logger.Error("UIShop", "Grant all failed after charging %d, refunded", price)
		return false, self._resultText
	end

	self._resultText = string.format("购入 %s ×%d（-%d 金币，余额 %d）",
		table.concat(names, "、"), granted, price, inv.gold)

	Logger.Info("UIShop", "Bought %d mod(s) for %d gold, granted %d, gold left %d",
		count, price, granted, inv.gold)

	return true, self._resultText
end

-- =============================================================================
-- 渲染文案
-- =============================================================================

---把所有展示字段重新算一遍。字段式缓存（而不是 getter 每次现算）是为了
---「Ctor 末尾自播种」这一条成立：View 拿到的 Model 一定是非空自洽的。
function UIShopModel:Refresh()
	self._discount = MetaSystem.GetShopDiscount() or 0
	self._price = priceOf(1, self._discount)
	self._price5 = priceOf(BUY_COUNT_5, self._discount)
	self._gold = goldOf()

	local pool = 0
	if ModConfig.AllIds then pool = #ModConfig.AllIds end
	self._itemName = string.format("随机 Mod ×1（全池 %d 种）", pool)
	self._itemDesc = "随机发放一张永久 Mod，进背包；回主城配装面板自行安装"
	self._goldText = string.format("金币 %d", self._gold)

	return self
end

---商品名（随机卡只能给到池子大小）
function UIShopModel:GetItemName()
	return self._itemName
end

function UIShopModel:GetItemDesc()
	return self._itemDesc
end

function UIShopModel:GetGoldText()
	return self._goldText
end

function UIShopModel:GetDiscountText()
	local d = self._discount
	if d <= 0 then
		return "商谊天赋 M04：商店 9 折（未购买）"
	end
	return string.format("商谊 %.0f 折（每张省 %d 金币）", (1 - d) * 10, BASE_PRICE - self._price)
end

function UIShopModel:GetBuyLabel()
	return string.format("购买（%d 金币）", self._price)
end

function UIShopModel:GetBuy5Label()
	return string.format("一次买 %d 张（%d 金币）", BUY_COUNT_5, self._price5)
end

---清空回执。
---CacheOnClose 复用窗口时 UIManager 只走 OnRefresh（不会再触发 OnOpen），
---若不清，重开面板会挂着上一轮的「购入 ×1」旧提示，玩家会误以为刚又买了一次。
function UIShopModel:ClearResult()
	self._resultText = ""
	return self
end

function UIShopModel:GetResultText()
	return self._resultText or ""
end

return UIShopModel
