--[[
=============================================================================
UILoginModel.lua - 登录面板数据模型（参考 ShaoNvClient_H02 UILoginModel）
=============================================================================
Module:     Game/UI/Login/UILoginModel
Version:    2.0.0
Description:
	存储登录面板的运行时数据：
	- 服务器信息（对齐 H02 ClientData.login_server_id / historyLoginServers）
	- 登录状态
	- 版本号信息
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UILoginModel = Class.Define("UILoginModel")
Class.Extend(UILoginModel, UIModel)

function UILoginModel:Ctor(windowName)
	self.super:Ctor(windowName)
	self.serverId = 1
	self.serverName = "离线模式"
	self.state = "idle"
	self.isLoggingIn = false
	self.reason = nil
end

function UILoginModel:SetServer(serverId, serverName)
	self.serverId = serverId
	self.serverName = serverName or ("Server " .. tostring(serverId))
end

function UILoginModel:GetServerId()
	return self.serverId
end

function UILoginModel:GetServerName()
	return self.serverName
end

function UILoginModel:SetState(state)
	self.state = state
	self.isLoggingIn = (state == "connecting" or state == "entering")
end

function UILoginModel:SetStatus(status)
	status = status or {}
	if status.serverId then self:SetServer(status.serverId, status.serverName) end
	self.reason = status.reason
	self:SetState(status.state or "idle")
end

function UILoginModel:GetStatusText()
	if self.state == "connecting" then return self.serverName .. " · 正在登录" end
	if self.state == "entering" then return self.serverName .. " · 正在进入" end
	if self.state == "failed" then return self.serverName .. " · 失败，请重试" end
	if self.reason == "online_unsupported" then return "离线模式 · 联网仅限编辑器" end
	return self.serverName
end

function UILoginModel:GetState()
	return self.state
end

function UILoginModel:IsLoggingIn()
	return self.isLoggingIn
end

return UILoginModel
