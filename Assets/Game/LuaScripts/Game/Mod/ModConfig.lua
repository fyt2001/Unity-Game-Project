--[[
=============================================================================
ModConfig.lua - Mod 卡牌配置表（Warframe 式）
=============================================================================
Module:     Game/Mod/ModConfig
Version:    1.0.0

Description:
	Mod 卡定义 + 极性枚举（设计稿附录 B）。

	字段：
	  category   Weapon | Skill | Frame | Universal —— 决定能装进哪个宿主
	  polarity   渊/骨/蚀/咒/无(Neutral)/Core
	  baseDrain  基础消耗（rank1 时的消耗）
	  maxRank    最大等级
	  effect     { stat, mode(add|mul), base, perRank }

	数值公式（附录 C）：
	  value = effect.base + effect.perRank * rank      （安装即 rank ≥ 1）
	  cost  = baseDrain + (rank - 1)

	⚠【重要】mode = "mul" 的语义统一为【乘数本身】：
	    mulAcc[stat] = mulAcc[stat] * value
	  即 value=1.30 表示 ×1.30，而不是 +30%。
	  这样「咒能 rank5 = 暴伤 ×2.0」才成立（base=1.0 + 0.20*5 = 2.0）。
	  因此所有 mul 型卡的 base 都是 1.0（设计稿附录 B 里「锐锋」base 原写 0.0，
	  与附录 C 的 1+value 公式配套；本实现统一口径后改为 1.0，
	  rank3 结果仍是 ×1.30，与附录 C 算例一致）。
=============================================================================
]]

local ModConfig = {}

---极性枚举
ModConfig.Polarity = {
	Abyss = "Abyss",           -- 渊
	Bone = "Bone",             -- 骨
	Corrosion = "Corrosion",   -- 蚀
	Curse = "Curse",           -- 咒
	Neutral = "Neutral",       -- 无
	Core = "Core",             -- 核心槽（Aura）
}

---特殊 stat：加宿主容量，不参与加/乘区
ModConfig.STAT_CAPACITY = "__capacity"

-- Weapon 类
ModConfig[1001] = {
	id = 1001, name = "锐锋", category = "Weapon", polarity = "Abyss",
	baseDrain = 4, maxRank = 5,
	effect = { stat = "damageMul", mode = "mul", base = 1.0, perRank = 0.10 },   -- rank3 → ×1.30
}
ModConfig[1002] = {
	id = 1002, name = "疾射", category = "Weapon", polarity = "Bone",
	baseDrain = 3, maxRank = 5,
	effect = { stat = "fireRate", mode = "add", base = 0.0, perRank = 0.15 },     -- rank5 → +0.75
}
ModConfig[1003] = {
	id = 1003, name = "多重投射", category = "Weapon", polarity = "Neutral",
	baseDrain = 6, maxRank = 3,
	effect = { stat = "projectileCount", mode = "add", base = 0.0, perRank = 1 }, -- rank3 → +3
}

-- Skill 类
ModConfig[2001] = {
	id = 2001, name = "寒冰护盾", category = "Skill", polarity = "Corrosion",
	baseDrain = 4, maxRank = 5,
	effect = { stat = "maxHp", mode = "add", base = 0.0, perRank = 20 },          -- rank5 → +100
}
ModConfig[2002] = {
	id = 2002, name = "咒能", category = "Skill", polarity = "Curse",
	baseDrain = 5, maxRank = 5,
	effect = { stat = "critDamage", mode = "mul", base = 1.0, perRank = 0.20 },   -- rank5 → ×2.0
}

-- Frame 类
ModConfig[3001] = {
	id = 3001, name = "渊核", category = "Frame", polarity = "Core",
	baseDrain = 0, maxRank = 3,
	effect = { stat = ModConfig.STAT_CAPACITY, mode = "add", base = 0.0, perRank = 6 },  -- 核心槽 +容量
}
ModConfig[3002] = {
	id = 3002, name = "迅步", category = "Frame", polarity = "Bone",
	baseDrain = 3, maxRank = 5,
	effect = { stat = "moveSpeed", mode = "mul", base = 1.0, perRank = 0.06 },    -- rank5 → ×1.30
}

---全部卡 id（随机发放时的默认池）
ModConfig.AllIds = {}
for id in pairs(ModConfig) do
	if type(id) == "number" then
		ModConfig.AllIds[#ModConfig.AllIds + 1] = id
	end
end
table.sort(ModConfig.AllIds)

---取卡牌定义
function ModConfig.Get(id)
	return ModConfig[id]
end

return ModConfig
