--[[
=============================================================================
SpawnSystem.lua
=============================================================================
Module:     Game/Battle/SpawnSystem
Version:    1.0.0

Description:
	刷怪系统。根据时间轴配置，按波次生成敌人。
	
	配置示例：
	waves = {
		{ startTime = 0,   enemyType = "slime",    count = 20, interval = 0.5, hpMult = 1.0 },
		{ startTime = 60,  enemyType = "bat",      count = 15, interval = 1.0, hpMult = 1.2 },
		{ startTime = 120, enemyType = "skeleton", count = 10, interval = 2.0, hpMult = 1.5 },
		{ startTime = 300, enemyType = "boss",     count = 1,  interval = 0,   hpMult = 5.0 },
	}

Usage:
	local ss = SpawnSystem.New()
	ss:Init(wavesConfig, enemyManager)
	ss:Update(dt, elapsedTime)
=============================================================================
]]

local Class = require "Framework.Core.Class"
local EnemyConfig = require "Game.Battle.EnemyConfig"

local SpawnSystem = Class.Define("SpawnSystem")

function SpawnSystem:Ctor()
	self.waves = {}           -- 波次配置
	self.enemyManager = nil

	-- 刷怪状态
	self._currentWaveIndex = 1
	self._spawnedInWave = 0
	self._nextSpawnTimer = 0
	self._mapWidth = 20
	self._mapHeight = 20
end

---初始化
---@param waves table 波次配置
---@param enemyManager table
function SpawnSystem:Init(waves, enemyManager)
	self.waves = waves or {}
	self.enemyManager = enemyManager
	self._currentWaveIndex = 1
	self._spawnedInWave = 0
	self._nextSpawnTimer = 0
end

---每帧更新
---@param dt number 秒
---@param elapsedTime number 已过时间（秒）
function SpawnSystem:Update(dt, elapsedTime)
	if self._currentWaveIndex > #self.waves then
		return -- 所有波次完成
	end

	local wave = self.waves[self._currentWaveIndex]

	-- 检查是否到达该波次的开始时间
	if elapsedTime < wave.startTime then
		return
	end

	-- 检查是否已刷完当前波次
	if self._spawnedInWave >= wave.count then
		-- 前进到下一波
		self._currentWaveIndex = self._currentWaveIndex + 1
		self._spawnedInWave = 0
		self._nextSpawnTimer = 0
		return
	end

	-- 刷怪间隔计时
	self._nextSpawnTimer = self._nextSpawnTimer - dt
	if self._nextSpawnTimer <= 0 then
		self._nextSpawnTimer = wave.interval or 0.5
		self:_spawnOne(wave)
	end
end

---生成一个敌人
function SpawnSystem:_spawnOne(wave)
	-- 随机位置（地图边缘或随机点）
	local spawnX, spawnY = self:_getRandomSpawnPos()

	-- 计算血量倍率
	local hpMult = wave.hpMult or 1.0
	local baseHp = self:_getBaseHp(wave.enemyType)
	local baseSpeed = self:_getBaseSpeed(wave.enemyType)
	local baseDamage = self:_getBaseDamage(wave.enemyType)
	local baseExp = self:_getBaseExp(wave.enemyType)

	self.enemyManager:SpawnEnemy({
		x = spawnX,
		y = spawnY,
		hp = math.floor(baseHp * hpMult),
		speed = baseSpeed,
		damage = baseDamage,
		exp = baseExp,
		enemyType = wave.enemyType,
		attackInterval = wave.attackInterval or 1.0,
	})

	self._spawnedInWave = self._spawnedInWave + 1
end

---获取随机出生位置（地图边缘或玩家远处）
function SpawnSystem:_getRandomSpawnPos()
	-- 在地图边缘随机生成
	local edge = math.random(1, 4)
	local margin = 2
	local x, y

	if edge == 1 then -- 上边
		x = math.random() * self._mapWidth - self._mapWidth / 2
		y = self._mapHeight / 2 + margin
	elseif edge == 2 then -- 下边
		x = math.random() * self._mapWidth - self._mapWidth / 2
		y = -self._mapHeight / 2 - margin
	elseif edge == 3 then -- 左边
		x = -self._mapWidth / 2 - margin
		y = math.random() * self._mapHeight - self._mapHeight / 2
	else -- 右边
		x = self._mapWidth / 2 + margin
		y = math.random() * self._mapHeight - self._mapHeight / 2
	end

	return x, y
end

---敌人基础属性：统一查 EnemyConfig
-- 此前硬编码在本文件，导致 Elite / Boss / SpawnDirector 无法复用，
-- 策划也没法只改数值。P2 抽出到 Game/Battle/EnemyConfig.lua。
function SpawnSystem:_getBaseHp(enemyType)
	return EnemyConfig.Get(enemyType).hp
end

function SpawnSystem:_getBaseSpeed(enemyType)
	return EnemyConfig.Get(enemyType).speed
end

function SpawnSystem:_getBaseDamage(enemyType)
	return EnemyConfig.Get(enemyType).damage
end

function SpawnSystem:_getBaseExp(enemyType)
	return EnemyConfig.Get(enemyType).exp
end

---是否所有波次已完成
---@return boolean
function SpawnSystem:IsComplete()
	return self._currentWaveIndex > #self.waves
end

function SpawnSystem:Destroy()
	self.waves = {}
end

return SpawnSystem
