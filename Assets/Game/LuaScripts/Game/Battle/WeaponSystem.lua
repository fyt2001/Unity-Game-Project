--[[
=============================================================================
WeaponSystem.lua
=============================================================================
Module:     Game/Battle/WeaponSystem
Version:    1.0.0

Description:
    武器系统。管理所有武器的自动攻击逻辑。
    
    设计原则：
        - 数据驱动：武器行为由配置决定，不写死每种武器
        - 组件化：武器由 AttackPattern + ProjectileType + Effect 组合
        - 与 PlayerController 解耦，通过接口交互

    攻击模式（AttackPattern）：
        - Melee: 近战范围攻击
        - Projectile: 发射弹道子弹
        - AOE: 范围爆炸
        - Orbit: 环绕飞行物
        - Chain: 连锁闪电
        - Beam: 持续光束

Usage:
    local ws = WeaponSystem.New()
    ws:Init(playerController)
    ws:AddWeapon(weaponConfig)
    ws:Update(dt)
=============================================================================
]]

local Class = require "Framework.Core.Class"

local WeaponSystem = Class.Define("WeaponSystem")

-- 攻击模式枚举
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
    self.weapons = {}        -- { weaponData }
    self.bulletManager = nil -- 由外部注入
    self.enemyManager = nil  -- 由外部注入

    -- 攻击计时
    self._attackTimers = {}  -- { [weaponId] = elapsed }
end

---初始化
---@param playerController table
function WeaponSystem:Init(playerController)
    self.playerController = playerController
end

---注入依赖
---@param bulletManager table
---@param enemyManager table
function WeaponSystem:Inject(bulletManager, enemyManager)
    self.bulletManager = bulletManager
    self.enemyManager = enemyManager
end

---添加武器
---@param config table 武器配置 { id, pattern, damage, interval, range, count, projectileType, ... }
function WeaponSystem:AddWeapon(config)
    local weapon = {
        id = config.id,
        pattern = config.pattern or WeaponSystem.Pattern.Projectile,
        damage = config.damage or 10,
        interval = config.interval or 1.0,     -- 攻击间隔（秒）
        range = config.range or 5.0,
        count = config.count or 1,             -- 每次攻击数量
        projectileSpeed = config.projectileSpeed or 10,
        projectileType = config.projectileType or "normal",
        aoeRadius = config.aoeRadius or 2.0,
        pierce = config.pierce or false,       -- 穿透
        level = config.level or 1,
    }
    table.insert(self.weapons, weapon)
    self._attackTimers[config.id] = 0
end

---升级武器
---@param weaponId number
---@param upgradeData table { damage, count, range, ... }
function WeaponSystem:UpgradeWeapon(weaponId, upgradeData)
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

---每帧更新
---@param dt number 秒
function WeaponSystem:Update(dt)
    local stats = self.playerController:GetStats()
    local atkSpeedMult = stats.atkSpeed

    for _, weapon in ipairs(self.weapons) do
        self._attackTimers[weapon.id] = self._attackTimers[weapon.id] + dt

        local effectiveInterval = weapon.interval / atkSpeedMult

        if self._attackTimers[weapon.id] >= effectiveInterval then
            self._attackTimers[weapon.id] = self._attackTimers[weapon.id] - effectiveInterval
            self:_executeAttack(weapon)
        end
    end
end

---执行攻击
function WeaponSystem:_executeAttack(weapon)
    local px, py, pz = self.playerController:GetPosition()
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

---近战攻击：范围伤害
function WeaponSystem:_attackMelee(weapon, px, py, dmg, isCrit)
    local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.range, weapon.count)
    for _, enemy in ipairs(targets) do
        self.enemyManager:TakeDamage(enemy.id, dmg, isCrit)
    end
end

---发射弹道子弹
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
            x = px, y = py,
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

---AOE 范围爆炸
function WeaponSystem:_attackAOE(weapon, px, py, dmg, isCrit)
    local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.aoeRadius, 99)
    for _, enemy in ipairs(targets) do
        self.enemyManager:TakeDamage(enemy.id, dmg, isCrit)
    end
end

---环绕飞行物
function WeaponSystem:_attackOrbit(weapon, px, py, dmg, isCrit)
    -- 环绕物由 BulletManager 特殊管理，这里只负责伤害判定
    local targets = self.enemyManager:GetEnemiesInRange(px, py, weapon.range, weapon.count)
    for _, enemy in ipairs(targets) do
        self.enemyManager:TakeDamage(enemy.id, dmg * 0.5, isCrit)
    end
end

---连锁闪电
function WeaponSystem:_attackChain(weapon, px, py, dmg, isCrit)
    local chainCount = weapon.count
    local chained = {}
    local sourceX, sourceY = px, py

    for i = 1, chainCount do
        local target = self.enemyManager:GetNearestEnemy(sourceX, sourceY, chained)
        if not target then break end

        table.insert(chained, target)
        self.enemyManager:TakeDamage(target.id, dmg * (1 - (i - 1) * 0.2), isCrit)

        sourceX, sourceY = target.x, target.y
    end
end

---持续光束（暂未实现完整逻辑，预留接口）
function WeaponSystem:_attackBeam(weapon, px, py, dmg, isCrit)
    -- TODO: 实现持续光束攻击，需要 Beam 状态管理
    -- 当前回退为最近敌人单体伤害
    local target = self.enemyManager:GetNearestEnemy(px, py)
    if target then
        self.enemyManager:TakeDamage(target.id, dmg * 0.8, isCrit)
    end
end

---获取所有武器信息
---@return table
function WeaponSystem:GetAllWeapons()
    return self.weapons
end

function WeaponSystem:Destroy()
    self.weapons = {}
    self._attackTimers = {}
end

return WeaponSystem