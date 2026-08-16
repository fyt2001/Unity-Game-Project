--[[
=============================================================================
UpgradeSystem.lua
=============================================================================
Module:     Game/Battle/UpgradeSystem
Version:    1.0.0

Description:
    升级三选一系统。玩家升级时从随机选项中选择一个强化。
    
    选项类型：
        - 属性加成（atk, atkSpeed, moveSpeed, critRate, critDmg, atkRange, maxHp, lifeSteal）
        - 武器强化（增加武器等级/数量）
        - 获得新武器

Usage:
    local us = UpgradeSystem.New()
    us:Init(playerController, weaponSystem)
    local options = us:GetRandomOptions(3)  -- 获取3个随机选项
    us:ApplyOption(selectedOption)          -- 应用选择
=============================================================================
]]

local Class = require "Framework.Core.Class"

local UpgradeSystem = Class.Define("UpgradeSystem")

-- 选项类型
UpgradeSystem.OptionType = {
    Stat = 1,       -- 属性加成
    WeaponUpgrade = 2,  -- 武器强化
    NewWeapon = 3,      -- 新武器
}

function UpgradeSystem:Ctor()
    self.playerController = nil
    self.weaponSystem = nil

    -- 升级选项池
    self._statOptions = {
        { type = UpgradeSystem.OptionType.Stat, stat = "atk",        name = "攻击力+10",       value = 10,  desc = "基础攻击力提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "atkSpeed",   name = "攻击速度+15%",     value = 0.15, desc = "攻击频率提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "moveSpeed",  name = "移动速度+10%",     value = 0.5,  desc = "移动速度提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "critRate",   name = "暴击率+5%",        value = 0.05, desc = "暴击概率提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "critDmg",    name = "暴击伤害+25%",     value = 0.25, desc = "暴击倍率提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "atkRange",   name = "攻击范围+20%",     value = 0.2,  desc = "攻击距离提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "maxHp",      name = "最大生命+30",      value = 30,   desc = "生命上限提升" },
        { type = UpgradeSystem.OptionType.Stat, stat = "lifeSteal",  name = "吸血+5%",          value = 0.05, desc = "造成伤害回复生命" },
    }
end

function UpgradeSystem:Init(playerController, weaponSystem)
    self.playerController = playerController
    self.weaponSystem = weaponSystem
end

---获取随机升级选项
---@param count number 选项数量（默认3）
---@return table options
function UpgradeSystem:GetRandomOptions(count)
    count = count or 3
    local pool = {}
    
    -- 复制属性选项
    for _, opt in ipairs(self._statOptions) do
        pool[#pool + 1] = opt
    end

    -- 添加武器强化选项（基于已有武器）
    local weapons = self.weaponSystem:GetAllWeapons()
    for _, weapon in ipairs(weapons) do
        if weapon.level < 5 then
            pool[#pool + 1] = {
                type = UpgradeSystem.OptionType.WeaponUpgrade,
                weaponId = weapon.id,
                name = string.format("强化武器 Lv.%d→%d", weapon.level, weapon.level + 1),
                value = { damage = weapon.damage * 0.3, count = weapon.count >= 3 and 0 or 1 },
                desc = "提升武器伤害和数量",
            }
        end
    end

    -- 随机抽取
    local result = {}
    local indices = {}
    local poolSize = #pool

    while #result < count and #indices < poolSize do
        local idx = math.random(1, poolSize)
        if not indices[idx] then
            indices[idx] = true
            result[#result + 1] = pool[idx]
        end
    end

    return result
end

---应用升级选项
---@param option table
function UpgradeSystem:ApplyOption(option)
    if option.type == UpgradeSystem.OptionType.Stat then
        self.playerController:AddStat(option.stat, option.value)
    elseif option.type == UpgradeSystem.OptionType.WeaponUpgrade then
        self.weaponSystem:UpgradeWeapon(option.weaponId, option.value)
    elseif option.type == UpgradeSystem.OptionType.NewWeapon then
        self.weaponSystem:AddWeapon(option.weaponConfig)
    end
end

function UpgradeSystem:Destroy()
    -- 清理
end

return UpgradeSystem
