--[[
=============================================================================
LoadingController.lua - 加载界面控制器（Prefab 模式）
=============================================================================
Module:     Game/UI/Loading/LoadingController
Version:    2.0.0
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local LoadingController = Class.Define("LoadingController")
Class.Extend(LoadingController, UIController)

function LoadingController:Ctor(model)
	self.super:Ctor(model)
end

function LoadingController:OnOpen(...)
end

---设置进度
function LoadingController:SetProgress(progress, text)
	if self.view and self.view.SetProgress then
		self.view:SetProgress(progress, text)
	end
end

---设置版本号
function LoadingController:SetVersion(version)
	if self.view and self.view.SetVersion then
		self.view:SetVersion(version)
	end
end

function LoadingController:OnClose() end

function LoadingController:OnDestroy()
	self.model = nil
	self.view = nil
end

return LoadingController