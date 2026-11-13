local project = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/home_ui_view.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = project .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
package.loaded["Framework.UI.Utils.BaseClass"] = function() return {} end
package.loaded["Framework.UI.Core.UIView"] = { OnDestroy = function() end }
package.loaded["Framework.UI.Utils.CJKFont"] = { ApplyAll = function() end }
local updates = { nextId = 0, callbacks = {} }
function updates:AddUpdate(fn) local id = self.nextId; self.nextId = id + 1; self.callbacks[id] = fn; return id end
function updates:RemoveUpdate(id) self.callbacks[id] = nil end
package.loaded["Framework.Core.UpdateManager"] = { GetInstance = function() return updates end }
typeof = function(x) return x end
CS = { UnityEngine = {
    RectTransform = {}, Vector2 = function(x, y) return { x = x, y = y } end,
    Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    Screen = { width = 1080, height = 1920, safeArea = {x=0,y=0,width=1080,height=1920} }
} }
local View = require "Game.UI.Home.UIHomeView"
local nodes = {}
local function rect(name)
    local r = { name=name, rect={width=1080,height=1920} }
    function r:GetComponent() return self end
    function r:Find(path) return assert(nodes[path], path) end
    return r
end
for _, name in ipairs({"TopBar","m_Profile","m_Currency","m_Profile/m_PlayerName","m_Profile/m_Level","m_Currency/m_Gold"}) do nodes[name] = rect(name) end
local root = rect("root")
root.parent = rect("parent")
local resets = 0
local v = setmetatable({ transform=root, _goldText={}, _joystick={Reset=function() resets=resets+1 end} }, {__index=View})
v:_adaptLayout()
assert(root.sizeDelta.x == 720 and root.sizeDelta.y == 1280)
assert(root.localScale.x == 1.5 and root.anchoredPosition.x == 0)
assert(nodes.m_Profile.anchoredPosition.x + nodes.m_Profile.sizeDelta.x/2 < 720 + nodes.m_Currency.anchoredPosition.x - nodes.m_Currency.sizeDelta.x/2)
local first=root.sizeDelta
v:_adaptLayout()
assert(root.sizeDelta == first and resets == 1, "unchanged frame must not write layout or reset input")
root.parent.rect={width=1920,height=1080}
CS.UnityEngine.Screen.width,CS.UnityEngine.Screen.height=1920,1080
CS.UnityEngine.Screen.safeArea={x=90,y=30,width=1740,height=1020}
v:_adaptLayout()
assert(root.sizeDelta.x==1160 and root.sizeDelta.y==680)
assert(root.anchoredPosition.x==0 and root.anchoredPosition.y==0)
CS.UnityEngine.Screen.safeArea={x=90,y=30,width=1830,height=1050}
v:_adaptLayout()
assert(math.abs(root.anchoredPosition.x-45)<0.001 and math.abs(root.anchoredPosition.y-15)<0.001, "asymmetric safe area must offset root")
v:SetGold(123456789)
assert(v._goldText.text=="123,456,789")
v:SetGold(-1)
assert(v._goldText.text=="0")
v:SetGold(nil)
assert(v._goldText.text=="0")
v._opened=true
v:OnFocus()
assert(v._joystick.enabled==true)
v:OnBlur()
assert(v._joystick.enabled==false)
v:OnFocus()
assert(v._joystick.enabled==true)
v:OnHide()
assert(v._joystick.enabled==false)
v._layoutUpdateId=updates:AddUpdate(function() end)
v._bootstrapper={BindJoystick=function() error("stale scene object") end}
v:OnClose()
assert(next(updates.callbacks)==nil and v._bootstrapper==nil and not v._opened)
v:OnClose()
print("home_ui_view: PASS layout, safe area, input preservation, formatting, focus and close cleanup")
