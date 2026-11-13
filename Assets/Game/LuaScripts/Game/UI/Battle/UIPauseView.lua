--[[
=============================================================================
UIPauseView.lua - 暂停菜单 View
=============================================================================
Module:     Game/UI/Battle/UIPauseView

Description:
	暂停面板：标题 + 本局信息 + [继续] + [撤离] + 右上角关闭。

	【为什么不用 AutoBind】
		本 prefab 由 MCP 运行时创建，没有在 UIComponentBinder 上登记绑定项，
		因此不能用 self.m_Xxx_Btn 注入字段，改为 FindGameObject + GetComponent。
		与 UIFloorEventView / UILevelUpView 保持同一套做法。

	【关闭按钮语义】
		暂停面板的关闭 = 「继续战斗」（不是「取消」）。
		玩家只是离开了这个菜单，战斗当然要恢复；若关闭不 Resume，
		战斗会永久冻结 —— 这是 P2-2 升级弹窗踩过的同类坑。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UIPauseView = BaseClass("UIPauseView", UIView)
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

function UIPauseView:OnCreate()
	base.OnCreate(self)
	CJKFont.ApplyAll(self.gameObject.transform)

	self._title = getTmp(self:FindGameObject("m_Title"))
	self._info = getTmp(self:FindGameObject("m_InfoText"))
	self._resumeBtn = getButton(self:FindGameObject("m_ResumeBtn"))
	self._extractBtn = getButton(self:FindGameObject("m_ExtractBtn"))
	self._closeBtn = getButton(self:FindGameObject("m_CloseBtn"))
end

---按钮文字位于独立的 m_Text 子节点。
local function getButtonLabel(btn)
	if not btn then return nil end
	local child = btn.gameObject.transform:Find("m_Text")
	return child and getTmp(child.gameObject) or nil
end

---渲染并提供三个回调
---@param model table UIPauseModel
---@param onResume function 继续战斗
---@param onExtract function 请求撤离（由 Controller 转交 DungeonManager）
function UIPauseView:Render(model, onResume, onExtract)
	if not model then return end

	setText(self._title, "暂 停")

	local lines = model:GetInfoLines()
	setText(self._info, table.concat(lines, "\n"))

	if self._resumeBtn then
		setText(getButtonLabel(self._resumeBtn), "继 续")
		self._resumeBtn.onClick:RemoveAllListeners()
		self._resumeBtn.onClick:AddListener(function()
			if onResume then onResume() end
		end)
	end

	if self._extractBtn then
		self._extractBtn.interactable = model.canExtract == true
		local label = model.canExtract and "撤 离" or "无 卷 轴"
		setText(getButtonLabel(self._extractBtn), label)
		self._extractBtn.onClick:RemoveAllListeners()
		self._extractBtn.onClick:AddListener(function()
			if onExtract then onExtract() end
		end)
	end

	-- 关闭 = 继续战斗
	if self._closeBtn then
		self._closeBtn.onClick:RemoveAllListeners()
		self._closeBtn.onClick:AddListener(function()
			if onResume then onResume() end
		end)
	end
end

return UIPauseView
