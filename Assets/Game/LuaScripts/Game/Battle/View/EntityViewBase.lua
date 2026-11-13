--[[
=============================================================================
EntityViewBase.lua - 战斗实体视图基类（Lua 组件）
=============================================================================
Module:     Game/Battle/View/EntityViewBase

Description:
	对齐 C# MonoBehaviour 语义的 Lua 视图基类。子类（EnemyView / BulletView /
	DropView …）继承后，自动获得「每帧 Update」与「自我销毁」能力。

基类职责：
  - OnCreate(go)  缓存 GameObject / Transform，并向 UpdateManager 注册逐帧 tick
  - Tick(dt)      UpdateManager 回调，转发到子类的 Update(dt)
  - Destroy()     注销 tick + 销毁 GameObject；C# 侧 OnDestroy 会回调 Base:OnDestroy

为什么必须由基类接管 Update：
	此前是「谁创建谁喂 dt」——EnemyView 的 Update 靠 EnemyManager 每帧调用。
	一旦敌人死亡的同时战斗结束（Boss 死亡 → 直接 Victory → BattleManager
	停止 Update），就没有人再喂 dt：
		① 尸体的延迟销毁计时不推进 → 模型永久残留
		② 受击闪红 / 缩放脉冲 / 死亡塌陷的恢复也全部卡死
	表现层的生命周期属于表现层自己，不该让逻辑层替它操心。

Usage:
	local EntityViewBase = require "Game.Battle.View.EntityViewBase"
	local MyView = Class.Define("MyView")
	Class.Extend(MyView, EntityViewBase)

	function MyView:OnCreate(go)
		EntityViewBase.OnCreate(self, go)   -- 必须先调基类
		-- 子类自己的字段…
	end

	function MyView:Update(dt)  -- 由基类 Tick 自动驱动，无需外部调用
	end
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UpdateManager = require "Framework.Core.UpdateManager"
local Logger = require "Framework.UI.Utils.Logger"

local EntityViewBase = Class.Define("EntityViewBase")

-- =============================================================================
-- 生命周期
-- =============================================================================

---绑定到 GameObject（由 C# LuaViewBehaviour.Bind 调用）
---@param go userdata UnityEngine.GameObject
function EntityViewBase:OnCreate(go)
	self.go = go
	self.transform = go and go.transform or nil
	self._tickId = nil
	self._destroyed = false

	self:_registerTick()
end

---每帧驱动：转发到子类的 Update(dt)。子类不要重写本方法。
---@param dt number 帧间隔（秒）
function EntityViewBase:Tick(dt)
	if self._destroyed then return end
	if not self.Update then return end

	local ok, err = pcall(function() self:Update(dt) end)
	if not ok then
		-- 不打日志的话，子类 Update 里的错误会每帧静默失败且永远查不到
		Logger.Error("EntityViewBase", "Update failed on %s: %s",
			self.__className or "?", tostring(err))
		-- 注销自己，避免同一条错误每帧刷屏
		self:_releaseTick()
	end
end

---C# OnDestroy 回调：注销 tick 并释放引用
function EntityViewBase:OnDestroy()
	self._destroyed = true
	self:_releaseTick()
	self.transform = nil
	self.go = nil
end

---主动销毁（逻辑层调用）：销毁 GameObject 会触发 C# OnDestroy → 回到 OnDestroy
function EntityViewBase:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	self:_releaseTick()
	if self.go then
		CS.UnityEngine.Object.Destroy(self.go)
	end
end

-- =============================================================================
-- 私有：UpdateManager 注册 / 注销
-- =============================================================================

function EntityViewBase:_registerTick()
	local ok, id = pcall(function()
		return UpdateManager:GetInstance():AddUpdate(function(dt)
			self:Tick(dt)
		end, self)
	end)

	if ok then
		self._tickId = id
	else
		Logger.Warn("EntityViewBase", "register UpdateManager failed: %s", tostring(id))
	end
end

function EntityViewBase:_releaseTick()
	local ok, err = pcall(function()
		local um = UpdateManager:GetInstance()
		if self._tickId then
			um:RemoveUpdate(self._tickId)
		else
			um:RemoveUpdateByTarget(self)
		end
	end)
	if not ok then
		Logger.Warn("EntityViewBase", "release UpdateManager failed: %s", tostring(err))
	end
	self._tickId = nil
end

return EntityViewBase
