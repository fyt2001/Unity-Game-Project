--[[
=============================================================================
EnemyConfig.lua - 敌人属性配置表
=============================================================================
Module:     Game/Battle/EnemyConfig
Version:    1.0.0

Description:
	敌人兵种基础属性 + 精英倍率 + 按 enemyLevel 的等级缩放。

	此前这些属性硬编码在 SpawnSystem:_getBaseHp/_getBaseSpeed/
	_getBaseDamage/_getBaseExp 四个函数里，无法被 Elite / Boss / 其它系统
	复用，也无法让策划只改数值。这里统一抽出（埋骨渊方案.md 附录 H）。

	兵种原型（附录 H）：
		近战小兵 slime    数量主体，直冲玩家
		远程/快   bat      高移速，逼走位
		精英型   skeleton  高血量高伤
		Boss     boss      多阶段
=============================================================================
]]

local EnemyConfig = {}

---兵种基础属性
EnemyConfig.Base = {
	slime    = { hp = 30,  speed = 1.5, damage = 5,  exp = 5,   attackInterval = 1.0 },
	bat      = { hp = 20,  speed = 3.0, damage = 8,  exp = 8,   attackInterval = 0.8 },
	skeleton = { hp = 80,  speed = 2.0, damage = 15, exp = 20,  attackInterval = 1.2 },
	boss     = { hp = 500, speed = 1.0, damage = 30, exp = 200, attackInterval = 1.5 },
}

---实体分类（按兵种）：
---  enemy  = 持武敌人（skeleton）：携带武器、用武器攻击玩家、击杀掉落该武器
---  monster= 怪物（slime/bat）：不持武器，击杀只掉落材料
---  boss   = Boss（Mod/金币由 BossConfig 单独处理）
EnemyConfig.Category = {
	slime    = "monster",
	bat      = "monster",
	skeleton = "enemy",
	boss     = "boss",
}

---近战兵种攻击范围（进入后停步攻击，而非无限贴脸）。单位：世界坐标距离
EnemyConfig.AttackRange = {
	slime    = 1.2,
	bat      = 1.0,
	skeleton = 2.0,
	boss     = 2.5,
}

---持武敌人（skeleton）可携带的武器池：
---击杀掉落的正是它携带的这把，且用它远程攻击玩家。
---纳入多元素抛射武器，使战斗中能稳定展示 VFXConfig.Bullet 中的全部元素弹体。
EnemyConfig.WeaponPool = {
	skeleton = {
		"w_frostbolt", "w_venom", "w_chain",
		"w_firebolt", "w_electricbolt", "w_waterbolt", "w_windblade",
		"w_lightbolt", "w_arcanbolt", "w_darkbolt",
	},
}

---怪物（非持武）死亡时掉落的材料
EnemyConfig.MaterialDrop = {
	slime = "m_gel",
	bat   = "m_wing",
}

---精英倍率
EnemyConfig.Elite = {
	hpMult = 2.0,
	damageMult = 1.5,
	speedMult = 1.1,
	expMult = 2.5,
}

---等级缩放系数（附录 D）
EnemyConfig.HP_SCALE_PER_LEVEL = 0.18
EnemyConfig.DMG_SCALE_PER_LEVEL = 0.15

---默认兵种（未知 type 时的兜底）
EnemyConfig.FALLBACK = "slime"

---取兵种基础属性
---@param enemyType string
---@return table
function EnemyConfig.Get(enemyType)
	return EnemyConfig.Base[enemyType] or EnemyConfig.Base[EnemyConfig.FALLBACK]
end

---按敌人等级（+是否精英）计算最终属性
---@param base table 兵种基础属性
---@param enemyLevel number 敌人等级
---@param isElite boolean|nil 是否精英
---@return table { hp, damage, speed, exp, attackInterval }
function EnemyConfig.Scale(base, enemyLevel, isElite)
	base = base or EnemyConfig.Get(EnemyConfig.FALLBACK)
	enemyLevel = enemyLevel or 1

	local hpScale = 1 + EnemyConfig.HP_SCALE_PER_LEVEL * (enemyLevel - 1)
	local dmgScale = 1 + EnemyConfig.DMG_SCALE_PER_LEVEL * (enemyLevel - 1)

	local hp = (base.hp or 50) * hpScale
	local damage = (base.damage or 10) * dmgScale
	local speed = base.speed or 2.0
	local exp = base.exp or 10

	if isElite then
		hp = hp * EnemyConfig.Elite.hpMult
		damage = damage * EnemyConfig.Elite.damageMult
		speed = speed * EnemyConfig.Elite.speedMult
		exp = exp * EnemyConfig.Elite.expMult
	end

	return {
		hp = math.floor(hp),
		damage = damage,
		speed = speed,
		exp = math.floor(exp),
		attackInterval = base.attackInterval or 1.0,
	}
end

return EnemyConfig
