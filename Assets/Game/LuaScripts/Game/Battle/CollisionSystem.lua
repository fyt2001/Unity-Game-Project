local Class = require "Framework.Core.Class"

local CollisionSystem = Class.Define("CollisionSystem")

function CollisionSystem:Ctor()
    self.bulletManager = nil
    self.enemyManager = nil
    self.playerController = nil
    self.damageSystem = nil

    self.bulletHitRadius = 0.5
    self.playerHitRadius = 0.6
end

function CollisionSystem:Init(
    bulletManager,
    enemyManager,
    playerController,
    damageSystem
)
    self.bulletManager = bulletManager
    self.enemyManager = enemyManager
    self.playerController = playerController
    self.damageSystem = damageSystem
end

function CollisionSystem:Update(dt)
    self:_checkBulletCollision()
    self:_checkEnemyPlayerCollision()
end

function CollisionSystem:_checkBulletCollision()
    local bullets =
        self.bulletManager:GetActiveBullets()

    for _, bullet in ipairs(bullets) do
        if not bullet._remove then

            local enemies =
                self.enemyManager:GetEnemiesInRange(
                    bullet.x,
                    bullet.y,
                    self.bulletHitRadius,
                    bullet.pierce and 99 or 1
                )

            for _, enemy in ipairs(enemies) do
                if not bullet.hitIds[enemy.id] then

                    bullet.hitIds[enemy.id] = true

                    local killed =
                        self.damageSystem:DamageEnemy(
                            enemy,
                            bullet.damage,
                            bullet.isCrit
                        )

                    if not bullet.pierce then
                        self.bulletManager:Remove(
                            bullet
                        )
                        break
                    end
                end
            end
        end
    end
end

function CollisionSystem:_checkEnemyPlayerCollision()
    if self.playerController:IsDead() then
        return
    end

    local px, py =
        self.playerController:GetPosition()

    local enemies =
        self.enemyManager:GetEnemiesInRange(
            px,
            py,
            self.playerHitRadius,
            99
        )

    for _, enemy in ipairs(enemies) do
        if enemy.attackCooldown <= 0 then

            self.damageSystem:DamagePlayer(
                enemy.damage
            )

            enemy.attackCooldown =
                enemy.attackInterval
        end
    end
end

function CollisionSystem:Destroy()
    self.bulletManager = nil
    self.enemyManager = nil
    self.playerController = nil
    self.damageSystem = nil
end

return CollisionSystem