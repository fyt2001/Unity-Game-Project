--[[
=============================================================================
ItemSystem.lua - 道具系统（回城卷轴统一入口）
=============================================================================
Module:     Game/Dungeon/ItemSystem
Version:    1.0.0

Description:
	回城卷轴的【唯一】读写入口。

	为什么需要它：
	  P3 的 MerchantEvent 直接改 RunData.scroll，属于「逻辑散落」。
	  卷轴是核心资源（设计稿 §11），获取途径有多种
	  （初始 / 每5层保底 / 商店 / 祭坛 / 宝箱），
	  必须有统一入口来做容量校验与日志，否则多處各写一份必然出 bug。

	容量语义：scroll.current = 当前持有；scroll.max = 携带上限。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"

local ItemSystem = Class.Define("ItemSystem")

---每多少层保底补 1 张卷轴（设计稿 §11 ⭐E）
local FLOOR_SCROLL_INTERVAL = 5

function ItemSystem:Ctor()
	self.runData = nil
end

function ItemSystem:Init(runData)
	self.runData = runData
end

function ItemSystem:Clear()
	self.runData = nil
end

function ItemSystem:GetScrollCount()
	if not self.runData or not self.runData.scroll then return 0 end
	return self.runData.scroll.current or 0
end

function ItemSystem:GetScrollMax()
	if not self.runData or not self.runData.scroll then return 0 end
	return self.runData.scroll.max or 0
end

function ItemSystem:CanUseReturnScroll()
	return self:GetScrollCount() > 0
end

---增加卷轴（受 max 容量限制）
---@return boolean 是否真的加成功
function ItemSystem:AddScroll(n)
	if not self.runData or not self.runData.scroll then return false end
	n = n or 1

	local sc = self.runData.scroll
	if (sc.current or 0) >= (sc.max or 0) then
		Logger.Info("ItemSystem", "Scroll bag full (%d/%d)", sc.current, sc.max)
		return false
	end

	sc.current = math.min(sc.max, (sc.current or 0) + n)
	Logger.Info("ItemSystem", "Scroll +%d (now %d/%d)", n, sc.current, sc.max)
	return true
end

---消耗一张回城卷轴
function ItemSystem:ConsumeReturnScroll()
	if not self.runData or not self.runData.scroll then return false end

	local sc = self.runData.scroll
	if (sc.current or 0) <= 0 then return false end

	sc.current = sc.current - 1
	Logger.Info("ItemSystem", "Scroll consumed (now %d/%d)", sc.current, sc.max)
	return true
end

---每 N 层保底补 1 张（清层发奖时调用）
function ItemSystem:TryGrantFloorScroll(floor)
	floor = floor or 0
	if floor <= 0 or (floor % FLOOR_SCROLL_INTERVAL) ~= 0 then return false end

	if self:AddScroll(1) then
		Logger.Info("ItemSystem", "Floor %d bonus: +1 return scroll", floor)
		return true
	end
	return false
end

return ItemSystem
