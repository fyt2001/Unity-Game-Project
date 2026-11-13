--[[
=============================================================================
UIHomeController.lua - 主界面控制器（俯视角战斗 HUD）
=============================================================================
Module:     Game/UI/Home/UIHomeController
Version:    3.0.0
Description:
	严格继承 UIController 基类，遵循 MVC 组件思想：
		- OnCreate：一次性绑定按钮事件
		- OnOpen：根据参数初始化 Model 数据 + 刷新 View
		- OnClose：取消事件订阅
		- OnDestroy：释放所有引用

	P2-3「战斗 HUD 归位」后，战斗数据的定时采样（HP / Exp / 等级）与回城卷轴
	按钮已迁到 Game/UI/Battle/UIBattleHudController —— 主城 Controller 不再
	反向依赖 BattleManager / DungeonManager。本文件只剩主城菜单职责。

	职责边界（对齐 UIController 基类规范）：
		- ✅ 接收 View 的用户输入事件（按钮点击）
		- ✅ 更新 Model 数据
		- ✅ 刷新 View 显示
		- ✅ 订阅/取消游戏事件
		- ❌ 禁止直接操作 Unity GameObject
		- ❌ 禁止直接实例化资源或 Prefab
		- ❌ 禁止管理层级/焦点

	注：战斗期间的 HUD 刷新策略（定时采样 / 脏标记）见 UIBattleHudController。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"
local UpdateManager = require "Framework.Core.UpdateManager"

local UIHomeController = Class.Define("UIHomeController")
Class.Extend(UIHomeController, UIController)

-- =============================================================================
-- 构造函数
-- =============================================================================

function UIHomeController:Ctor(model)
	self.super:Ctor(model)
	self._buttonBindings = {}
end

-- =============================================================================
-- 生命周期：OnCreate（一次性绑定）
-- =============================================================================

function UIHomeController:OnCreate()
	self.super:OnCreate()
	self:_bindButtonEvents()
end

-- =============================================================================
-- 生命周期：OnOpen（初始化数据 + 刷新 View）
-- =============================================================================

function UIHomeController:OnOpen(name, level)
	if self._destroyed then return end
	self._opened = true
	self:_bindButtonEvents()
	self.model:SetPlayerInfo(name, level)
	self.model:RefreshCurrency()
	self:_refreshView()
	if self._updateId ~= nil then return end
	self._elapsed = 0
	self._updateManager = UpdateManager:GetInstance()
	self._updateId = self._updateManager:AddUpdate(function()
		if not self._opened or self._destroyed then return end
		self._elapsed = self._elapsed + CS.UnityEngine.Time.unscaledDeltaTime
		if self._elapsed < 0.5 then return end
		self._elapsed = self._elapsed % 0.5
		if self.model:RefreshCurrency() and self.view then
			self.view:SetGold(self.model:GetGold())
		end
	end, self)
end

-- =============================================================================
-- 生命周期：OnClose（清理）
-- =============================================================================

function UIHomeController:OnRefresh(name, level)
	if self._opened then self:OnOpen(name, level) end
end

function UIHomeController:OnClose()
	self._opened = false
	if self._updateId ~= nil then
		self._updateManager:RemoveUpdate(self._updateId)
	end
	self._updateId, self._updateManager, self._elapsed = nil, nil, nil
end

-- =============================================================================
-- 生命周期：OnDestroy（释放引用）
-- =============================================================================

function UIHomeController:OnDestroy()
	self:OnClose()
	self._destroyed = true
	for _, binding in pairs(self._buttonBindings) do
		binding.button.onClick:RemoveListener(binding.callback)
	end
	self._buttonBindings = {}
	self.super:OnDestroy()
end

-- =============================================================================
-- 按钮事件绑定（集中管理）
-- =============================================================================

function UIHomeController:_bindButtonEvents()
	-- 战斗按钮已下线：进入玩法不再走 HUD 按钮，改为场景内的洞口
	--（走近 / 左键 → HomeSceneBootstrapper.TeleportToScene → GameMain.StartDungeonRun），
	-- 所以这里不再监听 HomePanel_OnBattle。
	self:_bindButton("Shop", "HomePanel_OnShop")
	-- 配装入（P3-1）：与商店同走事件广播，由 HomeScene 决定开什么面板（UI 层不反向驱动流程）
	self:_bindButton("Mod", "HomePanel_OnMod")
end

function UIHomeController:_bindButton(name, eventName)
	if not self.view or self._buttonBindings[name] then return end
	local btn = self.view:GetButton(name)
	if not btn then
		print(string.format("[UIHomeController] Button '%s' not found, skip", name))
		return
	end

	local callback = function()
		if not self._opened or self._destroyed then return end
		local joystick = self.view.GetJoystick and self.view:GetJoystick()
		if joystick and joystick.Reset then joystick:Reset() end
		print(string.format("[UIHomeController] %s clicked", name))
		local FW = require "Framework.Framework"
		FW.Event():Broadcast(eventName)
	end
	btn.onClick:AddListener(callback)
	self._buttonBindings[name] = { button = btn, callback = callback }
end

-- =============================================================================
-- View 刷新（全量）
-- =============================================================================

function UIHomeController:_refreshView()
	if not self.view or not self.model then return end

	self.view:SetPlayerName(self.model:GetPlayerName())
	self.view:SetLevel(self.model:GetPlayerLevel())
	self.view:SetGold(self.model:GetGold())
	self.view:SetDiamond(self.model:GetDiamond())
end

return UIHomeController
