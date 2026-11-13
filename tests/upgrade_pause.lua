-- Real DungeonManager; all game, UI, storage and Unity dependencies are inert.
local project = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/upgrade_pause.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = project .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local function noop() end
package.loaded["Framework.UI.Utils.Logger"] = { Info = noop, Warn = noop, Error = noop }
for _, name in ipairs({
    "Framework.Core.UpdateManager", "Game.Dungeon.FloorGenerator",
    "Game.Dungeon.FloorEventSystem", "Game.Dungeon.RunResult", "Game.Save.SaveData",
    "Game.Save.MetaSystem", "Game.Mod.ModSystem", "Game.Build.BuildSystem",
}) do package.loaded[name] = {} end
local currentUI
package.loaded["Game.GameMain"] = { GetUIManager = function() return currentUI end }
package.loaded["Game.Battle.BattleManager"] = {
    Phase = { Running = "Running", Paused = "Paused" },
}
local DungeonManager = require "Game.Dungeon.DungeonManager"

local function fixture(visible)
    local ui = { visible = false, showOnOpen = visible, opens = 0, closes = 0, closeReasons = {} }
    function ui:Open(name)
        assert(name == "LevelUpPopup")
        self.opens = self.opens + 1
        self.visible = self.showOnOpen
    end
    function ui:IsOpen(name)
        assert(name == "LevelUpPopup")
        return self.visible
    end
    function ui:Close(name, reason)
        assert(name == "LevelUpPopup" and (reason == "Selected" or reason == "Unavailable"))
        self.closes = self.closes + 1
        self.closeReasons[self.closes] = reason
        self.visible = false
    end
    currentUI = ui
    local bm = { phase = "Paused", resumes = 0 }
    function bm:Resume()
        self.resumes = self.resumes + 1
        if self.phase == "Paused" then self.phase = "Running" end
    end
    local build = { generated = 0, applied = {}, fallback = 0 }
    function build:GenerateChoices(manager, count)
        assert(manager == bm and count == 3)
        self.generated = self.generated + 1
        return { { name = "Choice " .. self.generated }, { name = "Second" } }
    end
    function build:ApplyLevelUpChoice(manager, option)
        assert(manager == bm)
        self.applied[#self.applied + 1] = option
    end
    function build:AutoPickFallback(manager, options)
        assert(manager == bm and options and #options == 2)
        self.fallback = self.fallback + 1
    end
    local dm = DungeonManager.New()
    dm.runData = dm:_newRunData()
    dm.battleManager, dm.buildSystem = bm, build
    return dm, bm, build, ui
end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

test("visible popup stays paused beyond 60 seconds", function()
    local dm, bm, build, ui = fixture(true)
    dm:_onLevelUp(1)
    for _ = 1, 65 do dm:Update(1) end
    assert(ui.visible and dm._levelUpOptions and dm._levelUpPending == 1)
    assert(dm._levelUpTimer == 0 and bm.phase == "Paused" and bm.resumes == 0)
    assert(build.fallback == 0 and #build.applied == 0)
end)

test("missing popup falls back at exactly 30 seconds once", function()
    local dm, bm, build, ui = fixture(false)
    dm:_onLevelUp(1)
    dm:Update(29)
    assert(bm.phase == "Paused" and bm.resumes == 0 and build.fallback == 0)
    assert(ui.closes == 0)
    dm:Update(1)
    assert(bm.phase == "Running" and bm.resumes == 1 and build.fallback == 1)
    assert(dm._levelUpOptions == nil and dm._levelUpPending == 0)
    assert(ui.closes == 1 and ui.closeReasons[1] == "Unavailable")
    dm:Update(60)
    dm:SelectLevelUpOption(1)
    assert(bm.resumes == 1 and build.fallback == 1 and #build.applied == 0)
    assert(ui.closes == 1)
end)

test("visible popup resets accumulated missing time", function()
    local dm, bm, build, ui = fixture(false)
    dm:_onLevelUp(1)
    dm:Update(29)
    ui.visible = true
    dm:Update(65)
    assert(dm._levelUpTimer == 0 and bm.resumes == 0)
    ui.visible = false
    dm:Update(29)
    assert(bm.phase == "Paused" and build.fallback == 0)
    dm:Update(1)
    assert(bm.resumes == 1 and build.fallback == 1)
end)

test("invalid choice preserves pending; valid choice applies and resumes once", function()
    local dm, bm, build, ui = fixture(true)
    dm:_onLevelUp(1)
    local options = dm._levelUpOptions
    for _, index in ipairs({ 0, 3, -1, "invalid" }) do dm:SelectLevelUpOption(index) end
    assert(dm._levelUpOptions == options and dm._levelUpPending == 1)
    assert(bm.resumes == 0 and #build.applied == 0 and ui.closes == 0)
    dm:SelectLevelUpOption(2)
    assert(build.applied[1] == options[2] and #build.applied == 1)
    assert(bm.resumes == 1 and bm.phase == "Running" and ui.closes == 1)
    -- A late callback must not release a subsequent unrelated pause.
    bm.phase = "Paused"
    dm:SelectLevelUpOption(2)
    dm:SelectLevelUpOption(99)
    dm:SelectLevelUpOption(nil)
    assert(bm.phase == "Paused" and bm.resumes == 1 and #build.applied == 1)
end)

test("consecutive levels remain paused until the final valid selection", function()
    local dm, bm, build, ui = fixture(true)
    dm:_onLevelUp(2)
    dm:_onLevelUp(1)
    assert(dm._levelUpPending == 3 and ui.opens == 1)
    for remaining = 3, 1, -1 do
        dm:Update(65)
        assert(bm.phase == "Paused" and bm.resumes == 0)
        local option = dm._levelUpOptions[1]
        dm:SelectLevelUpOption(1)
        assert(build.applied[#build.applied] == option)
        assert(dm._levelUpPending == remaining - 1)
        if remaining > 1 then assert(ui.visible and bm.phase == "Paused") end
    end
    assert(#build.applied == 3 and build.generated == 3 and build.fallback == 0)
    assert(ui.opens == 3 and ui.closes == 3 and not ui.visible)
    assert(dm._levelUpOptions == nil and bm.phase == "Running" and bm.resumes == 1)
    dm:SelectLevelUpOption(1)
    assert(bm.resumes == 1 and #build.applied == 3)
end)

print(string.format("RESULT %d passed, %d failed; no Unity or disk writes", passed, failed))
if failed > 0 then os.exit(1) end
