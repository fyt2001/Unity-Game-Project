--[[
=============================================================================
UIGMModel.lua - GM 调试面板数据模型（S2）
=============================================================================
Module:     Game.UI.GM.UIGMModel

职责：只持有数据（命令表 / 分组 / 窗口状态），不碰 UI。
  - commands : Game.GM.GMCommands.VisibleList()（S7）已过滤掉 devOnly 命令后持有，
              release 包里 advanced.run_lua 连列表都不进；面板按 group / keyword 过滤
  - groups   : 由 commands 去重出的分组名（视图侧渲染「全部 + 各组」）
  - status   : 最近一次执行反馈（由 Controller 写、View 读）
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"
local GMCommands = require "Game.GM.GMCommands"

local UIGMModel = Class.Define("UIGMModel")
Class.Extend(UIGMModel, UIModel)

function UIGMModel:OnCreate()
	self.isCreated = true
	-- devOnly 门控（§12.1 第 1 层）：Model 持过滤后的表，View 渲染也走 VisibleList，
	-- 两边同源，release 包才不会漏出 advanced.run_lua
	self.commands = GMCommands.VisibleList()
	self.groups = {}
	local seen = {}
	for _, cmd in ipairs(self.commands) do
		local g = (cmd and cmd.group) or "其他"
		if not seen[g] then seen[g] = true; self.groups[#self.groups + 1] = g end
	end
	self.status = "就绪"
end

function UIGMModel:GetCommands()
	return self.commands or {}
end

function UIGMModel:GetGroups()
	return self.groups or {}
end

function UIGMModel:SetStatus(s)
	self.status = s or ""
end

function UIGMModel:GetStatus()
	return self.status or ""
end

return UIGMModel
