--[[
=============================================================================
UILevelUpController.lua - 升级三选一 Controller
=============================================================================
Module:     Game/UI/Dungeon/UILevelUpController

Description:
	把本次候选交给 Model，再由 View 渲染；把玩家的点击转回 DungeonManager。

	刻意【不在 UI 层推进流程】（与 UIRunResultController / UIFloorEventController 同）：
	点选后只回调 DungeonManager:SelectLevelUpOption(index)，
	由它负责 Apply 选项、关面板、恢复战斗（Resume）。
	UI 一旦自己 Resume，就会出现「UI 与兜底路径各恢复一次」的双重恢复风险。

	调用链：
		BattleManager:OnExpGained -> OnLevelUp -> Pause
			-> DungeonManager:_onLevelUp(levels)
			-> ui:Open("LevelUpPopup", options, pending)
			-> UILevelUpController:OnOpen(options, pending)
			-> 玩家点第 index 项 -> DungeonManager:SelectLevelUpOption(index)
			-> Apply + Resume

	【类系统】Class.Define(name) + Class.Extend(X, UIController)。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local UILevelUpController = Class.Define("UILevelUpController")
Class.Extend(UILevelUpController, UIController)

---@param options table 候选列表
---@param pending number|nil 待选次数（含本次）
function UILevelUpController:OnOpen(options, pending)
	-- 框架按 UIWindow:Open 顺序已注入 self.view / self.model
	if not self.view or not self.model then
		print("[UILevelUpController] OnOpen: view/model not bound")
		return
	end

	self.model:SetOptions(options, pending)
	self.view:Render(self.model, function(index)
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if dm and dm.SelectLevelUpOption then
			dm:SelectLevelUpOption(index)
			return
		end

		-- 兜底：拿不到 DungeonManager 时也不能把玩家卡在已 Pause 的战斗里。
		-- （此时无人在本局上下文里，唯一能做的是把窗口关掉。）
		local ui = GameMain.GetUIManager()
		if ui and ui.Close then ui:Close("LevelUpPopup", "NoDungeonManager") end
	end)
end

return UILevelUpController
