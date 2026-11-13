local Class = require "Framework.Core.Class"
local VFXConfig = require "Game.Battle.VFXConfig"
local VFXManager = require "Game.Battle.VFXManager"
local BattleLayers = require "Game.Battle.BattleLayers"
local Logger = require "Framework.UI.Utils.Logger"

local DamageSystem = Class.Define("DamageSystem")

---受击/死亡特效的生成高度（统一分层常量）
local HIT_HEIGHT = BattleLayers.GroundHit

function DamageSystem:Ctor()
	self.playerController = nil
	self.enemyManager = nil
	self.onEnemyKilled = nil
	self.onExpGained = nil
	self._playerView = nil        -- C# 角色视图组件（懒取，见 _flashPlayerView）
	self._playerViewChecked = false
end

function DamageSystem:Init(playerController, enemyManager, onEnemyKilled, onExpGained)
	self.playerController = playerController
	self.enemyManager = enemyManager
	self.onEnemyKilled = onEnemyKilled
	self.onExpGained = onExpGained
end

---伤害敌人（所有伤害的唯一汇聚点）
-- 武器辐射/火焰/轨道/连锁/接触伤害都会走到这里，因此受击与死亡特效在此统一处理，
-- 无需在每种武器分支里各写一遍；预制体缺失时 VFXManager 自动静默。
function DamageSystem:DamageEnemy(enemy, damage, isCrit)
	if not enemy or enemy.isDead or not self.enemyManager then
		return false
	end

	-- 坐标提前取：TakeDamage 命中致死时会把 enemy 移出网格
	local ex, ey = enemy.x, enemy.y

	VFXManager.Spawn(
		isCrit and VFXConfig.Common.enemyCrit or VFXConfig.Common.enemyHit,
		ex, ey, HIT_HEIGHT, 1.0
	)

	local killed = self.enemyManager:TakeDamage(
		enemy.id,
		damage,
		isCrit
	)

	if killed then
		-- 精英 / Boss 用专属死亡特效（缺失则回退到普通死亡）
		local deathPath = VFXConfig.Common.enemyDeath
		if enemy.enemyType == "boss" then
			deathPath = VFXConfig.Common.bossDeath or deathPath
		elseif enemy.isElite then
			deathPath = VFXConfig.Common.eliteDeath or deathPath
		end
		VFXManager.Spawn(deathPath, ex, ey, HIT_HEIGHT, 1.0)
		if self.onEnemyKilled then
			self.onEnemyKilled(enemy)
		end
		if self.onExpGained and enemy.exp and enemy.exp > 0 then
			self.onExpGained(enemy.exp)
		end
	end

	return killed
end

function DamageSystem:DamagePlayer(damage)
	if not self.playerController then
		return 0
	end

	local actual = self.playerController:TakeDamage(damage)

	-- 无敌帧/已死亡时 TakeDamage 返回 0，此时不该出现受击表现
	if actual > 0 then
		local px, py = self.playerController:GetPosition()
		VFXManager.Spawn(VFXConfig.Common.playerHurt, px, py, HIT_HEIGHT, 1.0)
		self:_flashPlayerView()
	end

	return actual
end

---把受伤表现转发给 C# 角色视图（染红 + 缩放脉冲）
-- 引用来源必须是 ViewConfig.playerView：这是 HomeSceneBootstrapper 注入 Lua 的
-- 统一通道（与 enemyModel / bulletPlayer 同一套路）。
-- 不要改成 CS 反射去拿静态单例：IL2CPP 下成员会被裁剪而失效。
function DamageSystem:_flashPlayerView()
	if self._playerViewChecked and not self._playerView then return end

	if not self._playerViewChecked then
		local ok, view = pcall(function()
			local vc = _G.ViewConfig or {}
			return vc.playerView
		end)
		if ok and view ~= nil then
			self._playerView = view
			-- 只有真正取到才置位：否则 ViewConfig 尚未注入时受过一次伤，
			-- 会导致整局战斗的受伤表现永久失效。
			self._playerViewChecked = true
		else
			Logger.Debug("DamageSystem", "playerView not ready yet (ViewConfig.playerView missing)")
		end
	end

	if self._playerView then
		pcall(function() self._playerView:FlashHurt() end)
	end
end

function DamageSystem:Destroy()
	self.playerController = nil
	self.enemyManager = nil
	self.onEnemyKilled = nil
	self.onExpGained = nil
	self._playerView = nil
	self._playerViewChecked = false
end

return DamageSystem