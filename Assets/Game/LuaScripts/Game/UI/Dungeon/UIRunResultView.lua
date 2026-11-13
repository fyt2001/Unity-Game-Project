--[[
=============================================================================
UIRunResultView.lua - 结算面板 View
=============================================================================
Module:     Game/UI/Dungeon/UIRunResultView

Description:
	展示一局下潜的结算明细：层数 / 击杀 / 用时 / 渊获金币 / 战利品 / 记忆碎片，
	阵亡时额外显示「渊获已全部遗失」。

	只负责「文案 -> 控件」：所有文案由 UIRunResultModel 提供，View 不做规则计算。

	【为什么不用 AutoBind】
	  本 prefab 由 MCP 运行时创建（以 FloorEventPopup.prefab 为骨架复制），
	  没有在 UIComponentBinder 上登记绑定项，因此不能用 self.m_Xxx 注入字段，
	  改为 FindGameObject + GetComponent。

	【TMP 字体】
	  prefab 上 TextMeshProUGUI 已预置 LiberationSans SDF（随骨架继承），
	  这里再做一次运行时补字体作为双保险，并用 pcall 包住：
	  xLua 对 TMP 的 fontAsset 赋值可能抛 "no such field"，
	  不能让它连累整个面板打开。

	【类系统】View 必须是 BaseClass（UIView 用 __init(holder, var_arg) 构造），
	与 UIFloorEventView / UIHomeView 一致。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UIRunResultView = BaseClass("UIRunResultView", UIView)
local base = UIView

-- 中文 SDF 字体统一入口（见 Framework/UI/Utils/CJKFont.lua）
local CJKFont = require "Framework.UI.Utils.CJKFont"

local function getTmp(go)
	if not go then return nil end
	local ok, c = pcall(function()
		return go:GetComponent(typeof(CS.TMPro.TextMeshProUGUI))
	end)
	return ok and c or nil
end

local function getButton(go)
	if not go then return nil end
	local ok, c = pcall(function()
		return go:GetComponent(typeof(CS.UnityEngine.UI.Button))
	end)
	return ok and c or nil
end

function UIRunResultView:OnCreate()
	base.OnCreate(self)
	CJKFont.ApplyAll(self.gameObject.transform)

	self._title    = getTmp(self:FindGameObject("m_Title"))
	self._subtitle = getTmp(self:FindGameObject("m_Subtitle"))

	self._floorText = getTmp(self:FindGameObject("m_FloorText"))
	self._killText  = getTmp(self:FindGameObject("m_KillText"))
	self._timeText  = getTmp(self:FindGameObject("m_TimeText"))
	self._goldText  = getTmp(self:FindGameObject("m_GoldText"))
	self._itemText  = getTmp(self:FindGameObject("m_ItemText"))
	self._fragText  = getTmp(self:FindGameObject("m_FragText"))

	self._lootLostGo  = self:FindGameObject("m_LootLostText")
	self._lootLostTmp = getTmp(self._lootLostGo)

	self._confirmBtn = getButton(self:FindGameObject("m_ConfirmBtn"))
	-- 右上角关闭按钮（P2-美术接入 2026-10-01）：prefab 有则有，没有也不影响打开
	self._closeBtn = getButton(self:FindGameObject("m_CloseBtn"))

	self:_ensureFont()
end

---补 TMP 字体（双保险；失败不影响面板打开）
function UIRunResultView:_ensureFont()
	local targets = {
		self._title, self._subtitle,
		self._floorText, self._killText, self._timeText,
		self._goldText, self._itemText, self._fragText,
		self._lootLostTmp,
	}
	for i = 1, #targets do
		CJKFont.Apply(targets[i])
	end

	local child = self._confirmBtn and self._confirmBtn.gameObject.transform:Find("m_Text")
	CJKFont.Apply(child and getTmp(child.gameObject))
end

---渲染结算内容
---@param model table UIRunResultModel
---@param onConfirm function 点击「返回主城」的回调
function UIRunResultView:Render(model, onConfirm)
	if not model then return end

	local r = model.result or {}

	if self._title then self._title.text = model:GetTitle() end
	if self._subtitle then self._subtitle.text = model:GetSubtitle() end

	if self._floorText then
		self._floorText.text = string.format("层数        %d", r.floor or 0)
	end
	if self._killText then
		self._killText.text = string.format("击杀        %d", r.killCount or 0)
	end
	if self._timeText then
		self._timeText.text = "用时        " .. model:GetElapsedText()
	end
	if self._goldText then
		self._goldText.text = r.gold == nil and "金币        待确认" or string.format("渊获金币    %d", r.gold)
	end
	if self._itemText then
		self._itemText.text = "战利品      " .. model:GetLootText()
	end
	if self._fragText then
		self._fragText.text = r.fragments == nil and "记忆碎片    待确认" or string.format("记忆碎片    %d", r.fragments)
	end

	-- 阵亡且有损失时才显示损失行
	if self._lootLostGo then
		local lost = tonumber(r.lootLost) or 0
		local show = (not model.isExtract) and lost > 0
		if self._lootLostTmp then
			self._lootLostTmp.text = string.format("渊获全部遗失（-%d 金币）", lost)
		end
		self._lootLostGo:SetActive(show)
	end

	if self._confirmBtn then
		self._confirmBtn.interactable = not r.busy
		local textNode = self._confirmBtn.gameObject.transform:Find("m_Text")
		local label = textNode and getTmp(textNode.gameObject)
		if label then label.text = model:GetConfirmText() end
		self._confirmBtn.onClick:RemoveAllListeners()
		self._confirmBtn.onClick:AddListener(function()
			if onConfirm then onConfirm() end
		end)
	end

	-- 关闭按钮与「返回主城」同义：结算已定，关闭只是另一种确认入口
	if self._closeBtn then
		self._closeBtn.interactable = not r.busy
		self._closeBtn.onClick:RemoveAllListeners()
		self._closeBtn.onClick:AddListener(function()
			if onConfirm then onConfirm() end
		end)
	end
end

return UIRunResultView
