--[[
=============================================================================
UIFloorEventModel.lua - 层间事件弹窗 Model
=============================================================================
Module:     Game/UI/Dungeon/UIFloorEventModel

Description:
	事件弹窗本身【不持有】事件数据：事件实例与选择结果都在 DungeonManager 里。
	Model 只保存本次要展示的文案，避免 UI 层成为状态源。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UIFloorEventModel = Class.Define("UIFloorEventModel")
Class.Extend(UIFloorEventModel, UIModel)
local base = UIModel

---@param windowName string 由 UIWindowFactory 传入（ModelClass.New(window:GetName())）
function UIFloorEventModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self.title = ""
	self.body = ""
	self.options = {}     -- { {id, text, enabled}, ... }
end

---由 Controller 在打开时填充
function UIFloorEventModel:SetContent(title, body, options)
	self.title = title or ""
	self.body = body or ""
	self.options = options or {}
end

return UIFloorEventModel
