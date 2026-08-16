--[[
=============================================================================
WeaponSystem.lua
=============================================================================
Module:     Game/Battle/WeaponSystem
Version:    1.1.1

Description:
    武器系统。管理所有武器的自动攻击逻辑。

    设计原则：
        - 数据驱动：武器行为由配置决定，不写死每种武器
        - 组件化：武器由 AttackPattern + ProjectileType + Effect 组合
        - 与 PlayerController 解耦，通过接口交互
        - 伤害统一交给 DamageSystem
=============================================================================
]]

local Class = require "Framework.Core.Class"

local WeaponSystem = Class.Define("WeaponSystem")

WeaponSystem.Pattern = {
    Melee = 1,
    Projectile = 2,
    AOE = 3,
    Orbit = 4,
    Chain = 5,
    Beam = 6,
}

function WeaponSystem:Ctor()
    self.playerController = nil
    self.weapons = {}
    self.bulletManager = nil
    self.enemyManager = nil
    self.damageSystem = nil
    self._attackTimers = {}
end

function WeaponSystem:Init(playerController)
    self.playerController = playerController
end

--- 注入战斗依赖
---@param bulletManager table
---@param enemyManager table
---@param damageSystem table
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
        damage = config.damage or 10,
        interval = config.interval or 1.0,
        range = config.range or 5.0,
        count = config.count or 1,
        projectileSpeed = config.projectileSpeed or 10,
        projectileType = config.projectileType or "normal",
        aoeRadius = config.aoeRadius or 2.0,
        pierce = config.pierce or false,
        level = config.level or 1,
    }

    table.insert(self.weapons, weapon)
    self._attackTimers[weapon.id] = 0
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
    if not self.playerController then
        return
    end

    local stats = self.playerController:GetStats()
    local atkSpeedMult = stats.atkSpeed or 1
    if atkSpeedMult <= 0 then
        atkSpeedMult = 1
    end

    for _, weapon in ipairs(self.weapons) do
        self._attackTimers[weapon.id] = self._attackTimers[weapon.id] + dt

        local effectiveInterval = weapon.interval / atkSpeedMult

        if self._attackTimers[weapon.id] >= effectiveInterval then
            self._attackTimers[weapon.id] = self._attackTimers[weapon.id] - effectiveInterval
            self:_executeAttack(weapon)
        end
    end
end

function WeaponSystem:_executeAttack(weapon)
    local px, py = self.playerController:GetPosition()
    local dmg, isCrit = self.playerController:CalcDamage()
    dmg = dmg + weapon.damage

    local pattern = weapon.pattern

    if pattern == WeaponSystem.Pattern.Melee then
        self:_attackMelee(weapon, px, py, dmg, isCrit)
    elseif pattern == WeaponSystem.Pattern.Projectile then
        self:_attackProjectile(weapon, px, py, dmg, isCrit)
    elseif pattern == WeaponSystem.Pattern.AOE then
        self:_attackAOE(weapon, px, py, dmg, isCrit)
    elseif pattern == WeaponSystem.Pattern.Orbit then
        self:_attackOrbit(weapon, px, py, dmg, isCrit)
    elseif pattern == WeaponSystem.Pattern.Chain then
        self:_attackChain(weapon, px, py, dmg, isCrit)
    elseif pattern == WeaponSystem.Pattern.Beam then
        self:_attackBeam(weapon, px, py, dmg, isCrit)
    end
end

--- 统一伤害入口。V1.1 要求所有武器伤害经过 DamageSystem。
function WeaponSystem:_damageEnemy(enemy, damage, isCrit)
    if not enemy or enemy.isDead then
        return false
    end

    if self.damageSystem then
        return self.damageSystem:DamageEnemy(enemy, damage, isCrit)
    end

    -- 兼容独立使用 WeaponSystem 的旧调用方；BattleManager 正常运行时不会走这里。
    if self.enemyManager then
        return self.enemyManager:TakeDamage(enemy.id, damage, isCrit)
    end

    return false
end

function WeaponSystem:_attackMelee(weapon, px, py, dmg, isCrit)
    local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.range, weapon.count)
    for _, enemy in ipairs(targets) do
        self:_damageEnemy(enemy, dmg, isCrit)
    end
end

function WeaponSystem:_attackProjectile(weapon, px, py, dmg, isCrit)
    local targets = self.enemyManager:GetNearestEnemies(px, py, weapon.count)
    for _, enemy in ipairs(targets) do
        local ex, ey = enemy.x, enemy.y
        local dirX = ex - px
        local dirY = ey - py
        local len = math.sqrt(dirX * dirX + dirY * dirY)
        if len > 0 then
            dirX = dirX / len
            dirY = dirY / len
        end

        self.bulletManager:SpawnBullet({
            x = px,
            y = py,
            dirX = dirX,
            dirY = dirY,
            speed = weapon.projectileSpeed,
            damage = dmg,
            isCrit = isCrit,
            range = weapon.range,
            pierce = weapon.pierce,
            bulletType = weapon.projectileType,
        })
    end
end

function WeaponSystem:_attackAOE(weapon, px, py, dmg, isCrit)
    local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.aoeRadius, 99)
    for _, enemy in ipairs(targets) do
        self:_damageEnemy(enemy, dmg, isCrit)
    end
end

function WeaponSystem:_attackOrbit(weapon, px, py, dmg, isCrit)
    local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.range, weapon.count)
    for _, enemy in ipairs(targets) do
        self:_damageEnemy(enemy, dmg * 0.5, isCrit)
    end
end

function WeaponSystem:_attackChain(weapon, px, py, dmg, isCrit)
    local chainCount = weapon.count
    local chained = {}
    local sourceX, sourceY = px, py

    for i = 1, chainCount do
        local target = self.enemyManager:GetNearestEnemy(sourceX, sourceY, chained)
        if not target then
            break
        end

        table.insert(chained, target)
        self:_damageEnemy(target, dmg * (1 - (i - 1) * 0.2), isCrit)
        sourceX, sourceY = target.x, target.y
    end
end

--- Beam V1.1 暂不实现持续光束，保留明确的单目标回退行为。
function WeaponSystem:_attackBeam(weapon, px, py, dmg, isCrit)
    local target = self.enemyManager:GetNearestEnemy(px, py)
    if target then
        self:_damageEnemy(target, dmg * 0.8, isCrit)
    end
end

function WeaponSystem:GetAllWeapons()
    return self.weapons
end

function WeaponSystem:Destroy()
    self.weapons = {}
    self._attackTimers = {}
    self.playerController = nil
    self.bulletManager = nil
    self.enemyManager = nil
    self.damageSystem = nil
end

return WeaponSystem
