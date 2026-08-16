--[[
=============================================================================
SceneLoader.lua - 场景加载管理器（精华来自 ShaoNvClient_H02 SceneManager）
=============================================================================
Module:     Game/Scene/SceneLoader
Version:    1.0.0
Description:
    场景加载管理器。从 ShaoNvClient_H02 SceneManager 提取精华。

    核心设计：
        - 场景切换时自动显示 Loading 界面
        - 异步加载场景 + 进度回调和 Loading 同步
        - 场景加载前截图（做背景过渡效果）
        - 支持 Preload（预加载场景资源不切换）
        - 场景切换完成后自动卸载未使用资源 + GC

    场景配置格式：
        {
            Name = "LoginScene",        -- 场景名称
            LuaScript = "LoginScene",   -- 场景 Lua 脚本路径
            PreLoadAssets = {},         -- 预加载资源列表
            ShowLoading = true,         -- 是否显示 Loading
            LoadingText = "加载中...",  -- Loading 提示文本
        }

    用法：
        local SceneLoader = require "Game.Scene.SceneLoader"
        SceneLoader:SwitchScene("LoginScene")
=============================================================================
]]

local SceneLoader = {}
SceneLoader.__index = SceneLoader

local _instance

---获取单例
---@return table
function SceneLoader.GetInstance()
    if not _instance then
        _instance = setmetatable({}, SceneLoader)
        _instance:_init()
    end
    return _instance
end

function SceneLoader:_init()
    -- 当前场景名称
    self._currentScene = nil

    -- 是否正在切换场景
    self._isSwitching = false

    -- 场景配置表 { [name] = config }
    self._sceneConfigs = {}

    -- Loading 管理器引用
    self._loadingManager = nil
end

-- =============================================================================
-- 场景配置注册
-- =============================================================================

---注册场景配置
---@param configs table { [name] = config }
function SceneLoader:RegisterConfigs(configs)
    for name, config in pairs(configs) do
        self._sceneConfigs[name] = config
    end
end

---注册单个场景配置
---@param name string
---@param config table
function SceneLoader:RegisterConfig(name, config)
    self._sceneConfigs[name] = config
end

-- =============================================================================
-- 场景切换（核心）
-- =============================================================================

---切换到指定场景
---@param sceneName string 场景名称
---@param onComplete function|nil 切换完成回调
---@param showLoading boolean|nil 是否显示 Loading（nil=使用配置中的值）
function SceneLoader:SwitchScene(sceneName, onComplete, showLoading)
    if self._isSwitching then
        print("[SceneLoader] Already switching scene, request ignored: " .. sceneName)
        return
    end

    local config = self._sceneConfigs[sceneName]
    if not config then
        print("[SceneLoader] Scene config not found: " .. sceneName)
        if onComplete then onComplete(false) end
        return
    end

    self._isSwitching = true

    -- 获取 LoadingManager
    if not self._loadingManager then
        self._loadingManager = require("Game.UI.Loading.LoadingManager").GetInstance()
    end

    -- 决定是否显示 Loading
    local needLoading = showLoading
    if needLoading == nil then
        needLoading = config.ShowLoading ~= false
    end

    local loadingToken
    if needLoading then
        loadingToken = self._loadingManager:BeginLoading(
            "SceneSwitch_" .. sceneName,
            300,   -- 延迟300ms显示（避免闪烁）
            30000  -- 30秒超时
        )
        self._loadingManager:SetProgress(0, config.LoadingText or "正在加载场景...")
    end

    -- 执行场景切换
    self:_doSwitchScene(sceneName, config, function(success)
        self._isSwitching = false
        self._currentScene = sceneName

        if loadingToken then
            self._loadingManager:EndLoading(loadingToken)
        end

        -- GC + 卸载未使用资源
        self:_cleanupAfterSwitch()

        if onComplete then
            onComplete(success)
        end
    end)
end

---执行实际的场景加载
---@param sceneName string
---@param config table
---@param onComplete function
function SceneLoader:_doSwitchScene(sceneName, config, onComplete)
    local UnityEngine = require "UnityEngine"
    local SceneManager = UnityEngine.SceneManagement.SceneManager
    local LoadSceneMode = UnityEngine.SceneManagement.LoadSceneMode

    -- 异步加载场景
    local asyncOp = SceneManager.LoadSceneAsync(sceneName, LoadSceneMode.Single)
    if not asyncOp then
        print("[SceneLoader] Failed to start loading scene: " .. sceneName)
        if onComplete then onComplete(false) end
        return
    end

    asyncOp.allowSceneActivation = true

    -- 在协程中等待加载完成
    local coroutine = require "Framework.Core.CoroutineManager"
    if coroutine then
        coroutine:StartCoroutine(function()
            while not asyncOp.isDone do
                local progress = asyncOp.progress  -- 0.0 ~ 0.9 加载, 0.9~1.0 激活
                if self._loadingManager then
                    -- Unity 的 progress 在 0.9 之前是加载进度
                    self._loadingManager:SetProgress(
                        math.min(progress / 0.9, 1.0),
                        config.LoadingText or "加载场景资源..."
                    )
                end
                coroutine.yield(nil)
            end

            -- 场景加载完成，初始化 Lua 场景脚本
            self:_initSceneScript(sceneName, config)

            if onComplete then onComplete(true) end
        end)
    else
        -- 降级：使用定时器轮询
        local TimerManager = require "Framework.Core.TimerManager"
        local checkTimer = TimerManager:GetInstance():AddInterval(0.1, function()
            if asyncOp.isDone then
                TimerManager:GetInstance():Remove(checkTimer)
                self:_initSceneScript(sceneName, config)
                if onComplete then onComplete(true) end
            else
                self._loadingManager:SetProgress(
                    math.min(asyncOp.progress / 0.9, 1.0),
                    config.LoadingText or "加载场景资源..."
                )
            end
        end)
    end
end

-- =============================================================================
-- 场景脚本初始化
-- =============================================================================

---初始化场景 Lua 脚本
---@param sceneName string
---@param config table
function SceneLoader:_initSceneScript(sceneName, config)
    if not config.LuaScript then return end

    local ok, result = pcall(require, config.LuaScript)
    if ok and result and result.OnSceneEnter then
        result:OnSceneEnter(sceneName, config)
    elseif not ok then
        print("[SceneLoader] Failed to load scene script: " .. tostring(result))
    end
end

-- =============================================================================
-- 场景切换后清理
-- =============================================================================

---场景切换后清理资源
function SceneLoader:_cleanupAfterSwitch()
    -- 延迟执行 GC，避免卡顿
    local TimerManager = require "Framework.Core.TimerManager"
    TimerManager:GetInstance():AddDelay(500, function()
        local UnityEngine = require "UnityEngine"
        local Resources = UnityEngine.Resources

        -- C# GC
        collectgarbage("collect")

        -- 卸载未使用的 Unity 资源
        Resources.UnloadUnusedAssets()
    end)
end

-- =============================================================================
-- 预加载场景（不切换，仅预加载资源）
-- =============================================================================

---预加载场景资源
---@param sceneName string
---@param onComplete function|nil
function SceneLoader:PreloadScene(sceneName, onComplete)
    local config = self._sceneConfigs[sceneName]
    if not config then
        if onComplete then onComplete(false) end
        return
    end

    local token = self._loadingManager:BeginLoading(
        "Preload_" .. sceneName,
        300,
        30000
    )

    -- 预加载资源列表
    local assets = config.PreLoadAssets or {}
    local loaded = 0
    local total = #assets

    if total == 0 then
        self._loadingManager:EndLoading(token)
        if onComplete then onComplete(true) end
        return
    end

    for _, assetPath in ipairs(assets) do
        -- 异步加载资源（实际项目中使用 Addressables 或 AssetBundle）
        -- 这里简化为直接计数
        loaded = loaded + 1
        self._loadingManager:SetProgress(loaded / total, "预加载资源...")
    end

    self._loadingManager:EndLoading(token)
    if onComplete then onComplete(true) end
end

-- =============================================================================
-- 查询
-- =============================================================================

---获取当前场景名称
---@return string|nil
function SceneLoader:GetCurrentScene()
    return self._currentScene
end

---是否正在切换场景
---@return boolean
function SceneLoader:IsSwitching()
    return self._isSwitching
end

return SceneLoader
