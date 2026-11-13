local ROOT_DIR = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/home_ui_data.lua <project_root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = ROOT_DIR .. "/Assets/Game/LuaScripts/?.lua;" .. package.path

local noop = function() end
package.loaded["Framework.UI.Utils.Logger"] = setmetatable({}, { __index = function() return noop end })
package.loaded["Framework.Core.EventManager"] = {
	GetInstance = function() return { RemoveListenerByTarget = noop } end,
}

local SaveData = require "Game.Save.SaveData"
local UpdateManager = require "Framework.Core.UpdateManager"
local Model = require "Game.UI.Home.UIHomeModel"
local Controller = require "Game.UI.Home.UIHomeController"
local updates = UpdateManager:GetInstance()
updates:ClearAll()
local unrelated = updates:AddUpdate(noop, {})
local broadcasts, resets = {}, 0
package.loaded["Framework.Framework"] = {
	Event = function()
		return { Broadcast = function(_, event)
			assert(resets > 0, "reset must precede modal event")
			broadcasts[event] = (broadcasts[event] or 0) + 1
		end }
	end,
}
CS = { UnityEngine = { Time = { unscaledDeltaTime = 0.25 } } }

local function button()
	local listeners = {}
	return {
		listeners = listeners,
		onClick = {
			AddListener = function(_, callback) listeners[#listeners + 1] = callback end,
			RemoveListener = function(_, callback)
				for i = #listeners, 1, -1 do
					if listeners[i] == callback then table.remove(listeners, i) end
				end
			end,
		},
	}
end
local buttons = { Shop = button(), Mod = button() }
local rendered, goldRenders = {}, 0
local view = {
	GetButton = function(_, name) return buttons[name] end,
	GetJoystick = function() return { Reset = function() resets = resets + 1 end } end,
	SetPlayerName = function(_, value) rendered.name = value end,
	SetLevel = function(_, value) rendered.level = value end,
	SetGold = function(_, value) rendered.gold = value; goldRenders = goldRenders + 1 end,
	SetDiamond = function(_, value) rendered.diamond = value end,
}

-- Proxy the real save's fields so any HUD write fails immediately.
local inventory = { gold = 41 }
local function readonly(data)
	return setmetatable({}, { __index = data, __newindex = function() error("HUD wrote save") end })
end
SaveData.current = readonly({ inventory = readonly(inventory), player = readonly({}) })
SaveData.Commit = function() error("HUD committed save") end
local model = Model.New("HomePanel")
local controller = Controller.New(model)
controller:OnCreate() -- Also tolerate a late view binding.
controller:BindView(view)
controller:OnCreate()
controller:OnCreate()
controller:OnOpen("Provided", 7, 6800, 120)
assert(rendered.gold == 41 and rendered.diamond == 0)
assert(rendered.name == "Provided" and rendered.level == 7)
assert(#updates._updates == 2)
controller:OnOpen()
assert(rendered.name == model:GetPlayerName() and rendered.name ~= "")
assert(rendered.level == 1 and #updates._updates == 2)
assert(#buttons.Shop.listeners == 1 and #buttons.Mod.listeners == 1)
controller:OnRefresh("Refreshed", 3, 6800, 120)
assert(rendered.name == "Refreshed" and rendered.level == 3 and rendered.gold == 41)
assert(#updates._updates == 2 and #buttons.Shop.listeners == 1)
local count = goldRenders
updates:OnUpdate(0)
updates:OnUpdate(0)
assert(goldRenders == count, "unchanged gold should not render")
inventory.gold = 99
updates:OnUpdate(0)
assert(rendered.gold == 41, "must wait 500ms")
updates:OnUpdate(0)
assert(rendered.gold == 99 and goldRenders == count + 1)
buttons.Shop.listeners[1]()
buttons.Mod.listeners[1]()
assert(broadcasts.HomePanel_OnShop == 1 and broadcasts.HomePanel_OnMod == 1 and resets == 2)
controller:OnClose()
controller:OnClose()
assert(#updates._updates == 1 and updates._updates[1].id == unrelated)
buttons.Shop.listeners[1]()
assert(broadcasts.HomePanel_OnShop == 1)
inventory.gold = 123
controller:OnOpen()
assert(rendered.gold == 123 and #updates._updates == 2)
assert(#buttons.Shop.listeners == 1)
view.GetJoystick = nil
buttons.Mod.listeners[1]()
assert(broadcasts.HomePanel_OnMod == 2)
controller:OnDestroy()
controller:OnDestroy()
assert(#updates._updates == 1)
assert(#buttons.Shop.listeners == 0 and #buttons.Mod.listeners == 0)
assert(inventory.gold == 123 and SaveData.Get().player.level == nil)

local opened
package.loaded["Game.Scene.BaseScene"] = {}
local scene = require "Game.Scene.HomeScene"
scene._uiManager = { Open = function(_, ...) opened = table.pack(...) end }
scene:_initHomeUI()
assert(opened.n == 1 and opened[1] == "HomePanel", "scene must not supply fake currency")
print("home_ui_data: PASS")
