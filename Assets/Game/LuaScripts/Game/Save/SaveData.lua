--[[
=============================================================================
SaveData.lua - 永久存档（最小骨架）
=============================================================================
Module:     Game/Save/SaveData
Version:    0.1.0（骨架）

Description:
	永久存档的数据定义与「结算写入」入口。

	⚠ 本模块因 P4 需要而【提前引入】：
	  roadmap 里 SaveData 排在 P5，但 P4 的撤离/死亡结算必须有地方写，
	  否则结算无从谈起（P4 缺口 #1）。此处只做：
	    - 数据结构定义
	    - 内存持有（Get）
	    - ApplyExtract / ApplyDeath 两个写入函数
	  P5 再补：SaveManager（JSON 落盘 + 版本迁移）、TownStashView、Meta 天赋树。

	铁律（设计稿 §4.3）：
	  RunData 是临时对象，只有「撤离结算」与「Meta 发放」两处写入 SaveData。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"

local SaveData = {}

SaveData.VERSION = 1
SaveData.current = nil

local onlineSelected = false
local offlineCurrent

function SaveData.IsOnline()
	return onlineSelected
end

function SaveData.BeginOnline()
	if onlineSelected then return end
	offlineCurrent = SaveData.current
	onlineSelected = true
	SaveData.current = SaveData.Default()
end

-- Only the session service decides when leaving online mode is allowed.
function SaveData.EndOnline()
	if not onlineSelected then return end
	SaveData.current = offlineCurrent
	offlineCurrent = nil
	onlineSelected = false
end

function SaveData.ReplaceOnlineSnapshot(data)
	if not onlineSelected then return false, "not_online" end
	local SaveManager = require "Game.Save.SaveManager"
	if not SaveManager._isValid(data) then return false, "invalid_snapshot" end
	SaveData.current = SaveManager.EnsureSchema(data)
	return true
end

---默认空档结构（设计稿 §4.2）
-- 注：inventory 增加 gold 字段——loot.gold 需要归属（P4 缺口 #6）
function SaveData.Default()
	return {
		version = SaveData.VERSION,
		player = {
			unlockedCharacters = {},
			unlockedSkills = {},
			unlockedRelics = {},
		},
		inventory = {
			gold = 0,
			items = {},
			materials = {},
			mods = {},          -- P6 Mod 系统启用
		},
		-- 默认槽位极性：与 ModConfig 的卡牌极性对应，保证拿到就能装。
		-- 若 slots 为空数组，整个 Mod 装配合流程会空转（没有任何槽可装）。
		loadout = {
			weapon = {
				capacity = 10,
				slots = { { polarity = "Abyss" }, { polarity = "Bone" }, { polarity = "Neutral" } },
				installed = {},
			},
			skill = {
				capacity = 10,
				slots = { { polarity = "Corrosion" }, { polarity = "Curse" } },
				installed = {},
			},
			frame = {
				capacity = 10,
				slots = { { polarity = "Bone" }, { polarity = "Core" } },
				installed = {},
			},
		},
		meta = {
			memoryFragments = 0,
			upgrades = {},      -- P5 Meta 天赋树启用
		},
		statistics = {
			highestFloor = 0,
			totalRuns = 0,
			totalDeaths = 0,
			totalExtracts = 0,
		},
	}
end

---取当前存档（惰性创建；P5 改为从磁盘加载）
function SaveData.Get()
	if not SaveData.current then
		SaveData.current = SaveData.Default()
	end
	return SaveData.current
end

---撤离结算：渊获入账 + 记忆碎片（设计稿 §13）
function SaveData.ApplyExtract(result)
	if onlineSelected then return false, "online_authority" end
	result = result or {}
	local s = SaveData.Get()

	s.inventory.gold = (s.inventory.gold or 0) + (result.gold or 0)
	for _, m in ipairs(result.materials or {}) do
		s.inventory.materials[#s.inventory.materials + 1] = m
	end
	for _, it in ipairs(result.items or {}) do
		s.inventory.items[#s.inventory.items + 1] = it
	end

	s.meta.memoryFragments = (s.meta.memoryFragments or 0) + (result.fragments or 0)

	s.statistics.totalRuns = (s.statistics.totalRuns or 0) + 1
	s.statistics.totalExtracts = (s.statistics.totalExtracts or 0) + 1
	if (result.floor or 0) > (s.statistics.highestFloor or 0) then
		s.statistics.highestFloor = result.floor
	end

	Logger.Info("SaveData", "Extract: +%d gold, +%d fragments (total %d)",
		result.gold or 0, result.fragments or 0, s.meta.memoryFragments)
end

---死亡结算：渊获【清空】，只留记忆碎片（设计稿 §13）
function SaveData.ApplyDeath(result)
	if onlineSelected then return false, "online_authority" end
	result = result or {}
	local s = SaveData.Get()

	-- 刻意【不】写 inventory：本轮未结算的渊获全部损失
	s.meta.memoryFragments = (s.meta.memoryFragments or 0) + (result.fragments or 0)

	s.statistics.totalRuns = (s.statistics.totalRuns or 0) + 1
	s.statistics.totalDeaths = (s.statistics.totalDeaths or 0) + 1
	if (result.floor or 0) > (s.statistics.highestFloor or 0) then
		s.statistics.highestFloor = result.floor
	end

	Logger.Info("SaveData", "Death: lost %d gold, +%d fragments (total %d)",
		result.lootLost or 0, result.fragments or 0, s.meta.memoryFragments)
end

---统一保存入口
-- 惰性 require SaveManager：SaveManager 顶层要 require SaveData，
-- 若这里也顶层 require 就会形成加载期循环依赖。
function SaveData.Commit()
	if onlineSelected then return false, "online_authority" end
	local SaveManager = require "Game.Save.SaveManager"
	return SaveManager.Save(SaveData.Get())
end

return SaveData
