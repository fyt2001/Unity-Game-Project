--[[
=============================================================================
UIExtractConfirmController.lua - 撤离二次确认 Controller
=============================================================================
Module:     Game/UI/Battle/UIExtractConfirmController

Description:
	把撤离预览交给 View，并把玩家的确认/取消意图回传 DungeonManager。

	【本 Controller 不做决策，也不碰资源】
		真正的 ConsumeReturnScroll 在 DungeonManager:ConfirmExtract() 里，
		经由 UseReturnScroll 的既有统一入口执行。UI 若在确认瞬间就把卷轴
		扣掉，一旦后续结算失败就会「卷轴没了、收益也没了」。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local UIExtractConfirmController = Class.Define("UIExtractConfirmController")
Class.Extend(UIExtractConfirmController, UIController)

---@param data table 撤离预览（DungeonManager:BuildExtractPreview() 的产物）
function UIExtractConfirmController:OnOpen(data)
	if not self.view or not self.model then
		print("[UIExtractConfirmController] OnOpen: view/model not bound")
		return
	end

	self.model:SetConfirmData(data)

	-- 匿名闭包（不用 self，避免 luacheck 的 unused argument 'self'）
	self.view:Render(self.model, function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if dm and dm.ConfirmExtract then
			dm:ConfirmExtract()
		end
	end, function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if dm and dm.CancelExtract then
			dm:CancelExtract("CancelButton")
		end
	end)
end

---SingleTop 复用实例时的兜底：复用走了 Refresh 会漏掉 OnOpen 的渲染，
-- 不补的话确认框会保留【上次】的预览数字 —— 那比没有预览更危险。
function UIExtractConfirmController:OnRefresh(data)
	self:OnOpen(data)
end

return UIExtractConfirmController
