--[[
=============================================================================
SceneConfig.lua - 场景配置表
=============================================================================
Module:     Game/Scene/SceneConfig
Version:    1.0.0
Description:
    定义项目中所有场景的配置信息。
    生产项目中通常由 Excel/配置平台自动生成。
=============================================================================
]]

local SceneConfig = {
    -- 启动场景（空场景，仅用于初始化框架）
    Launch = {
        Name = "Launch",
        LuaScript = nil,            -- Launch 场景不需要 Lua 脚本
        ShowLoading = true,
        LoadingText = "正在初始化...",
        PreLoadAssets = {},
    },

    -- 登录场景
    Login = {
        Name = "LoginScene",
        LuaScript = "Game.Scene.LoginScene",
        ShowLoading = true,
        LoadingText = "正在进入登录...",
        PreLoadAssets = {
            -- "UI/Login/LoginPanel",
        },
    },

    -- 主城场景
    Home = {
        Name = "HomeScene",
        LuaScript = "Game.Scene.HomeScene",
        ShowLoading = true,
        LoadingText = "正在进入主城...",
        PreLoadAssets = {
            -- "UI/Home/HomePanel",
        },
    },

    -- 战斗测试场景
    TestBattle = {
        Name = "TestBattle",
        LuaScript = "Game.Scene.BattleScene",
        ShowLoading = true,
        LoadingText = "正在准备战斗...",
        PreLoadAssets = {},
    },
}

return SceneConfig
