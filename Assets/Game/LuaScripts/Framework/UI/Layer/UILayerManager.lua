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

local Class = require "Framework.UI.Utils.Class"
local UILayers = require "Framework.UI.Config.UILayers"

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
end

-- =============================================================================
-- 私有方法：构建层级
-- =============================================================================

---从配置构建运行时层级记录
function UILayerManager:BuildLayers()
    for key, config in pairs(self.layerConfigs) do
        -- 过滤非 table 值（如 GetLayerKeys 等函数）
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