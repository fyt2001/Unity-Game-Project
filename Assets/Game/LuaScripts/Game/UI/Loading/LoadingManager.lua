--[[
=============================================================================
LoadingManager.lua - 加载界面管理器（全局单例，引用计数模式）
=============================================================================
Module:     Game/UI/Loading/LoadingManager
Version:    2.0.0
Description:
    加载界面的全局管理器。核心设计来自 ShaoNvClient_H02 的 LoadingUtil 精华。

    核心设计理念 —— 引用计数模式：
        多个业务可以同时调用 BeginLoading()，LoadingManager 维护一个计数器。
        只有当所有调用者都调用 EndLoading()（计数器归零）时，Loading 界面才真正关闭。
        这解决了"A模块开始加载、B模块也加载、A加载完就关闭了Loading"的问题。

    关键特性：
        - 引用计数：Begin/End 配对，计数器归零才关闭
        - 延迟显示：默认延迟 500ms 才显示 Loading（避免闪烁）
        - 超时保护：默认 15 秒超时强制关闭，防止卡死
        - 进度合并：多个调用者各自报告进度，取最大值
        - 异步安全：UIManager 未就绪时缓存调用，就绪后自动执行
        - 场景切换：支持场景加载时的 Loading 管理

    用法：
        local LoadingMgr = LoadingManager.GetInstance()

        -- 业务A开始加载
        local token = LoadingMgr:BeginLoading("LoadConfig", 500, 15000)
        LoadingMgr:SetProgress(0.3, "加载配置表...")
        LoadingMgr:EndLoading(token)  -- 业务A完成

        -- 业务B同时加载
        local token2 = LoadingMgr:BeginLoading("LoadScene", 500, 15000)
        LoadingMgr:SetProgress(0.5, "加载场景...")
        LoadingMgr:EndLoading(token2) -- 业务B完成
        -- 此时计数器归零，Loading界面关闭
=============================================================================
]]

local LoadingManager = {}
LoadingManager.__index = LoadingManager

local _instance

---获取单例
---@return table
function LoadingManager.GetInstance()
    if not _instance then
        _instance = setmetatable({}, LoadingManager)
        _instance:_init()
    end
    return _instance
end

-- =============================================================================
-- 初始化
-- =============================================================================

function LoadingManager:_init()
    -- 引用计数：{ [token] = { name, progress, text, startTime } }
    self._loadings = {}

    -- 当前活跃的加载数量
    self._loadingCount = 0

    -- 加载令牌计数器
    self._tokenSeq = 0

    -- UIManager 引用（就绪后设置）
    self._uiManager = nil

    -- 是否已注册 Loading 窗口
    self._registered = false

    -- Loading 窗口是否正在显示
    self._isShown = false

    -- 当前合并后的进度
    self._currentProgress = 0
    self._currentText = ""

    -- 延迟显示定时器ID
    self._delayShowTimerId = nil

    -- 超时强制关闭定时器ID
    self._forceEndTimerId = nil

    -- 默认配置
    self._defaultDelayMs = 500       -- 默认延迟显示时间（毫秒）
    self._defaultForceEndMs = 15000  -- 默认超时强制关闭时间（毫秒）
    self._completeDelayMs = 300      -- 100%后延迟关闭时间（毫秒）

    -- 缓存的待处理操作（UIManager未就绪时）
    self._pendingOperations = {}
end

-- =============================================================================
-- 公共 API：初始化（在 UIManager 创建后调用）
-- =============================================================================

---初始化 Loading 系统（接入 UIManager）
---@param uiManager table UIManager 实例
function LoadingManager:Init(uiManager)
    self._uiManager = uiManager

    -- 注册 Loading 窗口
    if not self._registered then
        local RegisterLoading = require "Game.UI.Loading.RegisterLoading"
        RegisterLoading(uiManager)
        self._registered = true
    end

    -- 执行缓存的操作
    self:_flushPendingOperations()
end

-- =============================================================================
-- 公共 API：引用计数加载控制（精华）
-- =============================================================================

---开始加载（引用计数 + 1）
---@param name string 加载任务名称（用于日志和调试）
---@param delayMs number|nil 延迟显示毫秒数（nil=默认500ms, 0=立即显示）
---@param forceEndMs number|nil 超时强制关闭毫秒数（nil=默认15秒, 0=不超时）
---@return string token 加载令牌，用于 EndLoading
function LoadingManager:BeginLoading(name, delayMs, forceEndMs)
    self._tokenSeq = self._tokenSeq + 1
    local token = string.format("load_%d_%s", self._tokenSeq, name or "unknown")
    local startTime = os.clock()

    self._loadings[token] = {
        name = name or "unknown",
        progress = 0,
        text = "",
        startTime = startTime,
    }
    self._loadingCount = self._loadingCount + 1

    -- 设置超时保护
    local endTime = forceEndMs
    if endTime == nil then
        endTime = self._defaultForceEndMs
    end

    if endTime > 0 then
        self:_resetForceEndTimer(endTime)
    end

    -- 延迟显示 Loading
    local delay = delayMs
    if delay == nil then
        delay = self._defaultDelayMs
    end

    if self._loadingCount == 1 then
        -- 第一个加载任务，启动延迟显示
        if delay >= 0 then
            self:_scheduleShowLoading(delay)
        else
            self:_showLoadingNow()
        end
    end

    return token
end

---结束加载（引用计数 - 1）
---@param token string BeginLoading 返回的令牌
function LoadingManager:EndLoading(token)
    if not token or not self._loadings[token] then
        return
    end

    self._loadings[token] = nil
    if self._loadingCount > 0 then
        self._loadingCount = self._loadingCount - 1
    end

    -- 所有加载任务完成，关闭 Loading
    if self._loadingCount == 0 then
        self:_cancelDelayShowTimer()
        self:_cancelForceEndTimer()

        if self._isShown then
            self:_hideLoadingWithDelay(self._completeDelayMs)
        end
    end
end

---强制清除所有 Loading（异常情况使用）
function LoadingManager:ForceClearAll()
    self._loadings = {}
    self._loadingCount = 0
    self._cancelDelayShowTimer()
    self._cancelForceEndTimer()

    if self._isShown then
        self:_hideLoadingNow()
    end
end

-- =============================================================================
-- 公共 API：进度更新
-- =============================================================================

---设置进度（自动取所有任务的最大进度值）
---@param progress number 0.0 ~ 1.0
---@param text string|nil 提示文本
function LoadingManager:SetProgress(progress, text)
    progress = math.min(math.max(progress or 0, 0), 1)

    -- 合并进度：取最大值
    if progress > self._currentProgress then
        self._currentProgress = progress
    end

    if text then
        self._currentText = text
    end

    self:_updateLoadingUI()
end

---设置加载阶段描述
---@param phase string 阶段名称
---@param text string|nil 提示文本
function LoadingManager:SetPhase(phase, text)
    self:_setText(text or phase)
end

---设置版本号
---@param version string
function LoadingManager:SetVersion(version)
    self:_callPending("SetVersion", version)
    if self._isShown then
        self:_callController("SetVersion", version)
    end
end

---完成加载（设为100%，短暂延迟后关闭）
---@param onComplete function|nil
function LoadingManager:Complete(onComplete)
    self._currentProgress = 1
    self._currentText = "加载完成"
    self:_updateLoadingUI()

    -- 延迟关闭
    local TimerManager = require "Framework.Core.TimerManager"
    TimerManager:GetInstance():AddDelay(self._completeDelayMs, function()
        self:ForceClearAll()
        if onComplete then
            onComplete()
        end
    end)
end

-- =============================================================================
-- 私有方法：显示/隐藏控制
-- =============================================================================

function LoadingManager:_scheduleShowLoading(delayMs)
    self:_cancelDelayShowTimer()

    if self._isShown then return end

    local TimerManager = require "Framework.Core.TimerManager"
    self._delayShowTimerId = TimerManager:GetInstance():AddDelay(delayMs, function()
        self._delayShowTimerId = nil
        self:_showLoadingNow()
    end)
end

function LoadingManager:_showLoadingNow()
    if self._isShown then return end
    self._isShown = true

    if self._uiManager then
        if not self._uiManager:IsOpen("Loading") then
            self._uiManager:Open("Loading")
        end
    else
        self:_addPending("Show")
    end

    self:_updateLoadingUI()
end

function LoadingManager:_hideLoadingWithDelay(delayMs)
    if not self._isShown then return end

    local TimerManager = require "Framework.Core.TimerManager"
    TimerManager:GetInstance():AddDelay(delayMs, function()
        self:_hideLoadingNow()
    end)
end

function LoadingManager:_hideLoadingNow()
    if not self._isShown then return end
    self._isShown = false
    self._currentProgress = 0
    self._currentText = ""

    if self._uiManager then
        self._uiManager:Close("Loading", "Complete")
    else
        self:_addPending("Hide")
    end
end

-- =============================================================================
-- 私有方法：超时保护
-- =============================================================================

function LoadingManager:_resetForceEndTimer(forceEndMs)
    self:_cancelForceEndTimer()

    local TimerManager = require "Framework.Core.TimerManager"
    self._forceEndTimerId = TimerManager:GetInstance():AddDelay(forceEndMs, function()
        self._forceEndTimerId = nil
        self:ForceClearAll()
    end)
end

function LoadingManager:_cancelForceEndTimer()
    if self._forceEndTimerId then
        local TimerManager = require "Framework.Core.TimerManager"
        TimerManager:GetInstance():Remove(self._forceEndTimerId)
        self._forceEndTimerId = nil
    end
end

function LoadingManager:_cancelDelayShowTimer()
    if self._delayShowTimerId then
        local TimerManager = require "Framework.Core.TimerManager"
        TimerManager:GetInstance():Remove(self._delayShowTimerId)
        self._delayShowTimerId = nil
    end
end

-- =============================================================================
-- 私有方法：UI更新
-- =============================================================================

function LoadingManager:_updateLoadingUI()
    if not self._isShown then return end

    if self._uiManager then
        local window = self._uiManager:GetWindow("Loading")
        if window and window:IsOpened() then
            local controller = window:GetController()
            if controller and controller.SetProgress then
                controller:SetProgress(self._currentProgress, self._currentText)
            end
        end
    else
        self:_addPending("Update", { progress = self._currentProgress, text = self._currentText })
    end
end

function LoadingManager:_setText(text)
    self._currentText = text
    self:_updateLoadingUI()
end

function LoadingManager:_callController(method, ...)
    if self._uiManager then
        local window = self._uiManager:GetWindow("Loading")
        if window and window:IsOpened() then
            local controller = window:GetController()
            if controller and controller[method] then
                controller[method](controller, ...)
            end
        end
    end
end

-- =============================================================================
-- 私有方法：缓存操作（UIManager未就绪时）
-- =============================================================================

function LoadingManager:_addPending(type, data)
    table.insert(self._pendingOperations, { type = type, data = data })
end

function LoadingManager:_callPending(type, ...)
    -- 仅用于不需要真正执行的操作标记
end

function LoadingManager:_flushPendingOperations()
    for _, op in ipairs(self._pendingOperations) do
        if op.type == "Show" then
            self:_showLoadingNow()
        elseif op.type == "Hide" then
            self:_hideLoadingNow()
        elseif op.type == "Update" and op.data then
            self._currentProgress = op.data.progress
            self._currentText = op.data.text
            self:_updateLoadingUI()
        end
    end
    self._pendingOperations = {}
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---是否正在显示 Loading
---@return boolean
function LoadingManager:IsShown()
    return self._isShown
end

---获取当前加载任务数量
---@return number
function LoadingManager:GetLoadingCount()
    return self._loadingCount
end

---重置状态（用于场景切换等）
function LoadingManager:Reset()
    self:_cancelDelayShowTimer()
    self:_cancelForceEndTimer()
    self._loadings = {}
    self._loadingCount = 0
    self._isShown = false
    self._currentProgress = 0
    self._currentText = ""
    self._pendingOperations = {}
end

return LoadingManager
