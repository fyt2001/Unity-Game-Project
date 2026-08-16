--[[
=============================================================================
UISettings.lua
=============================================================================
Module:     Framework/UI/Config/UISettings
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UISettings 定义 UI 框架的全局配置参数，包括默认值、限制和调优常量。
    项目可通过修改此文件的默认值来调整框架行为，无需修改核心代码。

    配置项：
        - 默认缓存策略、Zone 策略、打开模式
        - 输入阻塞超时限制
        - 资源加载超时
        - 动画参数
        - 层级排序步长
        - 调试开关

Dependencies:
    - UIEnums (引用枚举默认值)

Usage:
    local settings = require "NewObject.Framework.UI.Config.UISettings"
    local cachePolicy = settings.DefaultCachePolicy
=============================================================================
]]

local UIEnums = require "NewObject.Framework.UI.Config.UIEnums"

local UISettings = {
    -- =========================================================================
    -- 默认策略
    -- =========================================================================

    DefaultCachePolicy = UIEnums.CachePolicy.DestroyOnClose,
    DefaultZonePolicy = UIEnums.ZonePolicy.Normal,
    DefaultOpenMode = UIEnums.OpenMode.Stack,

    -- =========================================================================
    -- 输入阻塞
    -- =========================================================================

    BlockTimeout = 10.0,
    BlockOnLoad = true,
    BlockOnOpenAnimation = true,
    BlockOnCloseAnimation = true,

    -- =========================================================================
    -- 资源加载
    -- =========================================================================

    ResourceLoadTimeout = 15.0,
    ResourcePreloadCount = 5,

    -- =========================================================================
    -- 动画
    -- =========================================================================

    DefaultOpenAnimationDuration = 0.3,
    DefaultCloseAnimationDuration = 0.2,
    EnableAnimation = true,

    -- =========================================================================
    -- 层级
    -- =========================================================================

    LayerOrderStep = 50,

    -- =========================================================================
    -- 缓存
    -- =========================================================================

    MaxCachedWindows = 20,
    MaxCachedAssets = 50,

    -- =========================================================================
    -- 调试
    -- =========================================================================

    EnableDebugLog = false,
    EnableStateValidation = true,
    EnablePerformanceMonitor = false,
}

---返回所有配置项的键名列表
---@return table keys
function UISettings.GetKeys()
    local keys = {}
    for key, _ in pairs(UISettings) do
        if type(UISettings[key]) ~= "function" then
            keys[#keys + 1] = key
        end
    end
    return keys
end

return UISettings