--[[
=============================================================================
UILoginController.lua - 登录面板控制器（参考 ShaoNvClient_H02 UILoginCtrl）
=============================================================================
Module:     Game/UI/Login/UILoginController
Version:    2.0.0
Description:
	参考 H02 UILoginCtrl 的设计：
	- 防连点保护（lastLoginRequestTime）
	- 按钮事件集中绑定（5 个按钮）
	- 服务器选择 / 条款隐私 / 登录 / 关闭 四个操作入口
	- 加载状态管理
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"

local UILoginController = Class.Define("UILoginController")
Class.Extend(UILoginController, UIController)

function UILoginController:Ctor(model)
	CS.UnityEngine.Debug.Log("[LoginPanel] UILoginController:Ctor 被调用（控制器已创建）")
	self.super:Ctor(model)
	self._loginCoolDown = 3.0
	-- 初始化为负值，保证登录场景刚加载时首次点击立即生效，
	-- 避免 timeSinceLevelLoad < 3 时前几次点击被静默吞掉（表现为“点击没反应”）
	self._lastLoginRequestTime = -self._loginCoolDown
end

function UILoginController:OnCreate()
	self:_bindEvents()
end

function UILoginController:OnOpen()
	self._active = true
	local eventMgr = require("Framework.Framework").Event()
	if not self._statusHandle then
		self._statusHandle = eventMgr:AddListener("LoginPanel_OnStatus", function(status)
			if self._active then self:_onStatus(status) end
		end, self)
	end
	local online = require "Game.Online.OnlineSession"
	self:_onStatus({
		state = online.IsBusy() and "connecting" or "idle",
		serverId = online.IsSelected() and 2 or 1,
		serverName = online.IsSelected() and "本地联调" or "离线练习",
	})
end

function UILoginController:OnRefresh()
	self:OnOpen()
end

function UILoginController:OnClose()
	self._active = false
	if self._statusHandle then
		require("Framework.Framework").Event():RemoveListener(self._statusHandle)
		self._statusHandle = nil
	end
end

function UILoginController:OnDestroy()
	self:OnClose()
	UIController.OnDestroy(self)
end

function UILoginController:_onStatus(status)
	self.model:SetStatus(status)
	self.view:SetLoadingVisible(self.model:IsLoggingIn())
	self.view:SetServerText(self.model:GetStatusText())
	if not self.model:IsLoggingIn() then self._lastLoginRequestTime = -self._loginCoolDown end
end

function UILoginController:_bindEvents()
	CS.UnityEngine.Debug.Log("[LoginPanel][bind] _bindEvents 开始; Macro.SkipLogin=" .. tostring(Macro and Macro.SkipLogin))

	local loginBtn = self.view:GetLoginButton()
	CS.UnityEngine.Debug.Log("[LoginPanel][bind] loginBtn=" .. tostring(loginBtn))
	if loginBtn then
		CS.UnityEngine.Debug.Log("[LoginPanel][bind] loginBtn:GetUnityButton()=" .. tostring(loginBtn:GetUnityButton()))
		loginBtn:SetOnClick(function()
			self:_onLoginClick()
		end)
	end

	local svrBtn = self.view:GetServerSelectButton()
	if svrBtn then
		svrBtn:SetOnClick(function()
			self:_onServerSelectClick()
		end)
	end

	local closeBtn = self.view:GetCloseButton()
	if closeBtn then
		closeBtn:SetOnClick(function()
			self:_onCloseClick()
		end)
	end

	local termsBtn = self.view:GetTermsButton()
	if termsBtn then
		termsBtn:SetOnClick(function()
			self:_onTermsClick()
		end)
	end

	local privacyBtn = self.view:GetPrivacyButton()
	if privacyBtn then
		privacyBtn:SetOnClick(function()
			self:_onPrivacyClick()
		end)
	end
end

function UILoginController:_onLoginClick()
	if not self._active or self.model:IsLoggingIn() then return end
	CS.UnityEngine.Debug.Log("[LoginPanel] >>> _onLoginClick 进入")
	local now = CS.UnityEngine.Time.timeSinceLevelLoad
	if now - self._lastLoginRequestTime < self._loginCoolDown then
		print("[LoginPanel] Login request ignored: cooldown active")
		return
	end
	self._lastLoginRequestTime = now

	if not self.model:GetServerId() or self.model:GetServerId() <= 0 then
		print("[LoginPanel] No server selected, opening server list...")
		self:_onServerSelectClick()
		return
	end

	self.view:SetLoadingVisible(true)
	self.model:SetState("connecting")

	print(string.format(
		"[LoginPanel] Login request: server=%s(%d)",
		self.model:GetServerName() or "unknown",
		self.model:GetServerId() or 0
	))

	local FW = require "Framework.Framework"
	local eventMgr = FW.Event()
	eventMgr:Broadcast("LoginPanel_OnLogin", self.model:GetServerId(), self.model:GetServerName())
end

function UILoginController:_onServerSelectClick()
	if not self._active or self.model:IsLoggingIn() then return end
	print("[LoginPanel] Server select clicked")
	local FW = require "Framework.Framework"
	local eventMgr = FW.Event()
	eventMgr:Broadcast("LoginPanel_OnServerSelect")
end

function UILoginController:_onCloseClick()
	print("[LoginPanel] Close clicked")
	CS.UnityEngine.Application.Quit()
end

function UILoginController:_onTermsClick()
	print("[LoginPanel] Terms of Service clicked")
	local FW = require "Framework.Framework"
	local eventMgr = FW.Event()
	eventMgr:Broadcast("LoginPanel_OnShowTerms")
end

function UILoginController:_onPrivacyClick()
	print("[LoginPanel] Privacy Policy clicked")
	local FW = require "Framework.Framework"
	local eventMgr = FW.Event()
	eventMgr:Broadcast("LoginPanel_OnShowPrivacy")
end

function UILoginController:SetServerName(name)
	self.view:SetServerText(name)
end

function UILoginController:SetLoadingVisible(visible)
	self.view:SetLoadingVisible(visible)
end

return UILoginController
