--[[
=============================================================================
LoginModel.lua - 登录面板数据模型
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local LoginModel = Class.Define("LoginModel")
Class.Extend(LoginModel, UIModel)

function LoginModel:Ctor(windowName)
    self.super:Ctor(windowName)
    self.account = ""
    self.password = ""
    self.serverName = "默认服务器"
    self.isLoggingIn = false
end

function LoginModel:SetAccount(account)
    self.account = account or ""
end

function LoginModel:SetPassword(password)
    self.password = password or ""
end

function LoginModel:SetServer(serverName)
    self.serverName = serverName or "默认服务器"
end

function LoginModel:SetLoggingIn(value)
    self.isLoggingIn = value
end

return LoginModel