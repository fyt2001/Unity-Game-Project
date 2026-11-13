--[[
=============================================================================
VFXConfig.lua - 武器/技能 特效映射表
=============================================================================
Module:     Game/Battle/VFXConfig

Description:
	把「武器 id / 弹道模式 / 抛射物类型」映射到特效预制体路径（Resources 下）。

	三级覆盖优先级（高 → 低）：
		WeaponId[weapon.id]  >  Pattern[patternName]  >  ProjectileType[projectileType]

	路径命名建议（待美术把素材放到 Assets/Game/Resources/VFX/ 下）：
		VFX/Proj_Frost_Muzzle      枪口
		VFX/Proj_Frost_Impact      命中
		VFX/Fireball_Cast          施法
		VFX/Fireball_Explosion     爆炸
		VFX/Sword_Slash            挥砍
		VFX/Lightning_Spark        电火花
		VFX/Beam_Hit               射线命中
		VFX/Melee_Slash            近战挥砍

	Combat feedback prefabs reuse the imported Kenney CC0 textures.
	See Resources/VFX/Combat/SOURCE.md for provenance and playback budgets.
=============================================================================
]]

local VFXConfig = {}

---抛射物类型 → 特效（对应武器配置的 projectileType 字段）
-- 弹体特效改由「子弹本体」承载（见 VFXConfig.Bullet）：
-- 这里不再生成静态枪口 / 命中——子弹本身就是那枚飞行弹体，再叠一次等于两颗弹。
VFXConfig.ProjectileType = {
	frost      = { muzzle = nil, impact = nil },
	fire       = { muzzle = nil, impact = nil },
	electric   = { muzzle = nil, impact = nil },
	water      = { muzzle = nil, impact = nil },
	wind       = { muzzle = nil, impact = nil },
	light      = { muzzle = nil, impact = nil },
	venom      = { muzzle = nil, impact = nil },
	dark_magic = { muzzle = nil, impact = nil },
	normal     = { muzzle = nil, impact = nil },
}

---子弹本体视觉：bulletType → 弹体预制体。
-- 由 BulletView 实例化并挂在子弹上随其移动；弹头与拖尾（TrailRenderer）
-- 依赖运动才生效，所以只能这样用，不能当静态爆点生成在某个坐标。
-- normal 留空 → 回退到 ViewConfig 的发光小球。
-- ⚠ 注意：本表只决定「若某把 Projectile 武器用了该元素，弹体长什么样」。
--   只有 pattern=Projectile 的武器才会生成飞行弹体（见 WeaponSystem），
--   当前 BuildConfig 里仅有 w_frostbolt 是 Projectile，故实际只会用到 frost。
VFXConfig.Bullet = {
	frost      = "VFX/CasualRPGVFX/prefabs/Projectiles_frost",
	fire       = "VFX/CasualRPGVFX/prefabs/Projectiles_fire",
	electric   = "VFX/CasualRPGVFX/prefabs/Projectiles_electric",
	water      = "VFX/CasualRPGVFX/prefabs/Projectiles_water",
	wind       = "VFX/CasualRPGVFX/prefabs/Projectiles_wind",
	light      = "VFX/CasualRPGVFX/prefabs/Projectiles_light",
	venom      = "VFX/CasualRPGVFX/prefabs/Projectiles_magic",
	dark_magic = "VFX/CasualRPGVFX/prefabs/Projectiles_dark_magic",
	normal     = nil,
}

---弹道模式 → 特效（键名为字符串，避免与 WeaponSystem 形成循环依赖）
-- Impact prefabs are separate bursts, not stationary projectile substitutes.
VFXConfig.Pattern = {
	Projectile = { muzzle = nil, hit = nil },
	AOE        = { cast = "VFX/Combat/FireCast", explosion = "VFX/Combat/FireExplosion" },
	-- Orbit（飞剑）：hit 是「剑刃砍中敌人的瞬时火花」。
	-- SwordHitVFX.prefab = Kenney Particle Pack（CC0）贴图组装的三套粒子：
	-- 中心闪光(star_05) + 电弧四散(spark_04) + 月牙斩弧(slash_01)，染剑的青色调。
	-- 来源与许可见 VFX/FlyingSword/SOURCE.txt。（旧权宜方案 Projectiles_wind 已废弃——
	-- 风刃弹体当爆点会变成一团原地粒子且拖尾不出。）
	Orbit      = { hit = "VFX/FlyingSword/SwordHitVFX" },
	Chain      = { hit = "VFX/Combat/LightningHit", chainColor = { 0.6, 0.85, 1.0 }, chainWidth = 0.14, chainLifetime = 0.18, chainJitter = 0.4 },
	Beam       = { hit = "VFX/Combat/VenomHit", beamColor = { 0.45, 0.9, 0.3 }, beamWidth = 0.1, beamLifetime = 0.16 },
	Melee      = { hit = "VFX/FlyingSword/SwordHitVFX" },
}

---武器 id → 特效（覆盖优先级最高；留空则回退到 弹道模式 / 抛射物类型）
VFXConfig.WeaponId = {
	w_frostbolt   = {},   -- 走 ProjectileType.frost
	w_fireball    = {},   -- 走 Pattern.AOE
	-- 环绕飞剑：剑本体为美术资产 VFX/FlyingSword/FlyingSword.prefab
	-- （KayKit CC0 剑模型 + TrailRenderer 剑光，来源与许可见该目录 SOURCE.txt），
	-- 这里只提供环绕半径。命中火花沿用 Pattern.Orbit 的配置。
	w_flyingsword = { orbitRadius = 1.8 },   -- 走 Pattern.Orbit
	w_venom       = {},   -- 走 Pattern.Beam
	w_chain       = { chainColor = { 0.7, 0.9, 1.0 }, chainWidth = 0.16, chainJitter = 0.45 },  -- 走 Pattern.Chain
}

---技能 id → 施法特效（由 BuildSystem:Apply 在玩家处触发）
---暂无施法光环素材，留空（等美术正式素材，见 VFXConfig.Common 注释）
VFXConfig.Skill = {}

---遗物 id → 获得特效（由 BuildSystem:Apply 在玩家处触发）
---暂无获得特效素材，留空
VFXConfig.Relic = {}

---通用战斗特效（不区分来源：任何命中/死亡/受伤都走这里）
-- Short, non-looping bursts; pooling owns cleanup rather than StopAction.Destroy.
VFXConfig.Common = {
	enemyHit     = "VFX/Combat/EnemyHit",
	enemyCrit    = "VFX/Combat/CriticalHit",
	enemyDeath   = "VFX/Combat/EnemyDeath",
	eliteDeath   = "VFX/Combat/EliteDeath",
	bossDeath    = "VFX/Combat/BossDeath",
	playerHurt   = "VFX/Combat/PlayerHurt",
	levelUp      = "VFX/Combat/LevelUp",
	footstepDust = nil,  -- 每步触发会刷屏
}

---取技能/遗物选项的特效路径
---@param option table BuildSystem 的 { type = "BuildSkill"|"BuildRelic", id = ... }
---@return string|nil 预制体路径
function VFXConfig.GetForBuild(option)
	if not option then return nil end
	if option.type == "BuildSkill" then
		return VFXConfig.Skill[option.id]
	elseif option.type == "BuildRelic" then
		return VFXConfig.Relic[option.id]
	end
	return nil
end

---收集配置里出现的全部特效路径（供 VFXManager.Preload 预热）
---@return string[] paths
function VFXConfig.AllPaths()
	local paths = {}
	local seen = {}

	local function add(v)
		if type(v) == "string" and v ~= "" and not seen[v] then
			seen[v] = true
			paths[#paths + 1] = v
		end
	end

	local function collect(t)
		for _, v in pairs(t or {}) do
			if type(v) == "string" then
				add(v)
			elseif type(v) == "table" then
				collect(v)
			end
		end
	end

	collect(VFXConfig.ProjectileType)
	collect(VFXConfig.Pattern)
	collect(VFXConfig.WeaponId)
	collect(VFXConfig.Skill)
	collect(VFXConfig.Relic)
	collect(VFXConfig.Common)

	return paths
end

---取某武器的合并特效配置
---@param weapon table WeaponSystem 的武器实例（需含 id / patternName / projectileType）
---@return table { muzzle, hit, cast, explosion, aura }
function VFXConfig.Get(weapon)
	weapon = weapon or {}
	local byId   = weapon.id and VFXConfig.WeaponId[weapon.id]
	local byPat  = VFXConfig.Pattern[weapon.patternName]
	local byType = weapon.projectileType and VFXConfig.ProjectileType[weapon.projectileType]

	-- ⚠ 不能写成 ipairs({ ... })：本函数的全部意义就是「跳过 nil 继续往下取」，
	--    而变参 spread 进表后若首位是 nil，ipairs 会【立即终止】，整条回退链直接失效。
	--    （后果：WeaponId 里没写、只有 Pattern 里写了路径的槽位永远取不到值 ——
	--      Orbit.hit 就是这样一直返回 nil 的。）
	--    改用 select('#', ...) 保留 nil 占位后逐个取。
	local function pick(...)
		local n = select("#", ...)
		for i = 1, n do
			local v = select(i, ...)
			if v ~= nil then return v end
		end
		return nil
	end

	return {
		muzzle    = pick(byId and byId.muzzle,    byType and byType.muzzle,    byPat and byPat.muzzle),
		hit       = pick(byId and byId.hit,       byPat and byPat.hit,         byType and byType.hit),
		cast      = pick(byId and byId.cast,      byPat and byPat.cast),
		explosion = pick(byId and byId.explosion, byPat and byPat.explosion),
		aura      = pick(byId and byId.aura,      byPat and byPat.aura),
		chainColor     = pick(byId and byId.chainColor,     byPat and byPat.chainColor),
		chainWidth     = pick(byId and byId.chainWidth,     byPat and byPat.chainWidth),
		chainLifetime  = pick(byId and byId.chainLifetime,  byPat and byPat.chainLifetime),
		chainJitter    = pick(byId and byId.chainJitter,    byPat and byPat.chainJitter),
		beamColor      = pick(byId and byId.beamColor,      byPat and byPat.beamColor),
		beamWidth      = pick(byId and byId.beamWidth,      byPat and byPat.beamWidth),
		beamLifetime   = pick(byId and byId.beamLifetime,   byPat and byPat.beamLifetime),
		-- 环绕飞剑（FlyingSwordView）专用：环绕半径（剑外观在 prefab 里）
		orbitRadius    = pick(byId and byId.orbitRadius,    byPat and byPat.orbitRadius),
	}
end

return VFXConfig
