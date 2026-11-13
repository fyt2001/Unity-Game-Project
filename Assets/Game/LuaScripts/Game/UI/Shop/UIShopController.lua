--[[
=============================================================================
UIShopController.lua - 主城商店（Shop）Controller
=============================================================================
Module:     Game/UI/Shop/UIShopController

Description:
	把玩家在商店面板上的点击翻译成 Model 调用，再让 View 重画。

	【Controller 不做价格与余额决策】
	买得起买不起、扣多少钱、发什么卡，全在 UIShopModel.Buy 里，
	Controller 只管「点了几张 → 调 Buy → 拿回执文案 → 重画」。
	这样金币不足时是 Model 给的回执（「需要 300，余额 120」），
	而不是 Controller 里再抄一遍价格常量。

	【买完要重画】
	Buy 改了 SaveData（金币 + 背包），所以买完必须 model:Refresh() + _refresh()，
	否则面板上还挂着买之前的余额和按钮文案。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"
local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"

local ONLINE_FEEDBACK = {
	busy = "请求处理中", not_logged_in = "请重新登录", unauthorized = "请重新登录",
	insufficient_gold = "金币不足", not_enough_gold = "金币不足",
	revision_conflict = "数据已更新，请重试", invalid_request = "购买参数无效",
	network_error = "连接失败，请重试", timeout = "请求超时，请重试",
	database_unavailable = "服务暂不可用", service_unavailable = "服务暂不可用",
}

local function onlineFeedback(reason)
	return ONLINE_FEEDBACK[reason] or "购买未完成，请重试"
end

local UIShopController = Class.Define("UIShopController")
Class.Extend(UIShopController, UIController)

---【为什么 OnOpen 也要清回执】
---CacheOnClose 的窗口关掉后不是「销毁」，Model 是复用实例（不会再走 Ctor，
---_resultText 还留着上一轮「购入 ×5」的旧回执）。而 UIWindow:Refresh() 要求窗口
---已经 IsOpened（见 Framework/UI/Core/UIWindow.lua:439「not opened, cannot refresh」），
---所以「关掉再打开」走的是 Open 这条路径，而不是 Refresh —— 只在 OnRefresh 里清，
---重开面板时旧回执照样挂在那儿。两个入口都得先清再画。
function UIShopController:OnOpen()
	self._closed = false
	self._onlineGeneration = (self._onlineGeneration or 0) + 1
	self._onlinePending = false
	if not self.view or not self.model then
		print("[UIShopController] OnOpen: view/model not bound")
		return
	end
	self.model:ClearResult()
	self.model:SetPending(false)
	self:_refresh()
	self:_refreshOnline()
end

---窗口已经 Opened 时被再次刷新（UIManager 显式 Refresh）走这里。
---同样得清掉上一轮回执，否则面板一打开就挂着旧提示。
function UIShopController:OnRefresh()
	if not self.model then return end
	if not self._onlinePending then self.model:ClearResult() end
	self:_refresh()
	self:_refreshOnline()
end

function UIShopController:OnClose()
	self._closed = true
	self._onlineGeneration = (self._onlineGeneration or 0) + 1
	self._onlinePending = false
	if self.model then self.model:SetPending(false) end
end

function UIShopController:OnDestroy()
	self:OnClose()
	UIController.OnDestroy(self)
end

-- The service owns hydration even when this window has already closed.
function UIShopController:_requestOnline(send, onComplete)
	if self._closed or not self.model or not self.view or self._onlinePending then return end
	local generation, model, view = self._onlineGeneration, self.model, self.view
	local finished = false
	local function done(ok, reason)
		if finished then return end
		finished = true
		if self._closed or self._onlineGeneration ~= generation
			or self.model ~= model or self.view ~= view or not SaveData.IsOnline() then return end
		self._onlinePending = false
		model:SetPending(false)
		onComplete(ok == true, reason)
		self:_refresh()
	end
	local ok = pcall(function()
		local session = require "Game.Online.OnlineSession"
		if session.IsBusy() then done(false, "busy"); return end
		self._onlinePending = true
		model:SetPending(true)
		model:SetResult("请求处理中")
		self:_refresh()
		send(session, done)
	end)
	if not ok then done(false, "service_unavailable") end
end

function UIShopController:_refreshOnline()
	if not SaveData.IsOnline() then return end
	self:_requestOnline(function(session, done) session.Refresh(done) end, function(ok, reason)
		self.model:SetResult(ok and "" or onlineFeedback(reason))
	end)
end

-- =============================================================================
-- 渲染
-- =============================================================================

function UIShopController:_refresh()
	if self._closed or not self.view or not self.model then return end
	self.model:Refresh()
	self.view:Render(
		self.model,
		function() self:_onBuy(1) end,
		function() self:_onBuy(5) end,
		function() self:_onClose() end)
end

-- =============================================================================
-- 玩家意图
-- =============================================================================

---@param count number 张数（1 / 5）
function UIShopController:_onBuy(count)
	local model = self.model
	if self._closed or not model then return end
	if SaveData.IsOnline() then
		self:_requestOnline(function(session, done) session.Purchase(count, done) end, function(ok, reason)
			model:SetResult(ok and "购买已完成" or onlineFeedback(reason))
		end)
		return
	end

	local ok, text = model:Buy(count)
	Logger.Info("UIShop", "buy %d -> ok=%s | %s", count, tostring(ok), tostring(text))

	-- 余额与按钮文案都跟着存档变了，必须重画
	model:Refresh()
	self:_refresh()
end

function UIShopController:_onClose()
	self:OnClose()
	Logger.Info("UIShop", "close requested")

	local GameMain = require "Game.GameMain"
	local ui = GameMain.GetUIManager()
	if ui and ui.Close then
		ui:Close("ShopPanel", "Closed")
	else
		print("[UIShopController] UIManager not available, cannot close ShopPanel")
	end
end

return UIShopController
