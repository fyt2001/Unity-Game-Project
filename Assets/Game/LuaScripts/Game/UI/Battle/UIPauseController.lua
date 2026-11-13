--[[
=============================================================================
UIPauseController.lua - 暂停菜单 Controller
=============================================================================
Module:     Game/UI/Battle/UIPauseController

Description:
	把 DungeonManager 给的本局快照交给 View 渲染，并把玩家意图回传。

	【本 Controller 不做任何决策】
		- 「继续」→ dm:ResumeGame(reason)：由 DungeonManager 决定是否真的 Resume
		- 「撤离」→ dm:RequestExtract()：由 DungeonManager 走二次确认
	UI 层同样不知道战斗是怎么暂停的，避免两处各写一份恢复逻辑。

	类系统对齐 UIFloorEventController：Class.Define + Class.Extend(..., UIController)。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local UIPauseController = Class.Define("UIPauseController")
Class.Extend(UIPauseController, UIController)

---@param snapshot table 本局快照（DungeonManager:GetPauseSnapshot() 的产物）
function UIPauseController:OnOpen(snapshot)
	if not self.view or not self.model then
		print("[UIPauseController] OnOpen: view/model not bound")
		return
	end

	self.model:SetSnapshot(snapshot)

	-- 三个回调一律写成匿名闭包：函数体不用 self，写成冒号方法会被
	-- luacheck 判 unused argument 'self'。决策全在 DungeonManager 侧。
	self.view:Render(self.model, function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if dm and dm.ResumeGame then
			dm:ResumeGame("ResumeButton")
		end
	end, function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if dm and dm.RequestExtract then
			dm:RequestExtract()
		end
	end)
end

---SingleTop 复用实例时 UIManager 可能走 Refresh 而不是 OnOpen。
-- 不实现的话，第二次暂停会展示【上一场】的快照（层数/击杀/卷轴全是旧值）。
function UIPauseController:OnRefresh(snapshot)
	self:OnOpen(snapshot)
end

return UIPauseController
