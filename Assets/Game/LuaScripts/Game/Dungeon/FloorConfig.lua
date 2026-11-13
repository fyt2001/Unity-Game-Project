--[[
=============================================================================
FloorConfig.lua - 楼层配置表（手工精调层）
=============================================================================
Module:     Game/Dungeon/FloorConfig
Version:    1.0.0

Description:
	手工定义的楼层数据。前几层手工精调手感，更深层由 FloorGenerator
	程序化生成（无限下潜）。所有数值改动只在配置文件，不改逻辑代码。

字段说明：
	floor        楼层号
	duration     本层持续时间（秒）—— 时间到即清层（P1 清层条件）
	enemyLevel   敌人等级（驱动 hpMult / 伤害缩放）
	spawn.density      刷怪密度倍率
	spawn.eliteRate    精英出现率（P2 启用，P1 仅占位）
	reward.gold        清层金币奖励
	reward.exp         清层经验奖励
	eventPool    层间事件池（P3 启用）
	boss         是否 Boss 层
	bossId       Boss 配置 id（P2 启用）
=============================================================================
]]

local FloorConfig = {}

---通用默认值：程序化生成时以此为基线
FloorConfig.DEFAULT = {
	duration = 180,
	enemyLevel = 1,
	spawn = {
		density = 1.0,
		eliteRate = 0.01,
		maxCount = 60,      -- 同屏敌人上限（P2 决策 #6：进配置而非硬编码）
	},
	reward = {
		gold = 100,
		exp = 100,
	},
	eventPool = { "Chest", "Shrine", "Merchant", "Trap" },
	boss = false,
	bossId = nil,
}

-- 第 1 层：入门，只有史莱姆
FloorConfig[1] = {
	floor = 1,
	duration = 180,
	enemyLevel = 1,
	spawn = { density = 1.0, eliteRate = 0.01 },
	reward = { gold = 100, exp = 100 },
	eventPool = { "Chest", "Shrine", "Merchant", "Trap" },
	boss = false,
}

-- 第 2 层：加入蝙蝠
FloorConfig[2] = {
	floor = 2,
	duration = 180,
	enemyLevel = 1.5,
	spawn = { density = 1.15, eliteRate = 0.03 },
	reward = { gold = 215, exp = 207 },
	eventPool = { "Chest", "Shrine", "Merchant", "Trap" },
	boss = false,
}

-- 第 3 层：加入骷髅
FloorConfig[3] = {
	floor = 3,
	duration = 180,
	enemyLevel = 2.0,
	spawn = { density = 1.30, eliteRate = 0.04 },
	reward = { gold = 340, exp = 326 },
	eventPool = { "Chest", "Shrine", "Merchant", "Trap" },
	boss = false,
}

return FloorConfig
