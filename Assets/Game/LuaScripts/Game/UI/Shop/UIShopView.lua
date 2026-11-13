--[[
=============================================================================
UIShopView.lua - 主城商店（Shop）View
=============================================================================
Module:     Game/UI/Shop/UIShopView

Description:
	把 Model 的数据画成「金币 / 折扣 / 商品卡 / 两个购买按钮 / 回执」。

	【为什么不用 AutoBind】
	prefab 由 MCP 运行时构建，没有在 UIComponentBinder 上登记绑定项，
	改为 FindGameObject + GetComponent —— 与 UIModStationView 同一套做法。

	【按钮文字走子节点】
	prefab 的按钮是「父节点 Image+Button / 子节点 m_Text(TMP)」结构：
	MCP 构建时发现 Image 与 TextMeshProUGUI 挂在同一 GameObject 上会互相挂载失败。
	取不到 m_Text 时退化成「只留背景、不显示文字」，绝不抛错打断面板打开。

	【金币不足的反馈】
	按钮整个换成暗底 + 暗字（不是禁用 Button 组件 —— 点了也只是弹一句
	回执，禁用反而让玩家点不动又不知道为什么）。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UIShopView = BaseClass("UIShopView", UIView)
local base = UIView

-- =============================================================================
-- 组件取用辅助（pcall 兜底：prefab 缺节点时静默降级，不打断打开）
-- =============================================================================

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

---按钮上的文字一律取【子节点 m_Text】
local function getButtonLabel(go)
	if not go then return nil end
	local child = go.transform:Find("m_Text")
	if not child then return nil end
	return getTmp(child.gameObject)
end

local function setText(tmp, s)
	if not tmp then return end
	CJKFont.Apply(tmp)
	tmp.text = s or ""
end

local function setImageColor(go, color)
	if not go or not color then return end
	pcall(function()
		local img = go:GetComponent(typeof(CS.UnityEngine.UI.Image))
		if img then img.color = color end
	end)
end

-- 注意：Lua 里浮点字面量不能带 f 后缀（0.26f 是语法错误），这里一律裸小数
local COLOR_TEXT   = CS.UnityEngine.Color(0.92, 0.94, 0.98, 1.0)
local COLOR_GOLD   = CS.UnityEngine.Color(0.95, 0.80, 0.30, 1.0)
local COLOR_BTN    = CS.UnityEngine.Color(1.0, 1.0, 1.0, 1.0)
local COLOR_BTN_OFF = CS.UnityEngine.Color(0.30, 0.31, 0.34, 1.0)
local COLOR_TEXT_OFF = CS.UnityEngine.Color(0.62, 0.64, 0.68, 1.0)

-- =============================================================================
-- 买按钮渲染（模块函数：只依赖入参，故意不挂成 View 方法）
-- =============================================================================

---文案 + 余额不足置灰 + 点击回调。
---做成模块函数而不是方法：它不需要碰 self，也就没必要为「像个方法」骗 luacheck。
local function renderBuyBtn(btn, label, labelText, enabled, onClick)
	setText(label, labelText)

	local go = btn and btn.gameObject
	setImageColor(go, enabled and COLOR_BTN or COLOR_BTN_OFF)
	if label then
		pcall(function() label.color = enabled and COLOR_TEXT or COLOR_TEXT_OFF end)
	end

	if btn then
		btn.onClick:RemoveAllListeners()
		btn.onClick:AddListener(function()
			if onClick then onClick() end
		end)
	end
end

-- =============================================================================
-- 生命周期
-- =============================================================================

function UIShopView:OnCreate()
	base.OnCreate(self)
	CJKFont.ApplyAll(self.gameObject.transform)

	self._title       = getTmp(self:FindGameObject("m_Main/m_Title"))
	self._closeBtn    = getButton(self:FindGameObject("m_Main/m_CloseBtn"))
	self._goldText    = getTmp(self:FindGameObject("m_Main/m_GoldText"))
	self._discountText = getTmp(self:FindGameObject("m_Main/m_DiscountText"))
	self._itemName    = getTmp(self:FindGameObject("m_Main/m_ItemCard/m_ItemName"))
	self._itemDesc    = getTmp(self:FindGameObject("m_Main/m_ItemCard/m_ItemDesc"))
	self._resultText  = getTmp(self:FindGameObject("m_Main/m_ResultScroll/Viewport/m_ResultText"))

	self._buyBtn      = getButton(self:FindGameObject("m_Main/m_BuyBtn"))
	self._buyLabel    = getButtonLabel(self:FindGameObject("m_Main/m_BuyBtn"))
	self._buy5Btn     = getButton(self:FindGameObject("m_Main/m_Buy5Btn"))
	self._buy5Label   = getButtonLabel(self:FindGameObject("m_Main/m_Buy5Btn"))
end

function UIShopView:OnDestroy()
	self._title = nil
	self._closeBtn = nil
	self._goldText = nil
	self._discountText = nil
	self._itemName = nil
	self._itemDesc = nil
	self._resultText = nil
	self._buyBtn = nil
	self._buyLabel = nil
	self._buy5Btn = nil
	self._buy5Label = nil

	base.OnDestroy(self)
end

-- =============================================================================
-- 渲染
-- =============================================================================

---@param model table UIShopModel
---@param onBuy function 点「买 1 张」
---@param onBuy5 function 点「买 5 张」
---@param onClose function 关面板
function UIShopView:Render(model, onBuy, onBuy5, onClose)
	if not model then return end

	setText(self._title, "商 店")
	setText(self._goldText, model:GetGoldText())
	setText(self._discountText, model:GetDiscountText())
	setText(self._itemName, model:GetItemName())
	setText(self._itemDesc, model:GetItemDesc())
	setText(self._resultText, model:GetResultText())

	renderBuyBtn(self._buyBtn, self._buyLabel, model:GetBuyLabel(), model:CanBuy(1), onBuy)
	renderBuyBtn(self._buy5Btn, self._buy5Label, model:GetBuy5Label(), model:CanBuy(5), onBuy5)

	setText(getButtonLabel(self._closeBtn and self._closeBtn.gameObject), "x")

	if self._closeBtn then
		self._closeBtn.onClick:RemoveAllListeners()
		self._closeBtn.onClick:AddListener(function()
			if onClose then onClose() end
		end)
	end

	-- 金币用金色的，一眼能认出这是钱
	pcall(function() if self._goldText then self._goldText.color = COLOR_GOLD end end)
end

return UIShopView
