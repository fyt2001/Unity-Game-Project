--[[
=============================================================================
UIModStationController.lua - 配装面板（ModStation）Controller
=============================================================================
Module:     Game/UI/Mod/UIModStationController

Description:
	把玩家在配装面板上的点击翻译成 ModSystem 调用，再让 View 重画。

	【本 Controller 不做装配决策】
	- 点槽位：有选中卡 → 安装、替换或移动；无选中卡且槽已占用 → 卸下。
	- 点背包：只置选中态（Model:SetSelected），不改存档
	装 / 卸的结果一律由 ModSystem 内部 Commit 存档，这里不做二次落盘。

	【为什么装完要清选中】
	装上的卡若还留着选中态，玩家再点别的槽就会把同一张卡「瞬移」过去，
	看起来像复制粘贴。装上即清空选中，与 Warframe 手感一致。

	为什么卸载后也要清：同一张卡可能被拆到别的宿主，留着选中是脏状态。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"
local Logger = require "Framework.UI.Utils.Logger"
local ModSystem = require "Game.Mod.ModSystem"
local SaveData = require "Game.Save.SaveData"

local ONLINE_REASONS = {
	mod_not_found = "no_mod", invalid_host = "no_host", invalid_slot = "no_slot",
	capacity_exceeded = "over_capacity", insufficient_capacity = "over_capacity",
	duplicate_mod = "duplicate_mod", over_capacity = "over_capacity",
	category_mismatch = "category_mismatch", core_slot_only = "core_slot_only",
	core_mod_only = "core_mod_only", capacity_dependency = "capacity_dependency",
	no_mod = "no_mod", no_cfg = "no_cfg", no_slot = "no_slot", no_host = "no_host",
}

local UIModStationController = Class.Define("UIModStationController")
Class.Extend(UIModStationController, UIController)

function UIModStationController:OnOpen()
	self._closed = false
	self._onlineGeneration = (self._onlineGeneration or 0) + 1
	self._onlinePending = false
	if not self.view or not self.model then
		print("[UIModStationController] OnOpen: view/model not bound")
		return
	end
	self:_refresh()
	self:_refreshOnline()
end

---SingleTop 复用实例时 UIManager 走的是 Refresh 而不是 OnOpen，
---不实现的话第二次打开会和第一次一样（其实内容相同），但为一致性补上。
function UIModStationController:OnRefresh()
	self:_refresh()
	self:_refreshOnline()
end

function UIModStationController:OnClose()
	self._closed = true
	self._onlineGeneration = (self._onlineGeneration or 0) + 1
	self._onlinePending = false
end

function UIModStationController:OnDestroy()
	self:OnClose()
	UIController.OnDestroy(self)
end

function UIModStationController:_requestOnline(send, onComplete)
	if self._closed or not self.model or not self.view or self._onlinePending then return end
	local generation, model, view = self._onlineGeneration, self.model, self.view
	local finished = false
	local function done(ok, reason)
		if finished then return end
		finished = true
		if self._closed or self._onlineGeneration ~= generation
			or self.model ~= model or self.view ~= view or not SaveData.IsOnline() then return end
		self._onlinePending = false
		onComplete(ok == true, reason)
		self:_refresh()
	end
	local ok = pcall(function()
		local session = require "Game.Online.OnlineSession"
		if session.IsBusy() then done(false, "busy"); return end
		self._onlinePending = true
		self.model:SetFeedback(nil)
		self:_refresh()
		send(session, done)
	end)
	if not ok then done(false, "service_unavailable") end
end

function UIModStationController:_refreshOnline()
	if not SaveData.IsOnline() then return end
	self:_requestOnline(function(session, done) session.Refresh(done) end, function(ok, reason)
		if ok then
			self.model:SetFeedback(nil)
		else
			self.model:SetFeedback(ONLINE_REASONS[reason] or "save_failed")
		end
	end)
end

-- =============================================================================
-- 渲染（全量重画：背包节点数最多几十个，全量重建比增量 diff 更不容易出错）
-- =============================================================================

function UIModStationController:_refresh()
	if self._closed or not self.view or not self.model then return end
	self.model:Refresh()
	self.view:Render(
		self.model,
		function(index) self:_onTab(index) end,
		function(index) self:_onSlot(index) end,
		function(uid) self:_onBagItem(uid) end,
		function() self:_onClose() end)
end

-- =============================================================================
-- 玩家意图
-- =============================================================================

function UIModStationController:_onTab(index)
	local model = self.model
	if self._closed or self._onlinePending or not model then return end

	local tab = model:GetTabs()[index]
	if tab then model:SetHost(tab.host) end
	self:_refresh()
end

function UIModStationController:_onBagItem(uid)
	if self._closed or self._onlinePending or not self.model then return end
	self.model:SetSelected(uid)
	self:_refresh()
end

function UIModStationController:_onSlot(index)
	local model = self.model
	if self._closed or self._onlinePending or not model then return end

	local slot = model:GetSlots()[index]
	if not slot then return end

	local uid = model:GetSelected()
	if SaveData.IsOnline() then
		if not uid and slot.empty then
			model:SetFeedback("select_mod")
			self:_refresh()
			return
		end
		local host = model:GetHost()
		self:_requestOnline(function(session, done) session.Loadout(host, index, uid or 0, done) end,
			function(ok, reason)
				if ok then
					model:SetSelected(nil)
					model:SetFeedback(uid and "installed" or "uninstalled")
				else
					model:SetFeedback(ONLINE_REASONS[reason] or "save_failed")
				end
			end)
		return
	end
	local ok, reason
	if uid then
		ok, reason = ModSystem.Install(model:GetHost(), uid, index)
		if ok then model:SetSelected(nil) end
	elseif not slot.empty then
		ok, reason = ModSystem.Uninstall(model:GetHost(), index)
	else
		model:SetFeedback("select_mod")
		self:_refresh()
		return
	end
	model:SetFeedback(ok and (uid and "installed" or "uninstalled") or reason)

	model:Refresh()
	self:_refresh()
end

function UIModStationController:_onClose()
	self:OnClose()
	local model = self.model
	local host = (model and model:GetHost()) or "?"
	Logger.Info("UIModStation", "close requested (host=%s)", tostring(host))

	local GameMain = require "Game.GameMain"
	local ui = GameMain.GetUIManager()
	if ui and ui.Close then
		ui:Close("ModStationPanel", "Closed")
	else
		print("[UIModStationController] UIManager not available, cannot close ModStationPanel")
	end
end

return UIModStationController
