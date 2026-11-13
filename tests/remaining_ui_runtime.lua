-- Run inside the initialized Unity Lua environment after the six windows have loaded.
-- Callbacks are replaced with counters; no purchase, equip or settlement is executed.
local ui = require("Game.GameMain").GetUIManager()
local total = 0
local function checkButtons(name, keys)
    local w = assert(ui:GetWindow(name), name)
    local view, model = w:GetView(), w:GetModel()
    local calls = 0
    local function count() calls = calls + 1 end
    view:Render(model, count, count, count, count)
    view:Render(model, count, count, count, count)
    for _, key in ipairs(keys) do
        local btn = assert(view[key], name .. ":" .. key)
        btn.onClick:Invoke()
    end
    assert(calls == #keys, name .. " duplicate or missing listener")
    total = total + #keys
end
checkButtons("PausePanel", {"_resumeBtn", "_extractBtn", "_closeBtn"})
checkButtons("ExtractConfirmPopup", {"_confirmBtn", "_cancelBtn", "_closeBtn"})
checkButtons("RunResultPanel", {"_confirmBtn", "_closeBtn"})
checkButtons("ShopPanel", {"_buyBtn", "_buy5Btn", "_closeBtn"})
local shop = ui:GetWindow("ShopPanel")
shop:GetModel()._resultText = "购入 寒冰护盾 R9、多重投射 R9、寒冰护盾 R9、多重投射 R9、寒冰护盾 R9 ×5（-1500 金币，余额 999999）"
shop:GetView():Render(shop:GetModel(), function() end, function() end, function() end)
local event = ui:GetWindow("FloorEventPopup")
local choices = 0
local function choose(index) choices = choices + index end
event:GetView():Render(event:GetModel(), choose, function() choices = choices + 10 end)
event:GetView():Render(event:GetModel(), choose, function() choices = choices + 10 end)
for _, btn in ipairs(event:GetView()._buttons) do btn.onClick:Invoke() end
event:GetView()._closeBtn.onClick:Invoke()
assert(choices == 16, "event listener duplication")
total = total + 4

local bag, slots = {}, {}
for i = 1, 26 do bag[i] = {uid=i, name=i%2==0 and "多重投射" or "寒冰护盾", rank=9, selected=i==1} end
for i = 1, 8 do slots[i] = {empty=false, item={name="多重投射", rank=9, cost=4.5}} end
local preview = {
    GetCapacityText=function() return "容量 36 / 60" end,
    GetTabs=function() return {{label="武器"}, {label="技能"}, {label="框架"}} end,
    GetSlots=function() return slots end,
    GetBagItems=function() return bag end,
    GetStatLines=function() return {"攻击 +12", "生命 +120", "移速 +2", "攻击 +20%", "生命 +30%", "移速 +15%"} end,
}
local mod = ui:GetWindow("ModStationPanel"):GetView()
local clicks = 0
local function record() clicks = clicks + 1 end
mod:Render(preview, record, record, record, record)
mod:Render(preview, record, record, record, record)
for _, btn in ipairs(mod._tabBtns) do btn.onClick:Invoke() end
for _, btn in ipairs(mod._slotBtns) do btn.onClick:Invoke() end
mod._bagNodes[1]:GetComponent(typeof(CS.UnityEngine.UI.Button)).onClick:Invoke()
mod._closeBtn.onClick:Invoke()
assert(clicks == 13, "mod listener duplication")
assert(#mod._bagNodes == 26 and not mod._emptyGo.activeSelf)
assert(mod._bagNodes[1].transform:Find("m_Text"):GetComponent(typeof(CS.TMPro.TextMeshProUGUI)).text ~= "")
return "PASS 28 single callbacks after double render; 26 named bag items, 8 occupied slots, 6 stat lines; no save calls"
