local SaveData = require "Game.Save.SaveData"
local Session = {}
local ready, busy = false, false
local revision, accountId, accountName = 0, nil, nil
local runId, pending, pendingSettlement, startPending

local function api() return CS.Game.LocalBackend.OnlineGameBridge end
local function finish(callback, ok, reason, value)
    if callback then callback(ok, reason, value) end
end
local function array(source, convert)
    local result = {}
    if source then
        for i = 0, source.Length - 1 do result[i + 1] = convert(source[i]) end
    end
    return result
end

local function adopt(profile)
    if not profile or not profile.game or (accountId and profile.accountId ~= accountId) then
        return false, "invalid_snapshot"
    end
    local game = profile.game
    if not game.inventory or not game.loadout or not game.meta or not game.statistics then
        return false, "invalid_snapshot"
    end
    local data = SaveData.Default()
    data.inventory.gold = game.inventory.gold
    data.inventory.mods = array(game.inventory.mods, function(card)
        return { uid = card.uid, id = card.id, rank = card.rank }
    end)
    for _, host in ipairs({ "weapon", "skill", "frame" }) do
        local source = game.loadout[host]
        if not source or not source.slots or not source.installed then return false, "invalid_snapshot" end
        local target = { capacity = source.capacity, slots = array(source.slots, function(slot)
            return { polarity = slot.polarity }
        end), installed = {} }
        for i = 0, source.installed.Length - 1 do
            local installed = source.installed[i]
            target.installed[installed.slot] = installed.uid
        end
        data.loadout[host] = target
    end
    data.meta.memoryFragments = game.meta.memoryFragments
    for _, field in ipairs({ "highestFloor", "totalRuns", "totalDeaths", "totalExtracts" }) do
        data.statistics[field] = game.statistics[field]
    end
    local ok, reason = SaveData.ReplaceOnlineSnapshot(data)
    if not ok then return false, reason end
    accountId, revision, ready = profile.accountId, profile.revision, true
    return true
end

local function safeAdopt(profile)
    local called, ok, reason = pcall(adopt, profile)
    if not called then return false, "invalid_snapshot" end
    return ok, reason
end

function Session.IsSupported() return api().IsSupported end
function Session.IsSelected() return SaveData.IsOnline() end
function Session.IsReady() return Session.IsSelected() and ready end
function Session.IsBusy() return busy end
function Session.GetRunId() return runId end
function Session.GetAccountName() return accountName or api().AccountName end
function Session.SelectOnline()
    if not Session.IsSupported() then return false, "development_only" end
    if busy then return false, "busy" end
    SaveData.BeginOnline()
    return true
end
function Session.SelectOffline()
    if busy or runId or pending or pendingSettlement or startPending then return false, "pending_request" end
    SaveData.EndOnline()
    ready, revision, accountId, accountName = false, 0, nil, nil
    return true
end

function Session.Login(name, callback)
    if not Session.IsSelected() or not Session.IsSupported() then finish(callback, false, "not_online"); return end
    if busy then finish(callback, false, "busy"); return end
    if accountName and name ~= accountName and (runId or pending or pendingSettlement or startPending) then
        finish(callback, false, "pending_request"); return
    end
    busy = true
    local invoked = pcall(function() api().Instance:Login(name, function(ok, reason, reply)
        busy = false
        if ok then
            -- Account changes are allowed only without unresolved transactions/runs.
            if name ~= accountName then accountId = nil end
            ok, reason = safeAdopt(reply and reply.profile)
            if ok then accountName = name end
        else ready = false end
        finish(callback, ok, reason)
    end) end)
    if not invoked then busy, ready = false, false; finish(callback, false, "invalid_response") end
end

local function request(command, callback)
    if busy then finish(callback, false, "busy"); return end
    if not Session.IsReady() then
        if Session.IsSelected() and accountName then
            Session.Login(accountName, function(ok, reason)
                if ok then request(command, callback) else finish(callback, false, reason) end
            end)
        else finish(callback, false, "not_logged_in") end
        return
    end
    busy = true
    local invoked = pcall(function() api().Instance:Request(command.operation, command.revision or revision, command.id or "",
        command.host or "", command.slot or 0, command.uid or 0, command.count or 0,
        command.outcome or "", function(ok, reason, reply)
            busy = false
            if ok then ok, reason = safeAdopt(reply and reply.profile) end
            if reason == "unauthorized" or reason == "not_logged_in" then ready = false end
            finish(callback, ok, reason, reply)
        end) end)
    if not invoked then busy = false; finish(callback, false, "invalid_response") end
end

local uncertain = { network_error = true, invalid_response = true, invalid_snapshot = true,
    unauthorized = true, not_logged_in = true, busy = true }
local function mutation(operation, host, slot, uid, count, callback)
    if runId or pendingSettlement or startPending then finish(callback, false, "active_run"); return end
    if not Session.IsSelected() or (not ready and not accountName) or busy then
        finish(callback, false, busy and "busy" or "not_logged_in"); return
    end
    if pending then
        if pending.operation ~= operation or pending.host ~= host or pending.slot ~= slot
            or pending.uid ~= uid or pending.count ~= count then
            finish(callback, false, "pending_request"); return
        end
    else
        pending = { operation = operation, host = host, slot = slot, uid = uid, count = count,
            revision = revision, id = api().NewRequestId() }
    end
    request(pending, function(ok, reason)
        if ok or not uncertain[reason] then pending = nil end
        if reason == "revision_conflict" then
            Session.Refresh(function() finish(callback, false, reason) end)
        else finish(callback, ok, reason) end
    end)
end
function Session.Purchase(count, callback) mutation("purchase", nil, nil, nil, count, callback) end
function Session.Loadout(host, slot, uid, callback) mutation("loadout", host, slot, uid, nil, callback) end
function Session.Upgrade(uid, callback) mutation("upgrade", nil, nil, uid, nil, callback) end
function Session.Refresh(callback) request({ operation = "refresh" }, callback) end

function Session.StartRun(callback)
    if pending or pendingSettlement then finish(callback, false, "pending_request"); return end
    if not Session.IsReady() or busy then finish(callback, false, busy and "busy" or "not_logged_in"); return end
    startPending = true
    -- A timed-out start is recoverable: the server returns the existing active run.
    request({ operation = "start" }, function(ok, reason, reply)
        if ok then runId, startPending = reply.runId, nil
        elseif not uncertain[reason] then startPending = nil end
        finish(callback, ok, reason, runId)
    end)
end
function Session.Settle(outcome, callback)
    outcome = string.lower(tostring(outcome))
    if outcome ~= "extract" and outcome ~= "death" then finish(callback, false, "invalid_outcome"); return end
    if not runId then finish(callback, false, "missing_run"); return end
    if pendingSettlement and pendingSettlement.outcome ~= outcome then
        finish(callback, false, "outcome_conflict"); return
    end
    pendingSettlement = pendingSettlement or { operation = "settle", id = runId, outcome = outcome }
    request(pendingSettlement, function(ok, reason, reply)
        local reward
        if ok then
            reward = { gold = reply.reward.gold, fragments = reply.reward.fragments,
                outcome = reply.reward.outcome, replayed = reply.replayed }
            runId, pendingSettlement = nil, nil
        end
        finish(callback, ok, reason, reward)
    end)
end

function Session.Shutdown()
    if Session.IsSupported() then api().Close() end
end

return Session
