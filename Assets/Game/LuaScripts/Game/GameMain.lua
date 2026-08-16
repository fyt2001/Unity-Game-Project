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

local FW = require "Framework.Framework"

local GameMain = {}

local eventMgr, timerMgr, updateMgr, uiManager, battleManager, loadingManager, sceneLoader

function GameMain.Init()
    print(string.format("[GameMain] Framework v%s initializing...", FW.Version))

    eventMgr = FW.Event()
    timerMgr = FW.Timer()
    updateMgr = FW.Update()

    uiManager = FW.CreateUIManager()

    -- 初始化 LoadingManager（仅用于场景切换等运行时Loading）
    loadingManager = require("Game.UI.Loading.LoadingManager").GetInstance()
    loadingManager:Init(uiManager)

    updateMgr:AddUpdate(function(dt)
        if battleManager then battleManager:Update(dt) end
    end)

    print("[GameMain] Framework initialized successfully")
end

-- =============================================================================
-- Loading API（仅用于场景切换等运行时场景）
-- =============================================================================

function GameMain.ShowLoading(text)
    if loadingManager then
        local token = loadingManager:BeginLoading("Runtime", 300, 30000)
        if text then loadingManager:SetProgress(0, text) end
        return token
    end
end

function GameMain.HideLoading(token)
    if loadingManager then
        if token then loadingManager:EndLoading(token)
        else loadingManager:ForceClearAll() end
    end
end

function GameMain.StartLoadingTask(name, delayMs, forceEndMs)
    return loadingManager and loadingManager:BeginLoading(name, delayMs, forceEndMs)
end

function GameMain.StopLoadingTask(token)
    if loadingManager then loadingManager:EndLoading(token) end
end

-- =============================================================================
-- 场景
-- =============================================================================

function GameMain.SwitchScene(sceneName, onComplete)
    if not sceneLoader then
        sceneLoader = require("Game.Scene.SceneLoader").GetInstance()
        local cfg = require "Game.Scene.SceneConfig"
        sceneLoader:RegisterConfigs(cfg)
    end
    sceneLoader:SwitchScene(sceneName, onComplete)
end

function GameMain.GetCurrentScene()
    return sceneLoader and sceneLoader:GetCurrentScene()
end

-- =============================================================================
-- 战斗
-- =============================================================================

function GameMain.StartBattle(config)
    print("[GameMain] Starting battle...")
    if not battleManager then
        local BM = require "Game.Battle.BattleManager"
        battleManager = BM.New()
        battleManager:Init(config)
        battleManager:Start()
    end
end

-- =============================================================================
-- Getters
-- =============================================================================

function GameMain.GetUIManager()    return uiManager end
function GameMain.GetLoadingManager() return loadingManager end
function GameMain.GetSceneLoader()  return sceneLoader end
function GameMain.GetEventManager() return eventMgr end
function GameMain.GetTimerManager() return timerMgr end
function GameMain.GetUpdateManager() return updateMgr end
function GameMain.GetBattleManager() return battleManager end

-- =============================================================================
-- 生命周期
-- =============================================================================

function GameMain.OnLevelWasLoaded() end

function GameMain.OnApplicationFocus(isFocus) end

function GameMain.OnApplicationQuit()
    GameMain.Shutdown()
end

function GameMain.Shutdown()
    if battleManager then battleManager:Destroy(); battleManager = nil end
    if loadingManager then loadingManager:ForceClearAll(); loadingManager:Reset() end
    if uiManager then uiManager:CloseAll("Shutdown") end
    print("[GameMain] Shutdown complete")
end

return GameMain
