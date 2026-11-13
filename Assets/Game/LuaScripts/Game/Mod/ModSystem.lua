--[[
=============================================================================
ModSystem.lua - Mod 装配 / 容量 / 极性 / 聚合
=============================================================================
Module:     Game/Mod/ModSystem
Version:    1.0.0

Description:
	Warframe 式 Mod 系统的核心（设计稿 §10 / 附录 C）。

	规则：
	  cost  = baseDrain + (rank - 1)
	极性：非中性匹配 ×0.5；两者都非 Neutral 且不相等 ×1.5；向上取整；中性不打折。
	  核心槽(Core)：只接受 Core 极性卡，不打折，其效果加所属宿主容量
	  有效消耗总和 ≤ capacity
	  capacity = 宿主基础 + Meta M05(+2/级) + __capacity 加成

	聚合：
	  add → addAcc[stat] += value
	  mul → mulAcc[stat] *= value        （value 即乘数，见 ModConfig 头部说明）
	  __capacity → 只加所属宿主容量，不进加/乘区

	宿主：weapon / skill / frame，各自独立容量与槽位。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"
local MetaSystem = require "Game.Save.MetaSystem"
local ModConfig = require "Game.Mod.ModConfig"
local ModInventory = require "Game.Mod.ModInventory"

local ModSystem = {}

ModSystem.HOSTS = { "weapon", "skill", "frame" }
ModSystem.BASE_CAPACITY = 10

-- =============================================================================
-- 成本与容量
-- =============================================================================

---单张 Mod 装在指定极性槽位上的有效消耗
function ModSystem.EffectiveCost(cfg, rank, slotPolarity)
	local cost = (cfg.baseDrain or 0) + ((rank or 1) - 1)

	local mp = cfg.polarity
	-- 核心槽不参与极性折扣
	if mp == "Core" or slotPolarity == "Core" then return cost end

	if mp ~= "Neutral" and mp == slotPolarity then return math.ceil(cost * 0.5) end
	if mp ~= "Neutral" and slotPolarity and slotPolarity ~= "Neutral" then
		return math.ceil(cost * 1.5)   -- 极性不匹配惩罚
	end
	return cost
end

---宿主基础容量（含 Meta M05 加成，不含 __capacity）
function ModSystem.GetHostCapacity(hostName)
	local loadout = SaveData.Get().loadout or {}
	local host = loadout[hostName] or {}
	local base = host.capacity or ModSystem.BASE_CAPACITY
	return base + MetaSystem.GetLevel("M05") * 2
end

---遍历宿主上已安装的 Mod
function ModSystem._forEachInstalled(hostName, fn)
	local loadout = SaveData.Get().loadout or {}
	local host = loadout[hostName] or {}

	for slotIndex, uid in pairs(host.installed or {}) do
		local inst = ModInventory.GetByUid(uid)
		local slot = (host.slots or {})[slotIndex]
		if inst and slot then
			local cfg = ModConfig.Get(inst.id)
			if cfg then fn(cfg, inst, slot, slotIndex) end
		end
	end
end

---已用容量
function ModSystem.TotalUsed(hostName)
	local total = 0
	ModSystem._forEachInstalled(hostName, function(cfg, inst, slot)
		total = total + ModSystem.EffectiveCost(cfg, inst.rank, slot.polarity)
	end)
	return total
end

---__capacity 加成（只算本宿主）
function ModSystem.CapacityBonus(hostName)
	local bonus = 0
	ModSystem._forEachInstalled(hostName, function(cfg, inst)
		if cfg.effect.stat == ModConfig.STAT_CAPACITY then
			bonus = bonus + ((cfg.effect.base or 0) + (cfg.effect.perRank or 0) * (inst.rank or 1))
		end
	end)
	return bonus
end

---可用总容量
function ModSystem.TotalCapacity(hostName)
	return ModSystem.GetHostCapacity(hostName) + ModSystem.CapacityBonus(hostName)
end

-- =============================================================================
-- 安装 / 拆卸
-- =============================================================================

---是否可安装
local function fitsCapacity(hostName, installed, rankUid, rank)
	local host = SaveData.Get().loadout[hostName]
	local used, capacity = 0, ModSystem.GetHostCapacity(hostName)
	for index, uid in pairs(installed) do
		local inst = ModInventory.GetByUid(uid)
		local cfg = inst and ModConfig.Get(inst.id)
		local slot = host.slots[index]
		if cfg and slot then
			local r = uid == rankUid and rank or inst.rank
			used = used + ModSystem.EffectiveCost(cfg, r, slot.polarity)
			if cfg.effect.stat == ModConfig.STAT_CAPACITY then
				capacity = capacity + (cfg.effect.base or 0) + (cfg.effect.perRank or 0) * (r or 1)
			end
		end
	end
	return used <= capacity
end

function ModSystem.CanInstall(hostName, uid, slotIndex)
	local loadout = SaveData.Get().loadout
	local host = loadout and loadout[hostName]
	if not host then return false, "no_host" end

	local slot = (host.slots or {})[slotIndex]
	if not slot then return false, "no_slot" end

	local inst = ModInventory.GetByUid(uid)
	if not inst then return false, "no_mod" end

	local cfg = ModConfig.Get(inst.id)
	if not cfg then return false, "no_cfg" end

	-- 核心槽与 Core 卡必须互相匹配
	if slot.polarity == "Core" and cfg.polarity ~= "Core" then return false, "core_slot_only" end
	if slot.polarity ~= "Core" and cfg.polarity == "Core" then return false, "core_mod_only" end

	-- 类别必须匹配宿主（Universal 通用）
	local cat = string.lower(cfg.category or "")
	if cat ~= hostName and cat ~= "universal" then return false, "category_mismatch" end

	-- Validate the resulting layout, not old usage plus the new card.
	local draft = {}
	for index, existingUid in pairs(host.installed or {}) do
		if index ~= slotIndex and existingUid ~= uid then
			local other = ModInventory.GetByUid(existingUid)
			if other and other.id == inst.id then return false, "duplicate_mod" end
			draft[index] = existingUid
		end
	end
	draft[slotIndex] = uid
	if not fitsCapacity(hostName, draft) then
		return false, "over_capacity"
	end

	return true, nil, draft
end

local function commitLayout(host, draft)
	local previous = host.installed
	host.installed = draft
	local ok, saved = pcall(SaveData.Commit)
	if not ok or saved ~= true then
		host.installed = previous
		return false, "save_failed"
	end
	return true
end

function ModSystem.Install(hostName, uid, slotIndex)
	if SaveData.IsOnline() then return false, "online_authority" end
	local ok, reason, draft = ModSystem.CanInstall(hostName, uid, slotIndex)
	if not ok then
		Logger.Info("ModSystem", "Install rejected: %s", tostring(reason))
		return false, reason
	end

	local host = SaveData.Get().loadout[hostName]
	local saved, saveReason = commitLayout(host, draft)
	if not saved then return false, saveReason end

	Logger.Info("ModSystem", "Installed uid=%d into %s slot %s", uid, hostName, tostring(slotIndex))
	return true
end

function ModSystem.Uninstall(hostName, slotIndex)
	if SaveData.IsOnline() then return false, "online_authority" end
	local loadout = SaveData.Get().loadout
	local host = loadout and loadout[hostName]
	if not host or not host.installed then return false end

	if host.installed[slotIndex] == nil then return false end
	local draft = {}
	for index, uid in pairs(host.installed) do
		if index ~= slotIndex then draft[index] = uid end
	end
	if not fitsCapacity(hostName, draft) then return false, "capacity_dependency" end
	return commitLayout(host, draft)
end

function ModSystem.CanUpgrade(uid, rank)
	for _, hostName in ipairs(ModSystem.HOSTS) do
		local host = (SaveData.Get().loadout or {})[hostName]
		if host then
			for _, installedUid in pairs(host.installed or {}) do
				if installedUid == uid and not fitsCapacity(hostName, host.installed, uid, rank) then
					return false, "over_capacity"
				end
			end
		end
	end
	return true
end

---【自动装配 —— P3-1 起已停用，见下】
-- 找第一个「类别匹配 + 极性合规 + 容量够」的空槽装上。
--
-- 停用时间与原因（用户 2026-10-02 拍板）：ModStationView 接上后，局内掉落的 Mod
-- 只进背包、不自动装配（DungeonManager.lua 的 Boss 掉落 与
-- MerchantEvent.lua 的商人购买 两处调用点均已摘掉）。
-- 理由：玩家没意识到自己被动改了配装，而自动装配的极性折扣/容量判定是玩家看不见的。
--
-- 函数体保留不用；确认没有外部调用后再连函数一并删（P5 清债）。
function ModSystem.TryAutoInstall(inst)
	if SaveData.IsOnline() then return false, "online_authority" end
	if not inst then return false end

	local cfg = ModConfig.Get(inst.id)
	if not cfg then return false end

	local cat = string.lower(cfg.category or "")
	local hosts = (cat == "universal") and ModSystem.HOSTS or { cat }

	for _, hostName in ipairs(hosts) do
		local loadout = SaveData.Get().loadout
		local host = loadout and loadout[hostName]
		if host and host.slots then
			for i in ipairs(host.slots) do
				local occupied = host.installed and host.installed[i]
				if not occupied and ModSystem.CanInstall(hostName, inst.uid, i) then
					return ModSystem.Install(hostName, inst.uid, i)
				end
			end
		end
	end
	return false
end

-- =============================================================================
-- 聚合
-- =============================================================================

---计算派生属性
---@return table { add={}, mul={}, capacity={}, used={} }
function ModSystem.ComputeDerived()
	local derived = { add = {}, mul = {}, capacity = {}, used = {} }

	for _, hostName in ipairs(ModSystem.HOSTS) do
		derived.capacity[hostName] = ModSystem.TotalCapacity(hostName)
		derived.used[hostName] = ModSystem.TotalUsed(hostName)

		ModSystem._forEachInstalled(hostName, function(cfg, inst)
			local value = (cfg.effect.base or 0) + (cfg.effect.perRank or 0) * (inst.rank or 1)
			local stat = cfg.effect.stat

			if stat == ModConfig.STAT_CAPACITY then
				return  -- 只影响容量，已单独计算
			elseif cfg.effect.mode == "add" then
				derived.add[stat] = (derived.add[stat] or 0) + value
			else
				-- mul：value 即乘数
				derived.mul[stat] = (derived.mul[stat] or 1) * value
			end
		end)
	end

	return derived
end

---开局应用：算好派生属性挂到 runData（真正作用玩家在 ApplyToPlayer）
function ModSystem.ApplyLoadout(runData)
	local derived = ModSystem.ComputeDerived()
	if runData then runData.derived = derived end
	return derived
end

-- =============================================================================
-- 作用于玩家
-- =============================================================================

---把派生属性落到 PlayerController
-- 只应用【有落点】的属性；projectileCount / pierce / range 等目前无落点，
-- 仅记录在 derived 里，等对应系统建成后再启用（P6 缺口 #3）。
function ModSystem.ApplyToPlayer(pc, derived)
	if not pc or not derived then return end

	local add = derived.add or {}
	local mul = derived.mul or {}

	if add.damage then pc:AddStat("atk", add.damage) end
	if add.fireRate then pc:AddStat("atkSpeed", add.fireRate) end
	if add.critChance then pc:AddStat("critRate", add.critChance) end
	if add.maxHp then pc:AddStat("maxHp", add.maxHp) end
	if add.lifeSteal then pc:AddStat("lifeSteal", add.lifeSteal) end
	if add.range then pc:AddStat("atkRange", add.range) end

	if mul.damageMul then pc.atk = pc.atk * mul.damageMul end
	if mul.critDamage then pc.critDmg = math.max(1, pc.critDmg * mul.critDamage) end
	if mul.moveSpeed then pc:AddStat("moveSpeed", (mul.moveSpeed - 1) * pc.moveSpeed) end

	-- 注意：本工程的 Logger 不支持 %.1f / %.2f（会原样输出并导致参数错位，
	-- 参见 LoginPanel 的 "open cost %.1f ms"）。这里一律用 %s + tostring。
	Logger.Info("ModSystem",
		"Mods applied: atk=%s critDmg=%s moveSpeed=%s maxHp=%s",
		tostring(pc.atk), tostring(pc.critDmg), tostring(pc.moveSpeed), tostring(pc.maxHp))
end

return ModSystem
