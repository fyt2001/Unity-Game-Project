--[[
=============================================================================
PlayerController.lua
=============================================================================
Module:     Game/Battle/PlayerController
Version:    1.0.0

Description:
    玩家控制器。处理：
        - 移动输入（摇杆/键盘）
        - 属性管理（HP/ATK/SPD/CRIT等）
        - 经验值和升级
        - 死亡判定

    玩家不手动攻击，武器系统自动攻击。

Usage:
    local pc = PlayerController.New()
    pc:Init(config)
    pc:Update(dt)
=============================================================================
]]

local Class = require "Framework.Core.Class"

local PlayerController = Class.Define("PlayerController")

function PlayerController:Ctor()
    -- 位置
    self.x = 0
    self.y = 0
    self.z = 0

    -- 属性
    self.maxHp = 100
    self.hp = 100
    self.atk = 10         -- 基础攻击力
    self.atkSpeed = 1.0   -- 攻击速度倍率
    self.moveSpeed = 5.0  -- 移动速度
    self.critRate = 0.05  -- 暴击率
    self.critDmg = 1.5    -- 暴击倍率
    self.atkRange = 1.0   -- 攻击范围倍率
    self.lifeSteal = 0    -- 吸血

    -- 成长
    self.level = 1
    self.exp = 0
    self.expToNext = 100

    -- 状态
    self.isDead = false
    self.isInvincible = false
    self.invincibleTimer = 0

    -- 输入
    self.inputX = 0
    self.inputY = 0
    self.boundsMinX = nil
    self.boundsMaxX = nil
    self.boundsMinY = nil
    self.boundsMaxY = nil
end

---初始化
---@param config table 玩家配置
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

---每帧更新
---@param dt number 秒
function PlayerController:Update(dt)
    if self.isDead then return end

    -- 无敌计时
    if self.isInvincible then
        self.invincibleTimer = self.invincibleTimer - dt
        if self.invincibleTimer <= 0 then
            self.isInvincible = false
        end
    end

    -- 移动
    if self.inputX ~= 0 or self.inputY ~= 0 then
        local dx = self.inputX * self.moveSpeed * dt
        local dy = self.inputY * self.moveSpeed * dt
        self.x = self.x + dx
        self.y = self.y + dy

        -- 边界限制
        self:_clampPosition()
    end
end

---设置移动输入
---@param x number -1到1
---@param y number -1到1
function PlayerController:SetInput(x, y)
    self.inputX = x or 0
    self.inputY = y or 0
end

---获取位置
---@return number, number, number
function PlayerController:GetPosition()
    return self.x, self.y, self.z
end

---受到伤害
---@param damage number
---@return number actualDamage 实际伤害
function PlayerController:TakeDamage(damage)
    if self.isDead or self.isInvincible then return 0 end

    local actualDmg = math.max(1, damage)
    self.hp = self.hp - actualDmg

    if self.hp <= 0 then
        self.hp = 0
        self.isDead = true
    end

    return actualDmg
end

---治疗
---@param amount number
function PlayerController:Heal(amount)
    if self.isDead then return end
    self.hp = math.min(self.maxHp, self.hp + amount)
end

---获得经验
---@param exp number
---@return boolean leveledUp 是否升级
function PlayerController:AddExp(exp)
    self.exp = self.exp + exp
    if self.exp >= self.expToNext then
        self.exp = self.exp - self.expToNext
        self.level = self.level + 1
        self.expToNext = self:_calcNextExp()
        -- 升级时回血
        self.hp = math.min(self.maxHp, self.hp + self.maxHp * 0.3)
        return true
    end
    return false
end

---计算下一级所需经验
function PlayerController:_calcNextExp()
    return math.floor(100 + self.level * 20)
end

---应用属性加成
---@param stat string 属性名
---@param value number 加成值
function PlayerController:AddStat(stat, value)
    if stat == "atk" then
        self.atk = self.atk + value
    elseif stat == "atkSpeed" then
        self.atkSpeed = self.atkSpeed + value
    elseif stat == "moveSpeed" then
        self.moveSpeed = self.moveSpeed + value
    elseif stat == "critRate" then
        self.critRate = math.min(1.0, self.critRate + value)
    elseif stat == "critDmg" then
        self.critDmg = self.critDmg + value
    elseif stat == "atkRange" then
        self.atkRange = self.atkRange + value
    elseif stat == "lifeSteal" then
        self.lifeSteal = self.lifeSteal + value
    elseif stat == "maxHp" then
        self.maxHp = self.maxHp + value
        self.hp = self.hp + value
    end
end

---计算实际伤害（含暴击）
---@return number damage, boolean isCrit
function PlayerController:CalcDamage()
    local dmg = self.atk
    local isCrit = math.random() < self.critRate
    if isCrit then
        dmg = dmg * self.critDmg
    end
    return math.floor(dmg), isCrit
end

---边界限制
function PlayerController:_clampPosition()
    if self.boundsMinX and self.x < self.boundsMinX then self.x = self.boundsMinX end
    if self.boundsMaxX and self.x > self.boundsMaxX then self.x = self.boundsMaxX end
    if self.boundsMinY and self.y < self.boundsMinY then self.y = self.boundsMinY end
    if self.boundsMaxY and self.y > self.boundsMaxY then self.y = self.boundsMaxY end
end

---是否死亡
---@return boolean
function PlayerController:IsDead()
    return self.isDead
end

---获取属性快照
---@return table
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
    -- 清理
end

return PlayerController
