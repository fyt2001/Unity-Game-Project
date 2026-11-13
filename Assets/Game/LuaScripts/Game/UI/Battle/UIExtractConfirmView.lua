--[[
=============================================================================
UIExtractConfirmView.lua - 撤离二次确认 View
=============================================================================
Module:     Game/UI/Battle/UIExtractConfirmView

Description:
	撤离确认框：标题 + 收益信息 + [确认撤离] + [继续战斗] + 右上角关闭。

	【为什么不用 AutoBind】
		同其余 Dungeon/Battle 弹窗：prefab 由 MCP 运行时创建，
		UIComponentBinder 上没有绑定项，走 FindGameObject + GetComponent。

	【关闭按钮语义 = 取消】
		X 与「继续战斗」等价：关闭确认框并恢复战斗。
		绝不可以是「确认撤离」—— 玩家点了 X 却被结算出局，比误触还糟。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UIExtractConfirmView = BaseClass("UIExtractConfirmView", UIView)
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

local function setText(tmp, s)
	if not tmp then return end
	CJKFont.Apply(tmp)
	tmp.text = s or ""
end

local function getButtonLabel(btn)
	if not btn then return nil end
	local child = btn.gameObject.transform:Find("m_Text")
	return child and getTmp(child.gameObject) or nil
end

function UIExtractConfirmView:OnCreate()
	base.OnCreate(self)
	CJKFont.ApplyAll(self.gameObject.transform)

	self._title = getTmp(self:FindGameObject("m_Title"))
	self._content = getTmp(self:FindGameObject("m_Content"))
	self._confirmBtn = getButton(self:FindGameObject("m_ConfirmBtn"))
	self._cancelBtn = getButton(self:FindGameObject("m_CancelBtn"))
	self._closeBtn = getButton(self:FindGameObject("m_CloseBtn"))
end

---渲染并提供确认/取消回调
---@param model table UIExtractConfirmModel
---@param onConfirm function 确认撤离
---@param onCancel function 取消（继续战斗）
function UIExtractConfirmView:Render(model, onConfirm, onCancel)
	if not model then return end

	setText(self._title, "确 认 撤 离")
	setText(self._content, table.concat(model:GetInfoLines(), "\n"))

	if self._confirmBtn then
		setText(getButtonLabel(self._confirmBtn), "确 认 撤 离")
		self._confirmBtn.onClick:RemoveAllListeners()
		self._confirmBtn.onClick:AddListener(function()
			if onConfirm then onConfirm() end
		end)
	end

	if self._cancelBtn then
		setText(getButtonLabel(self._cancelBtn), "继 续 战 斗")
		self._cancelBtn.onClick:RemoveAllListeners()
		self._cancelBtn.onClick:AddListener(function()
			if onCancel then onCancel() end
		end)
	end

	-- 关闭 = 取消（参见文件头注释）
	if self._closeBtn then
		self._closeBtn.onClick:RemoveAllListeners()
		self._closeBtn.onClick:AddListener(function()
			if onCancel then onCancel() end
		end)
	end
end

return UIExtractConfirmView
