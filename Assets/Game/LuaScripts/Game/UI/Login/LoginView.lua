--[[
=============================================================================
LoginView.lua - 登录面板视图
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIView = require "NewObject.Framework.UI.Core.UIView"

local LoginView = Class.Define("LoginView")
Class.Extend(LoginView, UIView)

function LoginView:OnCreate()
    local tr = self.gameObject.transform
    if not tr then return end

    -- 绑定 UI 组件引用（Find 找不到时返回 nil，安全降级）
    local bgTr = tr:Find("Background")
    if bgTr then self._bgImg = bgTr:GetComponent(typeof(CS.UnityEngine.UI.Image)) end

    local formTr = tr:Find("LoginForm")
    if formTr then
        local accTr = formTr:Find("Input_Account")
        if accTr then self._accountInput = accTr:GetComponent(typeof(CS.UnityEngine.UI.InputField)) end

        local pwdTr = formTr:Find("Input_Password")
        if pwdTr then self._passwordInput = pwdTr:GetComponent(typeof(CS.UnityEngine.UI.InputField)) end

        local btnTr = formTr:Find("Btn_Login")
        if btnTr then self._loginBtn = btnTr:GetComponent(typeof(CS.UnityEngine.UI.Button)) end
    end

    local exitTr = tr:Find("Btn_Exit")
    if exitTr then self._exitBtn = exitTr:GetComponent(typeof(CS.UnityEngine.UI.Button)) end
end

function LoginView:OnOpen(account, serverName)
    if self._accountInput and account then
        self._accountInput.text = account
    end
end

function LoginView:GetAccount()
    return self._accountInput and self._accountInput.text or ""
end

function LoginView:GetPassword()
    return self._passwordInput and self._passwordInput.text or ""
end

function LoginView:GetLoginButton()
    return self._loginBtn
end

function LoginView:GetExitButton()
    return self._exitBtn
end

return LoginView