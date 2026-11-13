--[[
=============================================================================
LoginScene.lua - 登录场景脚本（参考 ShaoNvClient_H02 LoginScene）
=============================================================================
Module:     Game/Scene/LoginScene
Version:    3.0.0
Description:
	对齐 ShaoNvClient_H02 的登录场景设计。

	生命周期（对齐 H02）:
		OnCreate  -> 预加载 LoginPanel Prefab 及相关资源
		OnComplete -> 打开 LoginPanel + 注册事件监听
		OnLeave   -> 清理资源 + 注销事件 + 关闭窗口

	登录流程（事件驱动，对齐 H02 UILoginCtrl -> HallConnector 模式）:
		- LoginPanel_OnLogin        -> 模拟登录流程
		- LoginPanel_OnServerSelect -> 打开服务器选择界面
		- LoginPanel_OnShowTerms    -> 打开服务条款
		- LoginPanel_OnShowPrivacy  -> 打开隐私政策

	核心设计（对齐 H02）:
		- Scene 不直接持有 Controller 引用，通过 EventManager 解耦
		- Login 按钮含防连点冷却（Controller 层实现）
		- 服务器未选时点击登录 -> 自动弹出服务器选择
		- 登录成功后切换 Home 场景
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"
local BaseScene = require "Game.Scene.BaseScene"

local LoginScene = {}
setmetatable(LoginScene, { __index = BaseScene })

local LoginState = {
	Idle = 0,
	Connecting = 1,
	Authenticating = 2,
	SelectingServer = 3,
	Entering = 4,
	Done = 5,
}

function LoginScene:OnCreate(sceneName, config)
	Logger.Info("LoginScene", "OnCreate: %s", sceneName)

	self._sceneName = sceneName
	self._config = config
	self._state = LoginState.Idle
	self._generation = (self._generation or 0) + 1
	self._active = true

	local preloadList = {
		"UI/Login/LoginPanel",
		"UI/Loading/LoadingPanel",
	}
	self._preloadResources = {}
	for _, path in ipairs(preloadList) do
		self._preloadResources[path] = true
	end

	Logger.Debug("LoginScene", "Registered %d preload resources", #preloadList)
end

function LoginScene:OnComplete(sceneName, config)
	Logger.Info("LoginScene", "OnComplete: %s", sceneName)

	self._state = LoginState.Idle

	self:_registerEvents()

	local GameMain = require "Game.GameMain"
	self._uiManager = GameMain.GetUIManager()

	Logger.Debug("LoginScene", "uiManager = %s", tostring(self._uiManager))

	if self._uiManager then
		Logger.Debug("LoginScene", "Calling uiManager:Open('LoginPanel')...")
		local ok, err = pcall(function()
			self._uiManager:Open("LoginPanel")
		end)
		if not ok then
			Logger.Error("LoginScene", "uiManager:Open FAILED: %s", tostring(err))
		else
			Logger.Debug("LoginScene", "LoginPanel opened via UIManager")
		end
	else
		Logger.Warn("LoginScene", "WARNING: UIManager not available")
	end
end

function LoginScene:OnLeave()
	Logger.Info("LoginScene", "OnLeave: cleaning up...")
	self._active = false
	self._generation = (self._generation or 0) + 1

	self:_unregisterEvents()

	if self._uiManager then
		self._uiManager:Close("LoginPanel", "SceneLeave")
	end

	self._state = LoginState.Idle
	self._uiManager = nil
	self._eventsRegistered = false
end

function LoginScene:_registerEvents()
	-- 幂等保护：OnComplete 可能被调用多次，重复注册会让监听器无限累积
	if self._eventsRegistered then return end
	self._eventsRegistered = true

	local FW = require "Framework.Framework"
	local eventMgr = FW.Event()

	-- 统一走 BaseScene:RegisterEvent（自动以 self 为 target，便于基类注销）
	local function listen(event, handler)
		self:RegisterEvent(eventMgr, event, handler)
	end

	listen("LoginPanel_OnLogin",        LoginScene._onLogin)
	listen("LoginPanel_OnServerSelect", LoginScene._onServerSelect)
	listen("LoginPanel_OnShowTerms",    LoginScene._onShowTerms)
	listen("LoginPanel_OnShowPrivacy",  LoginScene._onShowPrivacy)
end

function LoginScene:_unregisterEvents()
	local FW = require "Framework.Framework"
	local eventMgr = FW.Event()
	self:UnregisterAllEvents(eventMgr)
end

function LoginScene:_onLogin(serverId, serverName)
	if not self._active or self._state ~= LoginState.Idle then
		Logger.Warn("LoginScene", "Login already in progress, ignored")
		return
	end

	Logger.Info("LoginScene", "Login start: server=%s(%d)", serverName or "unknown", serverId or 0)
	local online = require "Game.Online.OnlineSession"
	if not online.IsSelected() then
		self:_onEnterGame()
		return
	end
	if not online.IsSupported() or online.IsBusy() then
		self:_loginFailed("online_unavailable")
		return
	end
	self._state = LoginState.Authenticating
	self:_publishStatus("connecting")
	local generation = self._generation
	local completed = false
	local function onLogin(ok, reason)
		if completed then return end
		completed = true
		if not self._active or generation ~= self._generation then return end
		if ok and online.IsReady() then
			self:_onEnterGame()
		else
			self:_loginFailed(reason or "online_not_ready")
		end
	end
	local ok, err = pcall(online.Login, online.GetAccountName(), onLogin)
	if not ok then onLogin(false, tostring(err)) end
end

function LoginScene:_onServerSelect()
	if not self._active or self._state ~= LoginState.Idle then return end
	local online = require "Game.Online.OnlineSession"
	local ok, reason
	if online.IsSelected() then
		ok, reason = online.SelectOffline()
	elseif online.IsSupported() then
		ok, reason = online.SelectOnline()
	else
		self:_publishStatus("idle", "online_unsupported")
		return
	end
	self:_publishStatus(ok and "idle" or "failed", reason)
end

function LoginScene:_publishStatus(state, reason)
	if not self._active then return end
	local online = require "Game.Online.OnlineSession"
	require("Framework.Framework").Event():Broadcast("LoginPanel_OnStatus", {
		state = state, reason = reason,
		serverId = online.IsSelected() and 2 or 1,
		serverName = online.IsSelected() and "本地联调" or "离线练习",
	})
end

function LoginScene:_loginFailed(reason)
	self._state = LoginState.Idle
	Logger.Warn("LoginScene", "Login failed: %s", tostring(reason))
	self:_publishStatus("failed", reason)
end

function LoginScene:_onShowTerms()
	Logger.Debug("LoginScene", "Terms of Service requested")
	Logger.Warn("LoginScene", "Terms UI not yet implemented (placeholder)")
end

function LoginScene:_onShowPrivacy()
	Logger.Debug("LoginScene", "Privacy Policy requested")
	Logger.Warn("LoginScene", "Privacy UI not yet implemented (placeholder)")
end

function LoginScene:_onEnterGame()
	self._state = LoginState.Entering
	self:_publishStatus("entering")
	local generation = self._generation
	Logger.Debug("LoginScene", "Entering game world...")

	local GameMain = require "Game.GameMain"
	local ok, err = pcall(GameMain.SwitchScene, "Home", function(success, reason)
		if not self._active or generation ~= self._generation then return end
		if success then
			self._state = LoginState.Done
			Logger.Info("LoginScene", "Successfully entered Home scene")
		else
			self:_loginFailed(reason or "scene_load_failed")
		end
	end)
	if not ok and self._active and generation == self._generation then self:_loginFailed(tostring(err)) end
end

function LoginScene:GetState()
	return self._state
end

function LoginScene:IsLoginDone()
	return self._state == LoginState.Done
end

return LoginScene
