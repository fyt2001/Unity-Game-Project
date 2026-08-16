--[[
=============================================================================
LoginScene.lua - 登录场景脚本（参考 ShaoNvClient_H02 精华）
=============================================================================
Module:     Game/Scene/LoginScene
Version:    1.0.0
Description:
    登录场景的 Lua 脚本。由 SceneLoader 在场景加载完成后调用 OnSceneEnter。
    负责：初始化登录 UI、处理登录逻辑、登录成功后切换到主城场景。

    核心设计：
        - 场景入口与出口分离：OnSceneEnter / OnSceneLeave
        - 登录状态机：Connect → Auth → SelectServer → EnterGame
        - 异步安全：登录过程中防止重复操作
        - UI 生命周期：场景退出时自动清理登录相关 UI

    用法：
        由 SceneLoader 自动调用，无需手动调用。
=============================================================================
]]

local LoginScene = {}
LoginScene.__index = LoginScene

-- 登录状态
local LoginState = {
    Idle = 0,
    Connecting = 1,
    Authenticating = 2,
    SelectingServer = 3,
    Entering = 4,
    Done = 5,
}

-- =============================================================================
-- 场景生命周期
-- =============================================================================

function LoginScene:OnSceneEnter(sceneName, config)
    print(string.format("[LoginScene] Entering scene: %s", sceneName))

    self._sceneName = sceneName
    self._config = config
    self._state = LoginState.Idle
    self._uiManager = nil

    -- 获取 UIManager 引用
    local GameMain = require "Game.GameMain"
    self._uiManager = GameMain.GetUIManager()

    -- 初始化登录 UI
    self:_initLoginUI()

    -- 开始登录流程
    self:_startLoginFlow()
end

function LoginScene:OnSceneLeave()
    print("[LoginScene] Leaving scene, cleaning up...")

    -- 关闭登录相关 UI
    if self._uiManager then
        self._uiManager:Close("LoginPanel", "SceneLeave")
    end

    self._state = LoginState.Idle
    self._uiManager = nil
end

-- =============================================================================
-- 登录 UI 初始化
-- =============================================================================

function LoginScene:_initLoginUI()
    -- 打开登录面板 Prefab（类似 LoadingPanel 方式，通过 UIManager 加载）
    if self._uiManager then
        self._uiManager:Open("LoginPanel")
        print("[LoginScene] LoginPanel opened")
    else
        print("[LoginScene] Login UI initialized (placeholder)")
    end
end

-- =============================================================================
-- 登录流程（状态机驱动）
-- =============================================================================

function LoginScene:_startLoginFlow()
    print("[LoginScene] Starting login flow...")

    -- 生产项目中，这里会连接服务器、认证、选择服务器等
    -- 当前为简化实现：直接模拟登录成功，进入主城

    self._state = LoginState.Connecting
    print("[LoginScene] State: Connecting...")

    -- 模拟网络连接延迟
    local TimerManager = require "Framework.Core.TimerManager"
    TimerManager:GetInstance():AddDelay(500, function()
        self:_onConnectSuccess()
    end)
end

function LoginScene:_onConnectSuccess()
    self._state = LoginState.Authenticating
    print("[LoginScene] State: Authenticating...")

    local TimerManager = require "Framework.Core.TimerManager"
    TimerManager:GetInstance():AddDelay(300, function()
        self:_onAuthSuccess()
    end)
end

function LoginScene:_onAuthSuccess()
    self._state = LoginState.SelectingServer
    print("[LoginScene] State: Selecting server...")

    local TimerManager = require "Framework.Core.TimerManager"
    TimerManager:GetInstance():AddDelay(200, function()
        self:_onEnterGame()
    end)
end

function LoginScene:_onEnterGame()
    self._state = LoginState.Entering
    print("[LoginScene] State: Entering game...")

    -- 登录完成，切换到主城场景
    local GameMain = require "Game.GameMain"
    GameMain.SwitchScene("Home", function(success)
        if success then
            self._state = LoginState.Done
            print("[LoginScene] Successfully entered Home scene")
        else
            print("[LoginScene] Failed to enter Home scene")
            self._state = LoginState.Idle
        end
    end)
end

-- =============================================================================
-- 公共 API
-- =============================================================================

function LoginScene:GetState()
    return self._state
end

function LoginScene:IsLoginDone()
    return self._state == LoginState.Done
end

return LoginScene