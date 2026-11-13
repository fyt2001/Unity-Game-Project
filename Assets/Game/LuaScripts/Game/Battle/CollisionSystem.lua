local Class = require "Framework.Core.Class"

local CollisionSystem = Class.Define("CollisionSystem")

function CollisionSystem:Ctor()
	self.bulletManager = nil
	self.enemyManager = nil
	self.playerController = nil
	self.damageSystem = nil

	self.bulletHitRadius = 0.5
	self.playerHitRadius = 0.6
end

function CollisionSystem:Init(
	bulletManager,
	enemyManager,
	playerController,
	damageSystem
)
	self.bulletManager = bulletManager
	self.enemyManager = enemyManager
	self.playerController = playerController
	self.damageSystem = damageSystem
end

function CollisionSystem:Update(dt)
	-- 子系统在 Destroy 后会被置 nil。此处统一防御，
	-- 否则一旦调用顺序变化（未先注销帧驱动）就会直接崩。
	if not self.bulletManager or not self.enemyManager
		or not self.playerController or not self.damageSystem then
		return
	end

	self:_checkBulletCollision()
	self:_checkEnemyBulletCollision()
	self:_checkEnemyPlayerCollision()
end

function CollisionSystem:_checkBulletCollision()
	local bullets =
		self.bulletManager:GetActiveBullets()

	for _, bullet in ipairs(bullets) do
		-- 仅玩家阵营子弹会伤害敌人；敌方子弹交给 _checkEnemyBulletCollision 处理
		if not bullet._remove and (bullet.faction or "player") ~= "enemy" then

			local enemies =
				self.enemyManager:GetEnemiesInRange(
					bullet.x,
					bullet.y,
					self.bulletHitRadius,
					bullet.pierce and 99 or 1
				)

			for _, enemy in ipairs(enemies) do
				if not bullet.hitIds[enemy.id] then

					bullet.hitIds[enemy.id] = true

					local killed =
						self.damageSystem:DamageEnemy(
							enemy,
							bullet.damage,
							bullet.isCrit
						)

					if not bullet.pierce then
						self.bulletManager:Remove(
							bullet,
							true
						)
						break
					end
				end
			end
		end
	end
end

---敌方子弹（faction=="enemy"）命中玩家：朝玩家发射的武器弹会真正伤害玩家
function CollisionSystem:_checkEnemyBulletCollision()
	if self.playerController:IsDead() then
		return
	end

	local px, py =
		self.playerController:GetPosition()

	local bullets =
		self.bulletManager:GetActiveBullets()

	for _, bullet in ipairs(bullets) do
		if not bullet._remove and (bullet.faction or "player") == "enemy" then
			local dx = bullet.x - px
			local dy = bullet.y - py
			if dx * dx + dy * dy <= self.playerHitRadius * self.playerHitRadius then
				self.damageSystem:DamagePlayer(bullet.damage)
				self.bulletManager:Remove(bullet, true)
			end
		end
	end
end

function CollisionSystem:_checkEnemyPlayerCollision()
	if self.playerController:IsDead() then
		return
	end

	local px, py =
		self.playerController:GetPosition()

	local enemies =
		self.enemyManager:GetEnemiesInRange(
			px,
			py,
			3.0,
			99
		)

	for _, enemy in ipairs(enemies) do
		-- 持武敌人改用远程攻击，这里跳过贴身接触伤害
		if (not enemy.rangedAttack) then
			local dx = px - enemy.x
			local dy = py - enemy.y
			local dist = math.sqrt(dx * dx + dy * dy)
			local range = enemy.attackRange or 1.3
			if dist <= range and enemy.attackCooldown <= 0 then
				self.damageSystem:DamagePlayer(enemy.damage)
				enemy.attackCooldown = enemy.attackInterval
				if enemy.view then enemy.view:PlayAttack("Punch") end
			end
		end
	end
end

function CollisionSystem:Destroy()
	self.bulletManager = nil
	self.enemyManager = nil
	self.playerController = nil
	self.damageSystem = nil
end

return CollisionSystem