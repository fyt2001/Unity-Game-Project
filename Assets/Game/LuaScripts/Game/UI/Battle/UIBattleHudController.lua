--[[
=============================================================================
UIBattleHudController.lua - 战斗 HUD 控制器
=============================================================================
Module:     Game/UI/Battle/UIBattleHudController
Version:    1.0.0
Description:
	P2-3「战斗 HUD 归位」的产物。

	【搬迁前是什么样】
		这段逻辑原先写在 UIHomeController 里：主城的 Controller 每 0.5s
		require BattleManager 并采样 pc.hp/maxHp/level/exp，还直接查
		DungeonManager:GetState() 决定回城卷轴按钮的显隐。
		=> 主城 UI 反向依赖战斗层，且主城 TopBar 的等级会被战斗数据覆盖。

	【现在】
		采样与卷轴都在战斗层的这个 Controller 里。HomePanel 回归纯主城菜单，
		战斗时打开的是 BattleHudPanel。

	职责边界（对齐 UIController 基类规范）：
		- ✅ 接收 View 的用户输入事件（回城卷轴点击）
		- ✅ 更新 Model 数据 / 刷新 View 显示
		- ❌ 禁止直接操作 Unity GameObject / 实例化资源 / 管理层级焦点

	HUD 刷新策略：
		- 定时采样：每 0.5s 从 BattleManager 读取战斗数据
		- 非每帧刷新：避免 60fps 跨语言调用开销
		- 脏标记优化：数据未变化时跳过 View 更新
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"
local Logger = require "Framework.UI.Utils.Logger"

local UIBattleHudController = Class.Define("UIBattleHudController")
Class.Extend(UIBattleHudController, UIController)

local HUD_REFRESH_INTERVAL = 500

-- =============================================================================
-- 构造函数
-- =============================================================================

function UIBattleHudController:Ctor(model)
	self.super:Ctor(model)
	self._hudTimerId = nil
	self._lastHp = -1
	self._lastMaxHp = -1
	self._lastLevel = -1
	self._lastExp = -1
	self._lastExpToNext = -1
end

-- =============================================================================
-- 生命周期
-- =============================================================================

function UIBattleHudController:OnCreate()
	self:_bindReturnScroll()
	self:_bindPause()   -- P2-4：暂停入口
	self:_ensureHudRefresh()
end

function UIBattleHudController:OnOpen(level)
	if level then
		self.model:SetLevel(level)
	end

	-- 采样定时器可能被 OnClose 停过（面板 CacheOnClose 复用时走 Refresh 而非
	-- OnCreate），这里幂等地补起，否则第二场战斗 HUD 会冻结在旧数值上。
	self:_ensureHudRefresh()

	-- 立即采样一次：定时器下一次触发要等 0.5s，期间会显示 HP 条的初始值
	-- （满格 100/100），与实际血量不符，看起来像数据没接上。
	self:_sampleBattleData()
end

---SingleTop 复用实例时 UIManager 走的是 Refresh 而不是 OnCreate/OnOpen，
-- 必须在这里把采样兜起来，否则复用场景下 HUD 不再刷新。
function UIBattleHudController:OnRefresh(level)
	if level then
		self.model:SetLevel(level)
	end
	self:_ensureHudRefresh()
	self:_sampleBattleData()
end

function UIBattleHudController:OnClose()
	self:_stopHudRefresh()
end

function UIBattleHudController:OnDestroy()
	self.super:OnDestroy()
end

-- =============================================================================
-- 回城卷轴按钮（战斗期间主动撤离）
-- =============================================================================

function UIBattleHudController:_bindReturnScroll()
	local btn = self.view and self.view:GetReturnScrollButton()
	if not btn then
		print("[UIBattleHudController] m_ReturnScrollBtn not found, skip")
		return
	end

	-- 内联匿名闭包（不写成 self:_onReturnScrollClick 方法）：
	-- 该函数体不用 self，写成冒号方法会被 luacheck 判 unused argument 'self'。
	btn.onClick:AddListener(function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if not dm then
			Logger.Warn("UIBattleHudController", "No dungeon run active, return scroll ignored")
			return
		end

		-- UI 层只回传「玩家想撤离」这个意图，不做二次确认、也不扣卷轴：
		-- P2-4 起确认框由 DungeonManager:RequestExtract() 统一负责（HUD 按钮与
		-- 暂停菜单的撤离按钮走同一个入口），否则两个入口各写一份必然不一致。
		local ok, used = pcall(function() return dm:RequestExtract() end)
		if not ok then
			Logger.Error("UIBattleHudController", "RequestExtract failed: %s", tostring(used))
			return
		end

		if not used then
			Logger.Warn("UIBattleHudController", "Extract rejected (no scroll, wrong state, or another modal is open)")
		end
	end)
end

---暂停按钮（P2-4）
function UIBattleHudController:_bindPause()
	local btn = self.view and self.view:GetPauseButton()
	if not btn then
		print("[UIBattleHudController] m_PauseBtn not found, pause entry unavailable")
		return
	end

	btn.onClick:AddListener(function()
		local GameMain = require "Game.GameMain"
		local dm = GameMain.GetDungeonManager()
		if not dm then
			Logger.Warn("UIBattleHudController", "No dungeon run active, pause ignored")
			return
		end

		local ok, paused = pcall(function() return dm:PauseGame() end)
		if not ok then
			Logger.Error("UIBattleHudController", "PauseGame failed: %s", tostring(paused))
			return
		end

		if not paused then
			Logger.Warn("UIBattleHudController", "Pause rejected (battle already paused by another modal)")
		end
	end)
end

-- =============================================================================
-- HUD 定时刷新（从 BattleManager 采样 → Model → View）
-- =============================================================================

---幂等地确保采样定时器在跑（已启动则跳过）
function UIBattleHudController:_ensureHudRefresh()
	if self._hudTimerId then return end
	self:_startHudRefresh()
end

function UIBattleHudController:_startHudRefresh()
	local TimerManager = require "Framework.Core.TimerManager"
	local timerMgr = TimerManager:GetInstance()

	self._hudTimerId = timerMgr:AddLoop(HUD_REFRESH_INTERVAL, function()
		self:_sampleBattleData()
	end)
end

function UIBattleHudController:_stopHudRefresh()
	if self._hudTimerId then
		local TimerManager = require "Framework.Core.TimerManager"
		local timerMgr = TimerManager:GetInstance()
		timerMgr:Remove(self._hudTimerId)
		self._hudTimerId = nil
	end
end

function UIBattleHudController:_sampleBattleData()
	local GameMain = require "Game.GameMain"
	local battleMgr = GameMain.GetBattleManager()
	if not battleMgr then return end

	local ok, stats = pcall(function()
		return battleMgr:GetStats()
	end)
	if not ok or not stats then return end

	local pc = battleMgr.playerController
	if not pc then return end

	local hp      = pc.hp or 0
	local maxHp   = pc.maxHp or 100
	local level   = pc.level or 1
	local exp     = pc.exp or 0
	local expNext = pc.expToNext or 100

	if hp ~= self._lastHp or maxHp ~= self._lastMaxHp then
		self._lastHp = hp
		self._lastMaxHp = maxHp
		self.model:SetHp(hp, maxHp)
		self.view:SetHp(hp, maxHp)
	end

	if level ~= self._lastLevel or exp ~= self._lastExp or expNext ~= self._lastExpToNext then
		self._lastLevel = level
		self._lastExp = exp
		self._lastExpToNext = expNext
		self.model:SetExp(exp, expNext)
		self.model:SetLevel(level)
		self.view:SetLevel(level)
		self.view:SetExp(exp, expNext)   -- 经验条（数据本就采到了，此前 View 侧无控件可写）
	end

	self:_refreshReturnScrollVisibility()
end

---回城卷轴按钮仅在「战斗中且有卷轴」时显示
function UIBattleHudController:_refreshReturnScrollVisibility()
	if not self.view or not self.view.SetReturnScrollVisible then return end

	local GameMain = require "Game.GameMain"
	local dm = GameMain.GetDungeonManager()
	local show = false

	if dm and dm.GetState then
		local st = dm:GetState()
		if st == "Fighting" or st == "Boss" or st == "PreparingNextFloor" then
			if dm.CanUseReturnScroll and dm:CanUseReturnScroll() then
				show = true
			end
		end
	end

	self.view:SetReturnScrollVisible(show)
end

return UIBattleHudController
