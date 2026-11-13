-- Actual Lua controller/framework, inert Unity/UI/game dependencies.
local project = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/gm_s01.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
local sourceRoot = (arg and arg[2]) or project
package.path = project .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local allowed, dev, frame, ui = true, true, nil, nil
local objects, removedTargets = {}, 0
local time = { realtimeSinceStartup = 0 }
local function noop() end
IsNull = function(value) return value == nil or value.destroyed == true end
typeof = function(value) return value end
local function vector(x, y) return { x = x, y = y } end
local function newGO(name)
    local rt = { SetParent = noop }
    local go = { name = name, active = true, components = {} }
    function go:AddComponent(kind)
        local component = {}
        if kind == "RectTransform" then component = rt end
        if kind == "Button" then
            component.onClick = { AddListener = function(_, fn) go.click = fn end }
        end
        self.components[kind] = component
        return component
    end
    function go:GetComponent() return rt end
    function go:SetActive(value) self.active = value end
    objects[#objects + 1] = go
    return go
end
CS = { UnityEngine = {
    Time = time, GameObject = newGO,
    Object = {
        FindObjectOfType = function() return {} end,
        DontDestroyOnLoad = noop,
        DestroyImmediate = function(go) go.destroyed = true end,
    },
    Input = { GetKey = function() return false end, GetKeyDown = function() return false end },
    UI = { Button = "Button", Text = "Text", Image = "Image", GraphicRaycaster = "Raycaster" },
    EventSystems = { EventSystem = "EventSystem", StandaloneInputModule = "InputModule" },
    Canvas = "Canvas", RectTransform = "RectTransform", Font = "Font",
    RenderMode = { ScreenSpaceOverlay = 0 }, TextAnchor = { MiddleCenter = 0 },
    Vector2 = vector, Color = function(...) return { ... } end,
    Resources = { GetBuiltinResource = function() return {} end },
} }
package.loaded["Framework.UI.Utils.Logger"] = { Info = noop, Warn = noop, Debug = noop }
package.loaded["Game.GM.GMConfig"] = {
    CanOpenPanel = function() return allowed end,
    IsDev = function() return dev end,
    IsEnabled = function() return allowed end,
    ToggleEnabled = function() allowed = not allowed end,
}
package.loaded["Game.GM.GMUnlock"] = { Init = noop }
package.loaded["Framework.Core.UpdateManager"] = {
    GetInstance = function()
        return { AddUpdate = function(_, callback) frame = callback end }
    end,
}
package.loaded["Framework.Core.EventManager"] = {
    GetInstance = function()
        return { RemoveListenerByTarget = function() removedTargets = removedTargets + 1 end }
    end,
}
package.loaded["Game.GameMain"] = { GetUIManager = function() return ui end }
local TimerManager = require("Framework.Core.TimerManager")
local tm = TimerManager:GetInstance()
local Controller = assert(loadfile(sourceRoot ..
    "/Assets/Game/LuaScripts/Game/UI/GM/UIGMController.lua"))()

local passed, failed = 0, 0
local function test(name, fn)
    allowed, dev, time.realtimeSinceStartup = true, true, 0
    objects = {}
    tm:ClearAll()
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function fixture()
    local values, statuses = {}, {}
    local c = Controller.New({})
    c:BindView({ SetExecPending = noop, SetExecNormal = noop,
        SetStatus = function(_, message) statuses[#statuses + 1] = message end })
    c:OnOpen()
    local cmd = { id = "inert", label = "inert", danger = true,
        fn = function(value) values[#values + 1] = { value = value }; return "inert" end }
    return c, cmd, values, statuses
end
test("same parameter executes once after two clicks", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); assert(#values == 0)
    c:Execute(cmd, 10); assert(#values == 1 and values[1].value == 10)
    assert(c._pending == nil)
end)
test("changed parameter requires new confirmation", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); c:Execute(cmd, 50)
    assert(#values == 0 and c._pending.value == 50)
    c:Execute(cmd, 50); assert(#values == 1 and values[1].value == 50)
end)
test("different primitive type is not the same confirmation", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); c:Execute(cmd, "10")
    assert(#values == 0); c:Execute(cmd, "10")
    assert(#values == 1 and values[1].value == "10")
end)
test("string and nil parameters remain supported", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, "return 1"); c:Execute(cmd, "return 1")
    assert(values[1].value == "return 1")
    c:Execute(cmd, nil); c:Execute(cmd, nil)
    assert(#values == 2 and values[2].value == nil)
end)
test("different command replaces confirmation", function()
    local c, cmd, values = fixture()
    local other = { id = "other", label = "other", danger = true, fn = cmd.fn }
    c:Execute(cmd, 10); c:Execute(other, 10); assert(#values == 0)
    c:Execute(other, 10); assert(#values == 1)
end)
test("expired deadline refuses second click without timer update", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); time.realtimeSinceStartup = 3.5
    c:Execute(cmd, 10); assert(#values == 0)
    c:Execute(cmd, 10); assert(#values == 1)
end)
test("real TimerManager timeout clears confirmation", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); tm:Update(3500)
    assert(c._pending == nil and next(tm._timers) == nil)
    c:Execute(cmd, 10); assert(#values == 0)
end)
test("obsolete timeout cannot cancel a new confirmation", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10)
    local stale = tm._timers[c._pending.timerId].callback
    c:Execute(cmd, 50); stale()
    assert(c._pending and c._pending.value == 50 and #values == 0)
end)
test("disabled ordinary command never executes", function()
    local c, cmd, values = fixture(); cmd.danger = false; allowed = false
    c:Execute(cmd, 10); assert(#values == 0)
end)
test("disable cancels pending and requires reconfirmation", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); allowed = false; c:Execute(cmd, 10)
    assert(c._pending == nil and #values == 0)
    allowed = true; c:Execute(cmd, 10); assert(#values == 0)
end)
test("devOnly command remains blocked in release", function()
    local c, cmd, values = fixture(); cmd.devOnly = true; dev = false
    c:Execute(cmd, 10); c:Execute(cmd, 10)
    assert(c._pending == nil and #values == 0)
end)
test("missing timer fails closed", function()
    local c, cmd, values = fixture()
    package.loaded["Framework.Core.TimerManager"] = { GetInstance = function() return nil end }
    c:Execute(cmd, 10); c:Execute(cmd, 10)
    package.loaded["Framework.Core.TimerManager"] = TimerManager
    assert(c._pending == nil and #values == 0)
end)
test("OnClose clears timer and refuses stale input", function()
    local c, cmd, values, statuses = fixture()
    c:Execute(cmd, 10); local callback = tm._timers[c._pending.timerId].callback
    c:OnClose(); local count = #statuses
    tm:Update(4000); callback(); c:Execute(cmd, 10)
    assert(c._pending == nil and next(tm._timers) == nil)
    assert(#values == 0 and #statuses == count)
end)
test("OnDestroy calls real base cleanup and refuses stale callbacks", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); local callback = tm._timers[c._pending.timerId].callback
    local before = removedTargets; c:OnDestroy(); callback(); c:Execute(cmd, 10)
    assert(c._pending == nil and c._closed == true)
    cmd.danger = false; c:Execute(cmd, 10)
    tm:Update(4000)
    assert(c:GetView() == nil and c:GetModel() == nil and removedTargets == before + 1)
    assert(c._pending == nil and #values == 0 and next(tm._timers) == nil)
end)
test("cached refresh clears confirmation and reopens controller", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); c:OnClose(); c:OnRefresh()
    c:Execute(cmd, 10); assert(#values == 0)
    c:Execute(cmd, 10); assert(#values == 1)
end)
test("closing request blocks input before the framework callback", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); c:OnPanelClosing(); c:Execute(cmd, 10)
    assert(c._pending == nil and #values == 0)
end)
test("group changes and view reopen reset confirmation", function()
    local c, cmd, values = fixture()
    c:Execute(cmd, 10); c:OnGroupChanged()
    c:Execute(cmd, 10); assert(#values == 0)
    c:OnViewOpened(); c:Execute(cmd, 10); assert(#values == 0)
end)
local function windowFixture()
    local c, cmd, values = fixture()
    local UIWindow = require("Framework.UI.Core.UIWindow")
    local window = UIWindow.New("GM", { layer = "Popup" })
    window:BeginLoading({ cancelled = false })
    window:CompleteLoading()
    window:BindMVC(c:GetView(), c, {})
    window:Create()
    window:Open()
    return window, c, cmd, values
end
test("real UIWindow close and cache reopen dispatch controller lifecycle", function()
    local window, c, cmd, values = windowFixture()
    c:Execute(cmd, 10); window:Close("audit")
    assert(c._closed and c._pending == nil and window:IsClosed())
    window:Open(); c:Execute(cmd, 10); assert(#values == 0)
    c:Execute(cmd, 10); assert(#values == 1)
    c:Execute(cmd, 10); window:Destroy()
    assert(c._destroyed and c:GetView() == nil and c._pending == nil)
end)
test("real UIWindow refresh during a close request cannot unblock input", function()
    local window, c, cmd, values = windowFixture()
    c:Execute(cmd, 10); c:OnPanelClosing()
    window:Refresh()
    c:Execute(cmd, 10)
    assert(c._closed and c._pending == nil and #values == 0)
    window:Close("audit"); window:Open()
    c:Execute(cmd, 10); c:Execute(cmd, 10); assert(#values == 1)
end)

local function uiFixture(state)
    local c = fixture()
    local window = {
        state = state or "closed", GetController = function() return c end,
        IsOpened = function(self) return self.state == "open" end,
        IsOpening = function(self) return self.state == "opening" end,
        IsLoading = function(self) return self.state == "loading" end,
        IsHidden = function(self) return self.state == "hidden" end,
        IsClosed = function(self) return self.state == "closed" end,
        IsDestroyed = function(self) return self.state == "destroyed" end,
    }
    ui = { opens = 0, closes = 0,
        GetWindow = function() return window end,
        IsOpen = function() return window.state == "open" end,
        Open = function(self)
            self.opens = self.opens + 1; window.state = "open"; c:OnOpen()
        end,
        Close = function(self) self.closes = self.closes + 1 end,
        layerManager = {
            HasLayer = function() return true end,
            GetLayer = function() return { root = {} } end,
        },
    }
    local gm = assert(loadfile(sourceRoot .. "/Assets/Game/LuaScripts/Game/GM/GMUI.lua"))()
    package.loaded["Game.GM.GMUI"] = gm
    gm.Init()
    return gm, window, c
end
test("disabled entry points cannot open", function()
    local gm = uiFixture(); allowed = false
    gm.OpenPanel(); gm.TogglePanel(); gm.SetPanelOpen(true)
    assert(ui.opens == 0)
end)
test("close remains available when disabled and is idempotent", function()
    local gm, _, c = uiFixture("open"); allowed = false
    gm.ClosePanel(); gm.TogglePanel(); gm.SetPanelOpen(false)
    assert(ui.closes == 1 and c._closed == true)
end)
test("disable frame cancels pending before async close completes", function()
    local gm, _, c = uiFixture("open")
    local values = {}
    local cmd = { id = "inert", danger = true, fn = function() values[#values + 1] = true end }
    c:Execute(cmd, 10); allowed = false; frame(); frame()
    c:Execute(cmd, 10)
    assert(ui.closes == 1 and c._pending == nil and #values == 0)
end)
test("incomplete windows are not cancelled into an empty cache", function()
    for _, state in ipairs({ "opening", "loading", "created" }) do
        uiFixture(state); allowed = false; frame(); frame()
        assert(ui.closes == 0 and ui.opens == 0)
    end
end)
test("late open while disabled keeps controller input blocked", function()
    local gm, window, c = uiFixture("loading"); allowed = false
    c:OnOpen(); window.state = "open"
    local count = 0
    c:Execute({ danger = false, fn = function() count = count + 1 end }, 10)
    assert(count == 0); frame(); assert(ui.closes == 1)
end)
test("close request cannot be undone by refresh or open callbacks", function()
    local gm, window, c = uiFixture("open")
    gm.ClosePanel(); c:OnRefresh(); c:OnViewOpened(); c:OnOpen()
    local count = 0
    c:Execute({ danger = false, fn = function() count = count + 1 end }, 10)
    gm.OpenPanel()
    assert(count == 0 and ui.opens == 0)
    c:OnClose(); window.state = "closed"
    gm.OpenPanel(); assert(ui.opens == 1)
end)
test("badge deactivates and is reused after enable", function()
    uiFixture(); frame()
    local badge
    for _, go in ipairs(objects) do if go.name == "GMBadge" then badge = go end end
    assert(badge and badge.active)
    allowed = false; frame(); assert(not badge.active)
    badge.click(); assert(ui.opens == 0)
    allowed = true; frame(); assert(badge.active)
    local count = 0
    for _, go in ipairs(objects) do if go.name == "GMBadge" then count = count + 1 end end
    assert(count == 1)
end)
test("header closes via the same guarded and idempotent path", function()
    local gm, window, c = uiFixture("open")
    c:OnCloseClicked(); c:OnCloseClicked()
    assert(ui.closes == 1 and c._closed)
    c:OnClose(); window.state = "closed"
    c:OnCloseClicked()
    gm.OpenPanel()
    assert(ui.opens == 1 and not c._closed and not c._closeRequested)
end)
test("mutable confirmation parameters are refused", function()
    local c, cmd, values = fixture()
    local value = { amount = 10 }
    c:Execute(cmd, value); value.amount = 50; c:Execute(cmd, value)
    assert(#values == 0 and c._pending == nil)
end)
test("destroyed controller cannot reopen via old callbacks", function()
    local c, cmd, values = fixture()
    c:OnDestroy(); c:OnOpen(); c:OnRefresh(); c:OnViewOpened()
    cmd.danger = false; c:Execute(cmd, 10)
    assert(c._closed and #values == 0)
end)
test("disable hotkey reconciles in the same frame", function()
    uiFixture("open"); frame()
    CS.UnityEngine.Input.GetKey = function(key) return key == "left ctrl" or key == "left shift" end
    CS.UnityEngine.Input.GetKeyDown = function(key) return key == "g" end
    frame()
    CS.UnityEngine.Input.GetKey = function() return false end
    CS.UnityEngine.Input.GetKeyDown = function() return false end
    assert(not allowed and ui.closes == 1)
    for _, go in ipairs(objects) do if go.name == "GMBadge" then assert(not go.active) end end
end)
print(string.format("RESULT %d passed, %d failed; inert dependencies only, no Unity/game writes", passed, failed))
if failed > 0 then os.exit(1) end
