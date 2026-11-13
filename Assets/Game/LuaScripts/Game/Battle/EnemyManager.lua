--[[
=============================================================================
EnemyManager.lua V1.1.2
=============================================================================
Description:
	敌人管理器。统一管理敌人数据、移动、空间索引、伤害与死亡。

V1.1.2 修复：
	- enemyMap O(1) ID 查找
	- Grid 仅跨 Cell 时更新
	- 死亡后立即从 enemyMap / Grid 移除，数组仍延迟清理
	- 最近目标查询使用 Grid 候选 + 保守提前退出条件
	- Top-N 查询避免全量 table.sort
=============================================================================
]]

local Class = require "Framework.Core.Class"
local EnemyConfig = require "Game.Battle.EnemyConfig"
local BuildConfig = require "Game.Build.BuildConfig"
local WeaponSystem = require "Game.Battle.WeaponSystem"
local EntityViewFactory = require "Game.Battle.View.EntityViewFactory"
local VFXConfig = require "Game.Battle.VFXConfig"
local VFXManager = require "Game.Battle.VFXManager"
local BattleLayers = require "Game.Battle.BattleLayers"
local ChainLightningView = require "Game.Battle.View.ChainLightningView"
local EnemyManager = Class.Define("EnemyManager")
local GRID_SIZE = 5

-- 敌人分离力参数（避免敌人之间没有间隔、挤成一坨）
local SEPARATION_RADIUS = 1.1          -- 互相推开的作用距离（约等于两个怪并排的体积）
local SEPARATION_SPEED = 2.0           -- Maximum correction speed, independent of chase speed.
local SEPARATION_MAX_NEIGHBORS = 8     -- 单次最多参考的邻居数，限制每帧查询开销

---弹道枚举 → 名称（供 VFXConfig 按名称匹配；敌人武器配置里只有枚举没有 patternName）
local PAT_NAME = {}
for _k, _v in pairs(WeaponSystem.Pattern) do PAT_NAME[_v] = _k end

---死亡表现档位：普通 < 精英 < Boss
-- 具体时长与姿态（塌陷/侧倒）由 EnemyView.DEATH_STYLE 决定，
-- 管理器只负责按兵种给出档位，不再自己持有计时。
local function deathKindOf(enemy)
    if enemy.enemyType == "boss" then return "boss" end
    if enemy.isElite then return "elite" end
    return "normal"
end

function EnemyManager:Ctor()
	self.enemies = {}
	self._enemyMap = {}
	self._idCounter = 0
	self._pendingRemove = {}
	self._grid = {}
	self.bulletManager = nil
	self.damageSystem = nil
end

function EnemyManager:Init()
	-- 表现层：先销毁上一局残留的实体视图（Lua 组件）
	if self.enemies then
		for _, enemy in ipairs(self.enemies) do
			if enemy.view then pcall(function() enemy.view:Destroy() end) end
		end
	end
	self.enemies = {}
	self._enemyMap = {}
	self._idCounter = 0
	self._pendingRemove = {}
	self._grid = {}
	self.bulletManager = nil
end

---注入子弹系统（供持武敌人发射敌方子弹）与伤害系统（供非抛射武器直接结算玩家）
function EnemyManager:Inject(bulletManager, damageSystem)
	self.bulletManager = bulletManager
	self.damageSystem = damageSystem
end

function EnemyManager:SpawnEnemy(config)
	config = config or {}
	self._idCounter = self._idCounter + 1

	local enemy = {
		id = self._idCounter,
		x = config.x or 0,
		y = config.y or 0,
		maxHp = config.hp or 50,
		hp = config.hp or 50,
		speed = config.speed or 2.0,
		damage = config.damage or 5,
		exp = config.exp or 10,
		enemyType = config.enemyType or "normal",
		-- C# HUD reads a non-nullable bool; nil reads leak stack entries in this XLua version.
		isElite = config.isElite == true,
		isDead = false,
		aiState = "chase",
		attackCooldown = 0,
		attackInterval = config.attackInterval or 1.0,
		gridX = nil,
		gridY = nil,
		gridKey = nil,
		-- 分离权重（见 _applySeparation）：Boss 视作重物，只会推开杂兵、不会被杂兵
		-- 挤离原位；普通怪为 1，等权互推。
		sepMass = config.sepMass or ((config.enemyType == "boss") and 12 or 1),
	}

	-- 分类与掉落（按兵种）：
	--   enemy  = 持武敌人（skeleton）：携带武器、用武器攻击玩家、击杀掉落该武器
	--   monster= 怪物（slime/bat）：不持武器，击杀只掉落材料
	local category = EnemyConfig.Category[config.enemyType] or "monster"
	enemy.category = category
	enemy.materialId = config.materialId or EnemyConfig.MaterialDrop[config.enemyType]
	-- 近战攻击范围（进入后停步攻击，而非无限贴脸）
	enemy.attackRange = (EnemyConfig.AttackRange and EnemyConfig.AttackRange[config.enemyType]) or 1.3

	-- 持武敌人随机携带一把武器：击杀掉落它，并用它远程攻击玩家
	enemy.weaponId = config.weaponId
	if not enemy.weaponId and category == "enemy" then
		local pool = EnemyConfig.WeaponPool[config.enemyType]
		if pool and #pool > 0 then
			enemy.weaponId = pool[math.random(#pool)]
		end
	end
	-- 持武敌人改用远程攻击，不再做贴身接触伤害（CollisionSystem 据此跳过接触判定）
	enemy.rangedAttack = (enemy.weaponId ~= nil)

	self.enemies[#self.enemies + 1] = enemy
	self._enemyMap[enemy.id] = enemy
	self:_addToGrid(enemy)

	-- 表现层：创建「Lua 组件」驱动的实体视图（人形 prefab + 可选武器）
	enemy.view = EntityViewFactory.CreateEnemyView(enemy)
	return enemy
end

function EnemyManager:Update(dt, targetX, targetY)
	self:_flushRemoved()
	if not dt or dt <= 0 then return end
	targetX = targetX or 0
	targetY = targetY or 0

	-- All avoidance queries use the same positions and grid for this frame.
	for _, enemy in ipairs(self.enemies) do
		enemy._sepX, enemy._sepY = enemy.x, enemy.y
	end
	for _, enemy in ipairs(self.enemies) do
		if not enemy.isDead then
			self:_updateEnemy(enemy, dt, targetX, targetY)
		end
	end
	for _, enemy in ipairs(self.enemies) do
		if not enemy.isDead then
			local gx, gy = math.floor(enemy.x / GRID_SIZE), math.floor(enemy.y / GRID_SIZE)
			if gx ~= enemy.gridX or gy ~= enemy.gridY then
				self:_removeFromGrid(enemy, enemy.gridX, enemy.gridY)
				self:_addToGrid(enemy, gx, gy)
			end
		end
	end
end

function EnemyManager:_updateEnemy(enemy, dt, targetX, targetY)
	local dx = targetX - enemy.x
	local dy = targetY - enemy.y
	local dist = math.sqrt(dx * dx + dy * dy)

	if dist > 0 then
		dx = dx / dist
		dy = dy / dist
	end

	local moveSpeed = enemy.speed
	local shouldMove = true
	if enemy.aiState == "flee" then
		moveSpeed = enemy.speed * 1.5
		dx = -dx
		dy = -dy
	elseif dist <= (enemy.attackRange or 1.3) then
		-- 进入近战攻击范围：停步攻击（面向玩家由 SetPosition 处理）
		shouldMove = false
	end

	local step = 0
	if shouldMove then
		step = moveSpeed * dt
		if enemy.aiState ~= "flee" then
			step = math.min(step, math.max(0, dist - (enemy.attackRange or 1.3)))
		end
	end

	-- 分离：把靠得太近的敌人互相推开。
	-- 必须放在 Grid 更新之前（下面按新坐标算格）；也【不能】只在 shouldMove 时施加 ——
	-- 近战怪进入 attackRange 后会停步，若停步时不做分离，它们仍会全部重合在同一个
	-- 半径圆上，那正是「敌人挤在一起」的主因。
	local sepDX, sepDY = dx, dy
	if enemy.aiState == "flee" then sepDX, sepDY = nil, nil end
	local crowdSpeed = self:_applySeparation(enemy, dt, sepDX, sepDY)
	enemy.x = enemy.x + dx * step * crowdSpeed
	enemy.y = enemy.y + dy * step * crowdSpeed

	-- 表现层：同步实体坐标与朝向
	if enemy.view then enemy.view:SetPosition(enemy.x, enemy.y, dx, dy, dt) end

	-- 表现层不再需要喂 dt：EnemyView 继承 EntityViewBase，
	-- 自己的 Update 由 UpdateManager 全局驱动。

	-- 持武敌人（skeleton）用携带的武器攻击玩家。
	-- 此前只按 Projectile 处理：非抛射武器会被错误地发射成 normal 子弹且无法命中玩家。
	-- 现在按 w.pattern 正确分发（见 _fireEnemyWeapon）。
	if enemy.weaponId and enemy.attackCooldown <= 0 then
		local w = BuildConfig.GetWeapon(enemy.weaponId)
		if w then
			self:_fireEnemyWeapon(enemy, w, targetX, targetY)
		end
	end

	if enemy.attackCooldown > 0 then
		enemy.attackCooldown = math.max(0, enemy.attackCooldown - dt)
	end
end

---敌人之间的分离力：把距离过近的邻居互相推开，让怪群保持间隔而不是叠成一坨。
--
-- 实现要点：
--   1. 复用已有的 Grid 邻域查询（GetEnemiesInRange），只在本格 + 相邻格找候选，
--      不做 O(n^2) 全量两两比较；候选上限 SEPARATION_MAX_NEIGHBORS 控制开销。
--   2. 推力与「重叠深度」成正比：刚好贴边时不推、越重叠推得越急，
--      因此多怪自然收敛到等间距，而不是持续抖动。
--   3. 不受 aiState / 是否停步影响 —— 逃跑与停步攻击的敌人都要分离。
--   4. 每个邻居按其 sepMass 反向加权：Boss 的 sepMass 很大，于是「小怪被 Boss
--      推开」而不是「Boss 被小怪挤走」，重物不会被杂兵拱离原位。
function EnemyManager:_applySeparation(enemy, dt, moveX, moveY)
	local x, y = enemy._sepX or enemy.x, enemy._sepY or enemy.y
	local neighbors = {}
	local r = SEPARATION_RADIUS
	for gx = math.floor((x - r) / GRID_SIZE), math.floor((x + r) / GRID_SIZE) do
		for gy = math.floor((y - r) / GRID_SIZE), math.floor((y + r) / GRID_SIZE) do
			for _, other in ipairs(self._grid[gx .. "_" .. gy] or {}) do
				if other ~= enemy and not other.isDead then
					local ox, oy = x - (other._sepX or other.x), y - (other._sepY or other.y)
					local d2 = ox * ox + oy * oy
					if d2 < r * r then
						local entry = { enemy = other, ox = ox, oy = oy, d2 = d2 }
						local i = #neighbors + 1
						while i > 1 do
							local prev = neighbors[i - 1]
							if prev.d2 < d2 or (prev.d2 == d2 and prev.enemy.id < other.id) then break end
							i = i - 1
						end
						if i <= SEPARATION_MAX_NEIGHBORS then
							table.insert(neighbors, i, entry)
							if #neighbors > SEPARATION_MAX_NEIGHBORS then table.remove(neighbors) end
						end
					end
				end
			end
		end
	end
	local pushX, pushY, crowdSpeed = 0, 0, 1
	for _, entry in ipairs(neighbors) do
		local ox, oy, d = entry.ox, entry.oy, math.sqrt(entry.d2)
		if d < 0.000001 then
			-- Stable, opposite directions for identical spawn positions; no random frame jitter.
			local lo, hi = math.min(enemy.id, entry.enemy.id), math.max(enemy.id, entry.enemy.id)
			local angle = ((lo * 73 + hi * 151) % 360) * math.pi / 180
			local sign = enemy.id == lo and 1 or -1
			ox, oy, d = math.cos(angle) * sign, math.sin(angle) * sign, 1
		end
		local depth = (r - math.sqrt(entry.d2)) / r
		local ownMass, otherMass = math.max(1, enemy.sepMass or 1), math.max(1, entry.enemy.sepMass or 1)
		local weight = otherMass / (ownMass + otherMass)
		-- Yield to bodies ahead instead of chasing into them then being pushed back.
		if moveX and moveY and (ox / d * moveX + oy / d * moveY) < -0.25 then
			local clearance = math.max(0, (math.sqrt(entry.d2) - 0.8) / (r - 0.8))
			crowdSpeed = math.min(crowdSpeed, math.max(0, 1 - (1 - clearance) * math.min(1, weight * 2)))
		end
		pushX = pushX + ox / d * depth * weight
		pushY = pushY + oy / d * depth * weight
	end

	local len = math.sqrt(pushX * pushX + pushY * pushY)
	if len <= 0.000001 then return crowdSpeed end
	-- Preserve shallow-overlap magnitude; only cap dense-crowd correction.
	local scale = r * (1 - math.exp(-SEPARATION_SPEED * dt / r)) / math.max(1, len)
	enemy.x = enemy.x + pushX * scale
	enemy.y = enemy.y + pushY * scale
	return crowdSpeed
end

---敌人按武器 pattern 攻击玩家（取代原先「一律发射子弹」的逻辑）
function EnemyManager:_fireEnemyWeapon(enemy, w, tx, ty)
	local dx = tx - enemy.x
	local dy = ty - enemy.y
	local dist = math.sqrt(dx * dx + dy * dy)
	local range = w.range or 8
	if dist <= 0 or dist > range then return end   -- 玩家不在射程内，不开火

	-- 合成带 patternName 的表，使 VFXConfig 的 Pattern 级与 WeaponId 级配置都能命中
	local vfx = VFXConfig.Get({ id = w.id, patternName = PAT_NAME[w.pattern], projectileType = w.projectileType })
	local Pattern = WeaponSystem.Pattern

	if w.pattern == Pattern.Projectile then
		-- 抛射：朝玩家发射敌方子弹（阵营=enemy）
		if self.bulletManager then
			self.bulletManager:SpawnBullet({
				x = enemy.x, y = enemy.y,
				dirX = dx / dist, dirY = dy / dist,
				speed = w.projectileSpeed or 10,
				damage = (w.damage or 10) * 0.8,
				isCrit = false,
				range = range,
				pierce = false,
				bulletType = w.projectileType or "normal",
				faction = "enemy",
			})
		end
	elseif w.pattern == Pattern.AOE then
		-- 范围：在玩家位置落爆炸，命中即结算
		if vfx and vfx.cast then VFXManager.Spawn(vfx.cast, tx, ty, BattleLayers.Projectile) end
		if vfx and vfx.explosion then VFXManager.Spawn(vfx.explosion, tx, ty, BattleLayers.GroundHit) end
		self:_damagePlayer(w.damage or 10)
	elseif w.pattern == Pattern.Orbit then
		-- 环绕/近身光环：玩家进入 range 内持续受伤（0.5x，与玩家侧一致）
		if vfx and vfx.hit then VFXManager.Spawn(vfx.hit, tx, ty, BattleLayers.GroundHit) end
		self:_damagePlayer((w.damage or 10) * 0.5)
	elseif w.pattern == Pattern.Beam then
		-- 射线：直击玩家
		ChainLightningView.Spawn({ { x = enemy.x, y = enemy.y }, { x = tx, y = ty } }, {
			name = "EnemyBeam", height = BattleLayers.Projectile, jitter = 0,
			width = (vfx and vfx.beamWidth) or 0.1,
			lifetime = (vfx and vfx.beamLifetime) or 0.16,
			color = (vfx and vfx.beamColor) or { 0.45, 0.9, 0.3 },
		})
		if vfx and vfx.hit then VFXManager.Spawn(vfx.hit, tx, ty, BattleLayers.GroundHit) end
		self:_damagePlayer((w.damage or 10) * 0.8)
	elseif w.pattern == Pattern.Chain then
		-- 闪电链：从敌人连到玩家（场景仅一名玩家，故为单段链），并绘制闪电连线
		if vfx and vfx.hit then VFXManager.Spawn(vfx.hit, tx, ty, BattleLayers.GroundHit) end
		self:_damagePlayer(w.damage or 10)
		ChainLightningView.Spawn(
			{ { x = enemy.x, y = enemy.y }, { x = tx, y = ty } },
			{
				height   = BattleLayers.Projectile,
				lifetime = (vfx and vfx.chainLifetime) or 0.18,
				jitter   = (vfx and vfx.chainJitter) or 0.35,
				width    = (vfx and vfx.chainWidth) or 0.12,
				color    = (vfx and vfx.chainColor) or { 0.6, 0.85, 1.0 },
			}
		)
	end

	enemy.attackCooldown = enemy.attackInterval
	if enemy.view then enemy.view:PlayAttack("Shoot_OneHanded") end
end

---敌人武器对玩家造成伤害（统一走 DamageSystem：含无敌帧 / 受击表现）
function EnemyManager:_damagePlayer(damage)
	if not self.damageSystem then return end
	self.damageSystem:DamagePlayer(damage)
end

function EnemyManager:TakeDamage(enemyId, damage, isCrit)
	local enemy = self._enemyMap[enemyId]
	if not enemy or enemy.isDead then return false end

	enemy.hp = enemy.hp - math.max(0, damage or 0)

	-- 表现层：未致死 → 受击反馈。
	-- 精英 / Boss 额外播美术的受击动作（RecieveHit）；普通怪只闪红，
	-- 因为受击太频繁，每次都打断移动动作会抽搐。
	if enemy.hp > 0 and enemy.view then
		local heavy = enemy.isElite or enemy.enemyType == "boss"
		pcall(function() enemy.view:FlashHit(heavy) end)
	end

	if enemy.hp <= 0 then
		enemy.hp = 0
		enemy.isDead = true
		self._enemyMap[enemyId] = nil
		self:_removeFromGrid(enemy, enemy.gridX, enemy.gridY)
		self._pendingRemove[#self._pendingRemove + 1] = enemyId
		-- 表现层：标记进入死亡表现（计时与销毁由视图自己走完）
		if enemy.view then
			pcall(function() enemy.view:OnDead(deathKindOf(enemy)) end)
		end
		return true
	end
	return false
end

function EnemyManager:GetEnemiesInRange(x, y, range, maxCount)
	local result = {}
	local rangeSq = range * range
	local minGX = math.floor((x - range) / GRID_SIZE)
	local maxGX = math.floor((x + range) / GRID_SIZE)
	local minGY = math.floor((y - range) / GRID_SIZE)
	local maxGY = math.floor((y + range) / GRID_SIZE)

	for gx = minGX, maxGX do
		for gy = minGY, maxGY do
			local cell = self._grid[gx .. "_" .. gy]
			if cell then
				for _, enemy in ipairs(cell) do
					if not enemy.isDead then
						local dx = enemy.x - x
						local dy = enemy.y - y
						if dx * dx + dy * dy <= rangeSq then
							result[#result + 1] = enemy
							if maxCount and #result >= maxCount then return result end
						end
					end
				end
			end
		end
	end
	return result
end

function EnemyManager:GetNearestEnemy(x, y, exclude, maxRange)
	local excludeSet = {}
	if exclude then
		for _, enemy in ipairs(exclude) do excludeSet[enemy.id] = true end
	end

	local centerGX = math.floor(x / GRID_SIZE)
	local centerGY = math.floor(y / GRID_SIZE)
	local nearest = nil
	local minDistSq = math.huge
	local maxRadius = 10

	for radius = 0, maxRadius do
		for dgx = -radius, radius do
			for dgy = -radius, radius do
				if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
					local cell = self._grid[(centerGX + dgx) .. "_" .. (centerGY + dgy)]
					if cell then
						for _, enemy in ipairs(cell) do
							if not enemy.isDead and not excludeSet[enemy.id] then
								local dx = enemy.x - x
								local dy = enemy.y - y
								local distSq = dx * dx + dy * dy
								if (not maxRange or distSq <= maxRange * maxRange) and distSq < minDistSq then
									minDistSq = distSq
									nearest = enemy
								end
							end
						end
					end
				end
			end
		end

		-- 保守下界：尚未搜索的下一圈不可能比 radius * GRID_SIZE 更近。
		-- 使用严格小于，避免边界 Cell 导致错误提前返回。
		if nearest and radius > 0 and minDistSq < (radius * GRID_SIZE) ^ 2 then
			return nearest
		end
	end

	-- 超出预设半径时，全量 fallback 保证结果仍是全局最近。
	for _, enemy in ipairs(self.enemies) do
		if not enemy.isDead and not excludeSet[enemy.id] then
			local dx = enemy.x - x
			local dy = enemy.y - y
			local distSq = dx * dx + dy * dy
			if (not maxRange or distSq <= maxRange * maxRange) and distSq < minDistSq then
				minDistSq = distSq
				nearest = enemy
			end
		end
	end
	return nearest
end

function EnemyManager:GetNearestEnemies(x, y, count)
	if not count or count <= 0 then return {} end

	local centerGX = math.floor(x / GRID_SIZE)
	local centerGY = math.floor(y / GRID_SIZE)
	local topN = {}
	local topNCount = 0

	local function insertTopN(enemy, distSq)
		if topNCount < count then
			topNCount = topNCount + 1
			topN[topNCount] = { enemy = enemy, distSq = distSq }
		elseif distSq >= topN[topNCount].distSq then
			return
		else
			topN[topNCount] = { enemy = enemy, distSq = distSq }
		end

		local i = topNCount
		while i > 1 and topN[i].distSq < topN[i - 1].distSq do
			topN[i], topN[i - 1] = topN[i - 1], topN[i]
			i = i - 1
		end
	end

	local maxRadius = 15
	for radius = 0, maxRadius do
		for dgx = -radius, radius do
			for dgy = -radius, radius do
				if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
					local cell = self._grid[(centerGX + dgx) .. "_" .. (centerGY + dgy)]
					if cell then
						for _, enemy in ipairs(cell) do
							if not enemy.isDead then
								local dx = enemy.x - x
								local dy = enemy.y - y
								insertTopN(enemy, dx * dx + dy * dy)
							end
						end
					end
				end
			end
		end

		-- topN 中第 N 近目标已经小于下一圈可能出现的保守距离时即可停止。
		if topNCount >= count and radius > 0 and topN[topNCount].distSq < (radius * GRID_SIZE) ^ 2 then
			break
		end
	end

	-- 如果没有足够候选，或搜索到最大半径仍不能证明正确性，则 fallback。
	-- fallback 仍使用 Top-N，不再创建全量 distances + table.sort。
	if topNCount < count or topNCount == count and maxRadius > 0 and topN[topNCount].distSq >= (maxRadius * GRID_SIZE) ^ 2 then
		for _, enemy in ipairs(self.enemies) do
			if not enemy.isDead then
				local dx = enemy.x - x
				local dy = enemy.y - y
				insertTopN(enemy, dx * dx + dy * dy)
			end
		end
	end

	local result = {}
	for i = 1, topNCount do result[i] = topN[i].enemy end
	return result
end

function EnemyManager:GetAliveCount()
	local count = 0
	for _, enemy in ipairs(self.enemies) do
		if not enemy.isDead then count = count + 1 end
	end
	return count
end

function EnemyManager:GetAllAlive()
	local result = {}
	for _, enemy in ipairs(self.enemies) do
		if not enemy.isDead then result[#result + 1] = enemy end
	end
	return result
end

function EnemyManager:_addToGrid(enemy, gx, gy)
	gx = gx or math.floor(enemy.x / GRID_SIZE)
	gy = gy or math.floor(enemy.y / GRID_SIZE)
	local key = gx .. "_" .. gy
	enemy.gridX = gx
	enemy.gridY = gy
	enemy.gridKey = key

	local cell = self._grid[key]
	if not cell then
		cell = {}
		self._grid[key] = cell
	end
	cell[#cell + 1] = enemy
end

function EnemyManager:_removeFromGrid(enemy, gx, gy)
	gx = gx or enemy.gridX
	gy = gy or enemy.gridY
	if gx == nil or gy == nil then return end

	local key = gx .. "_" .. gy
	local cell = self._grid[key]
	if cell then
		for i = #cell, 1, -1 do
			if cell[i] == enemy then
				table.remove(cell, i)
				break
			end
		end
		if #cell == 0 then self._grid[key] = nil end
	end

	enemy.gridX = nil
	enemy.gridY = nil
	enemy.gridKey = nil
end

function EnemyManager:_flushRemoved()
	if #self._pendingRemove == 0 then return end

	local removeSet = {}
	for _, id in ipairs(self._pendingRemove) do removeSet[id] = true end

	local alive = {}
	for _, enemy in ipairs(self.enemies) do
		if not removeSet[enemy.id] then
			alive[#alive + 1] = enemy
		elseif enemy.view then
			-- 表现层：交给视图播死亡动画 / 塌陷，并由它自己计时销毁。
			-- 直接 Destroy 会让尸体【同帧消失】；而计时若交给本管理器推进，
			-- 一旦战斗结束（Boss 死亡即 Victory）就没人再驱动，模型会残留。
			pcall(function() enemy.view:OnDead(deathKindOf(enemy)) end)
		end
	end

	self.enemies = alive
	self._pendingRemove = {}
end

function EnemyManager:Cleanup()
	self:_flushRemoved()
end

function EnemyManager:Destroy()
	-- 表现层：销毁所有残留实体视图
	if self.enemies then
		for _, enemy in ipairs(self.enemies) do
			if enemy.view then pcall(function() enemy.view:Destroy() end) end
		end
	end
	self.enemies = {}
	self._enemyMap = {}
	self._pendingRemove = {}
	self._grid = {}
	self._idCounter = 0
	self.bulletManager = nil
	self.damageSystem = nil
end

return EnemyManager
