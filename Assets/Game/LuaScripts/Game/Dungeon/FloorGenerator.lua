--[[
=============================================================================
FloorGenerator.lua - 楼层生成器（程序化 · 支撑无限下潜）
=============================================================================
Module:     Game/Dungeon/FloorGenerator
Version:    1.0.0

Description:
	1) Generate(floor)   —— 取得任意楼层的配置。
	   手工 FloorConfig[1..N] 优先；超出部分按公式程序化生成，
	   保证「无限下潜」在任何深度都有合法楼层。
	2) BuildWaves(cfg)   —— 把楼层配置转换成 SpawnSystem 能吃的波次时间轴。

	SpawnSystem 现有实现是「波次时间轴」制（startTime / count / interval /
	enemyType / hpMult），不是密度制。这里负责把 density / enemyLevel
	翻译成波次，P2 的 SpawnDirector 可直接替换本文件的 BuildWaves。
=============================================================================
]]

local FloorConfig = require "Game.Dungeon.FloorConfig"

local FloorGenerator = {}

---难度缩放公式（与埋骨渊方案.md 附录 D 一致）
local function calcEnemyLevel(f)
	return 1 + 0.5 * (f - 1)
end

local function calcDensity(f)
	return 1 + 0.15 * (f - 1)
end

local function calcEliteRate(f)
	return math.min(0.02 + 0.01 * (f - 1), 0.40)
end

local function calcGold(f)
	return math.floor(100 * f ^ 1.1)
end

local function calcExp(f)
	return math.floor(100 * f ^ 1.05)
end

---取得指定楼层的配置
---@param floor number 楼层号（从 1 开始）
---@return table 楼层配置
function FloorGenerator.Generate(floor)
	floor = math.max(1, math.floor(floor or 1))

	-- 手工精调层优先
	if FloorConfig[floor] then
		return FloorConfig[floor]
	end

	-- 程序化生成（每 10 层一个阶段 Boss）
	local isBoss = (floor % 10 == 0)
	local tier = math.floor((floor - 1) / 10)

	return {
		floor = floor,
		duration = FloorConfig.DEFAULT.duration,
		enemyLevel = calcEnemyLevel(floor),
		spawn = {
			density = calcDensity(floor),
			eliteRate = calcEliteRate(floor),
		},
		reward = {
			gold = calcGold(floor),
			exp = calcExp(floor),
		},
		-- Boss 战在【层内】进行（P2：层末 90% 时间刷 Boss，击杀才清层）。
		-- 因此层间事件回归普通池，否则同一个 Boss 会被触发两次。
		eventPool = FloorConfig.DEFAULT.eventPool,
		boss = isBoss,
		bossId = isBoss and ("StageBoss_" .. tier) or nil,
	}
end

---把楼层配置翻译成 SpawnSystem 的波次时间轴
---@param cfg table 楼层配置
---@return table waves
function FloorGenerator.BuildWaves(cfg)
	cfg = cfg or {}
	local duration = cfg.duration or FloorConfig.DEFAULT.duration
	local density = (cfg.spawn and cfg.spawn.density) or 1.0
	local enemyLevel = cfg.enemyLevel or 1

	-- 敌人血量倍率随等级成长（附录 D: 1 + 0.18*(level-1)）
	local hpMult = 1 + 0.18 * (enemyLevel - 1)

	local waves = {
		-- 前期：史莱姆压数量
		{
			startTime = 0,
			enemyType = "slime",
			count = math.floor(20 * density),
			interval = 0.8 / density,
			hpMult = hpMult,
		},
		-- 中期：蝙蝠逼走位
		{
			startTime = duration * 0.35,
			enemyType = "bat",
			count = math.floor(15 * density),
			interval = 1.0 / density,
			hpMult = hpMult,
		},
		-- 后期：骷髅抬强度
		{
			startTime = duration * 0.7,
			enemyType = "skeleton",
			count = math.floor(10 * density),
			interval = 1.5 / density,
			hpMult = hpMult,
		},
	}

	-- Boss 层：末尾刷一只 boss
	if cfg.boss then
		waves[#waves + 1] = {
			startTime = duration * 0.9,
			enemyType = "boss",
			count = 1,
			interval = 0,
			hpMult = hpMult * 5.0,
		}
	end

	return waves
end

---把楼层配置翻译成 SpawnDirector 的怪潮参数（P2）
---第一版只 3 个驱动参数：density / eliteRate / enemyLevel；
---maxCount 为同屏上限（P2 决策 #6：进配置，默认 60）。
---@param cfg table 楼层配置
---@return table { density, eliteRate, maxCount }
function FloorGenerator.BuildSpawnConfig(cfg)
	cfg = cfg or {}
	local spawn = cfg.spawn or {}

	return {
		density = spawn.density or 1.0,
		eliteRate = spawn.eliteRate or 0.0,
		maxCount = spawn.maxCount or 60,
	}
end

return FloorGenerator
