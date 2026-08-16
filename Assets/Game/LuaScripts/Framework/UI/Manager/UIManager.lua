--[[
=============================================================================
UIManager.lua
=============================================================================
Module:     Framework/UI/Manager/UIManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIManager 是 UI Framework 的唯一公共入口，协调所有子系统完成窗口的
    创建、打开、关闭、刷新、缓存和销毁。

    它协调以下子系统：
        - UIWindowFactory    (窗口创建和 MVC 实例化)
        - UIWindowStack      (窗口打开顺序)
        - UILayerManager     (层级管理)
        - UIZoneManager      (焦点管理)
        - UIWindowCache      (缓存管理)
        - UIResourceLoader   (资源加载)
        - UIAnimationManager (动画播放)
        - UIEventDispatcher  (事件分发)
        - UIBlockManager     (输入阻断)

    业务代码只能通过 UIManager 操作 UI，禁止直接调用子系统。

Public API:
    RegisterWindow(name, config)     - 注册窗口配置
    Open(name, ...)                  - 打开窗口
    Close(name, reason)              - 关闭窗口
    Back(reason)                     - 返回上一窗口
    CloseAll(reason)                 - 关闭所有窗口
    Destroy(nameOrWindow)            - 销毁窗口
    GetWindow(name)                  - 获取窗口
    IsOpen(name)                     - 是否已打开
    IsLoading(name)                  - 是否加载中
    Refresh(name, ...)               - 刷新窗口
    Preload(name, callback)          - 预加载资源
    AddListener(eventName, cb, ...)  - 订阅事件
    RemoveListener(handle)           - 取消订阅
    BlockInput(key, reason)          - 阻断输入
    UnblockInput(key)                - 解除阻断
    OnSceneChange()                  - 场景切换
    Dump()                           - 调试快照
    LogDump()                        - 打印调试快照

Open Modes:
    Stack           - 默认模式，堆叠打开
    Replace         - 替换当前窗口
    SingleTop       - 如果已在顶部，刷新而非重新打开
    RefreshIfOpen   - 如果已打开，刷新而非重新打开

Cache Policies:
    DestroyOnClose          - 关闭时立即销毁
    CacheOnClose            - 关闭时缓存逻辑窗口
    NeverDestroy            - 永久缓存，整个运行期不销毁
    DestroyOnSceneChange    - 场景切换时销毁

Dependencies:
    - 所有 Manager、Config、Core、Utils 模块

Usage:
    local UIFramework = require "NewObject.Framework.UI.UIFramework"
    local ui = UIFramework.Create()
    ui:Open("Bag", bagId)
    ui:Close("Bag", "UserClosed")
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local Logger = require "NewObject.Framework.UI.Utils.Logger"
local UIEnums = require "NewObject.Framework.UI.Config.UIEnums"
local UIWindowConfig = require "NewObject.Framework.UI.Config.UIWindowConfig"
local UIResourceLoader = require "NewObject.Framework.UI.Resource.UIResourceLoader"
local UIAnimationManager = require "NewObject.Framework.UI.Animation.UIAnimationManager"
local UIEventDispatcher = require "NewObject.Framework.UI.Event.UIEventDispatcher"
local UIWindowCache = require "NewObject.Framework.UI.Cache.UIWindowCache"
local UIWindowStack = require "NewObject.Framework.UI.Manager.UIWindowStack"
local UIWindowFactory = require "NewObject.Framework.UI.Manager.UIWindowFactory"
local UILayerManager = require "NewObject.Framework.UI.Layer.UILayerManager"
local UIZoneManager = require "NewObject.Framework.UI.Zone.UIZoneManager"
local UIBlockManager = require "NewObject.Framework.UI.Manager.UIBlockManager"

local UIManager = Class.Define("UIManager")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化 UIManager 及所有子系统管理器
---所有子系统均可通过 options 注入自定义实现，实现可替换架构
---@param options table|nil 可选配置
---@param options.config table UIWindowConfig 注册表
---@param options.resourceLoader table 自定义资源加载器
---@param options.animationManager table 自定义动画管理器
---@param options.eventDispatcher table 自定义事件分发器
---@param options.cache table 自定义缓存管理器
---@param options.stack table 自定义窗口栈
---@param options.layerManager table 自定义层级管理器
---@param options.zoneManager table 自定义 Zone 管理器
---@param options.blockManager table 自定义输入阻断管理器
---@param options.factory table 自定义工厂
---@param options.root any UIRoot 适配器
---@param options.layers table 自定义层级配置
---@param options.resourceProvider table 自定义资源提供者
---@param options.animationProvider table 自定义动画提供者
function UIManager:Ctor(options)
    options = options or {}

    -- 配置注册表
    self.config = options.config or UIWindowConfig

    -- 资源加载器（可替换为 Addressables / YooAsset / AssetBundle）
    self.resourceLoader = options.resourceLoader
        or UIResourceLoader.New(options.resourceProvider)

    -- 动画管理器（可替换为 DOTween / Animator / FairyGUI）
    self.animationManager = options.animationManager
        or UIAnimationManager.New(options.animationProvider)

    -- 事件分发器
    self.eventDispatcher = options.eventDispatcher
        or UIEventDispatcher.New()

    -- 窗口缓存
    self.cache = options.cache or UIWindowCache.New()

    -- 窗口栈
    self.stack = options.stack or UIWindowStack.New()

    -- 层级管理器
    self.layerManager = options.layerManager
        or UILayerManager.New(options.root, options.layers)

    -- Zone 管理器
    self.zoneManager = options.zoneManager or UIZoneManager.New()

    -- 输入阻断管理器
    self.blockManager = options.blockManager or UIBlockManager.New()

    -- 窗口工厂
    self.factory = options.factory
        or UIWindowFactory.New(self.resourceLoader)

    -- 正在加载的窗口映射表
    self.loadingWindows = {}
end

-- =============================================================================
-- 公共 API：窗口注册
-- =============================================================================

---注册一个窗口配置
---通常在游戏初始化时批量注册所有窗口
---@param name string 窗口唯一名称
---@param config table 窗口配置表
function UIManager:RegisterWindow(name, config)
    self.config.Register(name, config)
end

-- =============================================================================
-- 公共 API：打开窗口
-- =============================================================================

---打开一个窗口
---支持多种打开模式：Stack、Replace、SingleTop、RefreshIfOpen
---@param name string 窗口名称
---@param ... any 打开参数，传递给 MVC 的 OnOpen 回调
---@return table|nil window 如果立即可用则返回窗口实例，否则返回 nil
function UIManager:Open(name, ...)
    local config = self.config.Get(name)
    local openArgs = table.pack(...)

    -- 检查缓存中是否有可重用的窗口
    local cached = self.cache:Get(name)
    if cached and not cached:IsDestroyed() then
        return self:OpenExistingWindow(cached, table.unpack(openArgs, 1, openArgs.n))
    end

    -- 处理 RefreshIfOpen 模式：如果已打开则刷新
    if config.openMode == UIEnums.OpenMode.RefreshIfOpen then
        local opened = self:GetWindow(name)
        if opened and opened:IsOpened() then
            opened:Refresh(table.unpack(openArgs, 1, openArgs.n))
            self.eventDispatcher:Dispatch("WindowRefreshed", opened)
            return opened
        end
    end

    -- 处理 Replace 模式：关闭当前窗口后打开新窗口
    if config.openMode == UIEnums.OpenMode.Replace then
        local top = self.zoneManager:GetTopWindow() or self.stack:Peek()
        if top and top:GetName() ~= name then
            self:Close(top:GetName(), "Replace")
        end
    end

    -- 处理 SingleTop 模式：如果已在顶部则刷新
    if config.openMode == UIEnums.OpenMode.SingleTop then
        local top = self.stack:Peek()
        if top and top:GetName() == name and top:IsOpened() then
            top:Refresh(table.unpack(openArgs, 1, openArgs.n))
            self.eventDispatcher:Dispatch("WindowRefreshed", top)
            return top
        end
    end

    -- 创建新窗口
    local window = self.factory:CreateWindow(name, config)

    -- 输入阻断：在加载期间阻断输入
    self.blockManager:Block("UI_Loading_" .. name, "Window loading")

    -- 必须先将状态置为 Loading，再发起异步加载
    -- 因为 LoadAsync 在无 Provider 或缓存命中时会同步回调，
    -- 若回调先于 BeginLoading 执行，会导致状态机报错 None -> Loaded
    local token = self.resourceLoader:CreateToken(config.prefab or config.path or name)
    window:BeginLoading(token)

    self.resourceLoader:LoadAsync(
        config.prefab or config.path or name,
        function(asset, loadToken)
            self:OnWindowAssetLoaded(
                window, asset, loadToken,
                table.unpack(openArgs, 1, openArgs.n)
            )
        end,
        token
    )
    self.loadingWindows[name] = window
    self.eventDispatcher:Dispatch("WindowLoading", window)

    return window
end

-- =============================================================================
-- 私有方法：资源加载完成回调
-- =============================================================================

---异步资源加载完成后的处理流程
---1. 检查令牌是否已取消
---2. 完成加载状态
---3. 实例化 GameObject
---4. 创建 MVC 组件
---5. 添加到层级和 Zone
---6. 播放打开动画
---7. 完成窗口打开
---@param window table UIWindow 实例
---@param asset any 加载的资源
---@param token table 加载令牌
---@param ... any 原始打开参数
function UIManager:OnWindowAssetLoaded(window, asset, token, ...)
    -- 检查令牌是否被取消，或窗口是否已被销毁
    if token and token.cancelled or window:IsDestroyed() then
        self.blockManager:Unblock("UI_Loading_" .. window:GetName())
        return
    end

    local openArgs = table.pack(...)

    -- 从加载表中移除
    self.loadingWindows[window:GetName()] = nil

    -- 完成加载
    window:CompleteLoading()

    -- 实例化 Prefab
    local gameObject = self.resourceLoader:Instantiate(asset)

    -- 创建 MVC
    self.factory:CreateMVC(window, gameObject)

    -- 创建窗口
    window:Create()

    -- 添加到层级
    self.layerManager:AddWindow(window, window:GetConfig().layer)

    -- 添加到 Zone
    self.zoneManager:AddWindow(window)

    -- 添加到窗口栈
    self.stack:Push(window)

    -- 播放打开动画
    self.animationManager:PlayOpenAnimation(window:GetGameObject(), function()
        window:Open(table.unpack(openArgs, 1, openArgs.n))
        self.zoneManager:UpdateFocus()
        self.blockManager:Unblock("UI_Loading_" .. window:GetName())
        self.eventDispatcher:Dispatch("WindowOpened", window)
    end)
end

-- =============================================================================
-- 私有方法：打开已存在的窗口（从缓存中）
-- =============================================================================

---打开缓存中或已创建的窗口
---@param window table UIWindow 实例
---@param ... any 打开参数
---@return table window 窗口实例
function UIManager:OpenExistingWindow(window, ...)
    local openArgs = table.pack(...)

    -- 从缓存中移除
    self.cache:Remove(window:GetName())

    -- 重新添加到层级
    self.layerManager:AddWindow(window, window:GetConfig().layer)

    -- 重新添加到 Zone
    self.zoneManager:AddWindow(window)

    -- 重新添加到栈
    self.stack:Push(window)

    -- 播放显示动画
    self.animationManager:PlayOpenAnimation(window:GetGameObject(), function()
        if window:IsHidden() or window:IsClosed() then
            window:Open(table.unpack(openArgs, 1, openArgs.n))
        else
            window:Refresh(table.unpack(openArgs, 1, openArgs.n))
        end
        self.zoneManager:UpdateFocus()
        self.eventDispatcher:Dispatch("WindowOpened", window)
    end)

    return window
end

-- =============================================================================
-- 公共 API：关闭窗口
-- =============================================================================

---关闭一个窗口
---如果窗口正在加载中，会取消加载
---关闭后根据缓存策略决定是缓存还是销毁
---@param name string 窗口名称
---@param reason string|nil 关闭原因
function UIManager:Close(name, reason)
    local window = self:GetWindow(name)

    if not window then
        -- 检查是否在加载中，如果是则取消加载
        local loading = self.loadingWindows[name]
        if loading and loading.loadingToken then
            self.resourceLoader:Cancel(loading.loadingToken)
            loading:Close(reason or "CancelLoading")
            self.loadingWindows[name] = nil
            self.blockManager:Unblock("UI_Loading_" .. name)
        end
        return
    end

    -- 输入阻断：关闭动画期间阻断输入
    self.blockManager:Block("UI_Closing_" .. name, "Window closing")

    -- 播放关闭动画
    self.animationManager:PlayCloseAnimation(window:GetGameObject(), function()
        window:Close(reason)
        self.stack:Remove(window)
        self.zoneManager:RemoveWindow(window)
        self.layerManager:RemoveWindow(window)
        self:ApplyClosePolicy(window)
        self.blockManager:Unblock("UI_Closing_" .. name)
        self.eventDispatcher:Dispatch("WindowClosed", window)
    end)
end

-- =============================================================================
-- 私有方法：关闭后策略处理
-- =============================================================================

---根据窗口的缓存策略决定关闭后是缓存还是销毁
---@param window table UIWindow 实例
function UIManager:ApplyClosePolicy(window)
    local policy = window:GetConfig().cachePolicy

    if policy == UIEnums.CachePolicy.NeverDestroy then
        -- 永久缓存：不销毁
        self.cache:Put(window)
    elseif policy == UIEnums.CachePolicy.CacheOnClose then
        -- 关闭时缓存：保留逻辑窗口
        self.cache:Put(window)
    elseif policy == UIEnums.CachePolicy.DestroyOnSceneChange then
        -- 场景切换时销毁：当前关闭时缓存，OnSceneChange 时统一销毁
        self.cache:Put(window)
    else
        -- DestroyOnClose：立即销毁
        self:DestroyWindow(window)
    end
end

-- =============================================================================
-- 公共 API：销毁窗口
-- =============================================================================

---销毁一个窗口（通过名称或实例）
---销毁操作不可逆，窗口将完全释放
---@param target string|table 窗口名称或实例
function UIManager:Destroy(target)
    local window = type(target) == "string" and self:GetWindow(target) or target

    if not window then
        -- 可能只在缓存中
        window = type(target) == "string" and self.cache:Remove(target) or nil
    end

    if window then
        self:DestroyWindow(window)
    end
end

---执行窗口销毁的完整流程
---@param window table UIWindow 实例
function UIManager:DestroyWindow(window)
    self.stack:Remove(window)
    self.zoneManager:RemoveWindow(window)
    self.layerManager:RemoveWindow(window)
    self.cache:Remove(window:GetName())
    self.factory:DestroyRuntimeObject(window)
    window:Destroy()
    self.eventDispatcher:Dispatch("WindowDestroyed", window)
end

-- =============================================================================
-- 公共 API：返回
-- =============================================================================

---关闭当前顶部的焦点窗口（模拟 Android 返回键行为）
---@param reason string|nil 关闭原因
function UIManager:Back(reason)
    local top = self.zoneManager:GetTopWindow() or self.stack:Peek()
    if top then
        self:Close(top:GetName(), reason or "Back")
    end
end

-- =============================================================================
-- 公共 API：关闭所有窗口
-- =============================================================================

---关闭所有已知窗口（从顶层到底层依次关闭）
---@param reason string|nil 关闭原因
function UIManager:CloseAll(reason)
    local ordered = self.layerManager:GetOrderedWindows()
    for index = #ordered, 1, -1 do
        self:Close(ordered[index]:GetName(), reason or "CloseAll")
    end
end

-- =============================================================================
-- 公共 API：查询窗口
-- =============================================================================

---查找窗口实例（按层级、缓存、加载中的顺序查找）
---@param name string 窗口名称
---@return table|nil window 找到的窗口实例
function UIManager:GetWindow(name)
    -- 先在层级中查找
    for _, window in ipairs(self.layerManager:GetOrderedWindows()) do
        if window:GetName() == name then
            return window
        end
    end

    -- 在缓存中查找
    local cached = self.cache:Get(name)
    if cached then
        return cached
    end

    -- 在加载中查找
    return self.loadingWindows[name]
end

---判断窗口是否已打开
---@param name string 窗口名称
---@return boolean opened
function UIManager:IsOpen(name)
    local window = self:GetWindow(name)
    return window and window:IsOpened() or false
end

---判断窗口是否正在加载
---@param name string 窗口名称
---@return boolean loading
function UIManager:IsLoading(name)
    return self.loadingWindows[name] ~= nil
end

---返回当前打开的窗口数量
---@return number count
function UIManager:GetWindowCount()
    return #self.layerManager:GetOrderedWindows()
end

---返回加载中的窗口数量
---@return number count
function UIManager:GetLoadingCount()
    local count = 0
    for _ in pairs(self.loadingWindows) do
        count = count + 1
    end
    return count
end

-- =============================================================================
-- 公共 API：刷新窗口
-- =============================================================================

---刷新已打开的窗口
---如果窗口未打开或不存在，则忽略此操作
---@param name string 窗口名称
---@param ... any 刷新参数，传递给 MVC 的 OnRefresh 回调
function UIManager:Refresh(name, ...)
    local window = self:GetWindow(name)
    if window and window:IsOpened() then
        window:Refresh(...)
        self.eventDispatcher:Dispatch("WindowRefreshed", window)
    else
        Logger.Warn(string.format(
            "[UIManager] Cannot refresh window '%s': not opened or not found",
            tostring(name)
        ))
    end
end

-- =============================================================================
-- 公共 API：预加载
-- =============================================================================

---预加载窗口资源（不创建窗口实例）
---用于提前加载大型 Prefab，减少打开时的等待时间
---@param name string 窗口名称
---@param onComplete fun(asset:any)|nil 加载完成回调
---@return table token 可取消的加载令牌
function UIManager:Preload(name, onComplete)
    local config = self.config.Get(name)
    return self.resourceLoader:Preload(
        config.prefab or config.path or name,
        onComplete
    )
end

-- =============================================================================
-- 公共 API：事件订阅
-- =============================================================================

---订阅 UI Framework 事件
---框架事件包括：WindowLoading, WindowOpened, WindowClosed, WindowDestroyed, WindowRefreshed
---@param eventName string 事件名称
---@param callback fun(...:any) 回调函数
---@param owner any|nil 可选的所有者（用于批量取消订阅）
---@return number handle 监听器句柄
function UIManager:AddListener(eventName, callback, owner)
    return self.eventDispatcher:AddListener(eventName, callback, owner)
end

---取消订阅 UI Framework 事件
---@param handle number 监听器句柄
---@return boolean removed 是否成功取消
function UIManager:RemoveListener(handle)
    return self.eventDispatcher:RemoveListener(handle)
end

-- =============================================================================
-- 公共 API：输入阻断
-- =============================================================================

---阻断 UI 输入
---引用计数机制，每个 key 只能阻断一次，多次调用无害
---@param key string 唯一阻断键
---@param reason string|nil 阻断原因
function UIManager:BlockInput(key, reason)
    self.blockManager:Block(key, reason)
end

---解除 UI 输入阻断
---@param key string 唯一阻断键
function UIManager:UnblockInput(key)
    self.blockManager:Unblock(key)
end

---返回当前是否阻断输入
---@return boolean blocked
function UIManager:IsInputBlocked()
    return self.blockManager:IsBlocked()
end

-- =============================================================================
-- 公共 API：场景切换
-- =============================================================================

---场景切换时调用，处理 DestroyOnSceneChange 策略的窗口
---遍历所有缓存窗口，销毁标记为 DestroyOnSceneChange 的窗口
function UIManager:OnSceneChange()
    -- 先关闭所有打开的窗口
    self:CloseAll("SceneChange")

    -- 销毁标记为 DestroyOnSceneChange 的缓存窗口
    local toDestroy = {}
    for _, window in ipairs(self.cache:GetAll()) do
        local policy = window:GetConfig().cachePolicy
        if policy == UIEnums.CachePolicy.DestroyOnSceneChange then
            toDestroy[#toDestroy + 1] = window
        end
    end

    for _, window in ipairs(toDestroy) do
        self:DestroyWindow(window)
    end

    Logger.Info(string.format(
        "[UIManager] SceneChange: destroyed %d windows with DestroyOnSceneChange policy",
        #toDestroy
    ))
end

-- =============================================================================
-- 公共 API：调试
-- =============================================================================

---返回可读的框架快照字符串
---包含：阻断状态、缓存数量、栈数量、各窗口状态
---@return string dump
function UIManager:Dump()
    local lines = {}

    lines[#lines + 1] = string.format(
        "UIManager blocked=%s cache=%d stack=%d loading=%d",
        tostring(self.blockManager:IsBlocked()),
        self.cache:Count(),
        self.stack:Count(),
        self:GetLoadingCount()
    )

    for _, window in ipairs(self.layerManager:GetOrderedWindows()) do
        lines[#lines + 1] = "- " .. window:Snapshot()
    end

    if self.cache:Count() > 0 then
        lines[#lines + 1] = "--- Cached ---"
        for _, window in ipairs(self.cache:GetAll()) do
            lines[#lines + 1] = "- " .. window:Snapshot()
        end
    end

    return table.concat(lines, "\n")
end

---打印当前 UI 框架快照到日志
function UIManager:LogDump()
    Logger.Info(self:Dump())
end

return UIManager