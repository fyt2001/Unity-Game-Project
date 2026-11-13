--[[
=============================================================================
UIRunResultController.lua - 结算面板 Controller
=============================================================================
Module:     Game/UI/Dungeon/UIRunResultController

Description:
	把 RunResult 明细交给 Model，再由 View 渲染；把玩家的「返回主城」点击
	转回 DungeonManager。

	刻意【不在 UI 层推进流程】：点确认后只是回调 DungeonManager:BackToHome()，
	由它负责关面板 + 切场景。UI 不做场景切换，避免出现「UI 触发切场景」
	这种跨层反向依赖。

	调用链：
		DungeonManager:_settle(outcome)
			-> ui:Open("RunResultPanel", result)
			-> UIRunResultController:OnOpen(result)
			-> 玩家点确认 -> DungeonManager:BackToHome()

	【类系统】与 UILoginController / UIFloorEventController 对齐：
	Class.Define(name) + Class.Extend(X, UIController)。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local UIRunResultController = Class.Define("UIRunResultController")
Class.Extend(UIRunResultController, UIController)

function UIRunResultController:OnOpen(result)
	-- 框架按 UIWindow:Open 顺序已注入 self.view / self.model
	if not self.view or not self.model then
		print("[UIRunResultController] OnOpen: view/model not bound")
		return
	end

	self.model:SetResult(result)
	self.view:Render(self.model, function()
		-- 点击「返回主城」：只回传意图，不在这里切场景（UI 层不反向驱动流程）。
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if self.model.result.online and self.model.result.settlementStatus ~= "confirmed" then
			if dm and dm.RetrySettlement then dm:RetrySettlement() end
			return
		end
		if dm and dm.BackToHome then
			dm:BackToHome()
		else
			-- 兜底：拿不到 DungeonManager 时也不能把玩家卡在结算面板
			local ui = GameMain.GetUIManager()
			if ui and ui.Close then ui:Close("RunResultPanel", "Confirmed") end
			GameMain.SwitchScene("Home")
		end
	end)
end

function UIRunResultController:OnRefresh(result)
	self:OnOpen(result)
end

return UIRunResultController
