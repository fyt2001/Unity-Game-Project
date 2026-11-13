-- Run only in the actual Editor Home/GM window. No real business command executes.
local gm = require "Game.GameMain"
local window = assert(gm.GetUIManager():GetWindow("GM"))
local v, ctrl = window:GetView(), window:GetController()
local results = {}
local function check(condition, label)
    assert(condition, label)
    results[#results + 1] = label
end
local function clearSearch() v.m_Search_Ipt_Ipt:SetText("", false) end
local function category(group)
    for i = 0, #v._groups do
        local name = i == 0 and "全部" or v._groups[i]
        if name == group then
            local go = assert(v._catList:GetItem(i), "category not visible")
            go:GetComponent(typeof(CS.UnityEngine.UI.Button)).onClick:Invoke()
            check(v._curGroup == group, "real category click: " .. group)
            return
        end
    end
    error("missing category " .. group)
end
local function row(commandId)
    for i, command in ipairs(v._shownCmds) do
        if command.id == commandId then
            local go = assert(v._cmdList:GetItem(i - 1), "row not visible")
            return assert(v._cmdCompCache[go:GetInstanceID()]), go
        end
    end
    error("missing command " .. commandId)
end
check(gm.GetCurrentScene() == "Home", "Home scene")
check(gm.GetUIManager():IsOpen("GM") and v:BindFieldNilCount() == 0, "GM opened with zero missing bindings")
category("货币")
v.m_Search_Ipt_Ipt:SetText("currency", false)
check(#v._shownCmds == 2, "live search by ID")
local gold = row("currency.add_gold")
gold.ipt:SetText("12345", false)
clearSearch()
category("角色")
category("货币")
gold = row("currency.add_gold")
check(gold.ipt:GetText() == "12345", "draft retained across real category clicks")
local value = v:_readParamValue(v._idxOfGO[gold.ipt.gameObject.transform.parent.parent.gameObject:GetInstanceID()])
check(value == 12345, "real InputField numeric readback")
v.m_Search_Ipt_Ipt:SetText("__no_such_command__", false)
check(#v._shownCmds == 0 and v.transform:Find("m_Body/m_CmdList/m_Empty").gameObject.activeSelf, "visible empty search state")
clearSearch()
category("全部")
local list = v._cmdList
local maxY = math.max(0, list.content.rect.height - list.viewport.rect.height)
for i = 1, 200 do
    list.content.anchoredPosition = CS.UnityEngine.Vector2(0, i % 2 == 0 and maxY or 0)
    list.scrollRect.onValueChanged:Invoke(CS.UnityEngine.Vector2(0, i % 2))
end
check(list:GetItem(#v._shownCmds - 1) ~= nil, "eleventh row available after 200 real scroll notifications")
list.content.anchoredPosition = CS.UnityEngine.Vector2(0, 0)
list:Refill()
category("角色")
local command
for _, cmd in ipairs(v._shownCmds) do if cmd.id == "role.level_up" then command = cmd end end
local originalFn, originalAvailable = command.fn, command.available
local executions, executedValue = 0, nil
command.fn = function(n) executions = executions + 1; executedValue = n; return "隔离点击测试" end
command.available = function() return true end
local ok, err = xpcall(function()
    local c = row("role.level_up")
    c.ipt:SetText("10", false)
    c.exec:GetUnityButton().onClick:Invoke()
    check(executions == 0 and ctrl._pending ~= nil, "danger first click only confirms")
    c.ipt:SetText("20", false)
    c.exec:GetUnityButton().onClick:Invoke()
    check(executions == 0 and ctrl._pending.value == 20, "changed parameter requires fresh confirmation")
    c.exec:GetUnityButton().onClick:Invoke()
    check(executions == 1 and executedValue == 20, "single button listener executes isolated command once")
    c.ipt:SetText("bad", false)
    c.exec:GetUnityButton().onClick:Invoke()
    check(executions == 1 and ctrl._pending == nil, "invalid integer blocked before command")
end, debug.traceback)
command.fn, command.available = originalFn, originalAvailable
ctrl:OnGroupChanged()
if not ok then error(err) end
check(v.m_ValScene_Txt:GetText() == "Home", "real runtime scene text")
v:SetStatus("GM 界面交互验证完成")
check(v.m_LogTip_Txt:GetText():find("GM 界面交互验证完成", 1, true), "execution feedback reaches real log body")
v.mi_BtnLogClear_Btn:GetUnityButton().onClick:Invoke()
check(#require("Game.GM.GMLog").GetAll() == 0, "clear button clears actual log buffer")
clearSearch()
category("全部")
category("※高级")
local catList = v._catList
local selectedIndex = #v._groups
local selectedTop = selectedIndex * 60
check(selectedTop >= catList.content.anchoredPosition.y - 0.1
    and selectedTop + 56 <= catList.content.anchoredPosition.y + catList.viewport.rect.height + 0.1,
    "selected final category is fully visible")
category("全部")
return table.concat(results, "\n"), #results
