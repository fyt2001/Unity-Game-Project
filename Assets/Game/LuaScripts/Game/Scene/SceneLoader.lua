--[[
=============================================================================
SceneLoader.lua - 场景加载管理器（精华来自 ShaoNvClient_H02 SceneManager）
=============================================================================
Module:     Game/Scene/SceneLoader
Version:    2.0.0
Description:
	场景加载管理器。从 ShaoNvClient_H02 SceneManager 提取精华。

	核心设计：
		- 使用 Level（BuildSettings 索引）加载场景，比 Name 更可靠
		- 场景切换时自动显示 Loading 界面
		- 异步加载场景 + 进度回调和 Loading 同步
		- 场景生命周期：OnCreate（一次）→ OnComplete（每次进入）
		- 场景切换时自动清理旧场景（OnLeave）
		- 场景切换完成后自动卸载未使用资源 + GC

	场景配置格式：
		{
			Level = 1,                  -- BuildSettings 索引（必填）
			Name = "LoginScene",        -- 场景名称（用作回退）
			LuaScript = "LoginScene",   -- 场景 Lua 脚本路径
			PreLoadAssets = {},         -- 预加载资源列表
			ShowLoading = true,         -- 是否显示 Loading
			LoadingText = "加载中...",  -- Loading 提示文本
		}

	用法：
		local SceneLoader = require "Game.Scene.SceneLoader"
		SceneLoader:SwitchScene("Login")
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"

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

	-- 是否正在初始化场景脚本（防止 UpdateManager 回调内删除导致的重复调用）
	self._isInitializingScene = false

	-- 场景实例表 { [sceneName] = sceneInstance }
	self._sceneInstances = {}

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
	Logger.Debug("SceneLoader", "SwitchScene called: %s, isSwitching=%s", tostring(sceneName), tostring(self._isSwitching))

	if self._isSwitching then
		Logger.Warn("SceneLoader", "Already switching scene, request ignored: " .. sceneName)
		return
	end

	local config = self._sceneConfigs[sceneName]
	if not config then
		Logger.Error("SceneLoader", "Scene config not found: " .. sceneName)
		Logger.Error("SceneLoader", "Available configs: " .. table.concat(self:_getConfigNames(), ", "))
		if onComplete then onComplete(false) end
		return
	end

	Logger.Debug("SceneLoader", "Found config for '%s': Level=%s, Name=%s, LuaScript=%s",
		sceneName, tostring(config.Level), tostring(config.Name), tostring(config.LuaScript))

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
	Logger.Debug("SceneLoader", "_doSwitchScene: %s (Level=%s, Name=%s)", sceneName, tostring(config.Level), tostring(config.Name))

	self:_cleanupCurrentScene()

	local SceneManager = CS.UnityEngine.SceneManagement.SceneManager
	local LoadSceneMode = CS.UnityEngine.SceneManagement.LoadSceneMode

	local asyncOp
	if config.Level ~= nil then
		Logger.Debug("SceneLoader", "LoadSceneAsync(%d, Single)", config.Level)
		asyncOp = SceneManager.LoadSceneAsync(config.Level, LoadSceneMode.Single)
	else
		Logger.Debug("SceneLoader", "LoadSceneAsync('%s', Single)", config.Name)
		asyncOp = SceneManager.LoadSceneAsync(config.Name, LoadSceneMode.Single)
	end

	if not asyncOp then
		Logger.Error("SceneLoader", "Failed to start loading scene: " .. (config.Name or sceneName))
		if onComplete then onComplete(false) end
		return
	end

	Logger.Debug("SceneLoader", "LoadSceneAsync started, allowSceneActivation=true")
	asyncOp.allowSceneActivation = true

	-- 使用 UpdateManager 驱动加载等待
	--
	-- 【重要修复】必须用 done 标志做一次性守卫。
	-- 原先仅依赖 updateMgr:RemoveUpdate(checkId) 来停止轮询，一旦该移除未生效
	-- （实测回调未被摘除），本回调就会每帧继续执行：
	--   → _initSceneScript 每帧调用 → Scene:OnComplete 每帧重跑
	--   → LoginScene 每帧 _registerEvents()，事件监听器累积到数千个
	--   → 且每帧把 _state 重置为 Idle，登录状态机被反复打断，永远走不到切场景
	-- 因此这里显式加一次性守卫，确保完成回调只执行一次。
	local UpdateManager = require "Framework.Core.UpdateManager"
	local updateMgr = UpdateManager:GetInstance()
	local done = false
	local checkId
	checkId = updateMgr:AddUpdate(function(dt)
		if done then return end

		if asyncOp.isDone then
			done = true
			updateMgr:RemoveUpdate(checkId)
			self:_initSceneScript(sceneName, config)
			if onComplete then onComplete(true) end
		else
			local progress = asyncOp.progress
			if self._loadingManager then
				self._loadingManager:SetProgress(
					math.min(progress / 0.9, 1.0),
					config.LoadingText or "加载场景资源..."
				)
			end
		end
	end)
end

-- =============================================================================
-- 旧场景清理
-- =============================================================================

---清理当前场景（调用 OnLeave）
function SceneLoader:_cleanupCurrentScene()
	if not self._currentScene then return end

	local oldScene = self._sceneInstances[self._currentScene]
	if oldScene and oldScene.OnLeave then
		local ok, err = pcall(oldScene.OnLeave, oldScene)
		if not ok then
			Logger.Error("SceneLoader", "OnLeave error: " .. tostring(err))
		end
	end
end

-- =============================================================================
-- 场景脚本初始化
-- =============================================================================

---初始化场景 Lua 脚本（生命周期：OnCreate → OnComplete）
---@param sceneName string
---@param config table
function SceneLoader:_initSceneScript(sceneName, config)
	Logger.Debug("SceneLoader", "_initSceneScript: %s, LuaScript=%s", sceneName, tostring(config.LuaScript))

	if not config.LuaScript then
		Logger.Warn("SceneLoader", "No LuaScript configured, skip")
		return
	end

	if self._isInitializingScene then
		Logger.Warn("SceneLoader", "Scene script already initializing, skip: " .. sceneName)
		return
	end

	if self._sceneInstances[sceneName] then
		Logger.Debug("SceneLoader", "Scene already initialized, calling OnComplete only: %s", sceneName)
		local result = self._sceneInstances[sceneName]
		if result.OnComplete then
			local ok, err = pcall(result.OnComplete, result, sceneName, config)
			if not ok then
				Logger.Error("SceneLoader", "OnComplete error: " .. tostring(err))
			end
		end
		return
	end

	self._isInitializingScene = true

	local ok, result = pcall(require, config.LuaScript)
	if not ok then
		Logger.Error("SceneLoader", "Failed to load scene script: " .. tostring(result))
		self._isInitializingScene = false
		return
	end

	if not result then
		self._isInitializingScene = false
		return
	end

	-- OnCreate：场景脚本首次加载时调用一次（预加载资源等）
	if not self._sceneInstances[sceneName] and result.OnCreate then
		local ok2, err2 = pcall(result.OnCreate, result, sceneName, config)
		if not ok2 then
			Logger.Error("SceneLoader", "OnCreate error: " .. tostring(err2))
		end
	end

	-- 缓存场景实例
	self._sceneInstances[sceneName] = result

	-- OnComplete：每次场景加载完成时调用（打开 UI 等）
	if result.OnComplete then
		local ok3, err3 = pcall(result.OnComplete, result, sceneName, config)
		if not ok3 then
			Logger.Error("SceneLoader", "OnComplete error: " .. tostring(err3))
		end
	end

	self._isInitializingScene = false
end

-- =============================================================================
-- 场景切换后清理
-- =============================================================================

---场景切换后清理资源
function SceneLoader:_cleanupAfterSwitch()
	-- 延迟执行 GC，避免卡顿
	local TimerManager = require "Framework.Core.TimerManager"
	TimerManager:GetInstance():AddDelay(500, function()
		local Resources = CS.UnityEngine.Resources

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

function SceneLoader:_getConfigNames()
	local names = {}
	for k, _ in pairs(self._sceneConfigs) do
		names[#names + 1] = k
	end
	return names
end

return SceneLoader