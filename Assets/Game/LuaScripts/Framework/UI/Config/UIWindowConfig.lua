--[[
UIWindowConfig.lua

Window configuration registry. Commercial projects usually generate this file
from Excel, protobuf, or an internal config platform. This runtime registry is
kept small so tests can register mock windows easily.
]]

local UIEnums = require "NewObject.Framework.UI.Config.UIEnums"

local UIWindowConfig = {
	configs = {},
}

---Registers or replaces a window configuration.
---@param name string Unique window name.
---@param config table Window configuration table.
function UIWindowConfig.Register(name, config)
	assert(type(name) == "string" and name ~= "", "window config name must be a non-empty string")
	assert(type(config) == "table", "window config must be a table")
	config.name = name
	config.layer = config.layer or "Normal"
	config.windowType = config.windowType or UIEnums.WindowType.Normal
	config.cachePolicy = config.cachePolicy or UIEnums.CachePolicy.CacheOnClose
	config.zonePolicy = config.zonePolicy or UIEnums.ZonePolicy.Default
	config.openMode = config.openMode or UIEnums.OpenMode.Stack
	config.fullscreen = config.fullscreen == true
	UIWindowConfig.configs[name] = config
end

---Registers many window configurations.
---@param configs table Map from window name to config.
function UIWindowConfig.RegisterMany(configs)
	for name, config in pairs(configs or {}) do
		UIWindowConfig.Register(name, config)
	end
end

---Returns the configuration for a window.
---@param name string Window name.
---@return table config Window configuration.
function UIWindowConfig.Get(name)
	local config = UIWindowConfig.configs[name]
	assert(config, "missing window config: " .. tostring(name))
	return config
end

---Returns whether a window configuration exists.
---@param name string Window name.
---@return boolean exists True when registered.
function UIWindowConfig.Has(name)
	return UIWindowConfig.configs[name] ~= nil
end

---Clears all registered configurations, mostly for unit tests.
function UIWindowConfig.Clear()
	for key in pairs(UIWindowConfig.configs) do
		UIWindowConfig.configs[key] = nil
	end
end

return UIWindowConfig
