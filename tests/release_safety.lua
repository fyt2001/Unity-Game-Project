-- Run: lua tests/release_safety.lua
-- Optional globals: ROOT = absolute project directory; SOURCE_LOADER(path) = source string.
-- XLua: env.Global.Set("ROOT", projectPath);
-- env.Global.Set("SOURCE_LOADER", new System.Func<string, string>(System.IO.File.ReadAllText));
-- env.DoString(System.IO.File.ReadAllText(projectPath + "/tests/release_safety.lua"));
-- Use LuaEnv.DoString directly: assertion failures propagate to the caller.
-- Only the source loader reads disk. All production IO runs against isolated memory mocks.
local root = assert(rawget(_G, "ROOT") or (arg and arg[1]), "usage: lua tests/release_safety.lua <project_root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
assert(root:match("^%a:/") or root:match("^/"), "ROOT must be an absolute project path")
local sourceLoader = rawget(_G, "SOURCE_LOADER") or function(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return assert(source, "Unable to read " .. path)
end
local sources = {}
local function source(name)
    if not sources[name] then
        local path = root .. "/Assets/Game/LuaScripts/" .. name:gsub("%.", "/") .. ".lua"
        sources[name] = assert(sourceLoader(path), "Source loader returned nil: " .. path)
        assert(type(sources[name]) == "string", "Source loader must return a string")
    end
    return sources[name]
end

local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function fixture(debugBuild, editor, persisted)
    local storage = { files = {}, dirs = {}, calls = {}, faults = {}, hits = 0 }
    local function operation(op, path, action)
        storage.calls[#storage.calls + 1] = { op = op, path = path }
        for _, fault in ipairs(storage.faults) do
            if fault.op == op and fault.path == path then
                fault.seen = (fault.seen or 0) + 1
                if fault.seen == (fault.at or 1) then
                    storage.hits = storage.hits + 1
                    if fault.mode == "throw" then error("Injected " .. op .. " failure", 0) end
                    if fault.mode == "after-action" then
                        action()
                        error("Injected " .. op .. " failure after completion", 0)
                    end
                    if fault.mode == "partial-move" then
                        assert(op == "MoveFile" and fault.to, "Partial move requires a destination")
                        storage.files[fault.to] = assert(storage.files[path]):sub(1, 12)
                        error("Injected MoveFile failure after partial destination write", 0)
                    end
                    if fault.mode == "corrupt" then storage.files[path] = "return { broken" end
                    if fault.mode == "mismatch" then return "return { marker = 'wrong' }" end
                end
            end
        end
        return action()
    end
    function storage:DirectoryExists(path)
        return operation("DirectoryExists", path, function() return self.dirs[path] == true end)
    end
    function storage:CreateDirectory(path)
        return operation("CreateDirectory", path, function() self.dirs[path] = true end)
    end
    function storage:FileExists(path)
        return operation("FileExists", path, function() return self.files[path] ~= nil end)
    end
    function storage:WriteAllText(path, content)
        return operation("WriteAllText", path, function() self.files[path] = content end)
    end
    function storage:ReadAllText(path)
        return operation("ReadAllText", path, function() return assert(self.files[path], "Missing " .. path) end)
    end
    function storage:DeleteFile(path)
        return operation("DeleteFile", path, function() self.files[path] = nil end)
    end
    function storage:MoveFile(from, to)
        return operation("MoveFile", from, function()
            assert(self.files[to] == nil, "Move destination already exists")
            self.files[to] = assert(self.files[from], "Move source missing")
            self.files[from] = nil
        end)
    end
    local prefs = { values = {}, writes = 0, saves = 0 }
    prefs.values.GM_Enabled = persisted
    function prefs.HasKey(key) return prefs.values[key] ~= nil end
    function prefs.GetInt(key, default) return prefs.values[key] or default or 0 end
    function prefs.SetInt(key, value) prefs.writes = prefs.writes + 1; prefs.values[key] = value end
    function prefs.Save() prefs.saves = prefs.saves + 1 end
    local unity = {
        Application = { persistentDataPath = "/MEMORY_ONLY", isEditor = editor == true },
        Debug = { isDebugBuild = debugBuild == true },
        Time = { realtimeSinceStartup = 0 }, PlayerPrefs = prefs,
    }
    local classTypes, typeTokens = {}, {}
    local function mockUnityClass(name)
        local class, token = { name = name }, { typeName = name }
        classTypes[class], typeTokens[token] = token, true
        return class
    end
    local function mockTypeof(class)
        local token = assert(classTypes[class], "typeof requires a registered Unity class")
        return token
    end
    local env = {
        CS = { Storage = { Current = storage }, UnityEngine = unity,
            System = { IO = { Path = { GetDirectoryName = function(path) return path:match("^(.*)/[^/]+$") end } } } },
        assert = assert, error = error, ipairs = ipairs, pairs = pairs, pcall = pcall,
        type = type, tostring = tostring, tonumber = tonumber, select = select,
        math = math, string = string, table = table, load = load, typeof = mockTypeof,
    }
    env._G = env
    local noop = function() end
    local modules = { ["Framework.UI.Utils.Logger"] = {
        Debug = noop, Info = noop, Warn = noop, Error = noop,
    } }
    function env.require(name)
        if modules[name] == nil then
            local chunk = assert(load(source(name), "@" .. name, "t", env))
            modules[name] = assert(chunk(), "Module returned nil: " .. name)
        end
        return modules[name]
    end
    local registrations = {}
    local manager = { RegisterWindow = function(_, name, config)
        registrations[#registrations + 1] = { name = name, config = config }
    end }
    return { storage = storage, prefs = prefs, unity = unity, require = env.require,
        manager = manager, registrations = registrations, modules = modules,
        mockUnityClass = mockUnityClass, typeof = mockTypeof, typeTokens = typeTokens }
end

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name, fn } end
local old = "return { marker = 'old', inventory = { gold = 41 } }"
local newer = { marker = "new", inventory = { gold = 99 } }
local function saveFixture()
    local f = fixture()
    f.save = f.require("Game.Save.SaveManager")
    f.path = f.save.GetFilePath()
    f.tmp, f.backup = f.path .. ".tmp", f.path .. ".bak"
    return f
end
local function count(f, op, path)
    local n = 0
    for _, call in ipairs(f.storage.calls) do
        if call.op == op and (path == nil or call.path == path) then n = n + 1 end
    end
    return n
end
local function noTmpReads(f)
    equal(count(f, "ReadAllText", f.tmp), 0, "Load must never read tmp")
end
local failures = {
    { "temporary write throws", "WriteAllText", "tmp", "throw" },
    { "temporary readback differs", "ReadAllText", "tmp", "mismatch" },
    { "backup write throws", "WriteAllText", "backup", "throw" },
    { "backup readback differs", "ReadAllText", "backup", "mismatch" },
    { "primary delete throws", "DeleteFile", "path", "throw" },
    { "move throws after deletion", "MoveFile", "tmp", "throw" },
    { "committed readback corrupts primary", "ReadAllText", "path", "corrupt", 2 },
}
for _, spec in ipairs(failures) do
    test("save: " .. spec[1], function()
        local f = saveFixture()
        f.storage.files[f.path] = old
        f.storage.faults[1] = { op = spec[2], path = f[spec[3]], mode = spec[4], at = spec[5] }
        equal(f.save.Save({ marker = newer.marker, inventory = { gold = 99 } }), false, "Save failure")
        equal(f.storage.hits, 1, "injection reached")
        equal(count(f, "WriteAllText", f.path), 0, "no direct overwrite fallback")
        if spec[2] ~= "MoveFile" and spec[4] ~= "corrupt" then
            equal(f.storage.files[f.path], old, "primary preserved before commit")
            equal(count(f, "MoveFile"), 0, "replacement must stop on failure")
        else
            equal(f.storage.files[f.backup], old, "recoverable backup")
        end
        f.storage.calls = {}
        local recovered = assert(f.save.Load(), "Old save must remain recoverable")
        equal(recovered.marker, "old", "recovered marker")
        equal(recovered.inventory.gold, 41, "recovered gold")
        noTmpReads(f)
    end)
end

for _, primary in ipairs({ "missing", "corrupt", "read throws" }) do
    test("load: interrupted primary " .. primary .. " recovers backup", function()
        local f = saveFixture()
        f.storage.files[f.backup] = old
        f.storage.files[f.tmp] = "return { marker = 'uncommitted' }"
        if primary ~= "missing" then f.storage.files[f.path] = "return { broken" end
        if primary == "read throws" then
            f.storage.faults[1] = { op = "ReadAllText", path = f.path, mode = "throw" }
        end
        equal(assert(f.save.Load()).marker, "old", "backup selected")
        if primary == "read throws" then equal(f.storage.hits, 1, "read failure reached") end
        noTmpReads(f)
        equal(count(f, "WriteAllText"), 0, "recovery read is non-writing")
    end)
end
test("load: valid new primary wins over backup and tmp", function()
    local f = saveFixture()
    f.storage.files[f.path] = "return { marker = 'new' }"
    f.storage.files[f.backup], f.storage.files[f.tmp] = old, "return { marker = 'tmp' }"
    equal(assert(f.save.Load()).marker, "new")
    equal(count(f, "ReadAllText", f.backup), 0, "backup not read")
    noTmpReads(f)
end)
test("load: tmp alone is never a save", function()
    local f = saveFixture()
    f.storage.files[f.tmp] = old
    equal(f.save.Load(), nil)
    noTmpReads(f)
end)
test("load: both committed candidates corrupt returns nil", function()
    local f = saveFixture()
    f.storage.files[f.path], f.storage.files[f.backup], f.storage.files[f.tmp] = "broken", "return 5", old
    equal(f.save.Load(), nil)
    noTmpReads(f)
end)
test("save: first save commits and creates directory", function()
    local f = saveFixture()
    equal(f.save.Load(), nil)
    equal(f.save.Save({ marker = "first", inventory = { gold = 17 } }), true)
    equal(assert(f.save.Load()).inventory.gold, 17)
    equal(count(f, "CreateDirectory"), 1)
    equal(count(f, "DeleteFile"), 0)
    equal(count(f, "WriteAllText", f.backup), 0)
    equal(f.storage.files[f.tmp], nil, "tmp moved")
end)
test("save: successful replacement preserves old backup", function()
    local f = saveFixture()
    f.storage.files[f.path] = old
    equal(f.save.Save({ marker = "new", inventory = { gold = 99 } }), true)
    equal(assert(f.save.Load()).marker, "new")
    equal(f.storage.files[f.backup], old)
    equal(f.storage.files[f.tmp], nil)
end)
for _, mode in ipairs({ "partial-move", "after-action" }) do
    test("save: move " .. mode .. " throws with destination already changed", function()
        local f = saveFixture()
        f.storage.files[f.path] = old
        f.storage.faults[1] = { op = "MoveFile", path = f.tmp, to = f.path, mode = mode }
        equal(f.save.Save({ marker = "new", inventory = { gold = 99 } }), false)
        equal(f.storage.hits, 1, "move failure reached")
        assert(f.storage.files[f.path] and f.storage.files[f.path] ~= old, "Move changed destination before throwing")
        equal(f.storage.files[f.backup], old, "move failure preserves previous backup")
        equal(count(f, "WriteAllText", f.path), 0, "no direct overwrite fallback")
        equal(count(f, "MoveFile"), 1, "no retry after partial completion")
        if mode == "partial-move" then
            equal(f.save._deserialize(f.storage.files[f.path]), nil, "partial destination is corrupt")
            assert(f.storage.files[f.tmp], "partial copy leaves temporary source")
        else
            equal(f.storage.files[f.tmp], nil, "completed move consumes temporary source")
        end
        f.storage.calls = {}
        local loaded = assert(f.save.Load(), "At least one committed save must remain recoverable")
        equal(loaded.marker, mode == "partial-move" and "old" or "new")
        equal(loaded.inventory.gold, mode == "partial-move" and 41 or 99)
        noTmpReads(f)
    end)
end
test("save: corrupt primary cannot overwrite good backup", function()
    local f = saveFixture()
    f.storage.files[f.path], f.storage.files[f.backup] = "broken", old
    f.storage.faults[1] = { op = "MoveFile", path = f.tmp, mode = "throw" }
    equal(f.save.Save({ marker = "new" }), false)
    equal(f.storage.hits, 1)
    equal(count(f, "WriteAllText", f.backup), 0)
    equal(f.storage.files[f.backup], old)
    equal(assert(f.save.Load()).marker, "old")
end)

local function rejectedBeforeIO(f, data)
    f.storage.files[f.path], f.storage.files[f.backup] = old, old
    f.storage.files[f.tmp] = "previous temporary bytes"
    equal(f.save.Save(data), false, "invalid Save returns false without throwing")
    equal(#f.storage.calls, 0, "invalid Save must perform zero storage operations")
    equal(f.storage.files[f.path], old, "invalid Save preserves primary bytes")
    equal(f.storage.files[f.backup], old, "invalid Save preserves backup bytes")
    equal(f.storage.files[f.tmp], "previous temporary bytes", "invalid Save preserves tmp bytes")
end
for _, number in ipairs({ { "+infinity", math.huge }, { "-infinity", -math.huge }, { "NaN", 0 / 0 } }) do
    test("save validation: rejects " .. number[1] .. " gold before IO", function()
        rejectedBeforeIO(saveFixture(), { inventory = { gold = number[2] } })
    end)
    test("serialization: " .. number[1] .. " must raise instead of becoming nil", function()
        local f = saveFixture()
        local ok, err = pcall(f.save._serialize, { inventory = { gold = number[2] } })
        equal(ok, false, "non-finite serialization must throw")
        assert(tostring(err):find("Non-finite", 1, true), "Expected non-finite assertion: " .. tostring(err))
    end)
end
for _, cycle in ipairs({ "root", "nested" }) do
    test("save validation: rejects " .. cycle .. " cycle before IO", function()
        local data = { inventory = { gold = 99 } }
        if cycle == "root" then data.self = data else data.inventory.self = data.inventory end
        rejectedBeforeIO(saveFixture(), data)
    end)
end
local invalidTrees = {
    { "function in unknown nested field", function() return { extra = { callback = function() end } } end },
    { "thread in unknown nested field", function() return { extra = { coroutine.create(function() end) } } end },
    { "table key", function() return { extra = { [{}] = true } } end },
    { "non-finite numeric key", function() return { extra = { [math.huge] = true } } end },
    { "non-finite unknown nested value", function() return { extra = { { value = math.huge } } } end },
}
for _, spec in ipairs(invalidTrees) do
    test("save validation: rejects " .. spec[1], function()
        rejectedBeforeIO(saveFixture(), spec[2]())
    end)
end
local badSchemas = {
    { "inventory=false", "return { inventory = false }", function() return { inventory = false } end },
    { "gold='bad'", "return { inventory = { gold = 'bad' } }", function() return { inventory = { gold = "bad" } } end },
}
for _, spec in ipairs(badSchemas) do
    test("save validation: " .. spec[1] .. " rejected before IO", function()
        rejectedBeforeIO(saveFixture(), spec[3]())
    end)
    test("load validation: " .. spec[1] .. " recovers valid backup", function()
        local f = saveFixture()
        equal(f.save._deserialize(spec[2]), nil, "schema-invalid deserialize")
        f.storage.files[f.path], f.storage.files[f.backup], f.storage.files[f.tmp] = spec[2], old, old
        local loaded = assert(f.save.Load(), "Schema-invalid primary must recover backup")
        equal(loaded.marker, "old")
        equal(loaded.inventory.gold, 41)
        equal(f.storage.files[f.path], spec[2], "Load preserves invalid primary bytes")
        equal(count(f, "WriteAllText"), 0)
        noTmpReads(f)
    end)
    for _, fault in ipairs({
        { "delete failure", "DeleteFile", "path", "throw" },
        { "move failure", "MoveFile", "tmp", "throw" },
        { "commit corruption", "ReadAllText", "path", "corrupt", 2 },
    }) do
        test("save recovery: " .. spec[1] .. " keeps good backup on " .. fault[1], function()
            local f = saveFixture()
            f.storage.files[f.path], f.storage.files[f.backup] = spec[2], old
            f.storage.faults[1] = { op = fault[2], path = f[fault[3]], mode = fault[4], at = fault[5] }
            equal(f.save.Save({ inventory = { gold = 99 }, marker = "new" }), false)
            equal(f.storage.hits, 1, "failure injection reached")
            equal(count(f, "WriteAllText", f.backup), 0, "schema-invalid primary never copied to backup")
            equal(f.storage.files[f.backup], old, "good backup bytes preserved")
            local loaded = assert(f.save.Load(), "Good backup remains recoverable after failed save")
            equal(loaded.inventory.gold, 41)
            equal(loaded.marker, "old")
        end)
    end
end
test("schema validation: every wrong default field rejects save and recovers backup", function()
    local f = saveFixture()
    local defaults = f.require("Game.Save.SaveData").Default()
    local checked = 0
    local function checkFields(fields, path)
        for key, expected in pairs(fields) do
            local keys = {}
            for i, part in ipairs(path) do keys[i] = part end
            keys[#keys + 1] = key
            local data, target = {}, nil
            target = data
            for i = 1, #keys - 1 do target[keys[i]] = {}; target = target[keys[i]] end
            if type(expected) == "table" or type(expected) == "string" then
                target[key] = false
            else
                target[key] = "wrong type"
            end
            equal(f.save._isValid(data), false, "default field type mismatch")
            local invalid = "return " .. f.save._serialize(data)
            equal(f.save._deserialize(invalid), nil, "deserialize rejects wrong field type")
            rejectedBeforeIO(f, data)
            f.storage.files[f.path], f.storage.files[f.backup] = invalid, old
            local loaded = assert(f.save.Load(), "Wrong field primary must recover backup")
            equal(loaded.marker, "old")
            equal(loaded.inventory.gold, 41)
            equal(f.storage.files[f.path], invalid, "recovery leaves primary untouched")
            equal(f.storage.files[f.backup], old, "recovery leaves backup untouched")
            equal(count(f, "WriteAllText"), 0)
            noTmpReads(f)
            f.storage.calls = {}
            checked = checked + 1
            if type(expected) == "table" then checkFields(expected, keys) end
        end
    end
    checkFields(defaults, {})
    assert(checked > 0, "Must exercise actual default fields")
end)
test("schema migration: missing fields accepted and filled on load", function()
    local f = saveFixture()
    equal(f.save._isValid({ inventory = { gold = 7 } }), true)
    equal(f.save.Save({ inventory = { gold = 7 } }), true)
    local loaded = assert(f.save.Load())
    equal(loaded.inventory.gold, 7)
    equal(loaded.statistics.totalRuns, 0)
    equal(loaded.loadout.weapon.capacity, 10)
    equal(type(loaded.inventory.items), "table")
    equal(type(loaded.player.unlockedCharacters), "table")
    equal(loaded.version, f.require("Game.Save.SaveData").VERSION)
end)
test("save validation: shared acyclic tables and finite values round trip", function()
    local f = saveFixture()
    local shared = { value = 1.25, [false] = "boolean key", [3.5] = "numeric key" }
    equal(f.save.Save({ inventory = { gold = 1e20 }, extra = { shared, shared, negative = -2.5 } }), true)
    local loaded = assert(f.save.Load())
    equal(loaded.inventory.gold, 1e20)
    equal(loaded.extra[1].value, 1.25)
    equal(loaded.extra[2][false], "boolean key")
    equal(loaded.extra[2][3.5], "numeric key")
    equal(loaded.extra.negative, -2.5)
end)

local function gmFixture(debugBuild, editor, persisted)
    local f = fixture(debugBuild, editor, persisted)
    f.config = f.require("Game.GM.GMConfig")
    f.unlock = f.require("Game.GM.GMUnlock")
    f.uiConfig = f.require("Game.GM.GMUIConfig")
    f.register = f.require("Game.UI.GM.RegisterGM")
    f.unlock.Init()
    return f
end
local function releaseClosed(f)
    equal(f.config.IsDev(), false)
    equal(f.config.IsEnabled(), false)
    equal(f.config.CanOpenPanel(), false, "release panel gate")
    equal(f.config.IsUnlockedByTaps(), false)
    equal(f.unlock.IsUnlocked(), false)
    f.register(f.manager)
    equal(#f.registrations, 0, "release window registration")
    equal(f.prefs.writes, 0, "release prefs writes")
    equal(f.prefs.saves, 0, "release prefs flushes")
end
local actions = {
    { "stale GM_Enabled=1", function() end },
    { "SetEnabled(true)", function(f) equal(f.config.SetEnabled(true), false) end },
    { "ToggleEnabled repeatedly", function(f) for _ = 1, 10 do f.config.ToggleEnabled() end end },
    { "_SetUnlockedByTaps(true)", function(f) f.config._SetUnlockedByTaps(true) end },
    { "rapid taps with legacy enabled release channel", function(f)
        -- Re-enable the historical channel in memory to prove the build gate itself protects release.
        f.uiConfig.Channel.release = f.uiConfig.Channel.dev
        for i = 1, f.uiConfig.TapUnlock.taps * 3 do
            f.unity.Time.realtimeSinceStartup = i * 0.05
            equal(f.unlock.OnVersionTapped(), false, "release tap result")
        end
    end },
    { "combined bypass attempts", function(f)
        f.config.SetEnabled(true)
        f.config.ToggleEnabled()
        f.config._SetUnlockedByTaps(true)
        for _ = 1, 20 do equal(f.unlock.OnVersionTapped(), false) end
    end },
}
for _, action in ipairs(actions) do
    test("GM release: " .. action[1], function()
        local f = gmFixture(false, false, 1)
        action[2](f)
        releaseClosed(f)
        equal(f.prefs.values.GM_Enabled, 1, "stale preference stays in memory")
    end)
end
for _, mode in ipairs({ { "development", true, false }, { "editor", false, true } }) do
    test("GM " .. mode[1] .. ": enable, toggle and register", function()
        local f = gmFixture(mode[2], mode[3])
        equal(f.config.IsDev(), true)
        equal(f.config.CanOpenPanel(), false)
        equal(f.config.SetEnabled(true), true)
        equal(f.config.CanOpenPanel(), true)
        f.config.ToggleEnabled()
        equal(f.config.CanOpenPanel(), false)
        f.config.ToggleEnabled()
        equal(f.config.CanOpenPanel(), true)
        f.register(f.manager)
        equal(#f.registrations, 1)
        equal(f.registrations[1].name, "GM")
        equal(f.registrations[1].config.prefab, "UI/GM/GMPanel")
        equal(f.prefs.writes, 3)
        equal(f.prefs.saves, 3)
    end)
    test("GM " .. mode[1] .. ": taps retain debug unlock", function()
        local f = gmFixture(mode[2], mode[3], 0)
        for i = 1, f.uiConfig.TapUnlock.taps do
            f.unity.Time.realtimeSinceStartup = i * 0.1
            equal(f.unlock.OnVersionTapped(), i == f.uiConfig.TapUnlock.taps)
        end
        equal(f.config.CanOpenPanel(), true)
        equal(f.unlock.IsUnlocked(), true)
        equal(f.prefs.values.GM_Enabled, 1)
        equal(f.prefs.writes, 1)
        equal(f.prefs.saves, 1)
    end)
end
test("GM release: inaccessible build statics fail closed", function()
    local f = gmFixture(false, false, 1)
    local unavailable = setmetatable({}, { __index = function() error("Stripped static") end })
    f.unity.Debug, f.unity.Application = unavailable, unavailable
    f.config.SetEnabled(true)
    f.config._SetUnlockedByTaps(true)
    releaseClosed(f)
end)

local function gmUIFixture(debugBuild, editor, open, existingEventSystem)
    local f = gmFixture(debugBuild, editor, 1)
    local calls = { created = 0, components = 0, find = 0, input = 0,
        update = 0, updateInstance = 0, uiLookup = 0, ui = 0, opened = 0, closed = 0,
        objects = {}, persisted = {}, objectConstructors = 0, invalidTypes = 0, warnings = 0 }
    f.modules["Framework.UI.Utils.Logger"].Warn = function() calls.warnings = calls.warnings + 1 end
    local function create(_, name)
        calls.created = calls.created + 1
        local go = { name = name, components = {} }
        function go:AddComponent(componentType)
            calls.components = calls.components + 1
            -- Unity can log an error and return nil instead of throwing for a CS class argument.
            if not f.typeTokens[componentType] then calls.invalidTypes = calls.invalidTypes + 1; return nil end
            if componentType == calls.failComponent then return nil end
            self.components[#self.components + 1] = componentType
            return {}
        end
        calls.objects[#calls.objects + 1] = go
        return go
    end
    f.unity.GameObject = setmetatable({}, { __call = create })
    f.unity.Object = setmetatable({
        FindObjectOfType = function(componentType)
            calls.find = calls.find + 1
            calls.findType = componentType
            if not f.typeTokens[componentType] then calls.invalidTypes = calls.invalidTypes + 1; return nil end
            return existingEventSystem
        end,
        DontDestroyOnLoad = function(go) calls.persisted[#calls.persisted + 1] = go end,
        DestroyImmediate = function() end,
    }, { __call = function(_, ...)
        assert(select("#", ...) == 0, "invalid arguments to UnityEngine.Object constructor!")
        calls.objectConstructors = calls.objectConstructors + 1
        return {}
    end })
    f.unity.Input = {
        GetKey = function() calls.input = calls.input + 1; return false end,
        GetKeyDown = function() calls.input = calls.input + 1; return false end,
    }
    f.unity.KeyCode = { LeftControl = 1, RightControl = 2, LeftShift = 3, G = 4 }
    f.unity.UI = { Button = f.mockUnityClass("Button"), Text = f.mockUnityClass("Text") }
    f.unity.EventSystems = { EventSystem = f.mockUnityClass("EventSystem"),
        StandaloneInputModule = f.mockUnityClass("StandaloneInputModule") }
    local update = { AddUpdate = function(_, callback, target)
        calls.update = calls.update + 1
        calls.callback, calls.target = callback, target
    end }
    f.modules["Framework.Core.UpdateManager"] = { GetInstance = function()
        calls.updateInstance = calls.updateInstance + 1
        return update
    end }
    local ui = {
        IsOpen = function(_, name) calls.ui = calls.ui + 1; equal(name, "GM"); return open == true end,
        Open = function(_, name) calls.ui = calls.ui + 1; calls.opened = calls.opened + 1; equal(name, "GM"); open = true end,
        Close = function(_, name) calls.ui = calls.ui + 1; calls.closed = calls.closed + 1; equal(name, "GM"); open = false end,
        GetWindow = function() calls.ui = calls.ui + 1; return nil end,
    }
    f.modules["Game.GameMain"] = { GetUIManager = function()
        calls.uiLookup = calls.uiLookup + 1
        return ui
    end }
    f.gmUI, f.calls = f.require("Game.GM.GMUI"), calls
    return f
end
test("GMUI mock: class arguments return nil without throwing; Type tokens succeed", function()
    local existing = {}
    local f = gmUIFixture(true, false, false, existing)
    local es, input = f.unity.EventSystems.EventSystem, f.unity.EventSystems.StandaloneInputModule
    assert(f.typeof(es) ~= es and f.typeof(input) ~= input, "Class and Type must be distinct")
    assert(f.typeof(es) ~= f.typeof(input), "Each class must have its own Type token")
    equal(f.typeof(es), f.typeof(es), "typeof returns a stable token")
    local go = f.unity.GameObject("MockContract")
    local ok, result = pcall(function() return go:AddComponent(es) end)
    equal(ok, true, "class argument logs error without throwing")
    equal(result, nil)
    equal(#go.components, 0, "invalid class argument adds no component")
    ok, result = pcall(f.unity.Object.FindObjectOfType, es)
    equal(ok, true)
    equal(result, nil, "class argument cannot find existing EventSystem")
    equal(f.calls.invalidTypes, 2)
    assert(go:AddComponent(f.typeof(es)), "Type token must add component")
    equal(go.components[1], f.typeof(es))
    equal(f.unity.Object.FindObjectOfType(f.typeof(es)), existing)
end)
for _, component in ipairs({ "EventSystem", "StandaloneInputModule" }) do
    test("GMUI development: nil " .. component .. " component prevents persistence", function()
        local f = gmUIFixture(true, false)
        f.calls.failComponent = f.typeof(f.unity.EventSystems[component])
        f.gmUI.Init()
        equal(f.calls.created, 1)
        equal(f.calls.components, component == "EventSystem" and 1 or 2, "assert stops failed component setup")
        equal(#f.calls.persisted, 0, "incomplete EventSystem must not be persisted")
        equal(f.calls.warnings, 1, "component assertion reaches error handler")
        equal(f.calls.invalidTypes, 0, "failure uses correct Type token")
    end)
end
test("GMUI mock: Object only accepts no-argument construction", function()
    local f = gmUIFixture(true, false)
    equal(type(f.unity.Object()), "table")
    local ok, err = pcall(function() f.unity.Object("GMEventSystem") end)
    equal(ok, false, "named Object construction must throw")
    assert(tostring(err):find("invalid arguments to UnityEngine.Object constructor!", 1, true))
    equal(f.calls.objectConstructors, 1)
    equal(f.calls.created, 0, "Object never creates a GameObject")
end)
test("GMUI development: existing EventSystem prevents duplicate creation", function()
    local f = gmUIFixture(true, false, false, {})
    f.gmUI.Init()
    f.gmUI.Init()
    equal(f.calls.find, 1)
    equal(f.calls.findType, f.typeof(f.unity.EventSystems.EventSystem))
    equal(f.calls.invalidTypes, 0)
    equal(f.calls.created, 0)
    equal(f.calls.components, 0)
    equal(#f.calls.persisted, 0)
    equal(f.calls.objectConstructors, 0)
    equal(f.calls.update, 1, "hotkey initialization still proceeds")
end)
test("GMUI release: Init twice creates no objects or hotkey polling", function()
    local f = gmUIFixture(false, false)
    f.gmUI.Init()
    f.gmUI.Init()
    equal(f.calls.update, 0, "no hotkey callback registered")
    equal(f.calls.updateInstance, 0, "no UpdateManager lookup")
    equal(f.calls.find, 0, "no EventSystem lookup")
    equal(f.calls.created, 0, "no Unity object creation")
    equal(f.calls.objectConstructors, 0, "no Object constructor invocation")
    equal(#f.calls.persisted, 0, "no persistent Unity objects")
    equal(f.calls.components, 0, "no Unity component creation")
    equal(f.calls.input, 0, "no input polling")
    equal(f.calls.uiLookup, 0, "no UIManager lookup")
    releaseClosed(f)
end)
test("GMUI release: direct OpenPanel never calls UIManager", function()
    local f = gmUIFixture(false, false)
    f.gmUI.OpenPanel()
    equal(f.calls.uiLookup, 0)
    equal(f.calls.ui, 0)
    equal(f.calls.opened, 0)
end)
for _, initiallyOpen in ipairs({ false, true }) do
    test("GMUI release: direct TogglePanel never calls UIManager, open=" .. tostring(initiallyOpen), function()
        local f = gmUIFixture(false, false, initiallyOpen)
        f.gmUI.TogglePanel()
        -- Check window mutation first, then even queries: release must stop at the gate.
        equal(f.calls.opened, 0, "release TogglePanel cannot open a window")
        equal(f.calls.closed, 0, "release TogglePanel cannot close a window")
        equal(f.calls.ui, 0, "release TogglePanel cannot call UIManager methods")
        equal(f.calls.uiLookup, 0, "release TogglePanel cannot obtain UIManager")
    end)
end
for _, mode in ipairs({ { "development", true, false }, { "editor", false, true } }) do
    test("GMUI " .. mode[1] .. ": mock exercises Init and direct panel commands", function()
        local f = gmUIFixture(mode[2], mode[3])
        f.gmUI.Init()
        f.gmUI.Init()
        equal(f.calls.update, 1, "dev hotkey registered once")
        equal(f.calls.target, "GMHotkey")
        equal(type(f.calls.callback), "function")
        equal(f.calls.find, 1)
        equal(f.calls.findType, f.typeof(f.unity.EventSystems.EventSystem))
        equal(f.calls.invalidTypes, 0, "all Unity calls receive Type tokens")
        equal(f.calls.warnings, 0, "EventSystem setup succeeded")
        equal(f.calls.created, 1, "EventSystem created in memory")
        equal(f.calls.components, 2)
        equal(f.calls.objectConstructors, 0, "EventSystem must use GameObject constructor")
        local go = assert(f.calls.objects[1], "Missing EventSystem GameObject")
        equal(go.name, "GMEventSystem", "created GameObject name")
        equal(#go.components, 2, "exactly two EventSystem components")
        equal(go.components[1], f.typeof(f.unity.EventSystems.EventSystem))
        equal(go.components[2], f.typeof(f.unity.EventSystems.StandaloneInputModule))
        equal(#f.calls.persisted, 1, "EventSystem persisted exactly once")
        equal(f.calls.persisted[1], go, "persist the same created GameObject")
        f.gmUI.OpenPanel()
        equal(f.calls.opened, 1)
        f.gmUI.TogglePanel()
        equal(f.calls.closed, 1)
    end)
end

local passed, errors = 0, {}
for _, case in ipairs(tests) do
    local ok, err = xpcall(case[2], function(message)
        return debug and debug.traceback and debug.traceback(tostring(message), 2) or tostring(message)
    end)
    if ok then
        passed = passed + 1
        print("PASS " .. case[1])
    else
        errors[#errors + 1] = case[1] .. "\n" .. err
        print("FAIL " .. errors[#errors])
    end
end
local summary = string.format("release_safety: %d/%d passed, %d failed", passed, #tests, #errors)
print(summary)
-- Aggregate for a complete count, then rethrow every failure; never silently return success.
assert(#errors == 0, summary .. "\n" .. table.concat(errors, "\n\n"))
return { passed = passed, total = #tests, failed = #errors }
