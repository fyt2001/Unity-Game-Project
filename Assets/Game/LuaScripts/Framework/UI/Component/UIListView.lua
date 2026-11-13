--[[
=============================================================================
UIListView.lua - 虚拟滚动列表组件（纯 Lua 等效 SuperScroll，对齐 H02 设计意图）
=============================================================================
Module:     Framework/UI/Component/UIListView
Target:     Unity + XLua（My project 的 BaseClass 体系）

描述：
	基于 Unity 原生 ScrollRect 的【垂直虚拟滚动列表】。只实例化可视区 + 缓冲区的
	item，滚动时回收不可见 item 到对象池、取出新进入可视区的 item，从而：
		- 避免对成千上万个数据项做大量 Instantiate/Destroy（性能）
		- item GO 经 PrefabPool 复用，降低 GC 与卡顿

	约定（prefab 与布局）：
		- 挂载 ScrollRect 的节点挂本组件（或 AutoBind 的 ScrollRect 引用）
		- ScrollRect.content 的 pivot 需为 (0.5, 1)（顶中对齐），item prefab 的
		  RectTransform anchor = (0.5, 1)、pivot = (0.5, 0.5)，与 content 一致
		- item 固定高度（动态高度暂不支持，需后续扩展）

用法：
	local list = self:AddComponent(UIListView, "ContentRoot/m_Scroll")
	list:SetItemPrefab(itemPrefabGO)              -- 业务从 AB/Resources 加载的 prefab
	list:SetOnRefresh(function(go, index)         -- 每个 item 取出/复用时回调刷新
		local txt = UIUtil.FindText(go.transform)
		txt.text = "第 " .. index
	end)
	list:SetCount(dataCount)                      -- 设总数量，触发虚拟滚动

对齐说明：
	H02 的 UISuperScroll 依赖第三方 C# 插件 UnitySuperScrollView（SuperScrollView_LoopListView2）。
	My project 无此插件，故以纯 Lua 的 UIListView + PrefabPool 提供等效能力；如需组件化 item
	（每个 item 是一个 Lua 组件类），可在此之上扩展 SetItemClass（参考 H02 的 UISuperItemBase）。
]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"
local PrefabPool = require "Framework.UI.Utils.PrefabPool"

local UIListView = BaseClass("UIListView", UIBaseComponent)
local base = UIBaseComponent

function UIListView:OnCreate()
	base.OnCreate(self)
	self.scrollRect = self.__uiComp or UIUtil.FindScrollRect(self.transform)
	self.content = self.scrollRect and self.scrollRect.content or nil
	self.viewport = self.scrollRect and (self.scrollRect.viewport or self.scrollRect.transform) or nil
	self.itemPrefab = nil
	self.itemHeight = 0
	self.itemSpacing = 0
	self.itemCount = 0
	self.onRefresh = nil
	self.activeItems = {}   -- index -> item GO（仅可视区存在）
	self.pool = nil
	self._onValueChanged = function() self:Refill() end
	if not IsNull(self.scrollRect) then
		self.scrollRect.onValueChanged:AddListener(self._onValueChanged)
	end
end

---设置 item 预制体（业务需先自行加载 prefab 为 GameObject 传入）
function UIListView:SetItemPrefab(prefab)
	if IsNull(prefab) then return end
	if self.pool then self.pool:Clear() end
	self.itemPrefab = prefab
	self.pool = PrefabPool.New(prefab, self.content)
	local rt = prefab.transform
	self.itemHeight = rt.sizeDelta.y
	if self.itemCount > 0 then self:SetCount(self.itemCount) end
end

---覆盖 item 尺寸（prefab 尺寸异常时手动指定）
function UIListView:SetItemSize(height, spacing)
	if height then self.itemHeight = height end
	if spacing then self.itemSpacing = spacing end
end

---设置刷新回调：item 取出/复用时调用 fn(go, index)
function UIListView:SetOnRefresh(fn)
	self.onRefresh = fn
end

---设置数据总数，触发虚拟滚动填充
function UIListView:SetCount(n)
	self.itemCount = n or 0
	if not IsNull(self.content) then
		local total = self.itemCount * self.itemHeight + math.max(0, self.itemCount - 1) * self.itemSpacing
		self.content.sizeDelta = CS.UnityEngine.Vector2(self.content.sizeDelta.x, total)
	end
	self:Refill()
end

---取可视区内的 item GO（非可视区返回 nil）；业务可借此绑定点击等
function UIListView:GetItem(index)
	return self.activeItems[index]
end

---刷新某个可视 item（不在可视区则忽略）
function UIListView:RefreshItem(index)
	local go = self.activeItems[index]
	if go and self.onRefresh then self.onRefresh(go, index) end
end

---刷新所有可视 item
function UIListView:RefreshAll()
	for idx, go in pairs(self.activeItems) do
		if self.onRefresh then self.onRefresh(go, idx) end
	end
end

---核心：根据滚动位置回收不可见 item、填充新进入可视区的 item
function UIListView:Refill()
	if not self.pool or IsNull(self.content) or IsNull(self.viewport) then return end
	local n = self.itemCount
	if n <= 0 then
		for _, go in pairs(self.activeItems) do self.pool:Release(go) end
		self.activeItems = {}
		return
	end
	local step = self.itemHeight + self.itemSpacing
	local vpHeight = self.viewport.rect.height
	local scrollY = -self.content.anchoredPosition.y
	local first = math.floor(scrollY / step)
	local visible = math.ceil(vpHeight / step) + 1
	local buffer = 2
	local startIndex = math.max(0, first - buffer)
	local endIndex = math.min(n - 1, first + visible + buffer)

	for idx, go in pairs(self.activeItems) do
		if idx < startIndex or idx > endIndex then
			self.pool:Release(go)
			self.activeItems[idx] = nil
		end
	end
	for i = startIndex, endIndex do
		if not self.activeItems[i] then
			local go = self.pool:Get()
			self.activeItems[i] = go
			go.transform.anchoredPosition = CS.UnityEngine.Vector2(0, -(i * step + self.itemHeight * 0.5))
			if self.onRefresh then self.onRefresh(go, i) end
		end
	end
end

function UIListView:OnDestroy()
	if not IsNull(self.scrollRect) and self._onValueChanged then
		self.scrollRect.onValueChanged:RemoveListener(self._onValueChanged)
	end
	if self.pool then self.pool:Clear() end
	self.activeItems = nil
	self.pool = nil
	self.scrollRect = nil
	self.content = nil
	self.viewport = nil
	base.OnDestroy(self)
end

return UIListView
