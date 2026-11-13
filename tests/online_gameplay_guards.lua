-- Real gameplay modules; only Unity, storage, and the asynchronous service are mocked.
local project = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/online_gameplay_guards.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = project .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local function noop() end
package.loaded["Framework.UI.Utils.Logger"] = setmetatable({}, { __index = function() return noop end })
package.loaded["Game.GM.GMConfig"] = { IsDev = function() return true end }
package.loaded["Framework.Core.EventManager"] = { GetInstance = function()
    return { RemoveListenerByTarget = noop }
end }

local files, storageOps, snapshotOps = {}, 0, 0
local storage = {}
function storage.DirectoryExists(_) storageOps = storageOps + 1; return true end
function storage.FileExists(_, path) storageOps = storageOps + 1; return files[path] ~= nil end
function storage.WriteAllText(_, path, value) storageOps = storageOps + 1; files[path] = value end
function storage.ReadAllText(_, path) storageOps = storageOps + 1; return files[path] end
function storage.DeleteFile(_, path) storageOps = storageOps + 1; files[path] = nil end
function storage.MoveFile(_, from, to)
    storageOps = storageOps + 1
    assert(files[from]); files[to], files[from] = files[from], nil
end
_G.CS = {
    Storage = { Current = storage },
    UnityEngine = { Application = { persistentDataPath = "memory" }, PlayerPrefs = {
        SetString = noop, Save = noop,
    } },
    System = { IO = { Path = { GetDirectoryName = function() return "memory/save" end }, File = {
        WriteAllText = function() snapshotOps = snapshotOps + 1 end,
        Exists = function() return false end,
    } } },
}

local Save = require "Game.Save.SaveData"
local Manager = require "Game.Save.SaveManager"
local Meta = require "Game.Save.MetaSystem"
local Inventory = require "Game.Mod.ModInventory"
local Mods = require "Game.Mod.ModSystem"
local ShopModel = require "Game.UI.Shop.UIShopModel"
local ShopController = require "Game.UI.Shop.UIShopController"
local ModModel = require "Game.UI.Mod.UIModStationModel"
local ModController = require "Game.UI.Mod.UIModStationController"
local Merchant = require "Game.Dungeon.Events.MerchantEvent"
local Shrine = require "Game.Dungeon.Events.ShrineEvent"

local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = clone(item) end
    return copy
end
local function equal(actual, expected)
    assert(type(actual) == type(expected), "field type changed")
    if type(expected) ~= "table" then assert(actual == expected, "field value changed"); return end
    for key, item in pairs(expected) do equal(actual[key], item) end
    for key in pairs(actual) do assert(expected[key] ~= nil, "unexpected field " .. tostring(key)) end
end
local function fixture()
    local save = Save.Default()
    save.inventory.gold = 9000
    save.inventory.mods = { { uid = 1, id = 1001, rank = 1 }, { uid = 2, id = 1002, rank = 1 } }
    save.meta.memoryFragments = 30
    return save
end

local session = { busy = false, requests = {} }
function session.IsSelected() return Save.IsOnline() end
function session.IsBusy()
    if session.queryThrows then error("query failed") end
    return session.busy
end
local function enqueue(kind, callback, args)
    if session.throws then error("request failed") end
    session.busy = true
    session.requests[#session.requests + 1] = { kind = kind, callback = callback, args = args }
end
function session.Purchase(count, callback) enqueue("purchase", callback, { count }) end
function session.Loadout(host, slot, uid, callback) enqueue("loadout", callback, { host, slot, uid }) end
function session.Refresh(callback) enqueue("refresh", callback, {}) end
local function finish(request, ok, reason, snapshot)
    session.busy = false
    -- Matches the service contract: global state is applied before the UI callback.
    if ok then assert(Save.ReplaceOnlineSnapshot(snapshot or clone(Save.Get()))) end
    request.callback(ok, reason)
end
local function latest(kind)
    local request = session.requests[#session.requests]
    assert(request and request.kind == kind, "missing " .. kind .. " request")
    return request
end
local function reset(online)
    Save.EndOnline()
    Save.current = fixture()
    files, storageOps, snapshotOps = {}, 0, 0
    session.busy, session.requests, session.throws, session.queryThrows = false, {}, false, false
    package.loaded["Game.Online.OnlineSession"] = session
    package.preload["Game.Online.OnlineSession"] = nil
    if online then Save.BeginOnline(); assert(Save.ReplaceOnlineSnapshot(fixture())) end
end
local function controller(class, model, online)
    local view = { renders = 0 }
    function view:Render(renderedModel) assert(renderedModel == model); self.renders = self.renders + 1 end
    local ctrl = class.New(model)
    ctrl:BindView(view)
    ctrl:OnOpen()
    if online then finish(latest("refresh"), true) end
    return ctrl, model, view
end
local function shop(online) return controller(ShopController, ShopModel.New("ShopPanel"), online) end
local function station(online) return controller(ModController, ModModel.New("ModStationPanel"), online) end
local homeModel = { gold = 0, diamond = 0 }
function homeModel:RefreshCurrency() self.gold = Save.Get().inventory.gold end
function homeModel:GetGold() return self.gold end
function homeModel:GetDiamond() return self.diamond end
function homeModel:SetCurrency(gold, diamond) self.gold, self.diamond = gold, diamond end
package.loaded["Game.GameMain"] = { GetUIManager = function() return {
    GetWindow = function()
        return { GetModel = function() return homeModel end, GetView = function() return {} end }
    end,
    Close = noop,
} end }
local Commands = require "Game.GM.GMCommands"
local function command(id)
    for _, entry in ipairs(Commands.list) do if entry.id == id then return entry.fn end end
    error("missing command " .. id)
end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("online selection keeps the original offline pointer exactly once", function()
    reset(false)
    local offline, expected = Save.Get(), clone(Save.Get())
    Save.BeginOnline()
    assert(Save.IsOnline() and Save.Get() ~= offline and Save.Get().inventory.gold == 0)
    assert(#Save.Get().inventory.mods == 0)
    local first = Save.Get()
    Save.BeginOnline(); assert(Save.Get() == first)
    Save.Get().inventory.gold = 4
    Save.EndOnline(); assert(not Save.IsOnline() and Save.Get() == offline)
    equal(offline, expected); assert(storageOps == 0)
    Save.EndOnline(); assert(Save.Get() == offline)
end)

test("nil offline pointer and schema hydration never merge offline progression", function()
    reset(false); Save.current = nil
    Save.BeginOnline(); Save.EndOnline(); assert(Save.current == nil)
    Save.current = fixture(); local offline = Save.Get()
    offline.meta.upgrades.M05 = 1; offline.loadout.weapon.installed[1] = 1
    Save.BeginOnline()
    assert(Save.ReplaceOnlineSnapshot({ inventory = { gold = 7 } }))
    assert(Save.Get().inventory.gold == 7 and #Save.Get().inventory.mods == 0)
    assert(Save.Get().meta.upgrades.M05 == nil and Save.Get().loadout.weapon.installed[1] == nil)
    Save.EndOnline(); assert(Save.Get() == offline and offline.meta.upgrades.M05 == 1)
    assert(storageOps == 0)
end)

test("snapshot validation rejects wrong mode and malformed fields without replacement", function()
    reset(false); local before = Save.Get()
    assert(not Save.ReplaceOnlineSnapshot(fixture()) and Save.Get() == before)
    Save.BeginOnline(); before = Save.Get()
    assert(not Save.ReplaceOnlineSnapshot({ inventory = 2 }))
    assert(not Save.ReplaceOnlineSnapshot(nil))
    assert(Save.Get() == before and storageOps == 0)
end)

test("existing offline storage is unchanged throughout online selection", function()
    reset(false); local offline = Save.Get()
    assert(Manager.Save(offline))
    local disk, ops = clone(files), storageOps
    Save.BeginOnline(); assert(Save.ReplaceOnlineSnapshot(fixture()))
    Save.Get().inventory.gold = 1
    assert(not Save.Commit() and not Manager.Save(offline) and not Manager.Load())
    equal(files, disk); assert(storageOps == ops)
    Save.EndOnline(); assert(Save.Get() == offline)
    assert(Manager.Save(offline)); equal(Manager.Load(), offline)
end)

test("all public permanent mutations deny selected online mode even logged out", function()
    reset(true)
    session.loggedIn = false
    local current, expected, disk = Save.Get(), clone(Save.Get()), clone(files)
    local calls = {
        function() return Save.ApplyExtract({ gold = 100, fragments = 8, items = { "x" } }) end,
        function() return Save.ApplyDeath({ fragments = 8 }) end,
        Save.Commit, function() return Manager.Save(fixture()) end, Manager.Load,
        function() return Inventory.AddMod(1001, 2) end,
        function() return Inventory.GrantRandom({ 1001 }) end,
        function() return Inventory.Upgrade(Inventory.GetByUid(1)) end,
        Inventory.UpgradeRandom, function() return Meta.Buy("M01") end,
        function() return Mods.Install("weapon", 1, 1) end,
        function() return Mods.Uninstall("weapon", 1) end,
        function() return Mods.TryAutoInstall(Inventory.GetByUid(1)) end,
        function() return ShopModel.New("ShopPanel"):Buy(1) end,
    }
    for _, call in ipairs(calls) do
        local ok, reason = call()
        assert(not ok and reason == "online_authority")
        assert(Save.Get() == current); equal(current, expected)
    end
    assert(not Meta.CanBuy("M01") and not Inventory.CanUpgrade(Inventory.GetByUid(1)))
    equal(files, disk); assert(storageOps == 0)
end)

test("merchant and shrine reject before spending money or consuming opportunity", function()
    reset(true); local before = clone(Save.Get())
    local run = { loot = { gold = 500 }, scroll = { current = 1, max = 3 } }
    local merchant = Merchant.New(); merchant:Enter(run, {})
    assert(not merchant:GetOptions()[2].enabled)
    local ok, reason = merchant:Select("buy_mod")
    assert(not ok and reason == "online_authority" and run.loot.gold == 500)
    ok, reason = merchant:_buyMod()
    assert(not ok and reason == "online_authority")
    merchant:Select("buy_scroll"); assert(run.loot.gold == 350 and run.scroll.current == 2)
    local heals = 0
    local shrine = Shrine.New(); shrine:Enter(run, { playerController = { maxHp = 100, hp = 40,
        Heal = function() heals = heals + 1 end } })
    ok, reason = shrine:Select("fortify")
    assert(not ok and reason == "online_authority" and shrine._done == false)
    assert(#shrine:GetOptions() == 2)
    shrine:Select("pray"); assert(heals == 1 and shrine._done)
    equal(Save.Get(), before); assert(storageOps == 0)
end)

test("direct GM functions cannot mutate gold or execute Lua online", function()
    reset(true); local before = clone(Save.Get())
    local _, reason = command("currency.add_gold")(100)
    assert(reason == "online_authority")
    _G.onlineGuardMarker = nil
    _, reason = command("advanced.run_lua")("onlineGuardMarker = 1")
    assert(reason == "online_authority" and _G.onlineGuardMarker == nil)
    equal(Save.Get(), before); assert(storageOps == 0 and snapshotOps == 0)
end)

test("offline save, grants, upgrades, meta, shop and loadout remain functional", function()
    reset(false)
    assert(Inventory.AddMod(1001, 1)); assert(Inventory.Upgrade(Inventory.GetByUid(1)))
    assert(Meta.Buy("M01") and Meta.GetFragments() == 25)
    local ctrl = shop(false); local gold, count = Save.Get().inventory.gold, Inventory.Count()
    ctrl:_onBuy(1)
    assert(Save.Get().inventory.gold == gold - 300 and Inventory.Count() == count + 1)
    local modCtrl, model = station(false)
    modCtrl:_onBagItem(1); modCtrl:_onSlot(1)
    assert(model:GetSelected() == nil and Save.Get().loadout.weapon.installed[1] == 1)
    modCtrl:_onSlot(1); assert(Save.Get().loadout.weapon.installed[1] == nil)
    assert(Manager.Load().inventory.gold == Save.Get().inventory.gold and storageOps > 0)
    command("currency.add_gold")(10); assert(Save.Get().inventory.gold == gold - 290)
    command("advanced.run_lua")("onlineGuardMarker = 2"); assert(_G.onlineGuardMarker == 2)
    _G.onlineGuardMarker = nil
    assert(#session.requests == 0)
end)

test("shop waits for server hydration and blocks duplicate clicks", function()
    reset(true); local ctrl, model = shop(true)
    local before, count = clone(Save.Get()), #session.requests
    ctrl:_onBuy(5); assert(#session.requests == count + 1)
    assert(latest("purchase").args[1] == 5 and not model:CanBuy(1))
    ctrl:_onBuy(1); ctrl:OnRefresh(); assert(#session.requests == count + 1)
    equal(Save.Get(), before)
    local snapshot = clone(Save.Get()); snapshot.inventory.gold = 7500
    snapshot.inventory.mods[#snapshot.inventory.mods + 1] = { uid = 9, id = 1001, rank = 1 }
    finish(latest("purchase"), true, nil, snapshot)
    assert(model:GetGold() == 7500 and Inventory.GetByUid(9) and model:CanBuy(1))
    assert(storageOps == 0)
end)

test("online shop ignores cached wallet for authority and retains state on failure", function()
    reset(true); local ctrl, model = shop(true)
    Save.Get().inventory.gold = 0
    assert(model:CanBuy(1), "server decides affordability")
    ctrl:_onBuy(1); local before = clone(Save.Get())
    finish(latest("purchase"), false, "insufficient_gold")
    equal(Save.Get(), before); assert(model:GetResultText() ~= "" and model:CanBuy(1))
    assert(storageOps == 0)
end)

test("shop busy, service exceptions and unavailable service fail closed", function()
    reset(true); local ctrl, model = shop(true)
    session.busy = true; local count = #session.requests
    assert(not model:CanBuy(1)); ctrl:_onBuy(1); assert(#session.requests == count)
    session.busy = false; session.throws = true
    ctrl:_onBuy(1); assert(not ctrl._onlinePending and not model._onlinePending)
    session.throws = false; session.queryThrows = true
    assert(not model:CanBuy(1)); ctrl:_onBuy(1); assert(not ctrl._onlinePending)
    session.queryThrows = false
    package.loaded["Game.Online.OnlineSession"] = nil
    package.preload["Game.Online.OnlineSession"] = function() error("unavailable") end
    assert(not model:CanBuy(1)); ctrl:_onBuy(1); assert(not ctrl._onlinePending)
    assert(#session.requests == count and Save.Get().inventory.gold == 9000 and storageOps == 0)
end)

test("closing shop suppresses UI callback but allows global service completion", function()
    reset(true); local ctrl, model, view = shop(true)
    ctrl:_onBuy(1); local request = latest("purchase")
    ctrl:_onClose(); local renders, feedback = view.renders, model:GetResultText()
    local snapshot = clone(Save.Get()); snapshot.inventory.gold = 8700
    finish(request, true, nil, snapshot)
    assert(Save.Get().inventory.gold == 8700 and view.renders == renders)
    assert(model:GetResultText() == feedback and not ctrl._onlinePending)
end)

test("shop reopen generation ignores late old callback during a new request", function()
    reset(true); local ctrl, model, view = shop(true)
    ctrl:_onBuy(1); local old = latest("purchase")
    ctrl:OnClose(); session.busy = false; ctrl:OnOpen()
    local fresh = latest("refresh"); local renders = view.renders
    old.callback(false, "network_error")
    assert(ctrl._onlinePending and view.renders == renders)
    finish(fresh, true); assert(not ctrl._onlinePending and model:GetResultText() == "")
    old.callback(true); assert(model:GetResultText() == "")
end)

test("destroyed shop never touches view on completion", function()
    reset(true); local ctrl, _, view = shop(true)
    ctrl:_onBuy(1); local request = latest("purchase")
    ctrl:OnDestroy(); local renders = view.renders
    finish(request, true)
    assert(ctrl.view == nil and ctrl.model == nil and view.renders == renders)
end)

test("loadout keeps selection until successful server acknowledgment", function()
    reset(true); local ctrl, model = station(true)
    assert(model:GetFeedback() == "")
    ctrl:_onBagItem(1); local before = clone(Save.Get())
    ctrl:_onSlot(1); local request = latest("loadout")
    equal(request.args, { "weapon", 1, 1 })
    assert(model:GetSelected() == 1)
    ctrl:_onBagItem(2); ctrl:_onTab(2); ctrl:_onSlot(2)
    assert(model:GetSelected() == 1 and model:GetHost() == "weapon" and latest("loadout") == request)
    equal(Save.Get(), before)
    local snapshot = clone(Save.Get()); snapshot.loadout.weapon.installed[1] = 1
    finish(request, true, nil, snapshot)
    assert(model:GetSelected() == nil and model:GetSlots()[1].item.uid == 1)
    ctrl:_onSlot(1); request = latest("loadout"); assert(request.args[3] == 0)
    snapshot = clone(Save.Get()); snapshot.loadout.weapon.installed[1] = nil
    finish(request, true, nil, snapshot)
    assert(model:GetSlots()[1].empty and storageOps == 0)
end)

test("loadout failure, busy and exceptions preserve selection and snapshot", function()
    reset(true); local ctrl, model = station(true)
    ctrl:_onBagItem(1); local before = clone(Save.Get())
    ctrl:_onSlot(1); finish(latest("loadout"), false, "capacity_exceeded")
    assert(model:GetSelected() == 1 and model:GetFeedback() ~= "")
    session.busy = true; local count = #session.requests; ctrl:_onSlot(1)
    assert(#session.requests == count and model:GetSelected() == 1)
    session.busy = false; session.throws = true; ctrl:_onSlot(1)
    assert(not ctrl._onlinePending and model:GetSelected() == 1)
    equal(Save.Get(), before); assert(storageOps == 0)
end)

test("closed loadout preserves UI while service applies global state", function()
    reset(true); local ctrl, model, view = station(true)
    ctrl:_onBagItem(1); ctrl:_onSlot(1); local request = latest("loadout")
    ctrl:_onClose(); local renders = view.renders
    local snapshot = clone(Save.Get()); snapshot.loadout.weapon.installed[1] = 1
    finish(request, true, nil, snapshot)
    assert(Save.Get().loadout.weapon.installed[1] == 1 and view.renders == renders)
    assert(model:GetSelected() == 1)
end)

test("loadout reopen and destroy suppress stale and duplicate callbacks", function()
    reset(true); local ctrl, model, view = station(true)
    ctrl:_onBagItem(1); ctrl:_onSlot(1); local old = latest("loadout")
    ctrl:OnClose(); session.busy = false; ctrl:OnOpen()
    local fresh = latest("refresh"); local renders = view.renders
    old.callback(true); assert(ctrl._onlinePending and model:GetSelected() == 1 and view.renders == renders)
    finish(fresh, true); ctrl:_onSlot(1); local request = latest("loadout")
    ctrl:OnDestroy(); renders = view.renders
    finish(request, true); request.callback(false, "network_error")
    assert(ctrl.view == nil and ctrl.model == nil and view.renders == renders)
end)

test("mode exit suppresses pending UI completion and restores offline identity", function()
    reset(false); local offline, before = Save.Get(), clone(Save.Get())
    Save.BeginOnline(); assert(Save.ReplaceOnlineSnapshot(fixture()))
    local ctrl, _, view = shop(true)
    ctrl:_onBuy(1); local request, renders = latest("purchase"), view.renders
    Save.EndOnline(); request.callback(false, "unauthorized")
    assert(Save.Get() == offline and view.renders == renders)
    equal(offline, before); assert(storageOps == 0)
end)

test("synchronous and duplicate callbacks complete once after hydration", function()
    reset(true); local ctrl, model, view = shop(true)
    local callback
    local purchase = session.Purchase
    session.Purchase = function(_, done)
        callback = done
        local snapshot = clone(Save.Get()); snapshot.inventory.gold = 8700
        assert(Save.ReplaceOnlineSnapshot(snapshot))
        done(true)
    end
    ctrl:_onBuy(1)
    session.Purchase = purchase
    assert(not ctrl._onlinePending and model:GetGold() == 8700)
    local renders, feedback = view.renders, model:GetResultText()
    callback(false, "network_error")
    assert(view.renders == renders and model:GetResultText() == feedback and storageOps == 0)
end)

test("loadout service failure on refresh retains the existing snapshot", function()
    reset(true)
    local before = clone(Save.Get())
    local model, view = ModModel.New("ModStationPanel"), { renders = 0 }
    function view:Render() self.renders = self.renders + 1 end
    local ctrl = ModController.New(model); ctrl:BindView(view); ctrl:OnOpen()
    finish(latest("refresh"), false, "unauthorized")
    equal(Save.Get(), before); assert(not ctrl._onlinePending and model:GetFeedback() ~= "")
    session.queryThrows = true
    ctrl:_onBagItem(1); local count = #session.requests; ctrl:_onSlot(1)
    assert(#session.requests == count and model:GetSelected() == 1 and not ctrl._onlinePending)
    assert(storageOps == 0)
end)

print(string.format("online_gameplay_guards: %d passed, %d failed (isolated Lua; no Unity or physical save writes)",
    passed, failed))
assert(failed == 0, "online gameplay guard regressions")
