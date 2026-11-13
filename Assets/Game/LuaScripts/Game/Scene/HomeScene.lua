--[[
=============================================================================
HomeScene.lua - 主城/主界面场景脚本
=============================================================================
Module:     Game/Scene/HomeScene
Version:    4.0.0
Description:
	主城场景：3D 主场景 HomeScene.unity + HomePanel（摇杆 + HUD）。
	本场景【不跑战斗】，玩家只做自由移动与场景交互。
	战斗统一在 BattleScene.unity 中进行，【入口只有一个】：
		场景内洞口 Portal:Cave Portal —— 左键点击或走近自动触发。
		判定与传送都在 C# 侧（Interactable + HomeSceneBootstrapper.TeleportToScene
		→ GameMain.StartDungeonRun），Lua 侧不参与。
		（原 HomePanel 的 BattleBtn 已下线：HUD 上不再放战斗按钮。）

	操作方式：
		- 右键点地面 / 摇杆：移动（C# 每帧轮询 VirtualJoystick.GetOutput）
		- 左键点物体：触发 Interactable（后续商人/传送门等扩展点）

	核心设计（腾讯大厂级）：
		- 场景生命周期：OnCreate（预加载资源）→ OnComplete（打开 UI）
		- 单一职责：Scene 只负责生命周期编排，业务逻辑由 Controller 层处理
		- 事件驱动：通过 EventManager 解耦各模块
		- C# 桥接：HomeSceneBootstrapper 负责场景可视层 + 输入桥接

	架构：
		HomeScene.unity（3D 主城主场景；战斗场景为 BattleScene.unity）
		├── SceneCamera (TopDownCameraFollow → 跟随玩家)
		│   ├── BattleGround (Plane + Custom/BattleGrid Shader)
		│   ├── Player (3D 模型 / Cube+Cylinder 占位)
		│   └── CavePortal (Interactable：点击或走近 -> Battle)
		├── MoveClickIndicator (右键移动地表标记，挂在 Bootstrapper 下)
		├── UICamera (Canvas, ScreenSpaceCamera)
		│   └── HomePanel(Clone)
		│       ├── TopBar (玩家名/等级/金币/宝石)
		│       ├── CenterArea (奖杯)
		│       ├── BottomBar
		│       │   └── JoystickArea
		│       │       ├── Background (VirtualJoystick)
		│       │       └── Handle
		│       └── BattleBtn / ShopBtn
		└── HomeSceneBootstrapper (C# 组件)

		Changelog:
		v4.1.0 - 入口收敛：下线 HUD 战斗按钮，玩法入口只剩场景洞口（走近 / 点击）
		v4.0.0 - 主城化重构：本场景不再承载战斗，BattleBtn 与洞口统一切换到 Battle 场景；
		         移动改为右键点地/摇杆，左键留给场景交互（Interactable）
		v3.0.0 - 重构为俯视角战斗主界面，集成摇杆 + 战斗系统
		v2.0.0 - 对齐 ShaoNvClient_H02 生命周期
		v1.0.0 - 初始版本
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"
local BaseScene = require "Game.Scene.BaseScene"

local HomeScene = {}
setmetatable(HomeScene, { __index = BaseScene })

function HomeScene:OnCreate(sceneName, config)
	Logger.Info("HomeScene", "OnCreate: %s", sceneName)

	self._sceneName = sceneName
	self._config = config
	self._preloadResources = {}

	self._preloadResources["UI/Home/HomePanel"] = true

	Logger.Debug("HomeScene", "Registered preload resources")
end

function HomeScene:OnComplete(sceneName, _config)
	Logger.Info("HomeScene", "OnComplete: %s", sceneName)

	self._uiManager = nil
	self._eventManager = nil

	local GameMain = require "Game.GameMain"
	self._uiManager = GameMain.GetUIManager()
	self._eventManager = GameMain.GetEventManager()

	self:_initHomeUI()

	self:_registerEvents()

	Logger.Info("HomeScene", "Home scene ready (battle + joystick mode)")
end

function HomeScene:OnLeave()
	Logger.Info("HomeScene", "OnLeave: cleaning up...")

	self:_unregisterEvents()

	if self._uiManager then
		self._uiManager:Close("HomePanel", "SceneLeave")
	end

	self._uiManager = nil
	self._eventManager = nil
	self._eventsRegistered = false
end

function HomeScene:_initHomeUI()
	if self._uiManager then
		self._uiManager:Open("HomePanel")
		Logger.Debug("HomeScene", "HomePanel opened (battle HUD + joystick)")
	else
		Logger.Warn("HomeScene", "WARNING: UIManager not available")
	end
end

function HomeScene:_registerEvents()
	if not self._eventManager then return end

	-- 幂等保护：OnComplete 可能被调用多次，重复注册会让监听器无限累积
	if self._eventsRegistered then return end
	self._eventsRegistered = true

	-- 统一走 BaseScene:RegisterEvent（自动以 self 为 target，便于基类注销）
	local function listen(event, handler)
		self:RegisterEvent(self._eventManager, event, handler)
	end

	-- 【入口收敛】进入玩法只有洞口一条路：传送由 C# 侧
	-- HomeSceneBootstrapper.TeleportToScene 直接调 GameMain.StartDungeonRun()
	--（见该文件 :1326），不再经 EventManager 绕一圈，故此处没有 Battle 监听。
	listen("HomePanel_OnShop", HomeScene._onShopOpen)
	listen("HomePanel_OnMod", HomeScene._onModStationOpen)
end

function HomeScene:_unregisterEvents()
	self:UnregisterAllEvents(self._eventManager)
end

---商店入（P3-2）：开商店面板。
---同配装入：EventManager 直接 callback(payload) 调（不带 self 前置），
---所以写成点方法；用 pcall 包住，Lua 侧异常不该把 UI 事件链打断。
function HomeScene._onShopOpen()
	Logger.Info("HomeScene", "ShopBtn clicked -> 打开商店面板 (ShopPanel)")

	local ok, err = pcall(function()
		local GameMain = require "Game.GameMain"
		local ui = GameMain.GetUIManager()
		if ui and ui.Open then ui:Open("ShopPanel") end
	end)

	if not ok then
		Logger.Error("HomeScene", "Failed to open ShopPanel: %s", tostring(err))
	end
end

---配装入（P3-1）：开配装面板。与战斗按钮同款用 pcall 包住，
---Lua 侧异常不该把 UI 事件链打断。
---注意：EventManager 是直接 callback(payload) 调的（不带 self 前置），
---所以这里必须写成点方法（否则 self 恒为 nil），也不该用 self。
function HomeScene._onModStationOpen()
	Logger.Info("HomeScene", "ModBtn clicked -> 打开配装面板 (ModStationPanel)")

	local ok, err = pcall(function()
		local GameMain = require "Game.GameMain"
		local ui = GameMain.GetUIManager()
		if ui and ui.Open then ui:Open("ModStationPanel") end
	end)

	if not ok then
		Logger.Error("HomeScene", "Failed to open ModStationPanel: %s", tostring(err))
	end
end

function HomeScene:GetSceneName()
	return self._sceneName
end

return HomeScene
