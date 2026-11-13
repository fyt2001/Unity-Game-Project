--[[
=============================================================================
GameMain.lua - 游戏主入口（参考 ShaoNvClient_H02 GameMain.lua）
=============================================================================
Module:     Game/GameMain
Version:    3.0.0

Description:
	框架初始化 + 核心管理器创建。
	启动阶段进度由 C# GameLaunch 的 ProgressSlider 驱动。

Changelog:
	v3.0.0 - 启动 Loading 回归 C# 驱动（参考旧项目），Lua 层 Loading 仅用于场景切换
	v2.0.0 - 引用计数 Loading 模式
	v1.0.0 - 初始版本
=============================================================================
]]

-- C# 类型全局别名（Unity_Text / Unity_TMP_Text / Unity_Button / Unity_Slider /
-- Game_VirtualJoystick / Game_HomeSceneBootstrapper / Game_TopDownCameraFollow ...）
--
-- 【重要】必须在任何使用这些别名的 UI 模块之前加载。
-- 此前 Common/Define.lua 从未被任何模块 require，导致所有别名为 nil：
--   UILoginView:_getTextComponent() 中执行 typeof(Unity_Text) 即 typeof(nil)，
--   直接抛 "attempt to index a nil value (local 't')"，LoginPanel 永远打不开。
--   UIHomeView 的摇杆桥接同样依赖 Game_VirtualJoystick，也会一并失效。
require "Common.Define"

local FW = require "Framework.Framework"
local Logger = require "Framework.UI.Utils.Logger"

local GameMain = {}

local eventMgr, timerMgr, updateMgr, uiManager, battleManager, loadingManager, sceneLoader
-- uiResourceProvider：UI 面板资源提供者（AssetBundleProvider / ResourcesProvider）。
-- 暴露给业务 View 复用同一份缓存（如 UIGMView 取 GM item prefab），
-- 避免绕开 provider 直连 Resources 导致 AB 侧资源取不到。
local uiResourceProvider
local dungeonManager, pendingDungeonConfig
local dungeonStartPending = false
local sceneGeneration = 0
local startingDungeonBattle = false

local function GetOnlineSession()
	return require "Game.Online.OnlineSession"
end

-- =============================================================================
-- 私有：UI 窗口注册
-- =============================================================================

local function _registerUIWindows(uiManager)
	-- 登录面板
	local RegisterLoginPanel = require "Game.UI.Login.RegisterLoginPanel"
	RegisterLoginPanel(uiManager)

	-- 主城面板（P2-3 起只剩主城菜单：玩家信息 / 货币 / 战斗按钮 / 商店按钮 / 摇杆）
	local RegisterHomePanel = require "Game.UI.Home.RegisterHomePanel"
	RegisterHomePanel(uiManager)

	-- 配装面板（P3-1）：主城点「配装」打开，装 / 卸 Mod + 看派生属性
	local RegisterModStationPanel = require "Game.UI.Mod.RegisterModStationPanel"
	RegisterModStationPanel(uiManager)

	-- 商店面板（P3-2）：主城点「商店」打开，金币买随机 Mod
	local RegisterShopPanel = require "Game.UI.Shop.RegisterShopPanel"
	RegisterShopPanel(uiManager)

	-- 战斗 HUD 面板（P2-3）：HP 条 / 等级 / 回城卷轴 / 摇杆
	-- 原先这些控件连同采样逻辑都塞在 HomePanel 里，主城 Controller 反向依赖战斗层。
	local RegisterBattleHudPanel = require "Game.UI.Battle.RegisterBattleHudPanel"
	RegisterBattleHudPanel(uiManager)

	-- 暂停菜单（P2-4）：战斗暂停时的本局快照 + 撤离入口
	local RegisterPausePanel = require "Game.UI.Battle.RegisterPausePanel"
	RegisterPausePanel(uiManager)

	-- 撤离二次确认（P2-4）：卷轴是本局唯一稀缺资源，误触毁一局，必须有止损口
	local RegisterExtractConfirmPopup = require "Game.UI.Battle.RegisterExtractConfirmPopup"
	RegisterExtractConfirmPopup(uiManager)

	-- 层间事件弹窗（P8）
	local RegisterFloorEventPopup = require "Game.UI.Dungeon.RegisterFloorEventPopup"
	RegisterFloorEventPopup(uiManager)

	-- 结算面板（P2-1）：撤离 / 阵亡后展示本局收益，确认再回主城
	local RegisterRunResultPanel = require "Game.UI.Dungeon.RegisterRunResultPanel"
	RegisterRunResultPanel(uiManager)

	-- 升级三选一弹窗（P2-2）：每次升级让玩家自己选强化，而不是静默代选
	local RegisterLevelUpPopup = require "Game.UI.Dungeon.RegisterLevelUpPopup"
	RegisterLevelUpPopup(uiManager)

	-- GM 调试面板（悬浮入口在 Game.GM.GMUI，面板本体为框架窗口）
	local RegisterGM = require "Game.UI.GM.RegisterGM"
	RegisterGM(uiManager)
end

-- =============================================================================
-- 热更静默下载（对齐 H02 GameMain 的 WebDownLoadManager 调用）
-- 注意: CS.WebDownLoadManager 为新项目刚对齐的类，需 XLua 重新 Generate Code 后才能
--       从 Lua 访问；未生成前 CS.WebDownLoadManager 为 nil，这里用 pcall 容错，不影响启动。
-- =============================================================================

local function WebFileDownLoaded(bundleName)
	Logger.Info("GameMain", "Hotfix bundle downloaded: %s", tostring(bundleName))
end

local function WebFileDownLoadOne(path)
	Logger.Debug("GameMain", "Hotfix file downloaded: %s", tostring(path))
end

local function WebFileDownLoadSave()
	Logger.Debug("GameMain", "Hotfix manifest saved")
end

local function InitSilentDownload()
	local ok, err = pcall(function()
		local wm = CS.WebDownLoadManager.Get()
		if not wm then return end
		wm:Init()
		local total = wm:GetTotalDownLoad()
		if total == nil or total <= 0 then
			Logger.Debug("GameMain", "No hotfix files to download")
			return
		end
		wm:SetLuaCall(WebFileDownLoaded, WebFileDownLoadOne)
		wm:SetSaveLuaCall(WebFileDownLoadSave)
		wm:Resume()
		Logger.Info("GameMain", "Silent hotfix download started, total=%.0f", total)
	end)
	if not ok then
		Logger.Warn("GameMain", "InitSilentDownload failed: %s", tostring(err))
	end
end

-- =============================================================================
-- 初始化
-- =============================================================================

local function Init(self)
	Logger.Info("GameMain", "Framework v%s initializing...", FW.Version)

	eventMgr = FW.Event()
	timerMgr = FW.Timer()
	updateMgr = FW.Update()

	-- UI 资源加载方式：默认 AssetBundle（与 H02 对齐，按需加载 + 可热更）。
	-- 置 false 可退回 Resources 内置资源区，仅用于排查 AB 侧问题。
	local USE_ASSET_BUNDLE_FOR_UI = true

	if USE_ASSET_BUNDLE_FOR_UI then
		local AssetBundleProvider = require "Game.UI.Provider.AssetBundleProvider"
		uiResourceProvider = AssetBundleProvider.New()
	else
		local ResourcesProvider = require "Game.UI.Provider.ResourcesProvider"
		uiResourceProvider = ResourcesProvider.New()
	end
	uiManager = FW.CreateUIManager({ resourceProvider = uiResourceProvider })
	Logger.Info("GameMain", "UI provider = %s",
		USE_ASSET_BUNDLE_FOR_UI and "AssetBundleProvider" or "ResourcesProvider")

	-- 注册所有 UI 窗口
	_registerUIWindows(uiManager)

	-- 中文字体：把 CJKFullSDF 注册为 TMP 全局 fallback（幂等）
	-- 工程原字体缺汉字（LiberationSans 0 个；旧 CJK SDF 仅 131 个，UI 实际需要 1170 个），
	-- 注册后所有 TMP 缺字自动回落取字，无需逐个 prefab 改字体。详见 Framework/UI/Utils/CJKFont.lua
	local okFont, errFont = pcall(function()
		require("Framework.UI.Utils.CJKFont").InstallGlobalFallback()
	end)
	if not okFont then
		Logger.Warn("GameMain", "CJK font fallback init failed: %s", tostring(errFont))
	end

	-- 热更静默下载（对齐 H02）：有待下载项则后台拉取，无则自动跳过
	InitSilentDownload()

	-- 初始化 LoadingManager（仅用于场景切换等运行时Loading）
	loadingManager = require("Game.UI.Loading.LoadingManager").GetInstance()
	loadingManager:Init(uiManager)

	-- 【重要】这里【不要】再注册 battleManager:Update(dt)。
	-- BattleManager:Start() 内部已自行注册到 UpdateManager（_registerUpdate，幂等）。
	-- 若此处再注册一次，战斗每帧会被驱动两次（elapsedTime 双倍累加），
	-- 表现为「楼层时长被砍半、敌人移动/攻速翻倍」。驱动源保持唯一。

	-- 加载存档（P5）：读不到/损坏则回落新档，绝不让存档问题阻断启动
	local ok, err = pcall(function()
		local SaveManager = require "Game.Save.SaveManager"
		local SaveData = require "Game.Save.SaveData"
		local loaded = SaveManager.Load()
		if loaded then
			SaveData.current = loaded
			Logger.Info("GameMain", "Save loaded")
		else
			Logger.Info("GameMain", "No valid save, using a new one")
		end
	end)
	if not ok then
		Logger.Error("GameMain", "Load save failed: %s", tostring(err))
	end

	-- 初始化 GM 调试工具（悬浮入口 + 数据驱动作弊面板；Debug 默认开，Release 可持久化启用）
	local okGM, errGM = pcall(function()
		require("Game.GM.GMUI").Init()
	end)
	if not okGM then
		Logger.Warn("GameMain", "GM init failed: %s", tostring(errGM))
	end

	Logger.Info("GameMain", "Framework initialized successfully")
end

-- =============================================================================
-- Loading API
-- =============================================================================

local function ShowLoading(text)
	if loadingManager then
		local token = loadingManager:BeginLoading("Runtime", 300, 30000)
		if text then loadingManager:SetProgress(0, text) end
		return token
	end
end

local function HideLoading(token)
	if loadingManager then
		if token then loadingManager:EndLoading(token)
		else loadingManager:ForceClearAll() end
	end
end

local function StartLoadingTask(name, delayMs, forceEndMs)
	return loadingManager and loadingManager:BeginLoading(name, delayMs, forceEndMs)
end

local function StopLoadingTask(token)
	if loadingManager then loadingManager:EndLoading(token) end
end

-- =============================================================================
-- 场景
-- =============================================================================

local function SwitchScene(sceneName, onComplete)
	if sceneLoader and sceneLoader:IsSwitching() then
		if onComplete then onComplete(false, "scene_busy") end
		return false, "scene_busy"
	end
	if dungeonManager and dungeonManager:HasUnconfirmedSettlement() then
		if onComplete then onComplete(false, "settlement_unconfirmed") end
		return false, "settlement_unconfirmed"
	end
	if not sceneLoader then
		sceneLoader = require("Game.Scene.SceneLoader").GetInstance()
		local cfg = require "Game.Scene.SceneConfig"
		sceneLoader:RegisterConfigs(cfg)
	end
	sceneGeneration = sceneGeneration + 1
	dungeonStartPending = false

	-- 下潜 Run 一并清理：先于 battleManager 销毁，好让 Dispose 解掉 bm.onBattleEnd 钩子，
	-- 避免 BattleManager 在 Destroy 过程中回调到已废弃的 DungeonManager。
	if dungeonManager then
		dungeonManager:Dispose()
		dungeonManager = nil
		Logger.Info("GameMain", "Dungeon run disposed on scene switch")
	end

	-- 离开战斗场景时清理战斗：battleManager 是纯 Lua 对象、注册在 UpdateManager 上，
	-- Unity 场景卸载不会自动销毁它。若不清，切回主城后残留的 Update 回调会访问
	-- 已销毁的玩家/子系统而报错。战斗只在 BattleScene 创建，这里统一在切换时销毁即可。
	if battleManager then
		battleManager:Destroy()
		battleManager = nil
		Logger.Info("GameMain", "Battle stopped on scene switch")
	end

	sceneLoader:SwitchScene(sceneName, onComplete)
	return true
end

local function GetCurrentScene()
	return sceneLoader and sceneLoader:GetCurrentScene()
end

-- =============================================================================
-- 游戏启动（由 C# XLuaManager.StartGame 调用）
-- =============================================================================

local function StartGame()
	Logger.Info("GameMain", "StartGame - transitioning to first scene...")

	local ok, err = pcall(function()
		if not sceneLoader then
			sceneLoader = require("Game.Scene.SceneLoader").GetInstance()
			local cfg = require "Game.Scene.SceneConfig"
			sceneLoader:RegisterConfigs(cfg)
			Logger.Debug("GameMain", "SceneLoader initialized, configs registered")
		end

		Logger.Debug("GameMain", "Calling SwitchScene('Login')...")
		sceneLoader:SwitchScene("Login", function(success)
			if success then
				Logger.Info("GameMain", "Login scene loaded successfully")
			else
				Logger.Error("GameMain", "ERROR: Failed to load Login scene")
			end
		end)
	end)

	if not ok then
		Logger.Error("GameMain", "StartGame ERROR: " .. tostring(err))
	end
end

-- =============================================================================
-- 战斗
-- =============================================================================

local function StartBattle(config)
	local online = GetOnlineSession()
	if online.IsSelected() and not (startingDungeonBattle and online.IsReady()
		and dungeonManager and dungeonManager.runData
		and dungeonManager.runData.onlineRunId == online.GetRunId()) then
		Logger.Warn("GameMain", "Direct online battle start denied")
		return false, "online_run_required"
	end
	Logger.Info("GameMain", "Starting battle...")
	if not battleManager then
		local BM = require "Game.Battle.BattleManager"
		battleManager = BM.New()
		battleManager:Init(config)
		battleManager:Start()
	end
	return true
end

-- =============================================================================
-- 下潜（Dungeon Run）
-- =============================================================================

---请求开始一局下潜：切到战斗场景并标记「待启动」
-- 真正的 StartRun 放在 BattleScene:OnComplete 执行——必须等 HomePanel 打开、
-- 摇杆绑定到 Bootstrapper 之后再开打，否则玩家进场景无法操作。
local function StartDungeonRun(config)
	if dungeonStartPending or pendingDungeonConfig or dungeonManager
		or (sceneLoader and sceneLoader:IsSwitching()) then
		return false, "run_busy"
	end
	local online = GetOnlineSession()
	if online.IsSelected() and (not online.IsReady() or online.IsBusy()) then
		return false, "online_not_ready"
	end
	local runConfig = {}
	for key, value in pairs(config or {}) do runConfig[key] = value end
	runConfig.onlineRunId = nil
	dungeonStartPending = true
	local generation = sceneGeneration
	local completed = false
	local function startScene(ok, reason, runId)
		if completed then return end
		completed = true
		if generation ~= sceneGeneration then return end
		dungeonStartPending = false
		if not ok then
			Logger.Warn("GameMain", "Run start failed: %s", tostring(reason))
			return
		end
		if online.IsSelected() then
			if not online.IsReady() or not runId or runId ~= online.GetRunId() then
				Logger.Warn("GameMain", "Run start rejected: server run mismatch")
				return
			end
			runConfig.onlineRunId = runId
		end
		pendingDungeonConfig = runConfig
		local accepted = SwitchScene("Battle", function(success)
			if not success then
				pendingDungeonConfig = nil
				Logger.Error("GameMain", "Failed to load Battle scene for dungeon run")
			end
		end)
		if accepted == false then pendingDungeonConfig = nil end
	end
	if online.IsSelected() then
		local ok, err = pcall(online.StartRun, startScene)
		if not ok then startScene(false, tostring(err)) end
	else
		startScene(true)
	end
	return true
end

---是否存在待启动的下潜请求
local function HasPendingDungeon()
	return pendingDungeonConfig ~= nil
end

---启动待处理的下潜（由 BattleScene:OnComplete 调用）
local function StartPendingDungeon()
	if not pendingDungeonConfig then return end

	local config = pendingDungeonConfig
	pendingDungeonConfig = nil

	if not dungeonManager then
		local DM = require "Game.Dungeon.DungeonManager"
		dungeonManager = DM.New()
	end

	Logger.Info("GameMain", "Starting dungeon run...")
	startingDungeonBattle = true
	local ok, accepted, reason = pcall(dungeonManager.StartRun, dungeonManager, config)
	startingDungeonBattle = false
	if not ok or accepted == false then
		Logger.Error("GameMain", "Dungeon start failed: %s", tostring(ok and reason or accepted))
		dungeonManager:Dispose()
		dungeonManager = nil
		return false
	end
	return true
end

local function GetDungeonManager() return dungeonManager end

-- =============================================================================
-- Getters
-- =============================================================================

local function GetUIManager()    return uiManager end
local function GetUIResourceProvider() return uiResourceProvider end
local function GetLoadingManager() return loadingManager end
local function GetSceneLoader()  return sceneLoader end
local function GetEventManager() return eventMgr end
local function GetTimerManager() return timerMgr end
local function GetUpdateManager() return updateMgr end
local function GetBattleManager() return battleManager end

-- =============================================================================
-- 生命周期
-- =============================================================================

local shutdownStarted = false
local function Shutdown()
	if shutdownStarted then return end
	shutdownStarted = true
	pcall(function() GetOnlineSession().Shutdown() end)
	sceneGeneration = sceneGeneration + 1
	dungeonStartPending = false
	pendingDungeonConfig = nil
	-- 退出前落盘（P5）
	pcall(function()
		local SaveData = require "Game.Save.SaveData"
		SaveData.Commit()
	end)

	if dungeonManager then dungeonManager:Dispose(); dungeonManager = nil end
	if battleManager then battleManager:Destroy(); battleManager = nil end
	if loadingManager then loadingManager:ForceClearAll(); loadingManager:Reset() end
	if uiManager then uiManager:Shutdown() end
	if uiResourceProvider and uiResourceProvider.Dispose then uiResourceProvider:Dispose() end
	Logger.Info("GameMain", "Shutdown complete")
end

local function OnLevelWasLoaded() end

local function OnApplicationFocus(isFocus) end

local function OnApplicationQuit()
	Shutdown()
end

-- =============================================================================
-- GameMain 公共接口（其它一律为私有，只能在本模块访问）
-- =============================================================================

GameMain.Init = Init
GameMain.StartGame = StartGame
GameMain.StartBattle = StartBattle
GameMain.SwitchScene = SwitchScene
GameMain.StartDungeonRun = StartDungeonRun
GameMain.HasPendingDungeon = HasPendingDungeon
GameMain.StartPendingDungeon = StartPendingDungeon
GameMain.GetCurrentScene = GetCurrentScene
GameMain.ShowLoading = ShowLoading
GameMain.HideLoading = HideLoading
GameMain.StartLoadingTask = StartLoadingTask
GameMain.StopLoadingTask = StopLoadingTask
GameMain.GetUIManager = GetUIManager
GameMain.GetUIResourceProvider = GetUIResourceProvider
GameMain.GetLoadingManager = GetLoadingManager
GameMain.GetSceneLoader = GetSceneLoader
GameMain.GetEventManager = GetEventManager
GameMain.GetTimerManager = GetTimerManager
GameMain.GetUpdateManager = GetUpdateManager
GameMain.GetBattleManager = GetBattleManager
GameMain.GetDungeonManager = GetDungeonManager
GameMain.GetOnlineSession = GetOnlineSession
GameMain.OnLevelWasLoaded = OnLevelWasLoaded
GameMain.OnApplicationFocus = OnApplicationFocus
GameMain.OnApplicationQuit = OnApplicationQuit
GameMain.Shutdown = Shutdown

return GameMain
