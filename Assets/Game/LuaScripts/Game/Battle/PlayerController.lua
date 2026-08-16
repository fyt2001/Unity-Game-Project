--[[
=============================================================================
PlayerController.lua
=============================================================================
Module:     Game/Battle/PlayerController
Version:    1.1.0
=============================================================================
]]

local Class = require "Framework.Core.Class"

local PlayerController = Class.Define("PlayerController")

function PlayerController:Ctor()
    self.x, self.y, self.z = 0, 0, 0
    self.maxHp, self.hp = 100, 100
    self.atk = 10
    self.atkSpeed = 1.0
    self.moveSpeed = 5.0
    self.critRate = 0.05
    self.critDmg = 1.5
    self.atkRange = 1.0
    self.lifeSteal = 0
    self.level = 1
    self.exp = 0
    self.expToNext = 100
    self.isDead = false
    self.isInvincible = false
    self.invincibleTimer = 0
    self.inputX, self.inputY = 0, 0
    self.boundsMinX, self.boundsMaxX = nil, nil
    self.boundsMinY, self.boundsMaxY = nil, nil
end

function PlayerController:Init(config)
    config = config or {}
    self.maxHp = config.maxHp or 100
    self.hp = self.maxHp
    self.atk = config.atk or 10
    self.moveSpeed = config.moveSpeed or 5.0
    self.boundsMinX = config.boundsMinX
    self.boundsMaxX = config.boundsMaxX
    self.boundsMinY = config.boundsMinY
    self.boundsMaxY = config.boundsMaxY
end

function PlayerController:Update(dt)
    if self.isDead then return end

    if self.isInvincible then
        self.invincibleTimer = self.invincibleTimer - dt
        if self.invincibleTimer <= 0 then
            self.isInvincible = false
            self.invincibleTimer = 0
        end
    end

    if self.inputX ~= 0 or self.inputY ~= 0 then
        self.x = self.x + self.inputX * self.moveSpeed * dt
        self.y = self.y + self.inputY * self.moveSpeed * dt
        self:_clampPosition()
    end
end

function PlayerController:SetInput(x, y)
    self.inputX = x or 0
    self.inputY = y or 0
end

function PlayerController:GetPosition()
    return self.x, self.y, self.z
end

function PlayerController:TakeDamage(damage)
    if self.isDead or self.isInvincible then return 0 end
    local actualDmg = math.max(1, damage or 0)
    self.hp = self.hp - actualDmg
    if self.hp <= 0 then
        self.hp = 0
        self.isDead = true
    end
    return actualDmg
end

function PlayerController:Heal(amount)
    if self.isDead then return end
    self.hp = math.min(self.maxHp, self.hp + math.max(0, amount or 0))
end

function PlayerController:AddExp(exp)
    exp = math.max(0, exp or 0)
    if exp <= 0 or self.isDead then return false end

    self.exp = self.exp + exp
    local leveledUp = false

    -- 一次获得大量经验时允许连续升级，避免经验条超过阈值后卡住。
    while self.exp >= self.expToNext do
        self.exp = self.exp - self.expToNext
        self.level = self.level + 1
        self.expToNext = self:_calcNextExp()
        self.hp = math.min(self.maxHp, self.hp + self.maxHp * 0.3)
        leveledUp = true
    end

    return leveledUp
end

function PlayerController:_calcNextExp()
    return math.floor(100 + self.level * 20)
end

function PlayerController:AddStat(stat, value)
    value = value or 0
    if stat == "atk" then
        self.atk = self.atk + value
    elseif stat == "atkSpeed" then
        self.atkSpeed = math.max(0.01, self.atkSpeed + value)
    elseif stat == "moveSpeed" then
        self.moveSpeed = math.max(0, self.moveSpeed + value)
    elseif stat == "critRate" then
        self.critRate = math.min(1.0, math.max(0, self.critRate + value))
    elseif stat == "critDmg" then
        self.critDmg = math.max(1, self.critDmg + value)
    elseif stat == "atkRange" then
        self.atkRange = math.max(0, self.atkRange + value)
    elseif stat == "lifeSteal" then
        self.lifeSteal = math.min(1.0, math.max(0, self.lifeSteal + value))
    elseif stat == "maxHp" then
        self.maxHp = math.max(1, self.maxHp + value)
        self.hp = math.min(self.maxHp, self.hp + value)
    end
end

function PlayerController:CalcDamage()
    local dmg = self.atk
    local isCrit = math.random() < self.critRate
    if isCrit then dmg = dmg * self.critDmg end
    return math.floor(dmg), isCrit
end

function PlayerController:_clampPosition()
    if self.boundsMinX and self.x < self.boundsMinX then self.x = self.boundsMinX end
    if self.boundsMaxX and self.x > self.boundsMaxX then self.x = self.boundsMaxX end
    if self.boundsMinY and self.y < self.boundsMinY then self.y = self.boundsMinY end
    if self.boundsMaxY and self.y > self.boundsMaxY then self.y = self.boundsMaxY end
end

function PlayerController:IsDead()
    return self.isDead
end

function PlayerController:GetStats()
    return {
        level = self.level,
        exp = self.exp,
        expToNext = self.expToNext,
        hp = self.hp,
        maxHp = self.maxHp,
        atk = self.atk,
        atkSpeed = self.atkSpeed,
        moveSpeed = self.moveSpeed,
        critRate = self.critRate,
        critDmg = self.critDmg,
        atkRange = self.atkRange,
        lifeSteal = self.lifeSteal,
    }
end

function PlayerController:Destroy()
end

return PlayerController