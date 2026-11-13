--[[
=============================================================================
UIFloorEventController.lua - 层间事件弹窗 Controller
=============================================================================
Module:     Game/UI/Dungeon/UIFloorEventController

Description:
	把 Model 的内容交给 View 渲染，并把玩家点击转发给 DungeonManager。

	刻意【不在 UI 层保存事件状态】：事件实例与选项都在 DungeonManager，
	UI 只是展示 + 回传索引，避免状态分散。

	类系统对齐 UILoginController：
	  Class.Define + Class.Extend(..., UIController)，
	  通过框架注入的 self.view / self.model 访问（与 UILoginController 一致）。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local UIFloorEventController = Class.Define("UIFloorEventController")
Class.Extend(UIFloorEventController, UIController)

function UIFloorEventController:OnOpen(title, body, options)
	-- 框架按 UIWindow:Open 顺序已注入 self.view / self.model
	if not self.view or not self.model then
		print("[UIFloorEventController] OnOpen: view/model not bound")
		return
	end

	self.model:SetContent(title, body, options)
	-- 关闭按钮回调用匿名闭包（与 onSelect 一致）：选择决策在 DungeonManager:AutoSelectFloorEvent，
	-- 这里只回传意图，不需要 self 状态
	self.view:Render(self.model, function(index)
		self:_onSelect(index)
	end, function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if dm and dm.AutoSelectFloorEvent then
			dm:AutoSelectFloorEvent()
		end
	end)
end

function UIFloorEventController:_onSelect(index)
	local GameMain = require "Game.GameMain"
	local dm = GameMain.GetDungeonManager()
	if dm and dm.SelectFloorEventOption then
		dm:SelectFloorEventOption(index)
	end
end

return UIFloorEventController
