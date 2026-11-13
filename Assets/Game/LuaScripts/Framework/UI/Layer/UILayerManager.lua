--[[
=============================================================================
UILayerManager.lua
=============================================================================
Module:     Framework/UI/Layer/UILayerManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
	UILayerManager 管理 UI 层级（Canvas 层级）的运行时根节点和排序顺序。
	每个层级对应一个 Canvas，层级之间通过 order 决定渲染顺序。

	层级配置来自 UILayers 模块，定义了 Scene、Background、Normal、Popup、
	Toast、Guide、Top、Debug 等层级及其排序和间距。

	每个窗口分配一个递增的排序值，确保同一层级内的窗口按打开顺序渲染。

Dependencies:
	- Class (类系统)
	- UILayers (层级配置)

Usage:
	local layerMgr = UILayerManager.New(root, layers)
	local order = layerMgr:AddWindow(window, "Normal")
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UILayers = require "Framework.UI.Config.UILayers"
local Logger = require "Framework.UI.Utils.Logger"

local UILayerManager = Class.Define("UILayerManager")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化层级数据
---@param root any|nil UIRoot 适配器或 Unity Transform
---@param layerConfigs table|nil 层级配置表，默认使用 UILayers
function UILayerManager:Ctor(root, layerConfigs)
	self.root = root
	self.layerConfigs = layerConfigs or UILayers
	self.layers = {}
	self.windowOrders = {}
	self.orderStep = 50
	self:BuildLayers()
	self:EnsureSceneHierarchy()
end

-- =============================================================================
-- 私有方法：构建层级
-- =============================================================================

---从配置构建运行时层级记录
function UILayerManager:BuildLayers()
	for key, config in pairs(self.layerConfigs) do
		if type(config) == "table" then
			self.layers[key] = {
				key = key,
				name = config.name or key,
				order = config.order or 0,
				planeDistance = config.planeDistance or 1000,
				root = nil,
				windows = {},
				nextOrder = config.order or 0,
			}
		end
	end
end

function UILayerManager:EnsureSceneHierarchy()
	local UIRootPath = "UIRoot"
	local UICameraPath = "UICamera"

	local uiRoot = CS.UnityEngine.GameObject.Find(UIRootPath)
	if not uiRoot then
		uiRoot = CS.UnityEngine.GameObject(UIRootPath)
		CS.UnityEngine.Object.DontDestroyOnLoad(uiRoot)
		Logger.Info("UILayerManager", "Created UIRoot (no Canvas, container only)")
	end

	self.uiRoot = uiRoot
	self.root = uiRoot.transform

	local uiCameraTrans = uiRoot.transform:Find(UICameraPath)
	local uiCameraGo = uiCameraTrans and uiCameraTrans.gameObject
	if not uiCameraGo then
		uiCameraGo = CS.UnityEngine.GameObject.Find(UICameraPath)
	end

	if not uiCameraGo then
		uiCameraGo = CS.UnityEngine.GameObject(UICameraPath)
		uiCameraGo.transform:SetParent(uiRoot.transform, false)
		uiCameraGo.layer = 5

		local camera = uiCameraGo:AddComponent(typeof(CS.UnityEngine.Camera))
		camera.clearFlags = CS.UnityEngine.CameraClearFlags.Depth
		camera.orthographic = true
		camera.orthographicSize = 10
		camera.depth = 2
		camera.cullingMask = 32
		camera.nearClipPlane = 0.3
		camera.farClipPlane = 1500

		-- 与 EventSystem 同理：本对象刚被 SetParent 到 uiRoot，已不是根物体，
		-- 对非根物体调用 DontDestroyOnLoad 会报
		-- "DontDestroyOnLoad only works for root GameObjects"。
		-- 父级 uiRoot 已 DontDestroyOnLoad（见上方创建处），子物体会一并保留。
		Logger.Info("UILayerManager", "Created UICamera (orthographic, cullingMask=UI)")
	end

	self.uiCamera = uiCameraGo:GetComponent(typeof(CS.UnityEngine.Camera))
	if not self.uiCamera then
		self.uiCamera = uiCameraGo:AddComponent(typeof(CS.UnityEngine.Camera))
		self.uiCamera.clearFlags = CS.UnityEngine.CameraClearFlags.Depth
		self.uiCamera.orthographic = true
		self.uiCamera.orthographicSize = 10
		self.uiCamera.depth = 2
		self.uiCamera.cullingMask = 32
		self.uiCamera.nearClipPlane = 0.3
		self.uiCamera.farClipPlane = 1500
	end

	local eventSystem = CS.UnityEngine.GameObject.Find("EventSystem")
	if not eventSystem then
		eventSystem = CS.UnityEngine.GameObject("EventSystem")
		eventSystem.transform:SetParent(uiRoot.transform, false)
		-- 不要在这里调用 DontDestroyOnLoad：本对象已是 uiRoot 的子物体，
		-- 而 DontDestroyOnLoad 只对「根物体」生效，对非根调用会报
		-- "DontDestroyOnLoad only works for root GameObjects"。
		-- 父级 uiRoot 已 DontDestroyOnLoad（见上方创建处），子物体会一并保留，因此无需重复设置。
		Logger.Info("UILayerManager", "Created EventSystem")
	end
	-- 无论场景是否自带 EventSystem，都确保具备点击必需的组件
	-- （对齐 H02：场景自带 EventSystem 可能只挂了 EventSystem 而缺 StandaloneInputModule，
	--   会导致按钮点击无响应；故不再仅在「新建」时补组件，已存在也补）
	if not eventSystem:GetComponent(typeof(CS.UnityEngine.EventSystems.EventSystem)) then
		eventSystem:AddComponent(typeof(CS.UnityEngine.EventSystems.EventSystem))
	end
	if not eventSystem:GetComponent(typeof(CS.UnityEngine.EventSystems.StandaloneInputModule)) then
		eventSystem:AddComponent(typeof(CS.UnityEngine.EventSystems.StandaloneInputModule))
	end

	local sortedLayers = {}
	for key, layer in pairs(self.layers) do
		sortedLayers[#sortedLayers + 1] = { key = key, layer = layer }
	end
	table.sort(sortedLayers, function(a, b)
		return a.layer.order < b.layer.order
	end)

	for _, entry in ipairs(sortedLayers) do
		local key = entry.key
		local layer = entry.layer
		local layerName = layer.name
		local planeDistance = layer.planeDistance or (1000 - layer.order / 10)

		local child = uiRoot.transform:Find(layerName)
		if not child then
			local go = CS.UnityEngine.GameObject(layerName)
			go.layer = 5

			local layerCanvas = go:AddComponent(typeof(CS.UnityEngine.Canvas))
			layerCanvas.renderMode = CS.UnityEngine.RenderMode.ScreenSpaceCamera
			layerCanvas.worldCamera = self.uiCamera
			layerCanvas.planeDistance = planeDistance
			layerCanvas.sortingOrder = layer.order

			local scaler = go:AddComponent(typeof(CS.UnityEngine.UI.CanvasScaler))
			scaler.uiScaleMode = CS.UnityEngine.UI.CanvasScaler.ScaleMode.ScaleWithScreenSize
			scaler.screenMatchMode = CS.UnityEngine.UI.CanvasScaler.ScreenMatchMode.MatchWidthOrHeight
			scaler.referenceResolution = CS.UnityEngine.Vector2(1080, 2400)
			scaler.matchWidthOrHeight = 0.5

			go:AddComponent(typeof(CS.UnityEngine.UI.GraphicRaycaster))

			go.transform:SetParent(uiRoot.transform, false)

			child = go.transform
			Logger.Info("UILayerManager", "Created layer: %s (order=%d, planeDistance=%d, ScreenSpaceCamera+UICamera)",
				layerName, layer.order, planeDistance)
		else
			local existingCanvas = child.gameObject:GetComponent(typeof(CS.UnityEngine.Canvas))
			if existingCanvas and existingCanvas.worldCamera == nil and self.uiCamera then
				existingCanvas.renderMode = CS.UnityEngine.RenderMode.ScreenSpaceCamera
				existingCanvas.worldCamera = self.uiCamera
				existingCanvas.planeDistance = planeDistance
				Logger.Info("UILayerManager", "Fixed existing layer Canvas: %s -> ScreenSpaceCamera+UICamera", layerName)
			end
		end

		layer.root = child
	end
end

-- =============================================================================
-- 公共 API：层级查询
-- =============================================================================

---获取指定层级的运行时记录
---@param layerKey string 层级键名（如 "Normal"、"Popup"）
---@return table layer 层级记录
function UILayerManager:GetLayer(layerKey)
	local layer = self.layers[layerKey]
	assert(layer, "missing UI layer: " .. tostring(layerKey))
	return layer
end

---返回所有层级键名
---@return table keys 层级键名数组
function UILayerManager:GetLayerKeys()
	local keys = {}
	for key, _ in pairs(self.layers) do
		keys[#keys + 1] = key
	end
	return keys
end

---判断层级是否存在
---@param layerKey string 层级键名
---@return boolean exists
function UILayerManager:HasLayer(layerKey)
	return self.layers[layerKey] ~= nil
end

-- =============================================================================
-- 公共 API：窗口管理
-- =============================================================================

---将窗口添加到指定层级，分配排序值
---如果窗口已在其他层级中，会先从旧层级移除
---@param window table UIWindow 实例
---@param layerKey string 层级键名
---@return number order 分配的排序值
function UILayerManager:AddWindow(window, layerKey)
	local layer = self:GetLayer(layerKey)

	-- 先从旧层级中移除
	self:RemoveWindow(window)

	-- 添加到新层级
	layer.windows[#layer.windows + 1] = window
	layer.nextOrder = layer.nextOrder + self.orderStep

	self.windowOrders[window] = {
		layerKey = layerKey,
		order = layer.nextOrder,
	}

	window.layerName = layerKey
	return layer.nextOrder
end

---从当前层级中移除窗口
---@param window table UIWindow 实例
function UILayerManager:RemoveWindow(window)
	local record = self.windowOrders[window]
	if not record then
		return
	end

	local layer = self.layers[record.layerKey]
	if layer then
		for index = #layer.windows, 1, -1 do
			if layer.windows[index] == window then
				table.remove(layer.windows, index)
				break
			end
		end
	end

	self.windowOrders[window] = nil
end

-- =============================================================================
-- 公共 API：排序查询
-- =============================================================================

---获取窗口的排序值
---@param window table UIWindow 实例
---@return number|nil order 排序值，不存在返回 nil
function UILayerManager:GetWindowOrder(window)
	local record = self.windowOrders[window]
	return record and record.order or nil
end

---获取窗口所在的层级键名
---@param window table UIWindow 实例
---@return string|nil layerKey
function UILayerManager:GetWindowLayer(window)
	local record = self.windowOrders[window]
	return record and record.layerKey or nil
end

-- =============================================================================
-- 公共 API：窗口遍历
-- =============================================================================

---返回所有层级中窗口的有序列表（从底层到顶层）
---先按层级 order 排序，同一层级内按添加顺序
---@return table windows 有序窗口数组
function UILayerManager:GetOrderedWindows()
	local result = {}

	-- 按 order 排序层级
	local sortedLayers = {}
	for _, layer in pairs(self.layers) do
		sortedLayers[#sortedLayers + 1] = layer
	end
	table.sort(sortedLayers, function(a, b)
		return a.order < b.order
	end)

	-- 按层级顺序收集窗口
	for _, layer in ipairs(sortedLayers) do
		for _, window in ipairs(layer.windows) do
			result[#result + 1] = window
		end
	end

	return result
end

---获取指定层级中的窗口列表
---@param layerKey string 层级键名
---@return table windows 窗口数组
function UILayerManager:GetWindowsInLayer(layerKey)
	local layer = self.layers[layerKey]
	if not layer then
		return {}
	end
	local result = {}
	for _, window in ipairs(layer.windows) do
		result[#result + 1] = window
	end
	return result
end

---获取指定层级中的顶层窗口
---@param layerKey string 层级键名
---@return table|nil window 顶层窗口
function UILayerManager:GetTopWindowInLayer(layerKey)
	local layer = self.layers[layerKey]
	if not layer then
		return nil
	end
	return layer.windows[#layer.windows]
end

-- =============================================================================
-- 公共 API：批量操作
-- =============================================================================

---清空所有层级记录（不关闭或销毁窗口）
function UILayerManager:Clear()
	for _, layer in pairs(self.layers) do
		layer.windows = {}
		layer.nextOrder = layer.order
	end
	self.windowOrders = {}
end

return UILayerManager