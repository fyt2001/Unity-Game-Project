--[[
=============================================================================
BuildConfig.lua - Build 池（武器 / 技能 / 遗物）
=============================================================================
Module:     Game/Build/BuildConfig
Version:    1.0.0

Description:
	Build 三分类的候选池（设计稿 §8）：
		Weapon  决定主要攻击方式
		Skill   改变战斗能力（本阶段实现为「属性包」）
		Relic   改变规则（本阶段实现为「属性/规则属性」）

	武器配置的字段与 WeaponSystem:AddWeapon 完全兼容
	（pattern / damage / interval / range / count / projectileSpeed /
	  projectileType / aoeRadius / pierce / level）。

	⚠ 技能与遗物当前都落到【属性】上：
	  工程尚无独立技能系统与召唤实体，因此「召唤」等只给属性加成，
	  待对应系统建成后再升级为真实行为（P7 缺口 #4）。
=============================================================================
]]

local WeaponSystem = require "Game.Battle.WeaponSystem"

local BuildConfig = {}

---武器池（pattern 取自 WeaponSystem.Pattern）
BuildConfig.Weapons = {
	{
		id = "w_frostbolt", name = "冰霜弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 12, interval = 1.0, range = 8.0, count = 1,
		projectileSpeed = 12, projectileType = "frost", pierce = false,
		desc = "直线冰霜弹，命中减速目标",
	},
	{
		id = "w_fireball", name = "火球", pattern = WeaponSystem.Pattern.AOE,
		damage = 20, interval = 2.0, range = 7.0, count = 1,
		aoeRadius = 2.5, desc = "落点爆炸，范围伤害",
	},
	{
		id = "w_flyingsword", name = "飞剑", pattern = WeaponSystem.Pattern.Orbit,
		damage = 15, interval = 1.5, range = 4.0, count = 2,
		desc = "环绕飞剑，持续切割近身敌人",
	},
	{
		id = "w_venom", name = "毒液", pattern = WeaponSystem.Pattern.Beam,
		damage = 8, interval = 0.5, range = 6.0, count = 1,
		desc = "高频毒液射线，持续输出",
	},
	{
		id = "w_chain", name = "雷链", pattern = WeaponSystem.Pattern.Chain,
		damage = 18, interval = 1.8, range = 6.0, count = 3,
		desc = "闪电链，跳跃命中多个目标",
	},

	-- 多元素抛射武器：让 VFXConfig.Bullet 中每种元素弹体都能在战斗中实际出现。
	-- 统一为 Projectile 模式，弹体视觉由 projectileType 经 VFXConfig.Bullet 解析
	-- （数据驱动、单一数据源，代码不散落硬编码路径）。
	{
		id = "w_firebolt", name = "炎弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 16, interval = 1.1, range = 7.0, count = 1,
		projectileSpeed = 13, projectileType = "fire", pierce = false,
		desc = "炽炎弹，命中点燃",
	},
	{
		id = "w_electricbolt", name = "电光弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 10, interval = 0.8, range = 8.0, count = 1,
		projectileSpeed = 16, projectileType = "electric", pierce = false,
		desc = "高频电光弹",
	},
	{
		id = "w_waterbolt", name = "水流弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 11, interval = 1.0, range = 8.0, count = 1,
		projectileSpeed = 12, projectileType = "water", pierce = false,
		desc = "水流弹，命中减速",
	},
	{
		id = "w_windblade", name = "风刃", pattern = WeaponSystem.Pattern.Projectile,
		damage = 13, interval = 0.9, range = 9.0, count = 1,
		projectileSpeed = 18, projectileType = "wind", pierce = true,
		desc = "风刃，可穿透",
	},
	{
		id = "w_lightbolt", name = "圣光弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 14, interval = 1.0, range = 8.0, count = 1,
		projectileSpeed = 14, projectileType = "light", pierce = false,
		desc = "圣光弹，命中致盲",
	},
	{
		id = "w_arcanbolt", name = "奥术弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 12, interval = 1.0, range = 8.0, count = 1,
		projectileSpeed = 12, projectileType = "magic", pierce = false,
		desc = "奥术弹，命中削弱",
	},
	{
		id = "w_darkbolt", name = "暗影弹", pattern = WeaponSystem.Pattern.Projectile,
		damage = 15, interval = 1.2, range = 7.0, count = 1,
		projectileSpeed = 11, projectileType = "dark_magic", pierce = false,
		desc = "暗影弹，侵蚀生命",
	},
}

---技能池（属性包）
BuildConfig.Skills = {
	{ id = "s_frostnova", name = "寒冰Nova", stats = { atk = 8, atkRange = 0.3 }, desc = "提升攻击与范围" },
	{ id = "s_frostshield", name = "冰霜护盾", stats = { maxHp = 50 }, desc = "大幅提升生命上限" },
	{ id = "s_lightning", name = "闪电链", stats = { atkSpeed = 0.2, critRate = 0.03 }, desc = "提升攻速与暴击" },
	-- 召唤：当前无召唤实体，仅给属性，待召唤物系统建成后升级为真实行为
	{ id = "s_summon", name = "召唤", stats = { lifeSteal = 0.05, moveSpeed = 0.3 }, desc = "（待召唤实体）提升吸血与移速" },
}

---遗物池（规则/属性）
BuildConfig.Relics = {
	{ id = "r_frostbite", name = "霜结", stats = { critRate = 0.05, critDmg = 0.25 }, desc = "暴击率+5%，暴伤+25%" },
	{ id = "r_fullrage", name = "满血狂怒", stats = { atk = 15 }, desc = "满血时伤害提升" },
	{ id = "r_elitehunter", name = "精英猎手", stats = { lifeSteal = 0.08 }, desc = "击杀精英回复生命" },
	{ id = "r_gale", name = "疾风", stats = { moveSpeed = 1.0 }, desc = "移动速度大幅提升" },
}

---按 id 取武器定义
function BuildConfig.GetWeapon(id)
	for _, w in ipairs(BuildConfig.Weapons) do
		if w.id == id then return w end
	end
	return nil
end

return BuildConfig
