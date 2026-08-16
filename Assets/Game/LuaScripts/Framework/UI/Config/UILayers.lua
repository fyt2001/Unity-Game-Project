--[[
=============================================================================
UILayers.lua
=============================================================================
Module:     Framework/UI/Config/UILayers
Version:    3.1.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UILayers 定义 UI 层级配置，决定每个 Canvas 的渲染顺序和层间距。
    层级顺序从低到高：Scene < Background < Normal < Popup < Toast < Guide < Top < Debug

    每个层级定义：
        - name: 层级显示名称
        - order: 基础排序值（用于 Canvas.sortingOrder）
        - planeDistance: 平面距离（控制 3D 空间中的 z 轴偏移）

Dependencies:
    无外部依赖

Usage:
    local layers = require "NewObject.Framework.UI.Config.UILayers"
    local normalOrder = layers.Normal.order
=============================================================================
]]

local UILayers = {
    -- 场景层：3D 场景或全屏背景
    -- 位于最底层，所有 UI 元素之上
    Scene = {
        name = "Scene",
        order = 0,
        planeDistance = 1000,
    },

    -- 背景层：全屏背景界面（如主界面、场景背景）
    Background = {
        name = "Background",
        order = 100,
        planeDistance = 1000,
    },

    -- 普通层：大多数 UI 窗口的默认层级
    Normal = {
        name = "Normal",
        order = 200,
        planeDistance = 1000,
    },

    -- 弹窗层：模态对话框、确认框
    Popup = {
        name = "Popup",
        order = 300,
        planeDistance = 1000,
    },

    -- 提示层：Toast、提示消息
    Toast = {
        name = "Toast",
        order = 400,
        planeDistance = 1000,
    },

    -- 引导层：新手引导遮罩和高亮
    Guide = {
        name = "Guide",
        order = 500,
        planeDistance = 1000,
    },

    -- 加载层：启动Loading、场景切换Loading、全屏加载遮罩
    -- 位于 Guide 之上、Top 之下，确保覆盖普通UI但低于系统级弹窗
    Loading = {
        name = "Loading",
        order = 620,
        planeDistance = 1000,
    },

    -- 顶层：系统级弹窗（如网络错误、踢下线）
    Top = {
        name = "Top",
        order = 600,
        planeDistance = 1000,
    },

    -- 调试层：调试信息、性能面板
    Debug = {
        name = "Debug",
        order = 700,
        planeDistance = 1000,
    },
}

---返回所有层级键名列表
---@return table keys 层级键名数组
function UILayers.GetLayerKeys()
    return { "Scene", "Background", "Normal", "Popup", "Toast", "Guide", "Loading", "Top", "Debug" }
end

---返回层级数量
---@return number count
function UILayers.GetLayerCount()
    return 9
end

return UILayers