local ROOT_DIR = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/online_session.lua <project_root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = ROOT_DIR .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local noop = function() end
package.loaded["Framework.UI.Utils.Logger"] = setmetatable({}, { __index = function() return noop end })
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local calls, loginCallback, nextId = {}, nil, 0
local bridge = {
    Login = function(_, name, callback) loginCallback = callback end,
    Request = function(_, operation, revision, id, host, slot, uid, count, outcome, callback)
        calls[#calls + 1] = { operation = operation, revision = revision, id = id, host = host,
            slot = slot, uid = uid, count = count, outcome = outcome, callback = callback }
    end,
}
CS = { Game = { LocalBackend = { OnlineGameBridge = {
    IsSupported = true, AccountName = "test-account", Instance = bridge,
    NewRequestId = function() nextId = nextId + 1; return tostring(nextId) end, Close = noop,
} } }, UnityEngine = { Application = { persistentDataPath = "unreachable" } },
    Storage = { Current = setmetatable({}, { __index = function() error("online disk access") end }) } }

local function arr(values)
    local result = { Length = #values }
    for i, value in ipairs(values) do result[i - 1] = value end
    return result
end
local function profile(revision, gold)
    local loadout = {}
    for _, name in ipairs({ "weapon", "skill", "frame" }) do
        loadout[name] = { capacity = 10, slots = arr({ { polarity = "Neutral" } }), installed = arr({}) }
    end
    return { accountId = "account-a", revision = revision, game = {
        inventory = { gold = gold, mods = arr({ { uid = 1, id = 1001, rank = 2 } }) },
        loadout = loadout, meta = { memoryFragments = 5 }, statistics = {
            highestFloor = 1, totalRuns = 1, totalDeaths = 0, totalExtracts = 1,
        },
    } }
end
local Save = require "Game.Save.SaveData"
local Manager = require "Game.Save.SaveManager"
local Session = require "Game.Online.OnlineSession"
local offline = Save.Default()
offline.inventory.gold = 77
Save.current = offline
check(Session.SelectOnline() and Save.Get() ~= offline and Save.Get().inventory.gold == 0, "isolated online empty state")
check(not Save.Commit(), "no online disk commit")
check(not Manager.Save(offline), "no bypass disk save")
check(not Manager.Load(), "no disk load online")
check(require("Game.Mod.ModInventory").AddMod(1001) == nil, "no local online Mod grant")
check(not require("Game.Mod.ModSystem").Install("weapon", 1, 1), "no local online install")
Session.Login("test-account", function(ok) check(ok and Save.Get().inventory.gold == 900, "login applies profile before callback") end)
check(Session.IsBusy(), "login busy")
loginCallback(true, "", { profile = profile(1, 900) })
check(Session.IsReady() and not Session.IsBusy(), "login ready")
Session.Purchase(1, function(ok, reason) check(not ok and reason == "network_error", "purchase timeout") end)
local first = calls[#calls]
first.callback(false, "network_error")
check(not Session.SelectOffline(), "unresolved purchase blocks offline")
Session.Purchase(5, function(ok, reason) check(not ok and reason == "pending_request", "cannot replace uncertain intent") end)
Session.Purchase(1, function(ok) check(ok and Save.Get().inventory.gold == 600, "retry hydrates before callback") end)
local retry = calls[#calls]
check(retry.id == first.id and retry.revision == first.revision and retry.count == 1, "immutable retry identity")
retry.callback(true, "", { profile = profile(2, 600) })
check(offline.inventory.gold == 77, "offline unchanged")
Session.Loadout("weapon", 1, 1, function(ok, reason) check(not ok and reason == "revision_conflict", "conflict reported after refresh") end)
calls[#calls].callback(false, "revision_conflict")
check(calls[#calls].operation == "refresh", "conflict refresh")
calls[#calls].callback(true, "", { profile = profile(3, 600) })
Session.StartRun(function(ok) check(not ok, "start timeout") end)
calls[#calls].callback(false, "network_error")
check(not Session.SelectOffline(), "uncertain start blocks offline")
Session.Purchase(1, function(ok, reason) check(not ok and reason == "active_run", "uncertain run locks shop") end)
Session.StartRun(function(ok, reason, id) check(ok and id == "run-a", "start recovery") end)
local battleProfile = profile(3, 600)
battleProfile.game.loadout.weapon.installed = arr({ { slot = 1, uid = 1 } })
calls[#calls].callback(true, "", { profile = battleProfile, runId = "run-a" })
local derived = require("Game.Mod.ModSystem").ComputeDerived()
check(derived.mul.damageMul == 1.2, "authoritative loadout changes battle damage")
Session.Settle("Extract", function(ok) check(not ok, "settle timeout") end)
local settle = calls[#calls]
settle.callback(false, "network_error")
check(not Session.SelectOffline(), "pending settlement blocks offline")
Session.Settle("death", function(ok, reason) check(not ok and reason == "outcome_conflict", "cannot change pending outcome") end)
Session.Settle("extract", function(ok) check(not ok, "401 keeps pending settlement") end)
check(calls[#calls].id == settle.id and calls[#calls].outcome == settle.outcome, "same settlement retry")
calls[#calls].callback(false, "unauthorized")
check(Session.IsSelected() and not Session.IsReady() and Session.GetRunId() == "run-a", "expired session never falls offline")
Session.Settle("extract", function(ok, reason, receipt)
    check(ok and receipt.gold == 100 and Save.Get().inventory.gold == 700, "confirmed reward and snapshot")
end)
loginCallback(true, "", { profile = profile(4, 700) })
check(calls[#calls].id == "run-a", "reauth keeps settlement identity")
calls[#calls].callback(true, "", { profile = profile(4, 700), replayed = true,
    reward = { outcome = "extract", gold = 100, fragments = 5 } })
check(Session.GetRunId() == nil and Session.SelectOffline(), "confirmed run permits offline")
check(Save.Get() == offline and Save.Get().inventory.gold == 77, "original offline pointer restored")
return checks
