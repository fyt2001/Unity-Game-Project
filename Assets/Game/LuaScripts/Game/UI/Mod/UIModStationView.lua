--[[
=============================================================================
UIModStationView.lua - 配装面板（ModStation）View
=============================================================================
Module:     Game/UI/Mod/UIModStationView

Description:
	把 Model 数据画成上方配装槽位和下方插画收藏；支持点击选择及拖放：
		- 左：持有 Mod 网格（运行时 Instantiate 模板节点，不依赖 UIComponentBinder）
		- 右：三宿主 Tab + 槽位网格 + 容量文案
		- 底：全宿主派生属性摘要

	【为什么不用 AutoBind】
	本 prefab 由 MCP 运行时构建，没有在 UIComponentBinder 上登记绑定项，
	因此不能用 self.m_Xxx_Btn 注入字段，改为 FindGameObject + GetComponent。
	与 UIFloorEventView / UIPauseView 同一套做法。

	【按钮文字走子节点】
	prefab 的按钮是「父节点 Image+Button / 子节点 m_Text(TMP)」结构 ——
	MCP 构建时发现 Image 与 TextMeshProUGUI 挂在同一 GameObject 上会互相挂载失败，
	所以文字一律取按钮的子节点。取不到时退化成「只留背景，不显示文字」，
	绝不因为找不到 m_Text 就抛错打断面板打开。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"
local UpdateManager = require "Framework.Core.UpdateManager"

local UIModStationView = BaseClass("UIModStationView", UIView)
local base = UIView

local TAB_COUNT = 3
local SLOT_COUNT = 8

local POLARITY_LABEL = {
	Abyss = "渊",
	Bone = "骨",
	Corrosion = "蚀",
	Curse = "咒",
	Neutral = "中性",
	Core = "核心",
}

local function slotLabel(polarity)
	if polarity == "Core" then return "核心槽" end
	if polarity == "Neutral" then return "中性槽" end
	return (POLARITY_LABEL[polarity] or tostring(polarity or "")) .. "极性槽"
end

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

---选中态高亮：整块格子换成亮色底，否则玩家看不出「我选了哪张」
local function setTint(go, color)
	if not go or not color then return end
	pcall(function()
		local img = go:GetComponent(typeof(CS.UnityEngine.UI.Image))
		if img then img.color = color end
	end)
end

-- 注意：Lua 里浮点字面量不能带 f 后缀（0.26f 是语法错误），这里一律裸小数
local COLOR_CELL = CS.UnityEngine.Color(1.0, 1.0, 1.0, 1.0)
local COLOR_PICK = CS.UnityEngine.Color(1.0, 0.94, 0.78, 1.0)
local COLOR_TEXT = CS.UnityEngine.Color(0.88, 0.89, 0.85, 1)
local COLOR_MATCH = CS.UnityEngine.Color(0.64, 0.9, 0.72, 1)
local COLOR_MISMATCH = CS.UnityEngine.Color(1, 0.76, 0.46, 1)
local COLOR_BLOCKED = CS.UnityEngine.Color(1, 0.66, 0.59, 1)
local COLOR_CORE = CS.UnityEngine.Color(0.94, 0.82, 0.54, 1)

local function fitLabel(tmp, maxSize, minSize)
	if not tmp then return end
	tmp.enableAutoSizing = true
	tmp.fontSizeMin = minSize
	tmp.fontSizeMax = maxSize
	tmp.enableWordWrapping = true
end

-- =============================================================================
-- 生命周期
-- =============================================================================

function UIModStationView:OnCreate()
	base.OnCreate(self)
	CJKFont.ApplyAll(self.gameObject.transform)

	self._title        = getTmp(self:FindGameObject("m_Main/m_Title"))
	self._closeBtn     = getButton(self:FindGameObject("m_Main/m_CloseBtn"))
	self._bagLabel     = getTmp(self:FindGameObject("m_Main/m_Left/m_BagLabel"))
	self._emptyGo      = self:FindGameObject("m_Main/m_Left/m_EmptyText")
	self._visual = self:FindGameObject("m_Main/m_ArtLibrary") ~= nil
	self._capacityText = getTmp(self:FindGameObject(self._visual
		and "m_Main/m_Left/m_Current/m_CapacityText" or "m_Main/m_Right/m_CapacityText"))
	self._statText = getTmp(self:FindGameObject(self._visual
		and "m_Main/m_Right/m_StatsScroll/Viewport/m_StatText" or "m_Main/m_StatsScroll/Viewport/m_StatText"))
	self._feedbackText = getTmp(self:FindGameObject("m_Main/m_FeedbackText"))

	self._content = self:FindGameObject("m_Main/m_Left/m_BagScroll/Viewport/Content")
	self._bagItemTpl = self:FindGameObject("m_Main/m_Left/m_BagScroll/Viewport/Content/m_BagItem")

	self._tabBtns = {}
	self._tabTexts = {}
	for i = 0, TAB_COUNT - 1 do
		local path = (self._visual and "m_Main/m_Tabs/m_TabBtn" or "m_Main/m_Right/m_Tabs/m_TabBtn") .. tostring(i)
		self._tabBtns[i + 1] = getButton(self:FindGameObject(path))
		self._tabTexts[i + 1] = getTmp(self:FindGameObject(path .. "/m_Text"))
	end

	self._slotBtns = {}
	self._slotTexts = {}
	for i = 0, SLOT_COUNT - 1 do
		local slotRoot = self._visual and "m_Main/m_Left/m_Current/m_Slots/Content/"
			or "m_Main/m_Right/m_Slots/Content/"
		local path = slotRoot .. "m_SlotBtn" .. tostring(i)
		if not self:FindGameObject(path) then
			path = "m_Main/m_Right/m_Slots/m_SlotBtn" .. tostring(i)
		end
		self._slotBtns[i + 1] = getButton(self:FindGameObject(path))
		self._slotTexts[i + 1] = getTmp(self:FindGameObject(path .. "/m_Text"))
	end

	self._bagNodes = {}
	if self._visual then
		self._artLibrary = self:FindGameObject("m_Main/m_ArtLibrary").transform
		self._artSources = {}
		self._artTargets = {}
		local backdrop = self:FindGameObject("m_Main/m_Backdrop")
		self._artTargets[backdrop] = { image = backdrop:GetComponent(typeof(CS.UnityEngine.UI.RawImage)),
			uv = CS.UnityEngine.Rect(0,0,1,1) }
		self._capacityFill = self:FindGameObject("m_Main/m_Left/m_Current/m_CapacityTrack/m_Fill").transform
	end
	-- 新布局用父 Canvas 的逻辑尺寸；旧 AB 保留原布局与路径。
	if self._feedbackText then
		self._mainRect = self:FindGameObject("m_Main").transform
		self._bagGrid = self._content:GetComponent(typeof(CS.UnityEngine.UI.GridLayoutGroup))
		local slots = self:FindGameObject(self._visual and "m_Main/m_Left/m_Current/m_Slots" or "m_Main/m_Right/m_Slots")
		self._slotScroll = slots:GetComponent(typeof(CS.UnityEngine.UI.ScrollRect))
		self._slotGrid = slots.transform:Find("Content"):GetComponent(typeof(CS.UnityEngine.UI.GridLayoutGroup))
		self:_updateLayout()
		UpdateManager:GetInstance():AddUpdate(function()
			if self._dragState and not self.gameObject.activeInHierarchy then self:_cancelDrag() end
			self:_updateLayout()
			if self._needsVisualRefresh and self._renderCallbacks and self._renderModel then
				local callbacks = self._renderCallbacks
				self:Render(self._renderModel, callbacks[1], callbacks[2], callbacks[3], callbacks[4])
			end
		end, self)
	end
end

function UIModStationView:_updateLayout()
	if not self._mainRect or not self.gameObject.activeInHierarchy then return end
	local rect = self._mainRect.parent.rect
	if rect.width <= 0 or rect.height <= 0 then return end
	if self._visual then
		self:_layoutVisual(rect.width, rect.height)
		return
	end
	local width = math.min(1040, rect.width - 64)
	local height = math.min(720, rect.height * 0.66)
	if width == self._layoutWidth and height == self._layoutHeight then return end
	self._layoutWidth, self._layoutHeight = width, height
	self._mainRect.sizeDelta = CS.UnityEngine.Vector2(width, height)
	local columnWidth = (width - 104) / 2
	-- 窄窗口改单列，维持卡片字号及点击高度，通过滚动浏览。
	local count = columnWidth < 400 and 1 or 2
	local cellWidth = (columnWidth - 8 - (count - 1) * 12) / count
	self._bagGrid.constraintCount = count
	self._slotGrid.constraintCount = count
	self._bagGrid.cellSize = CS.UnityEngine.Vector2(cellWidth, 160)
	self._slotGrid.cellSize = CS.UnityEngine.Vector2(cellWidth, 104)
end

function UIModStationView:OnDestroy()
	self:_cancelDrag()
	self._renderModel, self._renderCallbacks, self._needsVisualRefresh = nil, nil, nil
	self._artTargets, self._artSources, self._artLibrary = nil, nil, nil
	self._detailName, self._detailEffect, self._detailMeta, self._detailArt = nil, nil, nil, nil
	self._actionBtn, self._capacityFill, self._bagScroll = nil, nil, nil
	UpdateManager:GetInstance():RemoveUpdateByTarget(self)
	self:_clearBagNodes()
	self._mainRect, self._bagGrid, self._slotGrid, self._slotScroll = nil, nil, nil, nil
	self._feedbackText = nil

	self._title = nil
	self._closeBtn = nil
	self._bagLabel = nil
	self._emptyGo = nil
	self._capacityText = nil
	self._statText = nil
	self._content = nil
	self._bagItemTpl = nil
	self._tabBtns = {}
	self._tabTexts = {}
	self._slotBtns = {}
	self._slotTexts = {}
	self._bagNodes = {}

	base.OnDestroy(self)
end

-- =============================================================================
-- 渲染
-- =============================================================================

---@param model table UIModStationModel
---@param onTab function(index) 1..3 -> 切宿主
---@param onSlot function(index) 1..8 -> 拖放完成后安装、移动或卸下
---@param onBagItem function(uid) 点背包条目 = 选中
---@param onClose function 关闭按钮
function UIModStationView:Render(model, onTab, onSlot, onBagItem, onClose)
	if not model then return end
	self:_cancelDrag()
	self._renderCallbacks = { onTab, onSlot, onBagItem, onClose }

	setText(self._title, "配 装")
	setText(getButtonLabel(self._closeBtn and self._closeBtn.gameObject), "×")
	setText(self._capacityText, model:GetCapacityText())
	local summary = table.concat(model:GetStatLines() or {}, "\n")
	local feedback = model:GetFeedback()
	if self._feedbackText then
		local statSummary = self._visual and self._layoutPortrait and table.concat(model:GetStatLines() or {}, " · ")
			or "配装效果\n" .. summary
		setText(self._statText, statSummary)
		local hint = self._visual and ""
			or "选卡后点槽安装；未选卡时点已装槽卸下"
		setText(self._feedbackText, feedback ~= "" and feedback or hint)
	else
		setText(self._statText, summary .. (feedback ~= "" and ("\n" .. feedback) or ""))
	end
	if self._slotScroll and self._lastHost ~= model:GetHost() then
		self._slotScroll:StopMovement()
		self._slotScroll.verticalNormalizedPosition = 1
	end
	if self._visual and self._lastHost ~= model:GetHost() then
		self:_cancelDrag()
		if self._bagScroll then self._bagScroll.verticalNormalizedPosition = 1 end
	end
	self._lastHost = model:GetHost()
	self:_updateLayout()

	self._renderModel = model
	self:_renderTabs(model:GetTabs(), onTab)
	self:_renderSlots(model:GetSlots(), onSlot, model)
	self:_renderBag(model:GetBagItems(), onBagItem)
	if self._visual then self:_updateCapacity(model) end

	if self._closeBtn then
		self._closeBtn.onClick:RemoveAllListeners()
		self._closeBtn.onClick:AddListener(function()
			self:_cancelDrag()
			if onClose then onClose() end
		end)
	end
	self._needsVisualRefresh = false
end

function UIModStationView:_renderTabs(tabs, onTab)
	for i = 1, TAB_COUNT do
		local btn = self._tabBtns[i]
		local tab = tabs[i]
		if btn and tab then
			btn.gameObject:SetActive(true)
			setText(self._tabTexts[i], tab.label)
			if self._visual then
				local line = btn.transform:Find("m_Frame"):GetComponent(typeof(CS.UnityEngine.UI.Image))
				line.sprite = nil
				line.color = tab.active and CS.UnityEngine.Color(0.04, 0.8, 0.82, 1)
					or CS.UnityEngine.Color(0.3, 0.4, 0.44, 0.25)
				if self._tabTexts[i] then self._tabTexts[i].color = tab.active and COLOR_CORE or COLOR_TEXT end
			else setTint(btn.gameObject, tab.active and COLOR_PICK or COLOR_CELL) end
			btn.onClick:RemoveAllListeners()
			btn.onClick:AddListener(function()
				if onTab then onTab(i) end
			end)
		end
	end
end

function UIModStationView:_renderSlots(slots, onSlot, model)
	if self._visual then self:_renderVisualSlots(slots, onSlot, model) return end
	for i = 1, SLOT_COUNT do
		local btn = self._slotBtns[i]
		local slot = slots[i]
		if btn then
			if not slot then
				-- 宿主槽位没这么多：直接隐藏，不留空壳按钮
				btn.gameObject:SetActive(false)
			else
				btn.gameObject:SetActive(true)
				setTint(btn.gameObject, model:CanSelectInto(i) and COLOR_PICK or COLOR_CELL)
				local label = self._slotTexts[i]
				local preview = model:GetSlotPreview(i)
				local item = slot.item
				local text = slotLabel(slot.polarity)
				if item then text = item.name .. "\n" .. text end
				if preview then
					if item and item.uid ~= preview.uid then
						text = item.name .. " → " .. preview.name .. "\n" .. slotLabel(slot.polarity)
					end
					if preview.allowed then
						text = text .. string.format("\n消耗 %g · %s", preview.cost, preview.relation)
					else
						text = text .. "\n" .. (preview.reason or "不可安装")
					end
				elseif item then
					text = text .. string.format("\n消耗 %g", item.cost or 0)
				else
					text = text .. (slot.empty and "\n空槽" or "\n卡片已失效")
				end
				fitLabel(label, 22, self._feedbackText and 18 or 14)
				if label then
					label.color = preview and (not preview.allowed and COLOR_BLOCKED
						or (preview.relation == "不匹配" and COLOR_CORE or COLOR_MATCH))
						or (slot.polarity == "Core" and COLOR_CORE or COLOR_TEXT)
				end
				setText(label, text)
				btn.onClick:RemoveAllListeners()
				btn.onClick:AddListener(function()
					if slot.item and self._renderCallbacks[3] then self._renderCallbacks[3](slot.item.uid) end
				end)
			end
		end
	end
end

function UIModStationView:_renderBag(items, onBagItem)
	if self._visual then self:_renderVisualBag(items, onBagItem) return end
	items = items or {}
	local total = 0
	for _, item in ipairs(items) do total = total + (item.count or 1) end
	setText(self._bagLabel, string.format("背包 (%d)", total))
	if self._emptyGo then self._emptyGo:SetActive(#items == 0) end
	self:_clearBagNodes()

	if not self._content or not self._bagItemTpl then return end

	for _, item in ipairs(items) do
		local node = CS.UnityEngine.GameObject.Instantiate(self._bagItemTpl)
		if node then
			node.transform:SetParent(self._content.transform, false)
			node:SetActive(true)
			self._bagNodes[#self._bagNodes + 1] = node
			local label = getButtonLabel(node)
			fitLabel(label, 22, self._feedbackText and 18 or 14)
			local countNode = node.transform:Find("m_Count")
			if countNode then
				countNode.gameObject:SetActive((item.count or 1) > 1)
				setText(getTmp(countNode.gameObject), tostring(item.count or 1))
			end
			local installedCount = item.installedCount or (item.installed and 1 or 0)
			local installedLabel = installedCount > 0 and " [已装]" or ""
			setText(label, string.format("%s%s\nR%d · %s极性\n基础消耗 %g\n%s", item.name or "",
				installedLabel, item.rank or 1,
				POLARITY_LABEL[item.polarity] or tostring(item.polarity or "中性"), item.baseCost or 0, item.desc or ""))
			setTint(node, item.selected and COLOR_PICK or COLOR_CELL)

			local btn = getButton(node)
			if btn then
				local uid = item.uid
				btn.onClick:RemoveAllListeners()
				btn.onClick:AddListener(function()
					if onBagItem then onBagItem(uid) end
				end)
			end
		end
	end
end

---清掉上次渲染生成的所有背包节点（模板 m_BagItem 本身保留）
function UIModStationView:_clearBagNodes()
	if self._artTargets then
		for _, node in ipairs(self._bagNodes or {}) do local art = node.transform:Find("m_Art")
			if art then self._artTargets[art.gameObject] = nil end end
	end
	if self._content then
		local tr = self._content.transform
		local kids = {}
		for i = 0, tr.childCount - 1 do
			kids[#kids + 1] = tr:GetChild(i)
		end
		for _, k in ipairs(kids) do
			if not self._bagItemTpl or k.gameObject ~= self._bagItemTpl then
				CS.UIRuntimeCleanup.ReleaseCallbacks(k.gameObject)
				k.gameObject:SetActive(false)
				CS.UnityEngine.Object.Destroy(k.gameObject)
			end
		end
	end
	self._bagNodes = {}
end


-- 插画页只读 prefab 内的序列化依赖，不引入另一套资源加载路径。
local function child(go, name)
	local tr = go and go.transform:Find(name)
	return tr and tr.gameObject or nil
end

local function rawImage(go)
	return go and go:GetComponent(typeof(CS.UnityEngine.UI.RawImage)) or nil
end

function UIModStationView:_setFrame(go, style)
	local frameGo = child(go, "m_Frame")
	local source = self._artLibrary:Find("m_" .. style)
	if frameGo and source then
		frameGo:GetComponent(typeof(CS.UnityEngine.UI.Image)).sprite =
			source:GetComponent(typeof(CS.UnityEngine.UI.Image)).sprite
	end
end

function UIModStationView:_setArt(go, id, detail)
	if not go then return end
	local key = (detail and id == 1002 and "m_Detail" or "m_Art") .. tostring(id)
	local source = self._artSources[key]
	if not source then
		local tr = self._artLibrary:Find(key)
		source = tr and rawImage(tr.gameObject)
		self._artSources[key] = source
	end
	local target = rawImage(go)
	go:SetActive(source ~= nil)
	if target and source then
		target.texture = source.texture
		self._artTargets[go] = { image = target, uv = source.uvRect }
	end
end

function UIModStationView:_fitArt()
	for _, data in pairs(self._artTargets or {}) do
		local image, uv = data.image, data.uv
		local rect = image.rectTransform.rect
		if rect.width > 0 and rect.height > 0 and image.texture then
			local sourceRatio = image.texture.width * uv.width / (image.texture.height * uv.height)
			local targetRatio = rect.width / rect.height
			local w, h = uv.width, uv.height
			if targetRatio < sourceRatio then w = w * targetRatio / sourceRatio
			else h = h * sourceRatio / targetRatio end
			image.uvRect = CS.UnityEngine.Rect(uv.x + (uv.width - w) / 2, uv.y + (uv.height - h) / 2, w, h)
		end
	end
end

function UIModStationView:_layoutVisual(parentWidth, parentHeight)
	local portrait = parentWidth / parentHeight < 1.1
	self._layoutPortrait = portrait
	local scale = portrait and (parentWidth - 24) / 480
		or math.min((parentWidth - 32) / 1280, parentHeight * 0.98 / 720)
	local width, height = portrait and 480 or 1280, portrait and math.min(1100, parentHeight * 0.98 / scale) or 720
	if width ~= self._layoutWidth or height ~= self._layoutHeight or scale ~= self._layoutScale then
		self:_cancelDrag()
		self._needsVisualRefresh = true
		self._layoutScale = scale
		self._layoutWidth, self._layoutHeight = width, height
		self._mainRect.sizeDelta = CS.UnityEngine.Vector2(width, height)
		self._mainRect.localScale = CS.UnityEngine.Vector3(scale, scale, 1)
		local function box(path, x0, y0, x1, y1, l, b, r, t)
			local rt = self:FindGameObject("m_Main/" .. path).transform
			rt.anchorMin, rt.anchorMax = CS.UnityEngine.Vector2(x0, y0), CS.UnityEngine.Vector2(x1, y1)
			rt.offsetMin, rt.offsetMax = CS.UnityEngine.Vector2(l, b), CS.UnityEngine.Vector2(r, t)
		end
		box("m_Tabs", 0, 1, portrait and 1 or 0, 1, portrait and 20 or 176, portrait and -120 or -72,
			portrait and -20 or 536, portrait and -72 or -16)
		box("m_Left", 0, 0, 1, 1, portrait and 20 or 32, 40, portrait and -20 or -32, portrait and -132 or -80)
		box("m_Left/m_Current", 0, 0.52, 1, 1, 0, 0, 0, 0)
		box("m_Left/m_Current/m_Label", 0, 1, 0.4, 1, 12, -36, 0, -4)
		box("m_Left/m_Current/m_CapacityText", 0.4, 1, 0.7, 1, 0, -36, 0, -4)
		box("m_Left/m_Current/m_CapacityTrack", 0.72, 1, 1, 1, 0, -24, -12, -18)
		local columns = portrait and 2 or 5
		local columnWidth = width - (portrait and 64 or 88)
		local cardWidth = (columnWidth - 24 - (columns - 1) * 16) / columns
		local available = (height - (portrait and 172 or 120)) * 0.48 - 52
		local cardHeight = portrait and math.min(cardWidth * 1.4, 280) or math.min(cardWidth * 1.4, available - 24)
		self._bagGrid.constraintCount, self._slotGrid.constraintCount = columns, columns
		self._bagGrid.spacing, self._slotGrid.spacing = CS.UnityEngine.Vector2(16,16), CS.UnityEngine.Vector2(16,16)
		self._bagGrid.cellSize = CS.UnityEngine.Vector2(cardWidth, cardHeight)
		self._slotGrid.cellSize = CS.UnityEngine.Vector2(cardWidth, cardHeight)
		self._bagScroll = self:FindGameObject("m_Main/m_Left/m_BagScroll"):GetComponent(typeof(CS.UnityEngine.UI.ScrollRect))
	end
	self:_fitArt()
end

local function costColor(polarity, slotPolarity, allowed)
	if allowed == false then return COLOR_BLOCKED end
	if not slotPolarity or polarity == "Neutral" or slotPolarity == "Neutral" then return COLOR_TEXT end
	return polarity == slotPolarity and COLOR_MATCH or COLOR_MISMATCH
end

function UIModStationView:_paintCard(node, detail, selected, empty, cost, slotPolarity)
	self:_setFrame(node, selected and "FrameSelected" or (empty and "FrameMuted" or "FrameGold"))
	local art = child(node, "m_Art")
	if detail then self:_setArt(art, detail.id, false)
	elseif art then art:SetActive(false) self._artTargets[art] = nil end
	setText(getButtonLabel(node), detail and detail.name or "")
	setText(getTmp(child(node, "m_Effect")), detail and detail.effect or "")
	self:_setPolarity(node, detail and detail.polarity)
	local marks = {}
	if detail then
		for i = 1, detail.maxRank do marks[i] = i <= detail.rank and "◆" or "◇" end
	end
	local rankText = table.concat(marks, " ")
	-- Rank is represented only by diamonds, including portrait layouts.
	setText(getTmp(child(node, "m_Rank")), rankText)
	local badge = child(node, "m_CostBadge")
	if badge then
		badge:SetActive(detail ~= nil and cost ~= nil)
		local value = getTmp(child(badge, "m_Value"))
		setText(value, cost and string.format("%g", cost) or "")
		if value then value.color = costColor(detail and detail.polarity, slotPolarity) end
	end
	local emptyMark = child(node, "m_EmptyMark")
	if emptyMark then emptyMark:SetActive(empty) end
end

function UIModStationView:_renderVisualSlots(slots, _, model)
	for i = 1, SLOT_COUNT do
		local btn, slot = self._slotBtns[i], slots[i]
		if btn then
			btn.gameObject:SetActive(slot ~= nil)
			if slot then
				local detail = slot.item and model:GetModDetail(slot.item.uid)
				local selected = detail and model:GetSelected() == detail.uid
				self:_paintCard(btn.gameObject, detail, selected, not detail, slot.item and slot.item.cost, slot.polarity)
				if not detail then
					setText(self._slotTexts[i], "")
					setText(getTmp(child(btn.gameObject, "m_Rank")), "")
					self:_setPolarity(btn.gameObject, slot.polarity)
				end
				btn.onClick:RemoveAllListeners()
				btn.onClick:AddListener(function()
					if self._dragState then return end
					if slot.item and self._renderCallbacks[3] then
						self._renderCallbacks[3](slot.item.uid)
					end
				end)
				self:_bindDrag(btn.gameObject, slot.item and slot.item.uid, i, selected)
			end
		end
	end
end

function UIModStationView:_renderVisualBag(items, onBagItem)
	items = items or {}
	local total = 0
	for _, item in ipairs(items) do total = total + (item.count or 1) end
	setText(self._bagLabel, string.format("模组收藏  ·  %d", total))
	if self._emptyGo then self._emptyGo:SetActive(#items == 0) end
	self:_clearBagNodes()
	for _, item in ipairs(items) do
		local node = CS.UnityEngine.GameObject.Instantiate(self._bagItemTpl)
		node.transform:SetParent(self._content.transform, false)
		node:SetActive(true)
		self._bagNodes[#self._bagNodes + 1] = node
		-- Detail values are supplied by the model in Render, without changing selected UID.
		local detail = self._renderModel:GetModDetail(item.uid)
		self:_paintCard(node, detail, item.selected, false, detail and detail.baseCost)
		local badge = child(node, "m_CountBadge")
		badge:SetActive((item.count or 1) > 1)
		setText(getTmp(child(badge, "m_Count")), tostring(item.count or 1))
		local status = child(node, "m_Status")
		status:SetActive(false)
		local uid = item.uid
		local btn = getButton(node)
		btn.onClick:RemoveAllListeners()
		btn.onClick:AddListener(function() if not self._dragState and onBagItem then onBagItem(uid) end end)
		self:_bindDrag(node, uid, nil, item.selected)
	end
end

function UIModStationView:_updateCapacity(model)
	local used, maximum = string.match(model:GetCapacityText(), "([%d%.]+)%s*/%s*([%d%.]+)")
	used, maximum = tonumber(used) or 0, tonumber(maximum) or 0
	self._capacityFill.anchorMax = CS.UnityEngine.Vector2(maximum > 0 and math.min(1, used / maximum) or 0, 1)
	self._capacityFill.offsetMin, self._capacityFill.offsetMax = CS.UnityEngine.Vector2.zero, CS.UnityEngine.Vector2.zero
	self:_fitArt()
end

-- Polarity sprites are serialized prefab dependencies, packaged with the UI bundle.
function UIModStationView:_setPolarity(node, polarity)
	local icon = child(node, "m_Polarity")
	if not icon then return end
	local source = polarity and self._artLibrary:Find("m_Polarity" .. polarity)
	icon:SetActive(source ~= nil)
	if source then
		local image = icon:GetComponent(typeof(CS.UnityEngine.UI.Image))
		image.sprite = source:GetComponent(typeof(CS.UnityEngine.UI.Image)).sprite
		image.preserveAspect = true
		image.raycastTarget = false
	end
end

function UIModStationView:_bindDrag(node, uid, slotIndex, selected)
	local relay = node:GetComponent(typeof(CS.ModCardDrag))
	if CS.ModCardDrag.IsMissing(relay) then relay = node:AddComponent(typeof(CS.ModCardDrag)) end
	local restingScale = selected and 1.035 or 1
	node.transform.localScale = CS.UnityEngine.Vector3(restingScale, restingScale, 1)
	for _, event in ipairs({relay.beginDrag, relay.drag, relay.endDrag, relay.enter, relay.exit}) do
		event:RemoveAllListeners()
	end
	relay.enter:AddListener(function()
		if not self._dragState and uid then node.transform.localScale = CS.UnityEngine.Vector3(1.035,1.035,1) end
	end)
	relay.exit:AddListener(function()
		if not self._dragState then node.transform.localScale = CS.UnityEngine.Vector3(restingScale,restingScale,1) end
	end)
	relay.beginDrag:AddListener(function() if uid then self:_beginDrag(node, uid, slotIndex, relay) end end)
	relay.drag:AddListener(function() self:_moveDrag(relay) end)
	relay.endDrag:AddListener(function() self:_endDrag(relay) end)
end

function UIModStationView:_beginDrag(node, uid, slotIndex, relay)
	if self._dragState or not self._renderModel:GetModDetail(uid) then return end
	local model = self._renderModel
	local previous = model:GetSelected()
	if previous ~= uid then model:SetSelected(uid) end
	local ghost = CS.UnityEngine.GameObject.Instantiate(node)
	ghost.name = "m_DragCard"
	ghost.transform:SetParent(self._mainRect, false)
	ghost.transform.anchorMin, ghost.transform.anchorMax = CS.UnityEngine.Vector2(0.5,0.5), CS.UnityEngine.Vector2(0.5,0.5)
	ghost.transform.sizeDelta = node.transform.rect.size
	ghost.transform.localScale = CS.UnityEngine.Vector3(1.06,1.06,1)
	ghost.transform:SetAsLastSibling()
	local shadow = ghost:AddComponent(typeof(CS.UnityEngine.UI.Shadow))
	shadow.effectColor = CS.UnityEngine.Color(0,0,0,0.65)
	shadow.effectDistance = CS.UnityEngine.Vector2(6,-8)
	ghost:GetComponent(typeof(CS.ModCardDrag)).enabled = false
	getButton(ghost).enabled = false
	local group = ghost:GetComponent(typeof(CS.UnityEngine.CanvasGroup))
	if CS.ModCardDrag.IsMissing(group) then group = ghost:AddComponent(typeof(CS.UnityEngine.CanvasGroup)) end
	group.alpha = 1
	group.blocksRaycasts, group.interactable = false, false
	local sourceGroup = node:GetComponent(typeof(CS.UnityEngine.CanvasGroup))
	if CS.ModCardDrag.IsMissing(sourceGroup) then
		sourceGroup = node:AddComponent(typeof(CS.UnityEngine.CanvasGroup))
	end
	local originalAlpha = sourceGroup.alpha
	sourceGroup.alpha = 0.35
	local pointerOk, pointer = CS.UnityEngine.RectTransformUtility.ScreenPointToLocalPointInRectangle(
		self._mainRect, relay.pointerPosition, relay.eventCamera)
	local origin = self._mainRect:InverseTransformPoint(node.transform.position)
	local grabOffset = pointerOk and CS.UnityEngine.Vector2(origin.x - pointer.x, origin.y - pointer.y)
		or CS.UnityEngine.Vector2.zero
	local sourceCost = getTmp(child(child(node, "m_CostBadge"), "m_Value"))
	self._dragState = { uid = uid, sourceSlot = slotIndex, ghost = ghost, source = node, owner = relay,
		group = sourceGroup, originalAlpha = originalAlpha, previous = previous, host = model:GetHost(),
		grabOffset = grabOffset, sourceCost = sourceCost.text, sourceColor = sourceCost.color }
	if self._bagScroll then self._bagScroll:StopMovement() self._bagScroll.enabled = false end
	self._slotScroll:StopMovement()
	self._slotScroll.enabled = false
	self:_moveDrag(relay)
end

function UIModStationView._hit(_, rect, relay)
	return rect and CS.UnityEngine.RectTransformUtility.RectangleContainsScreenPoint(
		rect, relay.pointerPosition, relay.eventCamera)
end

function UIModStationView:_hitScroll(scroll, relay)
	local viewport = scroll.viewport
	if CS.ModCardDrag.IsMissing(viewport) then viewport = scroll.transform end
	return self:_hit(viewport, relay)
end

function UIModStationView:_moveDrag(relay)
	local drag = self._dragState
	if not drag or drag.owner ~= relay then return end
	local ok, point = CS.UnityEngine.RectTransformUtility.ScreenPointToLocalPointInRectangle(self._mainRect,
		relay.pointerPosition, relay.eventCamera)
	if ok then drag.ghost.transform.anchoredPosition = point + drag.grabOffset end
	drag.target = nil
	local visible = self:_hitScroll(self._slotScroll, relay)
	for i, btn in ipairs(self._slotBtns) do
		local slot = self._renderModel:GetSlots()[i]
		if slot and btn.gameObject.activeInHierarchy then
			local hovered = visible and self:_hit(btn.transform, relay)
			local valid = hovered and self._renderModel:CanSelectInto(i)
			self:_setFrame(btn.gameObject, valid and "FrameSelected" or (slot.item and "FrameGold" or "FrameMuted"))
			local frameGo = child(btn.gameObject, "m_Frame")
			frameGo.transform.localScale = valid and CS.UnityEngine.Vector3(1.09,1.09,1) or CS.UnityEngine.Vector3.one
			local frame = frameGo:GetComponent(typeof(CS.UnityEngine.UI.Image))
			frame.color = hovered and not valid and COLOR_BLOCKED or CS.UnityEngine.Color.white
			if hovered then drag.target = i end
		end
	end
	local preview = drag.target and self._renderModel:GetSlotPreview(drag.target)
	local value = getTmp(child(child(drag.ghost, "m_CostBadge"), "m_Value"))
	setText(value, preview and string.format("%g", preview.cost) or drag.sourceCost)
	local slot = drag.target and self._renderModel:GetSlots()[drag.target]
	local detail = slot and self._renderModel:GetModDetail(drag.uid)
	value.color = preview and costColor(detail.polarity, slot.polarity, preview.allowed) or drag.sourceColor
	setText(self._feedbackText, preview and not preview.allowed and preview.reason or "")
end

function UIModStationView:_clearDragVisual()
	local drag = self._dragState
	if not drag then return end
	self._dragState = nil
	drag.group.alpha = drag.originalAlpha
	drag.ghost:SetActive(false)
	CS.UnityEngine.Object.Destroy(drag.ghost)
	if self._bagScroll then self._bagScroll.enabled = true end
	if self._slotScroll then self._slotScroll.enabled = true end
	for _, btn in ipairs(self._slotBtns or {}) do
		local frame = child(btn.gameObject, "m_Frame")
		if frame then
			frame:GetComponent(typeof(CS.UnityEngine.UI.Image)).color = CS.UnityEngine.Color.white
			frame.transform.localScale = CS.UnityEngine.Vector3.one
		end
	end
end

function UIModStationView:_cancelDrag()
	local drag = self._dragState
	if not drag then return end
	self:_clearDragVisual()
	if self._renderModel:GetHost() == drag.host and self._renderModel:GetSelected() ~= drag.previous then
		self._renderModel:SetSelected(drag.previous)
	end
end

function UIModStationView:_endDrag(relay)
	local drag = self._dragState
	if not drag or drag.owner ~= relay then return end
	self:_moveDrag(relay)
	local target = drag.target
	local intoBag = drag.sourceSlot and self:_hitScroll(self._bagScroll, relay)
	local callbacks, model = self._renderCallbacks, self._renderModel
	self:_clearDragVisual()
	if target and model:GetHost() == drag.host and target ~= drag.sourceSlot then
		-- The controller revalidates and emits feedback even for an invalid target.
		callbacks[2](target)
	elseif intoBag and model:GetHost() == drag.host then
		model:SetSelected(nil)
		callbacks[2](drag.sourceSlot)
	else
		if model:GetSelected() ~= drag.previous then model:SetSelected(drag.previous) end
		self:Render(model, callbacks[1], callbacks[2], callbacks[3], callbacks[4])
	end
end

function UIModStationView:OnClose()
	self:_cancelDrag()
	base.OnClose(self)
end

function UIModStationView:OnHide()
	self:_cancelDrag()
	base.OnHide(self)
end

return UIModStationView
