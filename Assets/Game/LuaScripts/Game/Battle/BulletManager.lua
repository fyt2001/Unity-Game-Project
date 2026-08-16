local Class = require "Framework.Core.Class"
local ObjectPool = require "Framework.Core.ObjectPool"

local BulletManager = Class.Define("BulletManager")

function BulletManager:Ctor()
    self.bullets = {}
    self._pendingRemove = {}
    self._pool = nil
    self.enemyManager = nil
end

function BulletManager:Init()
    self.bullets = {}
    self._pendingRemove = {}

    self._pool = ObjectPool.New(
        function()
            return {
                x = 0,
                y = 0,
                dirX = 0,
                dirY = 0,
                speed = 0,
                damage = 0,
                isCrit = false,
                range = 0,
                traveled = 0,
                pierce = false,
                bulletType = "normal",
                hitIds = {},
                _remove = false,
            }
        end,
        function(b)
            b.x = 0
            b.y = 0
            b.dirX = 0
            b.dirY = 0
            b.speed = 0
            b.damage = 0
            b.isCrit = false
            b.range = 0
            b.traveled = 0
            b.pierce = false
            b.bulletType = "normal"
            b._remove = false

            for k in pairs(b.hitIds) do
                b.hitIds[k] = nil
            end
        end,
        32,
        256
    )
end

function BulletManager:Inject(enemyManager)
    self.enemyManager = enemyManager
end

function BulletManager:SpawnBullet(config)
    config = config or {}
    local bullet = self._pool:Get()

    bullet.x = config.x or 0
    bullet.y = config.y or 0
    bullet.dirX = config.dirX or 0
    bullet.dirY = config.dirY or 0
    bullet.speed = config.speed or 10
    bullet.damage = config.damage or 10
    bullet.isCrit = config.isCrit or false
    bullet.range = config.range or 10
    bullet.traveled = 0
    bullet.pierce = config.pierce or false
    bullet.bulletType = config.bulletType or "normal"
    bullet._remove = false

    table.insert(self.bullets, bullet)
    return bullet
end

function BulletManager:Update(dt)
    for _, bullet in ipairs(self.bullets) do
        if not bullet._remove then
            local moveDist = bullet.speed * dt
            bullet.x = bullet.x + bullet.dirX * moveDist
            bullet.y = bullet.y + bullet.dirY * moveDist
            bullet.traveled = bullet.traveled + moveDist

            if bullet.traveled >= bullet.range then
                self:Remove(bullet)
            end
        end
    end
end

function BulletManager:Remove(bullet)
    if not bullet or bullet._remove then
        return
    end

    bullet._remove = true
    self._pendingRemove[#self._pendingRemove + 1] = bullet
end

function BulletManager:Cleanup()
    if #self._pendingRemove == 0 then
        return
    end

    for _, bullet in ipairs(self._pendingRemove) do
        for i = #self.bullets, 1, -1 do
            if self.bullets[i] == bullet then
                table.remove(self.bullets, i)
                break
            end
        end
        self._pool:Release(bullet)
    end

    self._pendingRemove = {}
end

function BulletManager:GetActiveBullets()
    return self.bullets
end

function BulletManager:GetActiveCount()
    return #self.bullets
end

function BulletManager:Destroy()
    self.bullets = {}
    self._pendingRemove = {}

    if self._pool then
        self._pool:Clear()
    end

    self._pool = nil
    self.enemyManager = nil
end

return BulletManager
