--[[
=============================================================================
DropSystem.lua - 击杀掉落系统
=============================================================================
Module:     Game/Battle/DropSystem
Version:    1.0.0

Description:
	统一管理战斗中击杀产生的掉落物（武器 / 材料 / 道具）。
	设计（按兵种区分）：
		enemy（持武敌人，skeleton）  击杀 → 掉落它【携带的武器】
		monster（怪物，slime/bat）    击杀 → 只掉落【材料】
		boss 的 Mod/金币由 BossConfig 单独处理，不走这里。

	拾取规则：玩家走入 pickupRadius 内自动拾取（无需点击）。
		- 武器：即时加入 weaponSystem，立刻能用来打（与升级获得同等）
		- 材料/道具：先累计到本系统，楼层清层时由 DungeonManager 并入本局渊获

	表现层：由 Lua 组件 DropView 驱动（继承 EntityViewBase，自己浮动旋转）。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local BuildConfig = require "Game.Build.BuildConfig"
local EntityViewFactory = require "Game.Battle.View.EntityViewFactory"

local DropSystem = Class.Define("DropSystem")

function DropSystem:Ctor()
	self.drops = {}
	self._idCounter = 0
	self._pendingRemove = {}
	self.weaponSystem = nil
	self.materials = {}   -- 已拾取材料计数：{ [materialId] = count }
	self.items = {}       -- 已拾取道具计数：{ [itemId] = count }
end

function DropSystem:Init(weaponSystem)
	self.weaponSystem = weaponSystem
end

---生成掉落物（内部入口）
function DropSystem:_spawn(kind, refId, x, y)
	self._idCounter = self._idCounter + 1
	local d = {
		id = self._idCounter,
		kind = kind,
		refId = refId,
		x = x or 0,
		y = y or 0,
		_remove = false,
	}
	self.drops[#self.drops + 1] = d
	-- 表现层：创建「Lua 组件」驱动的掉落视图（武器/材料/道具模型各异）
	d.view = EntityViewFactory.CreateDropView(d)
	return d
end

function DropSystem:SpawnWeaponDrop(weaponId, x, y)
	return self:_spawn("weapon", weaponId, x, y)
end

function DropSystem:SpawnMaterialDrop(materialId, x, y)
	return self:_spawn("material", materialId, x, y)
end

function DropSystem:SpawnItemDrop(itemId, x, y)
	return self:_spawn("item", itemId, x, y)
end

-- 每帧：检测玩家靠近自动拾取
function DropSystem:Update(dt, px, py, pickupRadius)
	pickupRadius = pickupRadius or 1.2
	local r2 = pickupRadius * pickupRadius
	for _, d in ipairs(self.drops) do
		if not d._remove then
			local dx = px - d.x
			local dy = py - d.y
			if dx * dx + dy * dy <= r2 then
				self:_pickup(d)
				d._remove = true
				self._pendingRemove[#self._pendingRemove + 1] = d
			end
		end
	end
	-- 表现层无需喂 dt：DropView 继承 EntityViewBase，浮动/旋转自己驱动
	self:_flushRemoved()
end

function DropSystem:_pickup(d)
	if d.kind == "weapon" then
		local w = BuildConfig.GetWeapon(d.refId)
		if w and self.weaponSystem then
			self.weaponSystem:AddWeapon(w)
		end
	elseif d.kind == "material" then
		self.materials[d.refId] = (self.materials[d.refId] or 0) + 1
	elseif d.kind == "item" then
		self.items[d.refId] = (self.items[d.refId] or 0) + 1
	end
end

-- 供 DungeonManager 在清层时并入本局渊获
function DropSystem:GetCollectedLoot()
	return { materials = self.materials, items = self.items }
end

function DropSystem:_flushRemoved()
	if #self._pendingRemove == 0 then return end
	local rm = {}
	for _, d in ipairs(self._pendingRemove) do rm[d.id] = true end

	local keep = {}
	for _, d in ipairs(self.drops) do
		if not rm[d.id] then
			keep[#keep + 1] = d
		else
			-- 表现层：销毁被拾取/移除的掉落视图
			if d.view then pcall(function() d.view:Destroy() end) end
		end
	end
	self.drops = keep
	self._pendingRemove = {}
end

function DropSystem:Reset()
	-- 表现层：先销毁场上掉落视图
	if self.drops then
		for _, d in ipairs(self.drops) do
			if d.view then pcall(function() d.view:Destroy() end) end
		end
	end
	self.drops = {}
	self._pendingRemove = {}
	self._idCounter = 0
	self.materials = {}
	self.items = {}
end

function DropSystem:Destroy()
	-- 表现层：销毁所有残留掉落视图
	if self.drops then
		for _, d in ipairs(self.drops) do
			if d.view then pcall(function() d.view:Destroy() end) end
		end
	end
	self.drops = {}
	self._pendingRemove = {}
	self._idCounter = 0
	self.materials = {}
	self.items = {}
	self.weaponSystem = nil
end

return DropSystem
