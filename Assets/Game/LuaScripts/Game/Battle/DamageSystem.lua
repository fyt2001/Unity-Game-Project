local Class = require "Framework.Core.Class"

local DamageSystem = Class.Define("DamageSystem")

function DamageSystem:Ctor()
    self.playerController = nil
    self.enemyManager = nil
    self.onEnemyKilled = nil
    self.onExpGained = nil
end

--- 初始化伤害系统并注册统一死亡回调
---@param playerController table
---@param enemyManager table
---@param onEnemyKilled function|nil function(enemyId, enemy)
---@param onExpGained function|nil function(exp, enemy)
function DamageSystem:Init(playerController, enemyManager, onEnemyKilled, onExpGained)
    self.playerController = playerController
    self.enemyManager = enemyManager
    self.onEnemyKilled = onEnemyKilled
    self.onExpGained = onExpGained

    -- 所有敌人死亡事件统一经过 DamageSystem，避免 Weapon/Collision 各自处理死亡奖励。
    if self.enemyManager then
        self.enemyManager:SetOnEnemyKilled(function(enemyId, enemy)
            if self.onEnemyKilled then
                self.onEnemyKilled(enemyId, enemy)
            end

            if self.onExpGained and enemy then
                self.onExpGained(enemy.exp or 0, enemy)
            end
        end)
    end
end

function DamageSystem:DamageEnemy(enemy, damage, isCrit)
    if not enemy or enemy.isDead or not self.enemyManager then
        return false
    end

    local killed = self.enemyManager:TakeDamage(
        enemy.id,
        damage,
        isCrit
    )

    if killed then
        if self.onEnemyKilled then
            self.onEnemyKilled(enemy.id)
        end
        if self.onExpGained and enemy.exp and enemy.exp > 0 then
            self.onExpGained(enemy.exp)
        end
    end

    return killed
end

function DamageSystem:DamagePlayer(damage)
    if not self.playerController then
        return 0
    end

    return self.playerController:TakeDamage(damage)
end

function DamageSystem:Destroy()
    if self.enemyManager then
        self.enemyManager:SetOnEnemyKilled(nil)
    end

    self.playerController = nil
    self.enemyManager = nil
    self.onEnemyKilled = nil
    self.onExpGained = nil
end

return DamageSystem
