--[[
=============================================================================
MetaSystem.lua - 记忆碎片天赋树（Meta Progression）
=============================================================================
Module:     Game/Save/MetaSystem
Version:    1.0.0

Description:
	用记忆碎片购买永久天赋（设计稿附录 F / §15 决策 #3）。
	数据落在 SaveData.meta.upgrades（{ [id] = level }），货币是 memoryFragments。

	【重要】只让「有落点」的节点可购买（available=true）。
	  没有落点的节点（如 M03 经验加成、M05 Mod容量、M06 武器池）
	  买了也没反应，会变成骗玩家的死节点——因此标记为 available=false，
	  等对应系统（P6/P7）建成后再打开。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"

local MetaSystem = {}

---天赋节点（附录 F）
-- available=false 表示该效果暂无落点，不开放购买
MetaSystem.Nodes = {
	M01 = { id = "M01", name = "初始卷轴+1",  cost = 5,  maxLevel = 1, requires = nil,   available = true,  desc = "每局初始多带 1 张回城卷轴" },
	M02 = { id = "M02", name = "坚骨",       cost = 3,  maxLevel = 3, requires = nil,   available = true,  desc = "最大生命 +20/级" },
	M03 = { id = "M03", name = "锐识",       cost = 4,  maxLevel = 1, requires = nil,   available = false, desc = "经验获取 +10%（暂无落点）" },
	M04 = { id = "M04", name = "商谊",       cost = 6,  maxLevel = 1, requires = "M03", available = true,  desc = "商店 9 折" },
	M05 = { id = "M05", name = "渊容",       cost = 8,  maxLevel = 1, requires = "M01", available = true,  desc = "初始 Mod 容量 +2" },
	M06 = { id = "M06", name = "武器精通",   cost = 10, maxLevel = 1, requires = "M02", available = true,  desc = "武器在升级选项中权重 +1/级" },
}

-- =============================================================================
-- 查询
-- =============================================================================

function MetaSystem.GetFragments()
	return (SaveData.Get().meta.memoryFragments) or 0
end

function MetaSystem.GetLevel(id)
	return (SaveData.Get().meta.upgrades[id]) or 0
end

---是否可购买
---@return boolean, string|nil 失败原因
function MetaSystem.CanBuy(id)
	if SaveData.IsOnline() then return false, "online_authority" end
	local node = MetaSystem.Nodes[id]
	if not node then return false, "unknown_node" end
	if not node.available then return false, "not_available" end
	if MetaSystem.GetLevel(id) >= node.maxLevel then return false, "max_level" end

	-- 前置：仅当前置节点【可购买】时才真正要求，否则会形成死节点
	if node.requires then
		local pre = MetaSystem.Nodes[node.requires]
		if pre and pre.available and MetaSystem.GetLevel(node.requires) <= 0 then
			return false, "requires_not_met"
		end
	end

	if MetaSystem.GetFragments() < node.cost then return false, "not_enough_fragments" end
	return true
end

-- =============================================================================
-- 购买
-- =============================================================================

function MetaSystem.Buy(id)
	if SaveData.IsOnline() then return false, "online_authority" end
	local ok, reason = MetaSystem.CanBuy(id)
	if not ok then
		Logger.Info("MetaSystem", "Buy %s rejected: %s", tostring(id), tostring(reason))
		return false
	end

	local s = SaveData.Get()
	local node = MetaSystem.Nodes[id]

	s.meta.memoryFragments = (s.meta.memoryFragments or 0) - node.cost
	s.meta.upgrades[id] = (s.meta.upgrades[id] or 0) + 1

	SaveData.Commit()
	Logger.Info("MetaSystem", "Bought %s (%s) lv%d, fragments left %d",
		id, node.name, s.meta.upgrades[id], s.meta.memoryFragments)
	return true
end

-- =============================================================================
-- 效果读取
-- =============================================================================

---商店折扣（0.10 = 9 折）
function MetaSystem.GetShopDiscount()
	if MetaSystem.GetLevel("M04") > 0 then return 0.10 end
	return 0
end

---武器在升级三选一中的额外权重（M06 武器精通）
function MetaSystem.GetWeaponWeight()
	return MetaSystem.GetLevel("M06")
end

-- =============================================================================
-- 开局生效
-- =============================================================================

---应用到本局 RunData（卷轴等）
function MetaSystem.ApplyToRun(runData)
	if not runData then return end

	local lv = MetaSystem.GetLevel("M01")
	if lv > 0 and runData.scroll then
		runData.scroll.max = (runData.scroll.max or 0) + lv
		runData.scroll.current = math.min(runData.scroll.max, (runData.scroll.current or 0) + lv)
		Logger.Info("MetaSystem", "M01 applied: scroll %d/%d",
			runData.scroll.current, runData.scroll.max)
	end
end

---应用到玩家（maxHp 等）。每局【只调用一次】，否则会重复叠加。
function MetaSystem.ApplyToPlayer(pc)
	if not pc then return end

	local lv = MetaSystem.GetLevel("M02")
	if lv > 0 then
		pc:AddStat("maxHp", 20 * lv)
		Logger.Info("MetaSystem", "M02 applied: maxHp +%d (now %d)", 20 * lv, pc.maxHp)
	end
end

return MetaSystem
