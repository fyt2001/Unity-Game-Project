--[[
=============================================================================
BuffSystem.lua
=============================================================================
Module:     Game/Battle/BuffSystem
Version:    1.0.0

Description:
    Buff/Debuff 系统。管理玩家身上的所有增益和减益效果。
    
    支持类型：
        - 永久 Buff（装备/被动技能）
        - 临时 Buff（限时）
        - 叠层 Buff

Usage:
    local bs = BuffSystem.New()
    bs:Init(playerController)
    bs:AddBuff({ type = "atk", value = 10, duration = 30 })
    bs:Update(dt)
=============================================================================
]]

local Class = require "Framework.Core.Class"

local BuffSystem = Class.Define("BuffSystem")

function BuffSystem:Ctor()
    self.playerController = nil
    self.buffs = {}        -- 活跃 Buff 列表
    self._idCounter = 0
end

---初始化
---@param playerController table
function BuffSystem:Init(playerController)
    self.playerController = playerController
end

---添加 Buff
---@param config table { type, value, duration, maxStack, source }
---@return number buffId
function BuffSystem:AddBuff(config)
    -- 检查是否可叠加
    if config.maxStack then
        local existing = self:_findBuff(config.type, config.source)
        if existing then
            existing.stack = math.min((existing.stack or 1) + 1, config.maxStack)
            existing.remaining = config.duration or 0
            return existing.id
        end
    end

    self._idCounter = self._idCounter + 1
    local buff = {
        id = self._idCounter,
        type = config.type,         -- "atk", "atkSpeed", "moveSpeed", "invincible", etc.
        value = config.value or 0,
        remaining = config.duration or 0,  -- 剩余时间（秒），0或nil表示永久
        isPermanent = not config.duration or config.duration <= 0,
        stack = 1,
        maxStack = config.maxStack or 1,
        source = config.source,     -- 来源标识（用于叠加判断）
    }

    -- 立即应用效果
    self:_applyBuff(buff, true)
    table.insert(self.buffs, buff)

    return buff.id
end

---移除 Buff
---@param buffId number
function BuffSystem:RemoveBuff(buffId)
    for i = #self.buffs, 1, -1 do
        if self.buffs[i].id == buffId then
            self:_applyBuff(self.buffs[i], false) -- 移除效果
            table.remove(self.buffs, i)
            return
        end
    end
end

---移除某来源的所有 Buff
---@param source string
function BuffSystem:RemoveBuffBySource(source)
    for i = #self.buffs, 1, -1 do
        if self.buffs[i].source == source then
            self:_applyBuff(self.buffs[i], false)
            table.remove(self.buffs, i)
        end
    end
end

---每帧更新
---@param dt number 秒
function BuffSystem:Update(dt)
    local toRemove = {}

    for i, buff in ipairs(self.buffs) do
        if not buff.isPermanent then
            buff.remaining = buff.remaining - dt
            if buff.remaining <= 0 then
                toRemove[#toRemove + 1] = i
            end
        end
    end

    -- 倒序移除
    for i = #toRemove, 1, -1 do
        local idx = toRemove[i]
        self:_applyBuff(self.buffs[idx], false)
        table.remove(self.buffs, idx)
    end
end

---应用/移除 Buff 效果
function BuffSystem:_applyBuff(buff, isAdd)
    if not self.playerController then return end

    local value = buff.value * buff.stack
    if not isAdd then value = -value end

    self.playerController:AddStat(buff.type, value)

    -- 特殊类型处理
    if buff.type == "invincible" then
        self.playerController.isInvincible = isAdd
    end
end

---查找同类型同来源的 Buff
function BuffSystem:_findBuff(buffType, source)
    for _, buff in ipairs(self.buffs) do
        if buff.type == buffType and buff.source == source then
            return buff
        end
    end
    return nil
end

---获取所有活跃 Buff
---@return table
function BuffSystem:GetAllBuffs()
    return self.buffs
end

---清除所有 Buff
function BuffSystem:ClearAll()
    for _, buff in ipairs(self.buffs) do
        self:_applyBuff(buff, false)
    end
    self.buffs = {}
end

function BuffSystem:Destroy()
    self:ClearAll()
end

return BuffSystem
