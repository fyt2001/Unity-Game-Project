local Class = require "Framework.Core.Class"

local DamageSystem = Class.Define("DamageSystem")

function DamageSystem:Ctor()
    self.playerController = nil
    self.enemyManager = nil
end

function DamageSystem:Init(playerController, enemyManager)
    self.playerController = playerController
    self.enemyManager = enemyManager
end

function DamageSystem:DamageEnemy(enemy, damage, isCrit)
    if not enemy or enemy.isDead then
        return false
    end

    return self.enemyManager:TakeDamage(
        enemy.id,
        damage,
        isCrit
    )
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
end

return DamageSystem