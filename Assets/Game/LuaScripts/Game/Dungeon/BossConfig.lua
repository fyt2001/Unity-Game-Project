--[[
=============================================================================
BossConfig.lua - Boss 模板配置表
=============================================================================
Module:     Game/Dungeon/BossConfig
Version:    1.0.0

Description:
	Boss 模板化（埋骨渊方案.md §12）：Boss 系统只负责「HP变化→Phase判定→
	切换阶段→Boss行为」，具体数据全在 Config。

	⚠ 降级说明（P2 决策 #2）：
	  当前工程【没有敌人技能系统】，敌人只会追击 + 普攻。
	  因此 phases[*].skillSet 目前只是数据占位，实际生效的是 statMod
	  （速度 / 伤害 / 攻击间隔）。等敌人技能系统建成后再启用 skillSet。

	获取方式统一走 BossConfig.Get(id)：
	  - 手工定义的 id（BuriedKing / StageBoss_0 / StageBoss_1 …）直接返回
	  - 未定义的 StageBoss_<tier> 按通用模板乘 tier 系数生成（P2 决策 #3）
=============================================================================
]]

local BossConfig = {}

---阶段模板（statMod 为阶段进入时的乘算系数）
local function makePhases(dmgStep, spdStep)
	return {
		{ hpPercent = 1.0, statMod = { speed = 1.00, damage = 1.00, attackInterval = 1.00 }, skillSet = {} },
		{ hpPercent = 0.7, statMod = { speed = 1.00 + spdStep, damage = 1.00 + dmgStep, attackInterval = 0.90 }, skillSet = {} },
		{ hpPercent = 0.3, statMod = { speed = 1.00 + spdStep * 2, damage = 1.00 + dmgStep * 2, attackInterval = 0.75 }, skillSet = {} },
	}
end

---Boss 掉落 Mod 池（设计稿 §10.5「Boss 必掉 mod」）
-- 池为空时 ModInventory.GrantRandom 会回落到 ModConfig.AllIds
local MOD_POOL = { 1001, 1002, 1003, 2001, 2002, 3001, 3002 }

---通用模板（未手工覆盖的 StageBoss_<tier> 用它生成）
BossConfig.Default = {
	id = "Unknown",
	hp = 500,
	phases = makePhases(0.20, 0.15),
	rewards = { gold = 1000, relicPool = {}, modPool = MOD_POOL },
}

---首个阶段 Boss（第 10 层）
BossConfig["StageBoss_0"] = {
	id = "StageBoss_0",
	hp = 800,
	phases = makePhases(0.20, 0.15),
	rewards = { gold = 1000, relicPool = {}, modPool = MOD_POOL },
}

---第 20 层
BossConfig["StageBoss_1"] = {
	id = "StageBoss_1",
	hp = 1600,
	phases = makePhases(0.25, 0.18),
	rewards = { gold = 1800, relicPool = {}, modPool = MOD_POOL },
}

---命名 Boss（FloorConfig 里 bossId="BuriedKing" 时使用）
BossConfig["BuriedKing"] = {
	id = "BuriedKing",
	hp = 2000,
	phases = makePhases(0.30, 0.20),
	rewards = { gold = 2500, relicPool = {}, modPool = MOD_POOL },
}

---取 Boss 模板：手工优先，未定义的 StageBoss_<tier> 按 tier 缩放生成
---@param id string|nil
---@return table
function BossConfig.Get(id)
	if not id then return BossConfig.Default end
	if BossConfig[id] then return BossConfig[id] end

	local tier = tonumber(string.match(id, "StageBoss_(%d+)"))
	if not tier then return BossConfig.Default end

	return {
		id = id,
		hp = math.floor(800 * (1 + 0.8 * tier)),
		phases = makePhases(0.20 + 0.05 * tier, 0.15 + 0.03 * tier),
		rewards = {
			gold = math.floor(1000 * (1 + 0.5 * tier)),
			relicPool = {},
			modPool = MOD_POOL,   -- P6 Mod 系统接入后启用（Boss 必掉 mod）
		},
	}
end

return BossConfig
