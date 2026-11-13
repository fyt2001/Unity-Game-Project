--[[
=============================================================================
UILevelUpView.lua - 升级三选一 View
=============================================================================
Module:     Game/UI/Dungeon/UILevelUpView

Description:
	展示最多 3 个升级候选，点击即选；文案与列表长度全部来自 UILevelUpModel，
	View 不做任何规则计算。

	【为什么不用 AutoBind】
	  本 prefab 由 MCP 运行时以 FloorEventPopup.prefab 为骨架复制生成，
	  没有在 UIComponentBinder 上登记绑定项，因此不能用 self.m_Xxx 注入字段，
	  改为 FindGameObject + GetComponent。好处：无需在 Inspector 手工补绑定。

	【TMP 字体】
	通过 CJKFont 统一应用中文字体及兼容当前运行平台的材质。

	【选项文案排版】
	按钮分别使用 m_Name 和 m_Description 展示名称与说明。

	【类系统】View 必须是 BaseClass（UIView 用 __init(holder, var_arg) 构造），
	与 UIFloorEventView / UIRunResultView 一致。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UILevelUpView = BaseClass("UILevelUpView", UIView)
local base = UIView

---面板最多支持几个候选（与 prefab 的 m_OptionBtn0~2 对应）
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

function UILevelUpView:OnCreate()
	base.OnCreate(self)

	self._title    = getTmp(self:FindGameObject("m_Panel/m_Title"))
	self._subtitle = getTmp(self:FindGameObject("m_Panel/m_Subtitle"))

	self._buttons = {}
	for i = 0, MAX_OPTIONS - 1 do
		self._buttons[i + 1] = getButton(self:FindGameObject("m_Panel/m_OptionBtn" .. i))
	end

	-- 运行时补字体，否则 TMP 不渲染（失败不影响面板打开）
	CJKFont.ApplyAll(self.gameObject.transform)
end

---渲染候选并绑定点击
---@param model table UILevelUpModel
---@param onSelect function(index) 点击回调
function UILevelUpView:Render(model, onSelect)
	if not model then return end

	if self._title then self._title.text = model:GetTitle() end
	if self._subtitle then self._subtitle.text = model:GetSubtitle() end

	local count = model:GetCount()

	for i = 1, MAX_OPTIONS do
		local btn = self._buttons[i]
		if btn then
			local exists = (i <= count)
			btn.gameObject:SetActive(exists)
			if exists then
				local label = getTmp(btn.gameObject.transform:Find("m_Name").gameObject)
				local description = getTmp(btn.gameObject.transform:Find("m_Description").gameObject)
				if label then
					CJKFont.Apply(label)
					-- 较长名称允许换行。
					pcall(function() label.enableWordWrapping = true end)
					pcall(function() label.alignment = CS.TMPro.TextAlignmentOptions.MidlineLeft end)
					label.text = model:GetOptionName(i)
				end
				if description then
					description.text = model:GetOptionDesc(i)
				end

				btn.onClick:RemoveAllListeners()
				btn.onClick:AddListener(function()
					if onSelect then onSelect(i) end
				end)
			end
		end
	end
end

return UILevelUpView
