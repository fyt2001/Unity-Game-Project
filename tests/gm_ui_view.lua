-- Real GM view, input/button/text/list wrappers, timer/update managers and log.
-- Unity objects, prefab pool, binding container and game data are inert doubles.
local project = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/gm_ui_view.lua <My project root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = project .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local function noop() end
typeof = function(value) return value end
IsNull = function(value) return value == nil or value.destroyed == true end
local function event()
    local e = { listeners = {}, adds = 0 }
    function e:AddListener(fn) self.listeners[fn] = true; self.adds = self.adds + 1 end
    function e:RemoveListener(fn) self.listeners[fn] = nil end
    function e:Fire(value) for fn in pairs(self.listeners) do fn(value) end end
    return e
end
local nextId = 0
local function go(name)
    nextId = nextId + 1
    local g = { name = name, id = nextId, active = true, comps = {} }
    local t = { gameObject = g, children = {}, sizeDelta = { x = 0, y = 68 },
        anchoredPosition = { x = 0, y = 0 }, rect = { height = 216 } }
    g.transform = t
    function g:GetInstanceID() return self.id end
    function g:SetActive(active) self.active = active end
    function t:Find(path)
        local node = self
        for part in path:gmatch("[^/]+") do node = node and node.children[part] end
        return node
    end
    function t:GetComponent(kind) return kind == "RectTransform" and self or g.comps[kind] end
    function g:GetComponent(kind) return self.comps[kind] end
    return g
end
local function attach(parent, node) parent.transform.children[node.name] = node.transform; return node end
local function textNode(name)
    local g = go(name)
    g.comps.TMP = { gameObject = g, text = "" }
    return g
end
local function inputNode(name)
    local g = go(name)
    local i = { gameObject = g, text = "", characterLimit = 3, onValueChanged = event(), writes = {} }
    function i:SetTextWithoutNotify(value)
        self.writes[#self.writes + 1] = { limit = self.characterLimit, value = value }
        self.text = self.characterLimit > 0 and value:sub(1, self.characterLimit) or value
    end
    function i:Enter(value) self:SetTextWithoutNotify(value); self.onValueChanged:Fire(self.text) end
    g.comps.Input = i
    return g
end
local function buttonNode(name)
    local g = go(name)
    local txt = attach(g, textNode("Label")).comps.TMP
    g.buttonText = txt
    g.comps.Button = { gameObject = g, image = { color = { original = true } }, onClick = event() }
    return g
end
local function row()
    local g = go("CmdItem")
    attach(g, textNode("m_CmdName")); attach(g, textNode("m_Desc"))
    local slot = attach(g, go("m_ParamSlot"))
    attach(slot, inputNode("m_Param_Ipt"))
    attach(g, buttonNode("mi_BtnExec")); attach(g, buttonNode("mi_BtnFav"))
    return g
end
local function category()
    local g = buttonNode("CategoryItem")
    attach(g, textNode("m_CatLabel"))
    g.transform.sizeDelta.y = 56
    return g
end
CS = { UnityEngine = { UI = { Text = "Text", InputField = "Input", Button = "Button" },
    Color = function(...) return { ... } end,
    Vector2 = function(x, y) return { x = x, y = y } end,
    Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    RectTransform = "RectTransform",
    Time = { unscaledDeltaTime = 0.5, deltaTime = 0, realtimeSinceStartup = 0 },
    Debug = { Log = noop } }, TMPro = { TextMeshProUGUI = "TMP" } }
package.loaded["Framework.UI.Utils.Logger"] = { Warn = noop, Info = noop }
package.loaded["Framework.UI.Utils.CJKFont"] = { ApplyAll = noop, Apply = noop }
package.loaded["Framework.UI.Utils.UIUtil"] = {
    FindText = function(t) return t.gameObject.buttonText or t.gameObject.comps.TMP end,
}
local BaseClass = require "Framework.UI.Utils.BaseClass"
local Component = BaseClass("TestComponent")
function Component:__init(holder, unity)
    if unity then self.__uiComp = unity; self.gameObject = unity.gameObject; self.transform = self.gameObject.transform end
    self.holder = holder
end
Component.OnCreate = noop
Component.OnDestroy = noop
function Component:SetActive(value) self.gameObject:SetActive(value) end
function Component:__delete() self:OnDestroy() end
package.loaded["Framework.UI.Base.UIBaseComponent"] = Component
local UIView = BaseClass("TestView", Component)
function UIView:OnCreate() self.components = {}; self.createdComponents = 0 end
function UIView:GetController() return self.controller end
function UIView:GetComponent(name, cls) return self.components[name] and self.components[name][cls] end
function UIView:AddComponent(cls, unity)
    local name = unity.gameObject.name
    self.components[name] = self.components[name] or {}
    assert(self.components[name][cls] == nil, "duplicate registration: " .. name)
    local c = cls.New(self, unity); c:OnCreate()
    self.components[name][cls] = c
    self.createdComponents = self.createdComponents + 1
    return c
end
UIView.OnOpen, UIView.OnClose, UIView.OnRefresh = noop, noop, noop
function UIView:OnDestroy()
    for _, record in pairs(self.components) do for _, c in pairs(record) do c:Delete() end end
end
package.loaded["Framework.UI.Core.UIView"] = UIView
package.loaded["Framework.UI.Utils.PrefabPool"] = {
    New = function(prefab)
        local pool = { spare = {}, all = {} }
        function pool:Get()
            local g = table.remove(self.spare)
            if not g then g = prefab.factory(); self.all[#self.all + 1] = g end
            g:SetActive(true)
            return g
        end
        function pool:Release(g) g:SetActive(false); self.spare[#self.spare + 1] = g end
        function pool:Clear() self.spare = {} end
        return pool
    end,
}
local commands, provider, copied, sample, dev = {}, nil, nil, nil, true
local statsCalls = 0
package.loaded["Game.GM.GMConfig"] = { IsDev = function() return dev end }
package.loaded["Game.GM.GMCommands"] = {
    VisibleList = function() return commands end,
    CopyLog = function(value) copied = value; return "copied" end,
}
package.loaded["Game.GM.GMRuntimeStats"] = {
    Sample = function() statsCalls = statsCalls + 1; if sample == "throw" then error("sample") end; return sample end,
    Stop = function() error("must not stop shared Stats") end,
}
package.loaded["Game.GameMain"] = { GetUIResourceProvider = function() return provider end }
local UIText = require "Framework.UI.Component.UIText"
local UIButton = require "Framework.UI.Component.UIButton"
local Input = require "Framework.UI.Component.UIInputField"
local UpdateManager = require "Framework.Core.UpdateManager"
local TimerManager = require "Framework.Core.TimerManager"
local GMLog = require "Game.GM.GMLog"
local View = require "Game.UI.GM.UIGMView"
local function prefab(factory) return { factory = factory, transform = factory().transform } end
local cmdPrefab, catPrefab = prefab(row), prefab(category)
local function successfulProvider()
    return { LoadAsync = function(_, path, cb) cb(path:find("CmdItem", 1, true) and cmdPrefab or catPrefab) end }
end
local function command(id, kind, default, group)
    return { id = id, label = "label " .. id, desc = "description " .. id, group = group or "A",
        input = kind and true or nil, inputDefault = default,
        params = kind and { { type = kind, min = kind == "int" and 1 or nil,
            max = kind == "int" and 99999999 or (kind == "string" and 2000 or nil) } } or nil }
end
local function fixture()
    local v = View.New()
    local root = go("GMPanel"); v.transform, v.gameObject = root.transform, root
    root.transform.parent = go("PopupCanvas").transform
    root.transform.parent.rect = { width = 1280, height = 720 }
    local body = attach(root, go("m_Body"))
    local cmdRoot = attach(body, go("m_CmdList"))
    attach(cmdRoot, textNode("m_Empty"))
    v.empty = cmdRoot.transform.children.m_Empty
    for _, field in ipairs({ "m_Title_Txt", "m_EnvTag_Txt", "m_Summary_Txt_Txt", "m_HitCount_Txt", "m_LogTip_Txt",
        "m_ValScene_Txt", "m_ValDungeon_Txt", "m_ValEnemy_Txt", "m_ValBullet_Txt", "m_ValTime_Txt", "m_ValFps_Txt", "m_ValGc_Txt" }) do
        v[field] = UIText.New(nil, textNode(field).comps.TMP); v[field]:OnCreate()
    end
    for _, field in ipairs({ "mi_BtnMaster_Btn", "mi_BtnFold_Btn", "mi_BtnClose_Btn", "mi_BtnClearSearch_Btn",
        "mi_BtnLogClear_Btn", "mi_BtnLogCopy_Btn", "mi_BtnLogFold_Btn" }) do
        v[field] = UIButton.New(nil, buttonNode(field).comps.Button); v[field]:OnCreate()
    end
    v.m_Search_Ipt_Ipt = Input.New(nil, inputNode("Search").comps.Input); v.m_Search_Ipt_Ipt:OnCreate()
    v.m_Search_Ipt_Ipt:SetCharacterLimit(2000)
    for _, field in ipairs({ "m_CategoryList_Srt", "m_CmdList_Srt" }) do
        local g = go(field)
        local sr = { gameObject = g, content = go("Content").transform, viewport = go("Viewport").transform,
            onValueChanged = event() }
        v[field] = { GetScrollRect = function() return sr end }
    end
    v.controller = { opened = 0, cancelled = 0, closed = 0, executions = {} }
    function v.controller:OnViewOpened() self.opened = self.opened + 1; v:SetExecNormal() end
    function v.controller:OnGroupChanged() self.cancelled = self.cancelled + 1; v:SetExecNormal() end
    function v.controller:OnCloseClicked() self.closed = self.closed + 1 end
    function v.controller:Execute(cmd, value) self.executions[#self.executions + 1] = { cmd = cmd, value = value } end
    v:OnCreate(); v:OnOpen()
    return v
end
local function cell(v, index)
    local g = assert(v._cmdList:GetItem(index or 0))
    return assert(v._cmdCompCache[g:GetInstanceID()]), g
end
local passed, failed = 0, 0
local views = {}
local function test(name, fn)
    commands = { command("gold", "int", "1000"), command("code", "string", "", "B"), command("wid", "enum", "random", "B") }
    provider, dev, copied = successfulProvider(), true, nil
    sample = { scene = "Home", dungeon = "Idle", enemies = 0, bullets = 2, battleTime = "1/60", fps = 60, luaGC = "512 KB" }
    GMLog.Clear(); statsCalls = 0; views = {}
    local ok, err = pcall(fn)
    for _, v in ipairs(views) do if not v._destroyed then v:OnDestroy() end end
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function newView() local v = fixture(); views[#views + 1] = v; return v end

test("search changes refresh immediately and cancel confirmation", function()
    local v = newView(); v.m_Search_Ipt_Ipt.unity_uiinput:Enter("code")
    assert(#v._shownCmds == 1 and v._shownCmds[1].id == "code" and v.controller.cancelled == 1)
end)
for _, field in ipairs({ "label", "id", "group", "desc" }) do
    test("literal search in " .. field, function()
        commands[1][field] = "unique.[%]"; local v = newView()
        v.m_Search_Ipt_Ipt.unity_uiinput:Enter(".[%]")
        assert(#v._shownCmds == 1 and v._shownCmds[1] == commands[1])
    end)
end
test("clear search restores rows and cancels pending", function()
    local v = newView(); v.m_Search_Ipt_Ipt.unity_uiinput:Enter("missing")
    v.mi_BtnClearSearch_Btn:GetUnityButton().onClick:Fire()
    assert(#v._shownCmds == 3 and v.controller.cancelled == 2)
end)
test("category root selects dynamically after reuse", function()
    local v = newView(); local g = v._catList:GetItem(1)
    v:_refreshCatItem(g, 2); g.comps.Button.onClick:Fire()
    assert(v._curGroup == "B" and #v._shownCmds == 2)
    assert(g.comps.Button.onClick.adds == 1)
end)
test("category colors refresh selection and restore original", function()
    local v = newView(); local all = v._catCompCache[v._catList:GetItem(0):GetInstanceID()]
    assert(all.btn:GetUnityButton().image.color ~= all.color0)
    v:SelectGroup("B")
    assert(all.btn:GetUnityButton().image.color == all.color0)
end)
test("draft survives filter, group and refresh", function()
    local v = newView(); local c = cell(v)
    c.ipt.unity_uiinput:Enter("98765432")
    v:SelectGroup("B"); v:SelectGroup("全部"); v._cmdList:RefreshAll()
    assert(cell(v).ipt:GetText() == "98765432")
end)
test("empty code draft stays empty rather than default", function()
    commands[2].inputDefault = "return 42"; local v = newView(); local c = cell(v, 1)
    c.ipt.unity_uiinput:Enter(""); v:SelectGroup("A"); v:SelectGroup("B")
    assert(cell(v).ipt:GetText() == "")
end)
test("numeric limits precede long default and are not numeric max", function()
    commands[1].inputDefault = "99999999"; local v = newView(); local c = cell(v)
    assert(c.ipt:GetText() == "99999999" and c.ipt:GetCharacterLimit() == 64)
    assert(c.ipt.unity_uiinput.writes[1].limit == 64)
end)
test("string limit resets to enum limit on same GO", function()
    local v = newView(); local c, g = cell(v, 1)
    commands[2].params[1].max = 4; v:_refreshCmdItem(g, 1)
    assert(c.ipt:GetCharacterLimit() == 4)
    v:_refreshCmdItem(g, 2); assert(c.ipt:GetCharacterLimit() == 2000)
end)
test("enum original text reaches execution", function()
    local v = newView(); local c, g = cell(v, 2)
    c.ipt.unity_uiinput:Enter("weapon_blade"); v:_execById(g:GetInstanceID())
    assert(v.controller.executions[1].value == "weapon_blade")
end)
test("raw text without schema reaches execution", function()
    commands[1].params = nil; local v = newView(); local c, g = cell(v)
    c.ipt.unity_uiinput:Enter("raw text"); v:_execById(g:GetInstanceID())
    assert(v.controller.executions[1].value == "raw text")
end)
for _, value in ipairs({ "", "nope", "1.5", "1e999", "0", "100000000" }) do
    test("invalid integer is blocked: " .. value, function()
        local v = newView(); local c, g = cell(v)
        c.ipt.unity_uiinput:Enter(value); v:_execById(g:GetInstanceID())
        assert(#v.controller.executions == 0 and #GMLog.GetAll() == 1 and v.controller.cancelled == 1)
    end)
end
test("valid numeric input executes as number", function()
    local v = newView(); local c, g = cell(v); c.ipt.unity_uiinput:Enter("99999999")
    v:_execById(g:GetInstanceID()); assert(v.controller.executions[1].value == 99999999)
end)
test("missing input does not execute numeric default", function()
    local v = newView(); local c, g = cell(v); c.ipt = nil
    v:_execById(g:GetInstanceID()); assert(#v.controller.executions == 0)
end)
test("ordinary reused row restores danger color and label", function()
    commands[1].danger = true; local v = newView(); local c, g = cell(v)
    local color = c.exec:GetUnityButton().image.color
    v:SetExecPending("gold"); assert(c.exec:GetText() == "确认执行？")
    v:_refreshCmdItem(g, 2)
    assert(c.exec:GetText() == "执行" and c.exec:GetUnityButton().image.color == color)
end)
test("200 scroll cycles preserve drafts and single listeners", function()
    commands = {}; for i = 1, 11 do commands[i] = command("c" .. i, "int", "10") end
    local v = newView(); cell(v).ipt.unity_uiinput:Enter("12345")
    for i = 1, 200 do
        v._cmdList.content.anchoredPosition.y = i % 2 == 0 and 0 or 572
        v._cmdList.scrollRect.onValueChanged:Fire()
    end
    assert(cell(v).ipt:GetText() == "12345")
    for _, c in pairs(v._cmdCompCache) do
        assert(c.exec:GetUnityButton().onClick.adds == 1 and c.ipt.unity_uiinput.onValueChanged.adds == 1)
    end
    local c = cell(v); c.exec:GetUnityButton().onClick:Fire()
    assert(#v.controller.executions == 1)
end)
test("eleventh row exists and its bottom meets viewport bottom", function()
    commands = {}; for i = 1, 11 do commands[i] = command("c" .. i) end
    local v = newView(); local l = v._cmdList
    assert(l.content.sizeDelta.y == 788)
    l.content.anchoredPosition.y = 572; l.scrollRect.onValueChanged:Fire()
    local last = assert(l:GetItem(10))
    assert(last.transform.anchoredPosition.y + 572 - 34 == -216)
    l.viewport.rect.height = 144; l.content.anchoredPosition.y = 644
    l.scrollRect.onValueChanged:Fire(); assert(l:GetItem(10))
end)
test("scrolling does not execute recycled inactive callback", function()
    commands = {}; for i = 1, 11 do commands[i] = command("c" .. i) end
    local v = newView(); local _, g = cell(v)
    v._cmdList.content.anchoredPosition.y = 572; v._cmdList:Refill()
    v._idxOfGO[g:GetInstanceID()] = 0
    v:_execById(g:GetInstanceID()); assert(#v.controller.executions == 0)
end)
test("status writes one actual log; refresh and open add none", function()
    local v = newView(); assert(#GMLog.GetAll() == 0)
    v:SetStatus("actual result"); v:RefreshLog(); v:OnOpen()
    assert(#GMLog.GetAll() == 1 and v.m_LogTip_Txt:GetText():find("actual result", 1, true))
end)
test("log caps at newest 200 and copy reads source", function()
    local v = newView(); for i = 1, 205 do GMLog.Append("info", "", "", "line" .. i) end
    v:RefreshLog(); local lines = GMLog.GetTextLines(200)
    assert(#lines == 200 and lines[1] == "line6" and lines[200] == "line205")
    v.m_LogTip_Txt:SetText("stale"); v:OnLogCopyClicked()
    assert(copied == table.concat(lines, "\n"))
end)
test("clear empties real buffer and display", function()
    local v = newView(); v:SetStatus("x"); v:OnLogClearClicked()
    assert(#GMLog.GetAll() == 0 and v.m_LogTip_Txt:GetText() == "暂无执行记录")
end)
test("loading and empty states display on actual node", function()
    provider = { LoadAsync = noop }; local v = newView()
    assert(v.empty.gameObject.active and v.empty:GetComponent("TMP").text == "正在加载命令…")
    assert(v.m_HitCount_Txt:GetText() == "加载中")
    v._listState = "ready"; v.m_Search_Ipt_Ipt.unity_uiinput:Enter("missing")
    assert(v.empty:GetComponent("TMP").text == "没有匹配的命令")
end)
test("nil assets fail then retry recovers", function()
    provider = { LoadAsync = function(_, _, cb) cb(nil) end }; local v = newView()
    assert(v._listState == "error" and v.mi_BtnMaster_Btn.gameObject.active)
    provider = successfulProvider(); v.mi_BtnMaster_Btn:GetUnityButton().onClick:Fire()
    assert(v._listState == "ready" and not v.mi_BtnMaster_Btn.gameObject.active and v._cmdList:GetItem(0))
end)
test("missing provider shows recoverable error", function()
    provider = nil; local v = newView(); assert(v._listState == "error")
    provider = successfulProvider(); v.mi_BtnMaster_Btn:GetUnityButton().onClick:Fire()
    assert(v._listState == "ready")
end)
test("duplicate async callbacks do not reapply or finish early", function()
    local callbacks = {}; provider = { LoadAsync = function(_, _, cb) callbacks[#callbacks + 1] = cb end }
    local v = newView(); callbacks[1](cmdPrefab); callbacks[1](cmdPrefab)
    assert(v._loading and not v._cmdPrefab)
    callbacks[2](catPrefab); local n = v.createdComponents; callbacks[2](catPrefab)
    assert(v.createdComponents == n and v._listState == "ready")
end)
test("destroy rejects late async callback and cleans detached listeners", function()
    local callbacks = {}; provider = { LoadAsync = function(_, _, cb) callbacks[#callbacks + 1] = cb end }
    local v = newView(); v:OnDestroy(); callbacks[1](cmdPrefab); callbacks[2](catPrefab)
    assert(v._cmdPrefab == nil and v._catPrefab == nil)
    provider = successfulProvider(); local other = newView(); local events = {}
    for _, c in pairs(other._cmdCompCache) do events[#events + 1] = c.exec:GetUnityButton().onClick end
    other:OnDestroy(); for _, e in ipairs(events) do assert(next(e.listeners) == nil) end
end)
test("seven runtime fields contain sampled values", function()
    local v = newView(); assert(v.m_ValScene_Txt:GetText() == "Home" and v.m_ValDungeon_Txt:GetText() == "Idle")
    assert(v.m_ValEnemy_Txt:GetText() == "0" and v.m_ValBullet_Txt:GetText() == "2")
    assert(v.m_ValTime_Txt:GetText() == "1/60" and v.m_ValFps_Txt:GetText() == "60" and v.m_ValGc_Txt:GetText() == "512 KB")
end)
test("unscaled timer updates while scaled dt is zero and is idempotent", function()
    local shared = TimerManager:GetInstance(); shared:SetScale(0)
    local v = newView(); local id = v._runtimeUpdateId; v:_ensureRuntimeTimer()
    assert(v._runtimeUpdateId == id)
    sample.scene = "Battle"; UpdateManager:GetInstance():OnUpdate(0)
    assert(v.m_ValScene_Txt:GetText() == "Battle" and shared._scale == 0)
    shared:SetScale(1)
end)
test("close removes own timer and reopen creates one", function()
    local v = newView(); v:OnClose(); local n = statsCalls
    UpdateManager:GetInstance():OnUpdate(0); assert(statsCalls == n and not v._runtimeTimerId)
    v:OnOpen(); assert(v._runtimeTimerId and statsCalls == n + 1)
    v:OnDestroy(); n = statsCalls; UpdateManager:GetInstance():OnUpdate(0); assert(statsCalls == n)
end)
test("bad runtime samples are unavailable, never made-up zeros", function()
    sample = {}; local v = newView(); assert(v.m_ValEnemy_Txt:GetText() == "采样不可用")
    sample = "throw"; v:_refreshRuntime(); assert(v.m_ValScene_Txt:GetText() == "采样不可用")
end)
test("environment comes from IsDev and placeholders stay hidden", function()
    dev = false; local v = newView(); assert(v.m_EnvTag_Txt:GetText() == "发布环境")
    assert(not v.mi_BtnMaster_Btn.gameObject.active and not v.mi_BtnFold_Btn.gameObject.active and not v.mi_BtnLogFold_Btn.gameObject.active)
    local _, g = cell(v); assert(not g.transform.children.mi_BtnFav.gameObject.active)
end)
test("close button delegates contract and closed view refuses execution", function()
    local v = newView(); local _, g = cell(v)
    v.mi_BtnClose_Btn:GetUnityButton().onClick:Fire(); assert(v.controller.closed == 1)
    v:OnClose(); v:_execById(g:GetInstanceID()); assert(#v.controller.executions == 0)
end)

test("GM layout matches parent percentages across screen shapes", function()
    local v = newView(); local root = v.transform
    for _, size in ipairs({ {1280, 720}, {2560, 1080}, {1080, 2400}, {1920, 1080} }) do
        root.parent.rect = { width = size[1], height = size[2] }; v:_adaptLayout()
        local scale = math.min(size[1] / 1280, size[2] / 720)
        assert(root.localScale.x == scale and root.localScale.y == scale and root.localScale.z == scale)
        assert(math.abs(root.sizeDelta.x * scale - size[1] * 0.88) < 0.000001)
        assert(math.abs(root.sizeDelta.y - math.min(size[2] * 0.90 / scale, 900)) < 0.000001)
        assert(root.anchorMin.x == 0.5 and root.anchorMax.y == 0.5 and root.pivot.y == 0.5)
        assert(root.anchoredPosition.x == 0 and root.anchoredPosition.y == 0)
    end
end)
test("half-second layout check only writes changed dimensions", function()
    local v = newView(); local root = v.transform; local original = root.sizeDelta
    UpdateManager:GetInstance():OnUpdate(0); assert(root.sizeDelta == original)
    root.parent.rect.width = 1600; UpdateManager:GetInstance():OnUpdate(0)
    assert(root.sizeDelta ~= original and v._layoutParentW == 1600)
    original = root.sizeDelta; UpdateManager:GetInstance():OnUpdate(0)
    assert(root.sizeDelta == original)
end)
test("reopening reapplies scale after an external reset", function()
    local v = newView(); local root = v.transform
    root.parent.rect = { width = 2560, height = 1440 }; v:_adaptLayout()
    v:OnClose(); root.localScale = { x = 1, y = 1, z = 1 }; v:OnOpen()
    assert(root.localScale.x == 2)
end)
test("zero-size parent delays adaptation until a valid canvas", function()
    local v = newView(); local root = v.transform; local original = root.sizeDelta
    root.parent.rect = { width = 0, height = 0 }; v:_adaptLayout(); assert(root.sizeDelta == original)
    root.parent.rect = { width = 640, height = 360 }; v:_adaptLayout(); assert(root.localScale.x == 0.5)
end)

test("portrait height is capped and landscape keeps 648 design pixels", function()
    local v = newView(); local root = v.transform
    assert(root.sizeDelta.y == 648)
    root.parent.rect = { width = 1080, height = 2400 }; v:_adaptLayout()
    assert(root.sizeDelta.y == 900)
end)
test("resize refreshes both lists without rebinding or losing draft", function()
    local v = newView(); local c = cell(v); c.ipt.unity_uiinput:Enter("54321")
    local counts = { cmd = 0, cat = 0 }
    local cmdRefresh, catRefresh = v._cmdList.onRefresh, v._catList.onRefresh
    v._cmdList.onRefresh = function(...) counts.cmd = counts.cmd + 1; cmdRefresh(...) end
    v._catList.onRefresh = function(...) counts.cat = counts.cat + 1; catRefresh(...) end
    local created = v.createdComponents
    v.transform.parent.rect = { width = 1080, height = 2400 }; v:_adaptLayout()
    assert(counts.cmd > 0 and counts.cat > 0 and v.createdComponents == created)
    assert(c.ipt:GetText() == "54321" and c.exec:GetUnityButton().onClick.adds == 1)
    assert(c.ipt.unity_uiinput.onValueChanged.adds == 1)
end)
test("stale recycled row cannot overwrite a newer command draft", function()
    local v = newView(); local old = row(); v:_refreshCmdItem(old, 0)
    local oldC = v._cmdCompCache[old:GetInstanceID()]
    oldC.ipt.unity_uiinput:Enter("111")
    local current = cell(v); current.ipt.unity_uiinput:Enter("222")
    v:_refreshCmdItem(old, 1); v:_refreshLists()
    assert(cell(v).ipt:GetText() == "222")
end)

test("category uses teal selection and white versus gray text", function()
    local v = newView(); local all = v._catCompCache[v._catList:GetItem(0):GetInstanceID()]
    local color = all.btn:GetUnityButton().image.color
    assert(color[1] == 0.086 and color[2] == 0.486 and color[3] == 0.439)
    assert(all.txt:GetUnityText().color[1] == 1)
    v:SelectGroup("B"); assert(all.txt:GetUnityText().color[1] == 0.78)
end)
test("no-input row hides entire bordered slot and reuse restores it", function()
    commands[2].input = nil; local v = newView(); local _, g = cell(v, 1)
    local slot = g.transform.children.m_ParamSlot.gameObject
    assert(not slot.active)
    v:_refreshCmdItem(g, 2)
    assert(slot.active and slot.transform.children.m_Param_Ipt.gameObject.active)
end)
test("empty log placeholder is never copied", function()
    local v = newView(); assert(v.m_LogTip_Txt:GetText() == "暂无执行记录")
    v:OnLogCopyClicked(); assert(copied == "")
end)

test("last selected category remains fully visible", function()
    commands = {}; for i = 1, 7 do commands[i] = command("c" .. i, nil, nil, "G" .. i) end
    local v = newView(); v:SelectGroup("G7")
    local list = v._catList; local y = list.content.anchoredPosition.y
    assert(y >= 0 and 7 * 60 >= y and 7 * 60 + 56 <= y + list.viewport.rect.height)
    assert(v._catCompCache[list:GetItem(7):GetInstanceID()].group == "G7")
end)

test("search preserves selected category scroll", function()
    commands = {}; for i = 1, 7 do commands[i] = command("c" .. i, nil, nil, "G" .. i) end
    local v = newView(); v:SelectGroup("G7")
    local y = v._catList.content.anchoredPosition.y
    v.m_Search_Ipt_Ipt:SetText("c7", false)
    assert(v._catList.content.anchoredPosition.y == y and #v._shownCmds == 1)
end)

test("category visibility adapts to smaller viewport and removed group", function()
    commands = {}; for i = 1, 7 do commands[i] = command("c" .. i, nil, nil, "G" .. i) end
    local v = newView(); v:SelectGroup("G7")
    local list = v._catList; list.viewport.rect.height = 120
    v.transform.parent.rect = { width = 1920, height = 1080 }; v:_adaptLayout()
    assert(7 * 60 + 56 <= list.content.anchoredPosition.y + 120)
    commands[7] = nil; v:_refreshLists()
    assert(v._curGroup == "全部" and list.content.anchoredPosition.y == 0)
end)

print(string.format("GM UI view: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
