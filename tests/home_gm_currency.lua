local root = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/home_gm_currency.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "") .. "/Assets/Game/LuaScripts/"
package.path = root .. "?.lua;" .. package.path

local function forbiddenSave()
	error("GM currency must not Save or Commit", 2)
end
local noop = function() end
package.loaded["Framework.UI.Utils.Logger"] = setmetatable({}, {
	__index = function() return noop end,
})
package.loaded["Game.Save.SaveManager"] = { Save = forbiddenSave }
package.loaded["Game.GM.GMConfig"] = { IsDev = function() return false end }
_G.CS = { UnityEngine = { Application = {}, PlayerPrefs = setmetatable({}, {
	__index = function() return forbiddenSave end,
}) }, System = { IO = { File = setmetatable({}, {
	__index = function() return forbiddenSave end,
}) } } }

local SaveData = require "Game.Save.SaveData"
SaveData.Commit = forbiddenSave
SaveData.current = SaveData.Default()
local save = SaveData.Get()
save.inventory.gold = 200
local Model = require "Game.UI.Home.UIHomeModel"
local model = Model.New("HomePanel")
model:SetCurrency(9000, 7)
local renderedGold, renderedDiamond, renders = nil, nil, 0
local view = {
	SetGold = function(_, value) renderedGold = value; renders = renders + 1 end,
	SetDiamond = function(_, value) renderedDiamond = value end,
}
local home = { GetModel = function() return model end, GetView = function() return view end }
local ui = { GetWindow = function(_, name) assert(name == "HomePanel"); return home end }
package.loaded["Game.GameMain"] = { GetUIManager = function() return ui end }

local commands = require "Game.GM.GMCommands"
local function command(id)
	for _, entry in ipairs(commands.list) do
		if entry.id == id then return entry end
	end
	error("Missing real command: " .. id)
end
local gold = command("currency.add_gold")
local diamond = command("currency.add_diamond")

-- Compare every persisted field, including keys, to catch schema additions.
local function clone(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = clone(item) end
	return copy
end
local function equal(actual, expected)
	assert(type(actual) == type(expected), "save field type changed")
	if type(expected) ~= "table" then assert(actual == expected, "save value changed"); return end
	for key, value in pairs(expected) do equal(actual[key], value) end
	for key in pairs(actual) do assert(expected[key] ~= nil, "unexpected persisted field: " .. key) end
end
local expected = clone(save)
assert(gold.available())
local result = gold.fn("25")
expected.inventory.gold = 225
equal(save, expected)
assert(model:GetGold() == 225 and renderedGold == 225 and renders == 1)
assert(result:find("225", 1, true))
assert(model:GetDiamond() == 7)
for _ = 1, 4 do
	assert(not model:RefreshCurrency())
	assert(model:GetGold() == 225, "poll must not revert GM balance")
end

model:SetCurrency(-50, 7)
gold.fn(10)
expected.inventory.gold = 235
equal(save, expected)
assert(model:GetGold() == 235 and renderedGold == 235)

local beforeRenders = renders
for _, invalid in ipairs({ "not-a-number", 0, -1, 100000000 }) do
	assert(type(gold.fn(invalid)) == "string")
	equal(save, expected)
	assert(model:GetGold() == 235 and renders == beforeRenders)
end
home = nil
assert(not gold.available())
assert(type(gold.fn(10)) == "string")
equal(save, expected)
assert(renders == beforeRenders)
ui = nil
gold.fn(10)
equal(save, expected)
assert(renders == beforeRenders)

home = { GetModel = function() return model end, GetView = function() return view end }
ui = { GetWindow = function() return home end }
diamond.fn(3)
assert(model:GetDiamond() == 10 and renderedDiamond == 10)
equal(save, expected)
assert(not model:RefreshCurrency() and model:GetGold() == 235 and model:GetDiamond() == 10)
gold.fn(nil)
expected.inventory.gold = 1235
equal(save, expected)
assert(model:GetGold() == 1235 and renderedGold == 1235)
assert(not model:RefreshCurrency())
assert(save == SaveData.Get(), "command must preserve current save identity")
assert(save.inventory.diamond == nil and save.inventory.gems == nil and save.diamond == nil)
print("home_gm_currency: PASS (real GM fn / SaveData / HomeModel; no Unity or disk writes)")
