--[[
=============================================================================
ConfigManager.lua
=============================================================================
Module:     Framework/Config/ConfigManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    配置表管理器。负责加载和管理所有 Excel/Json 导出的配置数据。
    支持按 ID 查询、条件筛选、批量获取。

Usage:
    local ConfigManager = require "Framework.Config.ConfigManager"
    local cm = ConfigManager.GetInstance()
    
    -- 注册配置表
    cm:Register("Weapon", require "Config.Data.table_Weapon")
    
    -- 查询
    local weaponConfig = cm:GetById("Weapon", 1001)
    local allWeapons = cm:GetAll("Weapon")
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Singleton = require "Framework.Core.Singleton"

local ConfigManager = Class.Define("ConfigManager")
Class.Extend(ConfigManager, Singleton)

function ConfigManager:Ctor()
    self._configs = {}  -- { [name] = { rawData, indexById } }
end

---注册配置表
---@param name string 配置表名称
---@param rawData table 原始配置数据
function ConfigManager:Register(name, rawData)
    local indexById = {}
    if rawData and rawData.config then
        for id, row in pairs(rawData.config) do
            indexById[id] = row
        end
    end
    self._configs[name] = {
        rawData = rawData,
        indexById = indexById,
    }
end

---按 ID 获取单行数据
---@param name string 配置表名称
---@param id number 配置 ID
---@return table|nil
function ConfigManager:GetById(name, id)
    local cfg = self._configs[name]
    if not cfg then return nil end
    return cfg.indexById[id]
end

---获取配置表全部数据
---@param name string
---@return table
function ConfigManager:GetAll(name)
    local cfg = self._configs[name]
    if not cfg then return {} end
    return cfg.indexById
end

---条件筛选
---@param name string
---@param predicate function(row) -> boolean
---@return table
function ConfigManager:Filter(name, predicate)
    local cfg = self._configs[name]
    if not cfg then return {} end
    local result = {}
    for id, row in pairs(cfg.indexById) do
        if predicate(row) then
            result[#result + 1] = row
        end
    end
    return result
end

---获取配置表行数
---@param name string
---@return number
function ConfigManager:GetCount(name)
    local cfg = self._configs[name]
    if not cfg then return 0 end
    local count = 0
    for _ in pairs(cfg.indexById) do count = count + 1 end
    return count
end

function ConfigManager:Delete()
    self._configs = {}
end

return ConfigManager
