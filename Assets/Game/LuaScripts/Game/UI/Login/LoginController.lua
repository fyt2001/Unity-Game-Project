--[[
=============================================================================
LoginController.lua - 登录面板控制器
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIController = require "NewObject.Framework.UI.Core.UIController"

local LoginController = Class.Define("LoginController")
Class.Extend(LoginController, UIController)

function LoginController:Ctor(model)
    self.super:Ctor(model)
end

function LoginController:OnCreate()
    -- 绑定按钮事件
    local loginBtn = self.view:GetLoginButton()
    if loginBtn then
        loginBtn.onClick:AddListener(function()
            self:_onLoginClick()
        end)
    end

    local exitBtn = self.view:GetExitButton()
    if exitBtn then
        exitBtn.onClick:AddListener(function()
            self:_onExitClick()
        end)
    end
end

function LoginController:_onLoginClick()
    local account = self.view:GetAccount()
    local password = self.view:GetPassword()

    print(string.format("[LoginPanel] Login attempt: account=%s", account))

    self.model:SetAccount(account)
    self.model:SetPassword(password)

    -- 触发登录事件（由 LoginScene 监听处理）
    local FW = require "Framework.Framework"
    local eventMgr = FW.Event()
    eventMgr:Dispatch("LoginPanel_OnLogin", account, password)
end

function LoginController:_onExitClick()
    print("[LoginPanel] Exit clicked")
    CS.UnityEngine.Application.Quit()
end

return LoginController