-- Real UIManager/UIWindow/UIBlockManager; inert resources and rendering collaborators.
local project = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/ui_loading_cancel.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = project .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local function noop() end
package.loaded["Framework.UI.Utils.Logger"] = setmetatable({}, { __index = function() return noop end })
for _, name in ipairs({
    "Framework.UI.Config.UIWindowConfig", "Framework.UI.Resource.UIResourceLoader",
    "Framework.UI.Animation.UIAnimationManager", "Framework.UI.Event.UIEventDispatcher",
    "Framework.UI.Cache.UIWindowCache", "Framework.UI.Manager.UIWindowStack",
    "Framework.UI.Manager.UIWindowFactory", "Framework.UI.Layer.UILayerManager",
    "Framework.UI.Zone.UIZoneManager",
}) do package.loaded[name] = {} end
typeof = function(value) return value end
CS = { UnityEngine = { RenderMode = {}, Canvas = "Canvas" } }
local Enums = require "Framework.UI.Config.UIEnums"
local Window = require "Framework.UI.Core.UIWindow"
local Manager = require "Framework.UI.Manager.UIManager"
local BlockManager = require "Framework.UI.Manager.UIBlockManager"
local key = "UI_Loading_LevelUpPopup"

local function fixture(sync)
    local calls = { requests = {}, cancels = 0, instances = 0, mvc = 0,
        closeAnimations = 0, events = {}, unblocks = {} }
    local block = BlockManager.New()
    -- Observe calls while preserving real source matching and reference counts.
    function block:Unblock(reason, source)
        calls.unblocks[reason] = (calls.unblocks[reason] or 0) + 1
        return BlockManager.Unblock(self, reason, source)
    end
    local asset = { GetType = function() return "InertAsset" end }
    local loader = {}
    function loader:CreateToken() return { cancelled = false } end
    function loader:Cancel(token) calls.cancels = calls.cancels + 1; token.cancelled = true end
    function loader:LoadAsync(_, callback, token)
        calls.requests[#calls.requests + 1] = { callback = callback, token = token }
        if sync then callback(asset, token) end
    end
    function loader:Instantiate()
        calls.instances = calls.instances + 1
        return { name = "InertGO", GetComponent = function() return nil end,
            GetComponentsInChildren = function() return { Length = 0 } end,
            SetActive = function(go, active) go.active = active end }
    end
    local layer = { windows = {} }
    function layer:GetOrderedWindows() return self.windows end
    function layer:GetLayer() return nil end
    function layer:AddWindow(w) self.windows[#self.windows + 1] = w end
    function layer:RemoveWindow(w)
        for i = #self.windows, 1, -1 do if self.windows[i] == w then table.remove(self.windows, i) end end
    end
    local cache = { windows = {} }
    function cache:Get(name) return self.windows[name] end
    function cache:Put(w) self.windows[w:GetName()] = w end
    local config = { prefab = "InertPrefab", layer = "Popup", cachePolicy = Enums.CachePolicy.CacheOnClose }
    local ui = Manager.New({
        config = { Has = function() return true end, Get = function() return config end },
        resourceLoader = loader,
        factory = {
            CreateWindow = function(_, name, cfg) return Window.New(name, cfg) end,
            CreateMVC = function(_, w, go) calls.mvc = calls.mvc + 1; w:AttachGameObject(go) end,
        },
        cache = cache, layerManager = layer,
        stack = { Push = noop, Remove = function() calls.stackRemoved = true end },
        zoneManager = { AddWindow = noop, UpdateFocus = noop,
            RemoveWindow = function() calls.zoneRemoved = true end },
        animationManager = {
            PlayOpenAnimation = function(_, _, callback) callback() end,
            PlayCloseAnimation = function(_, _, callback)
                calls.closeAnimations = calls.closeAnimations + 1; callback()
            end,
        },
        eventDispatcher = { Dispatch = function(_, event) calls.events[event] = (calls.events[event] or 0) + 1 end },
        blockManager = block,
    })
    return ui, calls, asset
end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

for _, withToken in ipairs({ true, false }) do
    test("loading close cleans entry/block " .. (withToken and "with token" or "without token"), function()
        local ui, calls = fixture(false)
        local w = ui:Open("LevelUpPopup")
        local token = w.loadingToken
        if not withToken then w.loadingToken = nil end
        assert(w:IsLoading() and ui:GetWindow("LevelUpPopup") == w and ui:IsInputBlocked())
        assert(ui.blockManager:GetBlockCount() == 1)
        ui:Close("LevelUpPopup", "Unavailable")
        assert(w:IsClosed() and w:GetCloseReason() == "Unavailable" and w.loadingToken == nil)
        assert(ui.loadingWindows.LevelUpPopup == nil and not ui:IsLoading("LevelUpPopup"))
        assert(not ui:IsInputBlocked() and calls.unblocks[key] == 1)
        assert(ui.blockManager:GetBlockCount() == 0 and #ui.blockManager:GetBlockDetails() == 0)
        assert(calls.cancels == (withToken and 1 or 0))
        if withToken then assert(token.cancelled) end
        assert(calls.closeAnimations == 0 and calls.instances == 0)
        ui:Close("LevelUpPopup", "Again")
        assert(calls.unblocks[key] == 1)
    end)
end

test("late cancelled callback cannot instantiate or unblock replacement", function()
    local ui, calls, asset = fixture(false)
    local old = ui:Open("LevelUpPopup")
    local request = calls.requests[1]
    ui:Close("LevelUpPopup", "Unavailable")
    local replacement = ui:Open("LevelUpPopup")
    local unblocks = calls.unblocks[key]
    request.callback(asset, request.token)
    request.callback(nil, request.token)
    assert(old:IsClosed() and replacement:IsLoading())
    assert(ui.loadingWindows.LevelUpPopup == replacement and ui:IsInputBlocked())
    local details = ui.blockManager:GetBlockDetails()
    assert(ui.blockManager:GetBlockCount() == 1 and #details == 1)
    assert(details[1].reason == key and details[1].source == "Window loading")
    assert(calls.unblocks[key] == unblocks and calls.instances == 0 and calls.mvc == 0)
    calls.requests[2].callback(asset, calls.requests[2].token)
    assert(replacement:IsOpened() and calls.instances == 1 and calls.mvc == 1)
    assert(not ui:IsInputBlocked() and ui.loadingWindows.LevelUpPopup == nil)
    assert(ui.blockManager:GetBlockCount() == 0)
end)

test("normal opened close retains animation, removal and cache behavior", function()
    local ui, calls, asset = fixture(false)
    local w = ui:Open("LevelUpPopup")
    calls.requests[1].callback(asset, calls.requests[1].token)
    assert(w:IsOpened())
    ui:Close("LevelUpPopup", "Selected")
    assert(w:IsClosed() and w:GetCloseReason() == "Selected")
    assert(calls.closeAnimations == 1 and calls.cancels == 0)
    assert(calls.stackRemoved and calls.zoneRemoved and #ui.layerManager.windows == 0)
    assert(ui.cache:Get("LevelUpPopup") == w and w:GetGameObject().active == false)
    assert(calls.events.WindowClosed == 1 and not ui:IsInputBlocked())
    assert(ui.blockManager:GetBlockCount() == 0 and #ui.blockManager:GetBlockDetails() == 0)
end)

test("synchronous successful callback leaves no stale loading entry", function()
    local ui, calls = fixture(true)
    local w = ui:Open("LevelUpPopup", "argument")
    assert(w:IsOpened() and w:GetOpenParams()[1] == "argument")
    assert(ui.loadingWindows.LevelUpPopup == nil and ui:GetLoadingCount() == 0)
    assert(ui:GetWindow("LevelUpPopup") == w and not ui:IsInputBlocked())
    assert(ui.blockManager:GetBlockCount() == 0)
    assert(calls.instances == 1 and calls.mvc == 1 and calls.events.WindowOpened == 1)
end)

test("synchronous failed callback also leaves no stale loading entry", function()
    local ui, calls = fixture(false)
    function ui.resourceLoader:LoadAsync(_, callback, token) callback(nil, token) end
    ui:Open("LevelUpPopup")
    assert(ui:GetLoadingCount() == 0 and not ui:IsInputBlocked() and calls.instances == 0)
    assert(ui.blockManager:GetBlockCount() == 0)
end)

print(string.format("RESULT %d passed, %d failed; inert collaborators, no Unity or disk writes", passed, failed))
if failed > 0 then os.exit(1) end
