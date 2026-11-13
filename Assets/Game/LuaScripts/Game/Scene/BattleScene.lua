--[[
=============================================================================
BattleScene.lua - 战斗场景脚本
=============================================================================
Module:     Game/Scene/BattleScene
Version:    1.0.0
Description:
	战斗场景（BattleScene.unity）的场景脚本。

	职责边界：本脚本【不负责启动战斗】。
	战斗由场景内的 HomeSceneBootstrapper（startBattle=true）在 Start() 中
	通过 GameMain.StartBattle 启动；本脚本唯一的职责是打开 BattleHudPanel，
	让摇杆与 HUD 能在战斗场景中生效。

	为什么必须打开 BattleHudPanel？
		摇杆是 BattleHudPanel 的 UI 子组件。UIBattleHudView:_bindJoystick() 会在面板打开时
		用 FindObjectOfType 找到场景中的 HomeSceneBootstrapper，并把摇杆交给它：
			UIBattleHudView:_bindJoystick -> bootstrapper:BindJoystick(joystick)
		之后 Bootstrapper 每帧轮询 GetOutput()，把输入转发给 Lua PlayerController。

		此前 SceneConfig.Battle.LuaScript 是 nil，SceneLoader 会直接跳过、
		没有任何脚本去打开战斗 UI，于是出现
		「进了战斗场景却没有摇杆、角色完全无法操作」的现象。

	Changelog:
		v1.0.0 - 初始版本：补齐战斗场景 UI（摇杆 + HUD）
		v1.1.0 - P2-3 战斗 HUD 归位：改开 BattleHudPanel（Game/UI/Battle/），
		         HomePanel 回归纯主城菜单，战斗不再反向依赖主城 UI
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"

local BattleScene = {}
BattleScene.__index = BattleScene

function BattleScene:OnCreate(sceneName, config)
	Logger.Info("BattleScene", "OnCreate: %s", sceneName)

	self._sceneName = sceneName
	self._config = config
	self._preloadResources = {}

	-- 登记战斗面板，让 SceneLoader 的预加载阶段把资源准备好
	self._preloadResources["UI/Battle/BattleHudPanel"] = true
	self._preloadResources["UI/Battle/PausePanel"] = true           -- P2-4
	self._preloadResources["UI/Battle/ExtractConfirmPopup"] = true   -- P2-4

	Logger.Debug("BattleScene", "Registered preload resources")
end

function BattleScene:OnComplete(sceneName, config)
	Logger.Info("BattleScene", "OnComplete: %s", sceneName)

	local GameMain = require "Game.GameMain"
	self._uiManager = GameMain.GetUIManager()

	-- 打开战斗 HUD。即便打开失败（如摇杆绑定到已销毁的跨场景 Bootstrapper 残引用
	-- 抛 NRE），也绝不允许中断下潜启动 —— 用 pcall 兜底。
	local okUI, uiErr = pcall(function() self:_openBattleUI() end)
	if not okUI then
		Logger.Error("BattleScene", "Open BattleHudPanel failed: %s", tostring(uiErr))
	end

	-- 下潜启动点：必须放在 _openBattleUI() 之后。
	-- BattleHudPanel 打开时 UIBattleHudView:_bindJoystick() 才会把摇杆绑定到场景内的
	-- Bootstrapper；在此之前开打，玩家将完全无法操作。
	-- 无待启动请求时（例如直接打开 BattleScene 按 Play）保持原行为：
	-- 由 Bootstrapper(startBattle=true) 自行起一场普通战斗。
	local ok, err = pcall(function()
		if GameMain.HasPendingDungeon and GameMain.HasPendingDungeon() then
			GameMain.StartPendingDungeon()
		end
	end)
	if not ok then
		Logger.Error("BattleScene", "Failed to start dungeon run: %s", tostring(err))
	end

	Logger.Info("BattleScene", "Battle scene ready (joystick + HUD)")
end

function BattleScene:OnLeave()
	Logger.Info("BattleScene", "OnLeave: cleaning up...")

	-- P2-4：这两个是战斗中随时可能开着的模态面板。场景都走了还留着，
	-- 下一场战斗复用实例时会带着上一局的回调与残留状态（同 OnRefresh 那类坑）。
	if self._uiManager then
		self._uiManager:Close("BattleHudPanel", "SceneLeave")
		self._uiManager:Close("PausePanel", "SceneLeave")
		self._uiManager:Close("ExtractConfirmPopup", "SceneLeave")
	end

	self._uiManager = nil
end

function BattleScene:_openBattleUI()
	if self._uiManager then
		-- 打开战斗 HUD 面板：UIBattleHudView 会自动把摇杆绑定到场景内的 Bootstrapper
		-- 战斗 HUD 不显示金币/宝石（那是主城面板的事），故无需传 Opening 参数。
		self._uiManager:Open("BattleHudPanel")
		Logger.Debug("BattleScene", "BattleHudPanel opened (joystick + battle HUD)")
	else
		Logger.Warn("BattleScene", "WARNING: UIManager not available")
	end
end

function BattleScene:GetSceneName()
	return self._sceneName
end

return BattleScene
