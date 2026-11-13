--[[
=============================================================================
SceneConfig.lua - 场景配置表（参考 ShaoNvClient_H02 SceneConfig）
=============================================================================
Module:     Game/Scene/SceneConfig
Version:    2.0.0
Description:
	定义项目中所有场景的配置信息。
	Level 对应 BuildSettings 中的场景索引（File → Build Settings → Scenes in Build）。
	使用 Level 加载比 Name 更可靠，不依赖场景文件名。

	Changelog:
		v2.0.0 - 新增 Level 字段，对齐 ShaoNvClient_H02 架构
		v1.0.0 - 初始版本
=============================================================================
]]

local SceneConfig = {
	-- 启动场景（空场景，仅用于初始化框架）
	Launch = {
		Level = 0,
		Name = "Launch",
		LuaScript = nil,
		ShowLoading = true,
		LoadingText = "正在初始化...",
		PreLoadAssets = {},
	},

	-- 登录场景
	Login = {
		Level = 1,
		Name = "LoginScene",
		LuaScript = "Game.Scene.LoginScene",
		ShowLoading = true,
		LoadingText = "正在进入登录...",
		PreLoadAssets = {
			"UI/Login/LoginPanel",
		},
	},

	-- 主城/主界面场景（真正的 3D 主场景）
	-- 【重要】Home 现使用 HomeScene.unity 作为场景内容（BuildSettings index = 2）。
	--   场景摄像头俯视观察人物（TopDownCameraFollow），
	--   UI 摄像头下渲染 HomePanel（摇杆 + HUD）。
	--   角色可用摇杆或点击地面移动；走入 CavePortal 洞口传送到 Battle 场景。
	--   详见 Game/Scene/HomeScene.lua 头部架构说明。
	Home = {
		Level = 2,
		Name = "HomeScene",
		LuaScript = "Game.Scene.HomeScene",
		ShowLoading = true,
		LoadingText = "正在进入主城...",
		PreLoadAssets = {
			"UI/Home/HomePanel",
		},
	},

	-- 战斗场景（由 TestBattle.unity 改名而来，BuildSettings index = 3）
	--   战斗由 BattleScene 中的 HomeSceneBootstrapper(startBattle=true) 直接驱动。
	Battle = {
		Level = 3,
		Name = "BattleScene",
		-- 【必须】该脚本负责打开 BattleHudPanel，从而把摇杆绑定到 Bootstrapper。
		-- 填 nil 会导致 SceneLoader 跳过场景脚本、没有任何地方打开 UI，
		-- 表现为「进入战斗场景后没有摇杆、角色无法操作」。
		LuaScript = "Game.Scene.BattleScene",
		ShowLoading = true,
		LoadingText = "正在进入战斗...",
		PreLoadAssets = {
			"UI/Battle/BattleHudPanel",
			-- P2-4：暂停菜单与撤离确认弹窗（首次打开时才 Resources.Load 会卡一帧，
			-- 而暂停/撤离都是「战斗中即时响应」的操作，必须预加载）
			"UI/Battle/PausePanel",
			"UI/Battle/ExtractConfirmPopup",
		},
	},
}

return SceneConfig
