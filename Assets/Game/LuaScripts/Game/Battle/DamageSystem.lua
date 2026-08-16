local Class = require "Framework.Core.Class"

local DamageSystem = Class.Define("DamageSystem")

function DamageSystem:Ctor()
    self.playerController = nil
    self.enemyManager = nil
    self.onEnemyKilled = nil
    self.onExpGained = nil
end

function DamageSystem:Init(playerController, enemyManager, onEnemyKilled, onExpGained)
    self.playerController = playerController
    self.enemyManager = enemyManager
    self.onEnemyKilled = onEnemyKilled
    self.onExpGained = onExpGained
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
    self.playerController = nil
    self.enemyManager = nil
    self.onEnemyKilled = nil
    self.onExpGained = nil
end

return DamageSystem