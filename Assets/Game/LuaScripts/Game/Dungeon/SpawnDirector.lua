--[[
=============================================================================
SpawnDirector.lua - 怪潮导演（持续密度刷怪 + 精英 + Boss）
=============================================================================
Module:     Game/Dungeon/SpawnDirector
Version:    1.0.0

Description:
	取代 P1 的「静态波次时间轴」，改为按【楼层 + 层内已过时间】持续驱动怪潮。

	设计约束（埋骨渊方案.md §6）：第一版【只 3 个驱动参数】
		density    刷怪密度 → 出怪间隔缩短、同屏上限提高
		eliteRate  精英概率
		enemyLevel 敌人等级 → 血/伤缩放
	不做几十个参数。

	与 SpawnSystem 的关系：
		SpawnSystem 保留「波次时间轴」能力，供【非下潜模式】
		（直接开 BattleScene、Bootstrapper 自起的普通战斗）使用，避免破坏既有流程。
		下潜走 SpawnDirector，二者由 BattleManager 按 useDirector 分流。

	注：本模块直接调用 EnemyManager:SpawnEnemy，属性统一查 EnemyConfig。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"
local EnemyConfig = require "Game.Battle.EnemyConfig"
local BossConfig = require "Game.Dungeon.BossConfig"

local SpawnDirector = Class.Define("SpawnDirector")

local MAP_WIDTH = 20
local MAP_HEIGHT = 20
local BOSS_SPAWN_RATIO = 0.9   -- 层末 90% 时间刷 Boss

function SpawnDirector:Ctor()
	self.enemyManager = nil
	self.floorCfg = nil
	self.elapsed = 0
	self._spawnTimer = 0
	self._boss = nil
	self._bossSpawned = false
end

---初始化
---@param floorCfg table { floor, duration, spawn={density,eliteRate,maxCount}, boss, bossId }
---@param enemyManager table
function SpawnDirector:Init(floorCfg, enemyManager)
	floorCfg = floorCfg or {}
	self.floorCfg = floorCfg
	self.enemyManager = enemyManager
	self.elapsed = 0
	self._spawnTimer = 0
	self._boss = nil
	self._bossSpawned = false
end

---当前怪潮参数（设计稿 §6 的三参数驱动）
-- floor / elapsedTime 均可省略：省略时取 floorCfg.floor 与内部累计时间。
---@param floor number|nil
---@param elapsedTime number|nil
---@return table { spawnInterval, maxEnemyCount, eliteRate, enemyLevel }
function SpawnDirector:GetConfig(floor, elapsedTime)
	floor = floor or (self.floorCfg and self.floorCfg.floor) or 1

	local spawn = (self.floorCfg and self.floorCfg.spawn) or {}
	local density = spawn.density or 1.0
	local eliteRate = spawn.eliteRate or 0.0
	local maxCount = spawn.maxCount or 60

	-- 楼层越深 → 敌人等级越高（附录 D）
	local enemyLevel = 1 + 0.5 * (floor - 1)
	-- 密度越高 → 出怪间隔越短
	local spawnInterval = math.max(0.15, 1.2 / math.max(0.1, density))

	return {
		spawnInterval = spawnInterval,
		maxEnemyCount = math.floor(maxCount),
		eliteRate = eliteRate,
		enemyLevel = enemyLevel,
	}
end

---每帧更新（由 BattleManager:Update 调用）
function SpawnDirector:Update(dt, elapsedTime)
	if not self.enemyManager then return end

	self.elapsed = elapsedTime or self.elapsed

	-- Boss 层：到点刷 Boss（只刷一次）
	if self.floorCfg and self.floorCfg.boss and not self._bossSpawned then
		local duration = self.floorCfg.duration or 180
		if self.elapsed >= duration * BOSS_SPAWN_RATIO then
			self:SpawnBoss(self.floorCfg.bossId)
		end
	end

	local cfg = self:GetConfig()

	-- 同屏上限
	if self:_aliveCount() >= cfg.maxEnemyCount then
		self:_updateBossPhase()
		return
	end

	self._spawnTimer = self._spawnTimer - dt
	if self._spawnTimer <= 0 then
		self._spawnTimer = cfg.spawnInterval
		self:_spawnOne(cfg)
	end

	self:_updateBossPhase()
end

-- =============================================================================
-- 刷怪
-- =============================================================================

function SpawnDirector:_spawnOne(cfg)
	local enemyType = self:_pickType()
	local base = EnemyConfig.Get(enemyType)
	local isElite = math.random() < (cfg.eliteRate or 0)
	local st = EnemyConfig.Scale(base, cfg.enemyLevel, isElite)

	local x, y = self:_randomPos()
	local enemy = self.enemyManager:SpawnEnemy({
		x = x,
		y = y,
		hp = st.hp,
		speed = st.speed,
		damage = st.damage,
		exp = st.exp,
		enemyType = enemyType,
		attackInterval = st.attackInterval,
	})

	-- 精英用标记区分，不新增 enemyType 枚举（P2 决策 #4）
	if enemy then enemy.isElite = isElite end
end

---按层内进度选兵种：前期史莱姆 → 中期蝙蝠 → 后期骷髅
function SpawnDirector:_pickType()
	local duration = (self.floorCfg and self.floorCfg.duration) or 180
	local ratio = duration > 0 and (self.elapsed / duration) or 0

	if ratio < 0.35 then return "slime" end
	if ratio < 0.7 then return "bat" end
	return "skeleton"
end

---地图边缘随机出生点
function SpawnDirector:_randomPos()
	local edge = math.random(1, 4)
	local margin = 2
	local x, y

	if edge == 1 then
		x = math.random() * MAP_WIDTH - MAP_WIDTH / 2
		y = MAP_HEIGHT / 2 + margin
	elseif edge == 2 then
		x = math.random() * MAP_WIDTH - MAP_WIDTH / 2
		y = -MAP_HEIGHT / 2 - margin
	elseif edge == 3 then
		x = -MAP_WIDTH / 2 - margin
		y = math.random() * MAP_HEIGHT - MAP_HEIGHT / 2
	else
		x = MAP_WIDTH / 2 + margin
		y = math.random() * MAP_HEIGHT - MAP_HEIGHT / 2
	end

	return x, y
end

function SpawnDirector:_aliveCount()
	if not self.enemyManager then return 0 end
	return self.enemyManager:GetAliveCount()
end

-- =============================================================================
-- Boss
-- =============================================================================

---召唤 Boss
function SpawnDirector:SpawnBoss(bossId)
	if not self.enemyManager then return nil end

	local tpl = BossConfig.Get(bossId)
	local base = EnemyConfig.Get("boss")

	local enemy = self.enemyManager:SpawnEnemy({
		x = 0,
		y = MAP_HEIGHT / 2 + 2,
		hp = tpl.hp,
		speed = base.speed,
		damage = base.damage,
		exp = base.exp,
		enemyType = "boss",
		attackInterval = base.attackInterval,
	})

	if not enemy then return nil end

	enemy.isBoss = true
	enemy.bossId = bossId
	enemy.phaseIndex = 1
	enemy.baseSpeed = base.speed
	enemy.baseDamage = base.damage
	enemy.baseAttackInterval = base.attackInterval

	self._boss = enemy
	self._bossSpawned = true

	Logger.Info("SpawnDirector", "Boss spawned: %s (hp=%d)", tostring(bossId), tpl.hp)
	return enemy
end

---Boss 是否已死（供 Boss 层清层判定）
function SpawnDirector:IsBossDead()
	if not self._boss then return false end
	return self._boss.isDead == true
end

---Boss 是否已刷出
function SpawnDirector:IsBossSpawned()
	return self._bossSpawned
end

---按 HP 百分比切换阶段
-- ⚠ 降级实现（P2 决策 #2）：当前无敌人技能系统，
--   阶段切换只改【属性】（速度/伤害/攻击间隔），skillSet 仅占位。
function SpawnDirector:_updateBossPhase()
	local boss = self._boss
	if not boss or boss.isDead then return end

	local tpl = BossConfig.Get(boss.bossId)
	local phases = tpl.phases or {}
	if #phases == 0 then return end

	local pct = boss.maxHp > 0 and (boss.hp / boss.maxHp) or 0

	-- 取「已越过的最低阈值」对应的阶段（phases 按 hpPercent 降序）
	local idx = 1
	for i, p in ipairs(phases) do
		if pct <= (p.hpPercent or 0) then idx = i end
	end

	if idx == boss.phaseIndex then return end

	local mod = (phases[idx] and phases[idx].statMod) or {}
	-- 基于初始值重算，避免多次切换时系数叠乘
	boss.speed = (boss.baseSpeed or boss.speed) * (mod.speed or 1)
	boss.damage = (boss.baseDamage or boss.damage) * (mod.damage or 1)
	boss.attackInterval = (boss.baseAttackInterval or boss.attackInterval) * (mod.attackInterval or 1)
	boss.phaseIndex = idx

	Logger.Info("SpawnDirector", "Boss %s -> phase %d (hp=%d/%d)",
		tostring(boss.bossId), idx, boss.hp, boss.maxHp)
end

function SpawnDirector:Destroy()
	self._boss = nil
	self.enemyManager = nil
	self.floorCfg = nil
end

return SpawnDirector
