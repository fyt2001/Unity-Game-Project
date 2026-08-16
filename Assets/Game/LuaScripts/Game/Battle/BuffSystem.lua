--[[
=============================================================================
BuffSystem.lua V1.1.1
=============================================================================
Description:
    管理玩家 Buff / Debuff 生命周期、叠层与属性应用。

V1.1.1 修复：
    - 叠层 Buff 只应用新增层数，避免重复/少算
    - 移除叠层 Buff 按当前总层数正确回滚
    - 多个 invincible Buff 并存时，移除其中一个不会错误取消无敌
    - Destroy / ClearAll 后正确重置状态
=============================================================================
]]

local Class = require "Framework.Core.Class"

local BuffSystem = Class.Define("BuffSystem")

function BuffSystem:Ctor()
    self.playerController = nil
    self.buffs = {}
    self._idCounter = 0
end

function BuffSystem:Init(playerController)
    self.playerController = playerController
    self.buffs = {}
    self._idCounter = 0
end

function BuffSystem:AddBuff(config)
    config = config or {}
    local buffType = config.type
    local value = config.value or 0
    local maxStack = config.maxStack or 1

    -- 可叠加 Buff：只对新增层数应用增量。
    if maxStack > 1 then
        local existing = self:_findBuff(buffType, config.source)
        if existing then
            local oldStack = existing.stack
            local newStack = math.min(oldStack + 1, maxStack)
            if newStack > oldStack then
                existing.stack = newStack
                self:_applyDelta(existing, newStack - oldStack)
            end
            existing.remaining = config.duration or existing.remaining
            return existing.id
        end
    end

    self._idCounter = self._idCounter + 1
    local buff = {
        id = self._idCounter,
        type = buffType,
        value = value,
        remaining = config.duration or 0,
        isPermanent = not config.duration or config.duration <= 0,
        stack = 1,
        maxStack = maxStack,
        source = config.source,
    }

    self:_applyDelta(buff, 1)
    self.buffs[#self.buffs + 1] = buff
    return buff.id
end

function BuffSystem:RemoveBuff(buffId)
    for i = #self.buffs, 1, -1 do
        local buff = self.buffs[i]
        if buff.id == buffId then
            self:_removeBuffEffect(buff)
            table.remove(self.buffs, i)
            self:_refreshSpecialStates()
            return
        end
    end
end

function BuffSystem:RemoveBuffBySource(source)
    for i = #self.buffs, 1, -1 do
        local buff = self.buffs[i]
        if buff.source == source then
            self:_removeBuffEffect(buff)
            table.remove(self.buffs, i)
        end
    end
    self:_refreshSpecialStates()
end

function BuffSystem:Update(dt)
    if not dt or dt <= 0 then return end

    local toRemove = {}
    for i, buff in ipairs(self.buffs) do
        if not buff.isPermanent then
            buff.remaining = buff.remaining - dt
            if buff.remaining <= 0 then
                toRemove[#toRemove + 1] = i
            end
        end
    end

    for i = #toRemove, 1, -1 do
        local idx = toRemove[i]
        local buff = self.buffs[idx]
        if buff then
            self:_removeBuffEffect(buff)
            table.remove(self.buffs, idx)
        end
    end

    if #toRemove > 0 then
        self:_refreshSpecialStates()
    end
end

-- 应用指定层数的增量。
function BuffSystem:_applyDelta(buff, stackDelta)
    if not self.playerController or stackDelta == 0 then return end

    if buff.type == "invincible" then
        self:_refreshSpecialStates()
        return
    end

    self.playerController:AddStat(buff.type, buff.value * stackDelta)
end

-- 完整回滚当前 Buff 已提供的所有层数。
function BuffSystem:_removeBuffEffect(buff)
    if not self.playerController then return end

    if buff.type ~= "invincible" then
        self.playerController:AddStat(buff.type, -(buff.value * buff.stack))
    end
end

-- 特殊状态不应简单使用单个 Buff 的 isAdd 覆盖。
function BuffSystem:_refreshSpecialStates()
    if not self.playerController then return end

    local invincible = false
    for _, buff in ipairs(self.buffs) do
        if buff.type == "invincible" then
            invincible = true
            break
        end
    end
    self.playerController.isInvincible = invincible
end

function BuffSystem:_findBuff(buffType, source)
    for _, buff in ipairs(self.buffs) do
        if buff.type == buffType and buff.source == source then
            return buff
        end
    end
    return nil
end

function BuffSystem:GetAllBuffs()
    return self.buffs
end

function BuffSystem:ClearAll()
    for _, buff in ipairs(self.buffs) do
        self:_removeBuffEffect(buff)
    end
    self.buffs = {}
    if self.playerController then
        self.playerController.isInvincible = false
    end
end

function BuffSystem:Destroy()
    self:ClearAll()
    self.playerController = nil
end

return BuffSystem
