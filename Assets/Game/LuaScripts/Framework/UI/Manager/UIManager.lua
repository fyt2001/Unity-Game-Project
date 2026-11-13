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
	Shutdown()                       - 终止加载并销毁所有窗口（不可再打开）
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
	local UIFramework = require "Framework.UI.UIFramework"
	local ui = UIFramework.Create()
	ui:Open("Bag", bagId)
	ui:Close("Bag", "UserClosed")
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"
local UIEnums = require "Framework.UI.Config.UIEnums"
local UIWindowConfig = require "Framework.UI.Config.UIWindowConfig"
local UIResourceLoader = require "Framework.UI.Resource.UIResourceLoader"
local UIAnimationManager = require "Framework.UI.Animation.UIAnimationManager"
local UIEventDispatcher = require "Framework.UI.Event.UIEventDispatcher"
local UIWindowCache = require "Framework.UI.Cache.UIWindowCache"
local UIWindowStack = require "Framework.UI.Manager.UIWindowStack"
local UIWindowFactory = require "Framework.UI.Manager.UIWindowFactory"
local UILayerManager = require "Framework.UI.Layer.UILayerManager"
local UIZoneManager = require "Framework.UI.Zone.UIZoneManager"
local UIBlockManager = require "Framework.UI.Manager.UIBlockManager"

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
	if self._shutdown then return nil end
	self._openTimers = self._openTimers or {}
	self._openTimers[name] = os.clock()
	Logger.Debug("UIManager", "Open called: %s", tostring(name))

	if not self.config.Has(name) then
		Logger.Error("UIManager", "Open FAILED: config not found for '%s'", tostring(name))
		return nil
	end
	local config = self.config.Get(name)

	Logger.Debug("UIManager", "Open config found: %s, prefab=%s, path=%s, layer=%s",
		tostring(name), tostring(config.prefab), tostring(config.path), tostring(config.layer))

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

	-- 处理 SingleTop 模式：同名单例窗口只保留一个实例，杜绝重复 Clone
	-- SingleTop 语义即“单例/栈顶唯一”。无论旧实例处于 打开 / 正在加载 / 已缓存(关闭·隐藏)
	-- 任一状态，都复用同一实例，而不是再次 CreateWindow + Instantiate 出新 Clone。
	-- 原先只判断 stack:Peek()，会漏掉“仍加载中”或“在图层非栈顶”的同名实例，
	-- 导致 Home→Battle 切换时旧 HomePanel(Clone) 未被复用、又新建一个 → 两个 Clone。
	if config.openMode == UIEnums.OpenMode.SingleTop then
		local existing = self:GetWindow(name)
		if existing and not existing:IsDestroyed() then
			if existing:IsLoading() then
				-- 已在异步加载中：直接复用，避免再次发起加载产生第二个 Clone
				Logger.Debug("UIManager", "SingleTop '%s' still loading, reuse instance", name)
				return existing
			elseif existing:IsOpened() or existing:IsOpening() or existing:IsFocused() or existing:IsHidden() then
				-- 已打开/正在打开/已聚焦/已隐藏：实例仍在图层中，刷新数据即可，不重建
				-- （Hidden 也走此分支，避免 OpenExistingWindow 把仍在图层的实例二次入栈/入层）
				existing:Refresh(table.unpack(openArgs, 1, openArgs.n))
				self.eventDispatcher:Dispatch("WindowRefreshed", existing)
				return existing
			else
				-- Closed / Hidden：复用实例重新打开（OpenExistingWindow 负责显示 + 入栈 + 播放动画）
				Logger.Debug("UIManager", "SingleTop '%s' cached/closed, reuse instance", name)
				return self:OpenExistingWindow(existing, table.unpack(openArgs, 1, openArgs.n))
			end
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
	self.loadingWindows[name] = window

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
	if self._shutdown then return end
	local winName = window:GetName()
	Logger.Debug("UIManager", "OnWindowAssetLoaded: window=%s", winName)

	-- 检查令牌是否被取消，或窗口是否已被销毁
	if (token and token.cancelled) or window:IsDestroyed() then
		Logger.Warn("UIManager", "OnWindowAssetLoaded CANCELLED: %s", winName)
		-- A late callback must not release a replacement window's input block.
		if self.loadingWindows[winName] == window then
			self.loadingWindows[winName] = nil
			self.blockManager:Unblock("UI_Loading_" .. winName, "Window loading")
		elseif not self.loadingWindows[winName] then
			self.blockManager:Unblock("UI_Loading_" .. winName, "Window loading")
		end
		return
	end

	if not asset then
		Logger.Error("UIManager", "OnWindowAssetLoaded FAILED: asset is nil for %s", winName)
		self.loadingWindows[winName] = nil
		self.blockManager:Unblock("UI_Loading_" .. winName, "Window loading")
		return
	end

	Logger.Debug("UIManager", "OnWindowAssetLoaded: asset type=%s",
		tostring(asset:GetType()))

	local openArgs = table.pack(...)

	self.loadingWindows[winName] = nil

	window:CompleteLoading()

	local gameObject = self.resourceLoader:Instantiate(asset)
	Logger.Debug("UIManager", "Instantiated: %s",
		gameObject and gameObject.name or "NULL")

	if not gameObject then
		Logger.Error("UIManager", "OnWindowAssetLoaded FAILED: Instantiate returned nil for %s", winName)
		self.blockManager:Unblock("UI_Loading_" .. winName, "Window loading")
		return
	end

	local layerKey = window:GetConfig().layer or "Normal"
	local layer = self.layerManager:GetLayer(layerKey)
	local parentTransform = layer and layer.root

	if not parentTransform then
		parentTransform = self.layerManager.root
	end

	if parentTransform and gameObject.transform then
		gameObject.transform:SetParent(parentTransform, false)
		Logger.Debug("UIManager", "Parented to layer '%s': %s",
			layerKey, parentTransform.name)

		-- 关键：把窗口连同所有子物体对齐到所属层容器的 layer。
		-- 层 Canvas 走 ScreenSpaceCamera + 专用 UICamera（cullingMask=UI 层），
		-- 而 prefab 默认是 Default 层(layer 0)，不对齐就会「打开了但完全看不见」。
		self:_ApplyLayerRecursive(gameObject.transform, parentTransform)
	else
		Logger.Warn("UIManager", "WARNING: Cannot parent. parentTransform=%s, gameObject=%s",
			parentTransform and "exists" or "nil",
			gameObject and gameObject.name or "nil")
	end

	-- 全屏窗口：将根 RectTransform 拉伸铺满父级 Canvas。
	-- 很多 prefab 根节点默认是 100x100 居中（anchorMin=anchorMax=(0.5,0.5)），
	-- 若不撑满，子节点（TopBar/BottomBar 等）会被压成屏幕中央的小方块。
	if window:GetConfig().fullscreen then
		local RectTransformType = typeof(CS.UnityEngine.RectTransform)
		local rectT = gameObject:GetComponent(RectTransformType)
		if rectT then
			rectT.anchorMin = CS.UnityEngine.Vector2(0, 0)
			rectT.anchorMax = CS.UnityEngine.Vector2(1, 1)
			rectT.sizeDelta = CS.UnityEngine.Vector2(0, 0)
			rectT.anchoredPosition = CS.UnityEngine.Vector2(0, 0)
			rectT.pivot = CS.UnityEngine.Vector2(0.5, 0.5)
			Logger.Debug("UIManager", "Stretched fullscreen window '%s' to fill layer '%s'",
				winName, layerKey)
		end
	end

	self:_fixWindowCanvas(gameObject, layerKey)

	-- 创建 MVC
	local ok, err = pcall(function()
		self.factory:CreateMVC(window, gameObject)
	end)
	if not ok then
		Logger.Error("UIManager", "CreateMVC FAILED: %s", tostring(err))
	else
		Logger.Debug("UIManager", "CreateMVC OK for %s", winName)
	end

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
		self.blockManager:Unblock("UI_Loading_" .. winName, "Window loading")
		self.eventDispatcher:Dispatch("WindowOpened", window)
		self:_reportOpenCost(winName)
		Logger.Debug("UIManager", "WindowOpened dispatched: %s", winName)
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

	-- 关闭时被隐藏的 GameObject 需重新显示，否则重开后一直不可见
	self:_SetWindowActive(window, true)

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
		self:_reportOpenCost(window:GetName())
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
	local loading = self.loadingWindows[name]
	if loading and loading:IsLoading() then
		if loading.loadingToken then
			self.resourceLoader:Cancel(loading.loadingToken)
		end
		loading:Close(reason or "CancelLoading")
		self.loadingWindows[name] = nil
		self.blockManager:Unblock("UI_Loading_" .. name, "Window loading")
		return
	end

	local window = self:GetWindow(name)
	if not window then
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
		self.blockManager:Unblock("UI_Closing_" .. name, "Window closing")
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
		-- 永久缓存：不销毁，但必须隐藏 GameObject，否则会一直挂在层级上可见
		self.cache:Put(window)
		self:_SetWindowActive(window, false)
	elseif policy == UIEnums.CachePolicy.CacheOnClose then
		-- 关闭时缓存：保留逻辑窗口，并隐藏 GameObject
		self.cache:Put(window)
		self:_SetWindowActive(window, false)
	elseif policy == UIEnums.CachePolicy.DestroyOnSceneChange then
		-- 场景切换时销毁：当前关闭时缓存，OnSceneChange 时统一销毁，先隐藏
		self.cache:Put(window)
		self:_SetWindowActive(window, false)
	else
		-- DestroyOnClose：立即销毁（销毁流程会释放 GameObject）
		self:DestroyWindow(window)
	end
end

---显示 / 隐藏窗口的运行时 GameObject
---缓存类策略关闭窗口后需要隐藏，重开前需要重新显示，避免"状态 Closed 但画面还在"
---@param window table UIWindow 实例
---@param active boolean 是否激活
---把窗口根节点及所有子物体对齐到父层容器的 layer
---@param transform any 窗口根节点 Transform
---@param parentTransform any 层容器 Transform
function UIManager:_ApplyLayerRecursive(transform, parentTransform)
	if not transform or not parentTransform then return end

	pcall(function()
		local targetLayer = parentTransform.gameObject.layer
		self:_SetLayerRecursive(transform, targetLayer)
	end)
end

function UIManager:_SetLayerRecursive(transform, layer)
	transform.gameObject.layer = layer
	for i = 0, transform.childCount - 1 do
		self:_SetLayerRecursive(transform:GetChild(i), layer)
	end
end

function UIManager:_SetWindowActive(window, active)
	local go = window and window:GetGameObject()
	if go and go.SetActive then
		go:SetActive(active)
	end
end

---打印窗口打开耗时（从 Open 调用到打开动画完成）
---@param name string 窗口名称
function UIManager:_reportOpenCost(name)
	if not self._openTimers then return end
	local t0 = self._openTimers[name]
	if not t0 then return end
	Logger.Info(name, "open cost %.1f ms", (os.clock() - t0) * 1000)
	self._openTimers[name] = nil
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

-- Unlike CloseAll, teardown must include cached and still-loading windows.
function UIManager:Shutdown()
	if self._shutdown then return end
	self._shutdown = true
	self.animationManager:StopAll()
	local windows, seen = {}, {}
	local function include(window)
		if window and not seen[window] then
			seen[window] = true
			windows[#windows + 1] = window
		end
	end
	for _, window in ipairs(self.layerManager:GetOrderedWindows()) do include(window) end
	for _, window in ipairs(self.cache:GetAll()) do include(window) end
	for _, window in pairs(self.loadingWindows) do
		if window.loadingToken then self.resourceLoader:Cancel(window.loadingToken) end
		include(window)
	end
	local root = self.layerManager.uiRoot
	if root then CS.UIRuntimeCleanup.ReleaseCallbacks(root) end
	self.loadingWindows = {}
	for index = #windows, 1, -1 do self:DestroyWindow(windows[index]) end
	self.blockManager:ForceClear()
	self.eventDispatcher:Clear()
	self._openTimers = {}
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
	if self._shutdown then return nil end
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

-- =============================================================================
-- 私有方法：修复窗口 Canvas（对齐 H02 UILayer.OnCreate 的运行时修复）
-- =============================================================================

---修复预制体实例中的 Canvas 组件
---H02 的预制体（如 UILogin）根节点和子节点可能自带 Canvas 组件，
---renderMode=ScreenSpaceCamera 但 worldCamera=nil（H02 在 UILayer.OnCreate 中
---运行时设置 worldCamera=UIManager.UICamera）。
---当前项目层级 Canvas 使用 ScreenSpaceCamera+UICamera（对齐 H02 架构），
---因此需要：
---1. 将 ScreenSpaceCamera(nil camera) 的 Canvas 继承父 Canvas 的渲染模式和 Camera
---2. 将 ScreenSpaceOverlay 的子 Canvas（不应存在于 ScreenSpaceCamera 父级下）也继承父模式
---3. 设置 overrideSorting=true 以支持层级内排序
---4. 分配 sortingOrder（从 LayerManager 获取，确保层级内窗口按打开顺序渲染）
---@param gameObject any 实例化的窗口 GameObject
---@param layerKey string 层级键名
function UIManager:_fixWindowCanvas(gameObject, layerKey)
	if not gameObject then return end

	local RenderMode = CS.UnityEngine.RenderMode
	local CanvasType = typeof(CS.UnityEngine.Canvas)

	local layerOrder = 0
	if layerKey then
		local layer = self.layerManager:GetLayer(layerKey)
		if layer then
			layerOrder = layer.order or 0
		end
	end

	local windowOrder = 0
	local layerRecord = layerKey and self.layerManager:GetLayer(layerKey)
	if layerRecord then
		layerRecord.nextOrder = (layerRecord.nextOrder or layerOrder) + self.layerManager.orderStep
		windowOrder = layerRecord.nextOrder
	end

	-- 判断 Canvas 是否真实有效：Unity 的“假 null”/已销毁组件访问属性会抛异常，
	-- 用 pcall 探测 renderMode，比 IsNull(ReferenceEquals) 更可靠（ReferenceEquals 对假 null 返回 false）。
	local function _canvasValid(c)
		if c == nil then return false end
		local ok = pcall(function() return c.renderMode ~= nil end)
		return ok
	end

	local function fixCanvas(c, isRoot)
		if not _canvasValid(c) then return end
		local needsFix = false

		if c.renderMode == RenderMode.ScreenSpaceCamera and c.worldCamera == nil then
			needsFix = true
		end

		if c.renderMode == RenderMode.ScreenSpaceOverlay then
			local parentT = c.transform.parent
			if parentT then
				local parentCanvas = parentT.gameObject:GetComponent(CanvasType)
				if _canvasValid(parentCanvas) then
					needsFix = true
				end
			end
		end

		if needsFix then
			local parentT = c.transform.parent
			local parentGO = parentT and parentT.gameObject
			local parentCanvas = parentGO and parentGO:GetComponent(CanvasType)

			if _canvasValid(parentCanvas) then
				c.renderMode = parentCanvas.renderMode
				if parentCanvas.renderMode == RenderMode.ScreenSpaceCamera then
					c.worldCamera = parentCanvas.worldCamera
					c.planeDistance = math.max(parentCanvas.planeDistance - 1, 0.1)
				end
				Logger.Debug("UIManager", "Fixed %s Canvas: %s -> inherit parent (renderMode=%s, hasCamera=%s)",
					isRoot and "root" or "child",
					c.gameObject.name,
					tostring(parentCanvas.renderMode),
					tostring(parentCanvas.worldCamera ~= nil))
			else
				c.renderMode = RenderMode.ScreenSpaceOverlay
				Logger.Debug("UIManager", "Fixed %s Canvas: %s -> ScreenSpaceOverlay (no parent Canvas)",
					isRoot and "root" or "child", c.gameObject.name)
			end
		end

		if not c.overrideSorting then
			c.overrideSorting = true
		end

		if isRoot and windowOrder > 0 then
			c.sortingOrder = windowOrder
		end
	end

	local rootCanvas = gameObject:GetComponent(CanvasType)
	if _canvasValid(rootCanvas) then
		fixCanvas(rootCanvas, true)
	end

	local canvases = gameObject:GetComponentsInChildren(CanvasType, true)
	if not canvases then return end

	for i = 0, canvases.Length - 1 do
		local c = canvases[i]
		if c and c ~= rootCanvas then
			fixCanvas(c, false)
		end
	end
end

return UIManager
