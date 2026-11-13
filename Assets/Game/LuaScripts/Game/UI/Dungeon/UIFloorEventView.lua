--[[
=============================================================================
UIFloorEventView.lua - 层间事件弹窗 View
=============================================================================
Module:     Game/UI/Dungeon/UIFloorEventView

Description:
	展示层间事件的标题、描述与最多 3 个选项；点击选项回调 DungeonManager。

	【为什么不用 AutoBind】
	  本 prefab 由 MCP 运行时创建，没有在 UIComponentBinder 上登记绑定项，
	  因此不能用 self.m_Xxx_Btn 注入字段，改为 FindGameObject + GetComponent。
	  好处：不需要在 Inspector 里手工补绑定。

	【TMP 字体】
	  prefab 上 TextMeshProUGUI 的 fontAsset 默认为空（脚本创建不会自动带字体），
	  这里运行时从 Resources 载入 TMP 默认字体赋值，否则文字不显示。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UIFloorEventView = BaseClass("UIFloorEventView", UIView)
local base = UIView

local MAX_OPTIONS = 3

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

function UIFloorEventView:OnCreate()
	base.OnCreate(self)
	CJKFont.ApplyAll(self.gameObject.transform)

	self._title = getTmp(self:FindGameObject("m_EventTitle"))
	self._body = getTmp(self:FindGameObject("m_EventBody"))

	self._buttons = {}
	for i = 0, MAX_OPTIONS - 1 do
		self._buttons[i + 1] = getButton(self:FindGameObject("m_OptionBtn" .. i))
	end

	-- 右上角关闭按钮（P2-美术接入 2026-10-01）：prefab 有则有，没有也不影响打开
	self._closeBtn = getButton(self:FindGameObject("m_CloseBtn"))

end

---渲染内容并绑定点击
---@param model table UIFloorEventModel
---@param onSelect function(index) 点击回调
---@param onClose function|nil 关闭按钮回调（关闭 = 交给 DungeonManager 自动选择；prefab 无此按钮时忽略）
function UIFloorEventView:Render(model, onSelect, onClose)
	if not model then return end

	if self._title then self._title.text = model.title end
	if self._body then self._body.text = model.body end

	local options = model.options or {}
	for i = 1, MAX_OPTIONS do
		local btn = self._buttons[i]
		local opt = options[i]
		if btn then
			btn.gameObject:SetActive(opt ~= nil)
			if opt then
				local child = btn.gameObject.transform:Find("m_Text")
				local label = child and getTmp(child.gameObject) or nil
				if label then
					CJKFont.Apply(label)
					label.text = opt.text or ""
				end
				btn.onClick:RemoveAllListeners()
				btn.onClick:AddListener(function()
					if onSelect then onSelect(i) end
				end)
			end
		end
	end

	-- 关闭 = 「不想纠结，帮我选」：选择权仍在 DungeonManager（走自动选择），UI 不做决策
	if self._closeBtn then
		self._closeBtn.onClick:RemoveAllListeners()
		self._closeBtn.onClick:AddListener(function()
			if onClose then onClose() end
		end)
	end
end

return UIFloorEventView
