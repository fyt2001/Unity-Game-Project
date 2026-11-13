--[[
=============================================================================
WeaponSystem.lua
=============================================================================
Module:     Game/Battle/WeaponSystem
Version:    1.1.0

Description:
	武器系统。管理所有武器的自动攻击逻辑。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local VFXConfig = require "Game.Battle.VFXConfig"
local VFXManager = require "Game.Battle.VFXManager"
local BattleLayers = require "Game.Battle.BattleLayers"
local ChainLightningView = require "Game.Battle.View.ChainLightningView"
local FlyingSwordView = require "Game.Battle.View.FlyingSwordView"

local WeaponSystem = Class.Define("WeaponSystem")

WeaponSystem.Pattern = {
	Melee = 1,
	Projectile = 2,
	AOE = 3,
	Orbit = 4,
	Chain = 5,
	Beam = 6,
}

-- 弹道枚举 → 名称（供 VFX 配置按名称匹配，避免循环依赖）
local PatternName = {}
for _k, _v in pairs(WeaponSystem.Pattern) do PatternName[_v] = _k end

function WeaponSystem:Ctor()
	self.playerController = nil
	self.weapons = {}
	self.bulletManager = nil
	self.enemyManager = nil
	self.damageSystem = nil
	self._attackTimers = {}
	self._modDamageMul = 1
	self._modProjectileBonus = 0
	self._primaryWeaponId = nil
	self._pendingAttacks = {}
	self._combatView = nil
	self._combatPaused = false
end

local function combatView()
	return _G.ViewConfig and _G.ViewConfig.playerView
end

-- Only a held sword/gun drives the character; secondary weapons retain their own timers.
function WeaponSystem:SetPrimaryWeapon(weaponId)
	for _, weapon in ipairs(self.weapons) do
		if weapon.id == weaponId and (weapon.pattern == self.Pattern.Melee or weapon.pattern == self.Pattern.Projectile) then
			if self._primaryWeaponId ~= weaponId then
				local paused = self._combatPaused
				self:ResetCombatPresentation()
				self._primaryWeaponId = weaponId
				self:SetCombatPaused(paused)
			end
			return true
		end
	end
	return false
end

function WeaponSystem:ResetCombatPresentation()
	self._pendingAttacks = {}
	self._combatPaused = false
	local view = self._combatView or combatView()
	if view then
		pcall(function() view:SetCombatPaused(false) end)
		pcall(function() view:ResetCombatWeapon() end)
	end
	self._combatView = nil
end

function WeaponSystem:SetCombatPaused(paused)
	self._combatPaused = paused == true
	local view = self._combatView or combatView()
	if view then pcall(function() view:SetCombatPaused(self._combatPaused) end) end
end

function WeaponSystem:_ensureCombatView()
	local view = combatView()
	if view ~= self._combatView then
		self._combatView = view
		for _, weapon in ipairs(self.weapons) do
			if view and weapon.id == self._primaryWeaponId then
				pcall(function() view:EquipCombatWeapon(weapon.pattern) end)
				break
			end
		end
		if view then pcall(function() view:SetCombatPaused(self._combatPaused) end) end
	end
	return view
end

function WeaponSystem:_releaseAttack(weapon, held)
	if held then
		local px, py = self.playerController:GetPosition()
		local maxRange = weapon.pattern == self.Pattern.Melee and weapon.range or nil
		if not self.enemyManager:GetNearestEnemy(px, py, nil, maxRange) then
			self:_executeAttack(weapon)
			return
		end
		local view = self:_ensureCombatView()
		if view then pcall(function() view:ReleaseCombatAttack(weapon.pattern) end) end
	end
	self:_executeAttack(weapon, held)
end

function WeaponSystem:_scheduleAttack(weapon, interval, overdue)
	if weapon.id ~= self._primaryWeaponId then
		self:_executeAttack(weapon)
		return
	end
	local view = self:_ensureCombatView()
	local px, py = self.playerController:GetPosition()
	local maxRange = weapon.pattern == self.Pattern.Melee and weapon.range or nil
	local target = self.enemyManager:GetNearestEnemy(px, py, nil, maxRange)
	if not target then
		-- Retain the existing gameplay tick, without pretending an empty shot is an attack pose.
		self:_executeAttack(weapon)
		return
	end
	local delay = 0
	if view and target then
		local dx, dy = target.x - px, target.y - py
		local length = math.sqrt(dx * dx + dy * dy)
		if length > 0 then dx, dy = dx / length, dy / length end
		local ok, value = pcall(function() return view:BeginCombatAttack(weapon.pattern, dx, dy, interval) end)
		if ok and type(value) == "number" and value == value then delay = math.max(0, value) end
	end
	-- The timer remainder is time already elapsed since this attack became due.
	-- Subtract it so a long frame does not postpone every catch-up shot by another windup.
	delay = delay - overdue
	if delay <= 0 then
		self:_releaseAttack(weapon, true)
	else
		self._pendingAttacks[#self._pendingAttacks + 1] = { weapon = weapon, remaining = delay }
	end
end

function WeaponSystem:SetModDerived(derived)
	local mul = derived and derived.mul or {}
	local add = derived and derived.add or {}
	local damageMul = mul.damageMul or 1
	local extra = math.max(0, math.floor(add.projectileCount or 0))
	for _, weapon in ipairs(self.weapons) do
		weapon.damage = weapon.damage / self._modDamageMul * damageMul
		if weapon.pattern == WeaponSystem.Pattern.Projectile then
			weapon.count = math.max(1, weapon.count - self._modProjectileBonus + extra)
		end
	end
	self._modDamageMul = damageMul
	self._modProjectileBonus = extra
end

function WeaponSystem:Init(playerController)
	self.playerController = playerController
end

function WeaponSystem:Inject(bulletManager, enemyManager, damageSystem)
	self.bulletManager = bulletManager
	self.enemyManager = enemyManager
	self.damageSystem = damageSystem
end

function WeaponSystem:AddWeapon(config)
	config = config or {}
	local weapon = {
		id = config.id,
		pattern = config.pattern or WeaponSystem.Pattern.Projectile,
		damage = (config.damage or 10) * self._modDamageMul,
		interval = config.interval or 1.0,
		range = config.range or 5.0,
		count = config.count or 1,
		projectileSpeed = config.projectileSpeed or 10,
		projectileType = config.projectileType or "normal",
		aoeRadius = config.aoeRadius or 2.0,
		pierce = config.pierce or false,
		level = config.level or 1,
	patternName = PatternName[config.pattern or WeaponSystem.Pattern.Projectile] or "Projectile",
	}
	if weapon.pattern == WeaponSystem.Pattern.Projectile then
		weapon.count = weapon.count + self._modProjectileBonus
	end
	table.insert(self.weapons, weapon)
	self._attackTimers[weapon.id] = 0
	local canHold = weapon.pattern == self.Pattern.Melee or weapon.pattern == self.Pattern.Projectile
	if self._primaryWeaponId == nil and canHold then
		self:SetPrimaryWeapon(weapon.id)
	end
end

function WeaponSystem:UpgradeWeapon(weaponId, upgradeData)
	upgradeData = upgradeData or {}
	for _, weapon in ipairs(self.weapons) do
		if weapon.id == weaponId then
			weapon.level = weapon.level + 1
			if upgradeData.damage then weapon.damage = weapon.damage + upgradeData.damage end
			if upgradeData.count then weapon.count = weapon.count + upgradeData.count end
			if upgradeData.range then weapon.range = weapon.range + upgradeData.range end
			if upgradeData.interval then
				weapon.interval = math.max(0.1, weapon.interval - upgradeData.interval)
			end
			return
		end
	end
end

function WeaponSystem:Update(dt)
	if not self.playerController or not self.enemyManager then
		return
	end
	if self.playerController.isDead then
		self:ResetCombatPresentation()
		return
	end
	if self._combatPaused then return end
	self:_ensureCombatView()
	local pending = self._pendingAttacks
	self._pendingAttacks = {}
	for _, attack in ipairs(pending) do
		attack.remaining = attack.remaining - dt
		if attack.remaining <= 0 then
			self:_releaseAttack(attack.weapon, true)
		else
			self._pendingAttacks[#self._pendingAttacks + 1] = attack
		end
	end

	local stats = self.playerController:GetStats()
	local atkSpeedMult = math.max(0.01, stats.atkSpeed or 1)

	for _, weapon in ipairs(self.weapons) do
		self._attackTimers[weapon.id] = self._attackTimers[weapon.id] + dt
		local effectiveInterval = math.max(0.01, weapon.interval / atkSpeedMult)

		while self._attackTimers[weapon.id] >= effectiveInterval do
			self._attackTimers[weapon.id] = self._attackTimers[weapon.id] - effectiveInterval
			self:_scheduleAttack(weapon, effectiveInterval, self._attackTimers[weapon.id])
		end
	end

	-- 环绕飞剑是【持续环绕】的表现，不能只在攻击那一拍更新，必须每帧驱动。
	self:_updateFlyingSword(dt)
end

---环绕飞剑的视觉驱动（与伤害结算解耦：伤害在 _attackOrbit，这里只管画）。
-- 每帧都要跑：飞剑持续绕着玩家转，只在 interval(默认 1.5s) 那一拍更新会一卡一卡。
-- 多把 Orbit 武器时取并集：剑数累加、半径取最大。剑外观由美术资产
-- FlyingSword.prefab 承载（见 View/FlyingSwordView.lua 头注释）。
function WeaponSystem:_updateFlyingSword(dt)
	if not self.playerController then return end

	local count, radius = 0, 0
	for _, weapon in ipairs(self.weapons) do
		if weapon.pattern == WeaponSystem.Pattern.Orbit then
			local vfx = VFXConfig.Get(weapon)
			count = count + (weapon.count or 1)
			radius = math.max(radius, vfx.orbitRadius or (weapon.range or 4.0) * 0.45)
		end
	end

	local px, py = self.playerController:GetPosition()
	FlyingSwordView.Update(dt, px, py, count, radius)
end

function WeaponSystem:_damageEnemy(enemy, damage, isCrit)
	if not enemy or enemy.isDead then
		return false
	end
	if self.damageSystem then
		return self.damageSystem:DamageEnemy(enemy, damage, isCrit)
	end
	return self.enemyManager:TakeDamage(enemy.id, damage, isCrit)
end

function WeaponSystem:_executeAttack(weapon, held)
	local px, py = self.playerController:GetPosition()
	local dmg, isCrit = self.playerController:CalcDamage()
	dmg = dmg + weapon.damage
	local vfx = VFXConfig.Get(weapon)

	if weapon.pattern == WeaponSystem.Pattern.Melee then
		self:_attackMelee(weapon, px, py, dmg, isCrit, vfx)
	elseif weapon.pattern == WeaponSystem.Pattern.Projectile then
		self:_attackProjectile(weapon, px, py, dmg, isCrit, vfx, held)
	elseif weapon.pattern == WeaponSystem.Pattern.AOE then
		self:_attackAOE(weapon, px, py, dmg, isCrit, vfx)
	elseif weapon.pattern == WeaponSystem.Pattern.Orbit then
		self:_attackOrbit(weapon, px, py, dmg, isCrit, vfx)
	elseif weapon.pattern == WeaponSystem.Pattern.Chain then
		self:_attackChain(weapon, px, py, dmg, isCrit, vfx)
	elseif weapon.pattern == WeaponSystem.Pattern.Beam then
		self:_attackBeam(weapon, px, py, dmg, isCrit, vfx)
	end
end

function WeaponSystem:_attackMelee(weapon, px, py, dmg, isCrit, vfx)
	local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.range, weapon.count)
	for _, enemy in ipairs(targets) do
		self:_damageEnemy(enemy, dmg, isCrit)
		if vfx and vfx.hit then VFXManager.Spawn(vfx.hit, enemy.x, enemy.y, BattleLayers.GroundHit) end
	end
end

function WeaponSystem:_attackProjectile(weapon, px, py, dmg, isCrit, vfx, held)
	if not self.bulletManager then return end
	-- Select targets around the player as before; attachment offsets only change shot origin.
	local targets = self.enemyManager:GetNearestEnemies(px, py, weapon.count)
	if #targets == 0 then return end
	local spawnHeight
	if held then
		local view = self:_ensureCombatView()
		if view then
			local ok, muzzle = pcall(function() return view:GetCombatMuzzlePosition() end)
			if ok and muzzle then px, py, spawnHeight = muzzle.x, muzzle.z, muzzle.y end
		end
	end
	if vfx and vfx.muzzle then VFXManager.Spawn(vfx.muzzle, px, py, spawnHeight or BattleLayers.Projectile) end
	for shot = 1, weapon.count do
		local enemy = targets[(shot - 1) % #targets + 1]
		local ex, ey = enemy.x, enemy.y
		local dirX, dirY = ex - px, ey - py
		local len = math.sqrt(dirX * dirX + dirY * dirY)
		if len > 0 then
			dirX, dirY = dirX / len, dirY / len
		end
		-- Repeated targets still receive distinct projectiles when only one enemy remains.
		if weapon.count > #targets then
			local angle = (shot - (weapon.count + 1) / 2) * 0.04
			local c, s = math.cos(angle), math.sin(angle)
			dirX, dirY = dirX * c - dirY * s, dirX * s + dirY * c
		end
		self.bulletManager:SpawnBullet({
			x = px, y = py,
			visualSpawnHeight = spawnHeight,
			dirX = dirX, dirY = dirY,
			speed = weapon.projectileSpeed,
			damage = dmg,
			isCrit = isCrit,
			range = weapon.range,
			pierce = weapon.pierce,
			bulletType = weapon.projectileType,
		})
	end
end

function WeaponSystem:_attackAOE(weapon, px, py, dmg, isCrit, vfx)
	if vfx and vfx.cast then VFXManager.Spawn(vfx.cast, px, py, BattleLayers.Projectile) end
	if vfx and vfx.explosion then VFXManager.Spawn(vfx.explosion, px, py, BattleLayers.GroundHit, nil, weapon.aoeRadius) end
	local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.aoeRadius, 99)
	for _, enemy in ipairs(targets) do
		self:_damageEnemy(enemy, dmg, isCrit)
	end
end

function WeaponSystem:_attackOrbit(weapon, px, py, dmg, isCrit, vfx)
	local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.range, weapon.count)
	for _, enemy in ipairs(targets) do
		self:_damageEnemy(enemy, dmg * 0.5, isCrit)
		if vfx and vfx.hit then VFXManager.Spawn(vfx.hit, enemy.x, enemy.y, BattleLayers.GroundHit) end
	end
end

function WeaponSystem:_attackChain(weapon, px, py, dmg, isCrit, vfx)
	local chained = {}
	local sourceX, sourceY = px, py
	local chainPoints = { { x = px, y = py } }   -- 记录完整跳跃路径（起点→每个被链中的敌人）
	local maxRange = weapon.range               -- 每跳最大跳跃距离，避免跨全图串联

	for i = 1, weapon.count do
		local target = self.enemyManager:GetNearestEnemy(sourceX, sourceY, chained, maxRange)
		if not target then break end
		table.insert(chained, target)
		self:_damageEnemy(target, dmg * (1 - (i - 1) * 0.2), isCrit)
		if vfx and vfx.hit then
			VFXManager.Spawn(vfx.hit, target.x, target.y, BattleLayers.GroundHit)
		end
		chainPoints[#chainPoints + 1] = { x = target.x, y = target.y }
		sourceX, sourceY = target.x, target.y
	end

	-- 绘制闪电连线（程序化 LineRenderer，参数由 VFXConfig 透传）
	if #chainPoints >= 2 then
		ChainLightningView.Spawn(chainPoints, {
			height    = BattleLayers.Projectile,
			lifetime  = (vfx and vfx.chainLifetime) or 0.18,
			jitter    = (vfx and vfx.chainJitter) or 0.35,
			width     = (vfx and vfx.chainWidth) or 0.12,
			color     = (vfx and vfx.chainColor) or { 0.6, 0.85, 1.0 },
		})
	end
end

function WeaponSystem:_attackBeam(weapon, px, py, dmg, isCrit, vfx)
	local target = self.enemyManager:GetNearestEnemy(px, py, nil, weapon.range)
	if target then
		ChainLightningView.Spawn({ { x = px, y = py }, { x = target.x, y = target.y } }, {
			name = "WeaponBeam", height = BattleLayers.Projectile, jitter = 0,
			width = (vfx and vfx.beamWidth) or 0.1,
			lifetime = (vfx and vfx.beamLifetime) or 0.16,
			color = (vfx and vfx.beamColor) or { 0.45, 0.9, 0.3 },
		})
		self:_damageEnemy(target, dmg * 0.8, isCrit)
		if vfx and vfx.hit then VFXManager.Spawn(vfx.hit, target.x, target.y, BattleLayers.GroundHit) end
	end
end

function WeaponSystem:GetAllWeapons()
	return self.weapons
end

function WeaponSystem:Destroy()
	self:ResetCombatPresentation()
	self._primaryWeaponId = nil
	-- 战斗结束 / 切场景后不再有每帧 Update，飞剑必须显式收起，
	-- 否则剑体会残留在场景里（与 EnemyManager:Destroy 清残留视图同理）。
	FlyingSwordView.Hide()

	self.weapons = {}
	self._attackTimers = {}
	self.playerController = nil
	self.bulletManager = nil
	self.enemyManager = nil
	self.damageSystem = nil
end

return WeaponSystem
