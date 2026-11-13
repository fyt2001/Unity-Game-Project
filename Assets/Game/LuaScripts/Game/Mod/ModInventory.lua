--[[
=============================================================================
ModInventory.lua - 拥有的 Mod（接 SaveData.inventory.mods）
=============================================================================
Module:     Game/Mod/ModInventory
Version:    1.0.0

Description:
	玩家拥有的 Mod 卡实例。持久化在 SaveData.inventory.mods：
		{ { uid = 1, id = 1001, rank = 2 }, ... }

	Mod 是【永久】资产（Warframe 式），Run 结束不清空，
	这与 RunData 的临时性形成对比（设计稿 §4.3）。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"
local ModConfig = require "Game.Mod.ModConfig"

local ModInventory = {}

---取背包列表
function ModInventory.GetAll()
	return SaveData.Get().inventory.mods
end

---生成新 uid（基于现有最大 uid，避免读档后撞号）
function ModInventory._nextUid()
	local max = 0
	for _, m in ipairs(ModInventory.GetAll()) do
		if (m.uid or 0) > max then max = m.uid end
	end
	return max + 1
end

---添加一张 Mod
function ModInventory.AddMod(id, rank)
	if SaveData.IsOnline() then return nil, "online_authority" end
	if not ModConfig.Get(id) then
		Logger.Warn("ModInventory", "Unknown mod id: %s", tostring(id))
		return nil
	end

	local inst = { uid = ModInventory._nextUid(), id = id, rank = math.max(1, rank or 1) }
	table.insert(ModInventory.GetAll(), inst)
	SaveData.Commit()
	Logger.Info("ModInventory", "Got mod %s (uid=%d, rank=%d)", tostring(id), inst.uid, inst.rank)
	return inst
end

function ModInventory.GetByUid(uid)
	if not uid then return nil end
	for _, m in ipairs(ModInventory.GetAll()) do
		if m.uid == uid then return m end
	end
	return nil
end

function ModInventory.Count()
	return #ModInventory.GetAll()
end

---是否可升级
function ModInventory.CanUpgrade(inst)
	if SaveData.IsOnline() then return false, "online_authority" end
	if not inst then return false end
	local cfg = ModConfig.Get(inst.id)
	if not cfg then return false end
	if (inst.rank or 1) >= (cfg.maxRank or 1) then return false end
	return require("Game.Mod.ModSystem").CanUpgrade(inst.uid, (inst.rank or 1) + 1)
end

---升级指定 Mod
function ModInventory.Upgrade(inst)
	if SaveData.IsOnline() then return false, "online_authority" end
	if not ModInventory.CanUpgrade(inst) then return false end
	if ModInventory.GetByUid(inst.uid) ~= inst then return false, "no_mod" end
	local nextRank = (inst.rank or 1) + 1
	local allowed, reason = require("Game.Mod.ModSystem").CanUpgrade(inst.uid, nextRank)
	if not allowed then return false, reason end
	local previous = inst.rank
	inst.rank = nextRank
	local ok, saved = pcall(SaveData.Commit)
	if not ok or saved ~= true then
		inst.rank = previous
		return false, "save_failed"
	end
	Logger.Info("ModInventory", "Mod uid=%d upgraded to rank %d", inst.uid, inst.rank)
	return true
end

---随机强化一张可升级的 Mod（祭坛用）
function ModInventory.UpgradeRandom()
	if SaveData.IsOnline() then return nil, "online_authority" end
	local candidates = {}
	for _, m in ipairs(ModInventory.GetAll()) do
		if ModInventory.CanUpgrade(m) then
			candidates[#candidates + 1] = m
		end
	end

	if #candidates == 0 then return nil end

	local pick = candidates[math.random(1, #candidates)]
	if ModInventory.Upgrade(pick) then return pick end
	return nil
end

---随机发放一张 Mod
---@param pool table|nil 候选 id 池；为空时回落到 ModConfig.AllIds
function ModInventory.GrantRandom(pool)
	if SaveData.IsOnline() then return nil, "online_authority" end
	if not pool or #pool == 0 then pool = ModConfig.AllIds end
	if not pool or #pool == 0 then return nil end

	local id = pool[math.random(1, #pool)]
	return ModInventory.AddMod(id, 1)
end

return ModInventory
