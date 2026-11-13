local Class = require "Framework.Core.Class"
local UpdateManager = require "Framework.Core.UpdateManager"
local Logger = require "Framework.UI.Utils.Logger"
local VFXConfig = require "Game.Battle.VFXConfig"
local VFXManager = require "Game.Battle.VFXManager"
local BattleLayers = require "Game.Battle.BattleLayers"

local BattleManager = Class.Define("BattleManager")

BattleManager.Phase = {
	None = 0,
	Loading = 1,
	Countdown = 2,
	Running = 3,
	Paused = 4,
	Victory = 5,
	Defeat = 6,
}

function BattleManager:Ctor()
	self.phase = BattleManager.Phase.None
	self.elapsedTime = 0
	self.maxTime = 1200
	self.killCount = 0
	self.expTotal = 0
	self.playerController = nil
	self.weaponSystem = nil
	self.bulletManager = nil
	self.enemyManager = nil
	self.spawnSystem = nil
	self.upgradeSystem = nil    -- 升级三选一（P7 接入）
	self.spawnDirector = nil    -- 怪潮导演（下潜模式使用）
	self.useDirector = false    -- true=走 SpawnDirector；false=走 SpawnSystem 波次时间轴
	self.isBossFloor = false    -- Boss 层：清层条件改为「击杀 Boss」而非时间到
	self.buffSystem = nil
	self.collisionSystem = nil
	self.damageSystem = nil
	self.onPhaseChanged = nil
	self.onEnemyKilled = nil
	self.onLevelUp = nil
	self.onBattleEnd = nil
	self._lastFootstepX = nil    -- 脚步尘：上一次落点
	self._lastFootstepY = nil
end

function BattleManager:Init(config)
	config = config or {}
	self:Destroy()

	self.phase = BattleManager.Phase.None
	self.maxTime = config.maxTime or 1200
	self.elapsedTime = 0
	self.killCount = 0
	self.expTotal = 0

	local PlayerController = require "Game.Battle.PlayerController"
	local WeaponSystem = require "Game.Battle.WeaponSystem"
	local BulletManager = require "Game.Battle.BulletManager"
	local EnemyManager = require "Game.Battle.EnemyManager"
	local SpawnSystem = require "Game.Battle.SpawnSystem"
	local BuffSystem = require "Game.Battle.BuffSystem"
	local CollisionSystem = require "Game.Battle.CollisionSystem"
	local DamageSystem = require "Game.Battle.DamageSystem"
	local DropSystem = require "Game.Battle.DropSystem"
	-- P7：此前 UpgradeSystem 从未被创建，导致升级时 OnLevelUp 无回调、战斗冻结
	local UpgradeSystem = require "Game.Battle.UpgradeSystem"

	-- 1. 创建所有系统
	self.playerController = PlayerController.New()
	self.weaponSystem = WeaponSystem.New()
	self.bulletManager = BulletManager.New()
	self.enemyManager = EnemyManager.New()
	self.spawnSystem = SpawnSystem.New()
	self.upgradeSystem = UpgradeSystem.New()
	self.buffSystem = BuffSystem.New()
	self.collisionSystem = CollisionSystem.New()
	self.damageSystem = DamageSystem.New()

	-- 2. 初始化基础系统
	self.playerController:Init(config.player)
	self.enemyManager:Init()
	self.bulletManager:Init()

	-- 3. 初始化 DamageSystem（回调只依赖 BattleManager 自身状态）
	self.damageSystem:Init(
		self.playerController,
		self.enemyManager,
		function(enemy) self:OnEnemyKilled(enemy) end,   -- 传的是 enemy 表，不是 id
		function(exp) self:OnExpGained(exp) end
	)

	-- 4. 注入相互依赖
	self.bulletManager:Inject(self.enemyManager)
	self.weaponSystem:Init(self.playerController)
	self.weaponSystem:Inject(
		self.bulletManager,
		self.enemyManager,
		self.damageSystem
	)

	-- 5. 初始化高层系统
	self.spawnSystem:Init(config.waves, self.enemyManager)
	self.buffSystem:Init(self.playerController)
	self.upgradeSystem:Init(self.playerController, self.weaponSystem)
	self.collisionSystem:Init(
		self.bulletManager,
		self.enemyManager,
		self.playerController,
		self.damageSystem
	)

	-- 掉落系统：击杀掉落武器/材料/道具（需 enemyManager 能发射敌方子弹）
	self.enemyManager:Inject(self.bulletManager, self.damageSystem)
	self.dropSystem = DropSystem.New()
	self.dropSystem:Init(self.weaponSystem)

	self:_setPhase(BattleManager.Phase.Loading)
end

function BattleManager:Start()
	if self.phase == BattleManager.Phase.Loading then
		self:_setPhase(BattleManager.Phase.Running)
		-- 【关键】BattleManager 自身不会凭空 Update，必须注册到 UpdateManager。
		-- 调用链：C# XLuaManager -> __LuaTick(dt)
		--         -> UpdateManager:OnUpdate(dt) -> BattleManager:Update(dt)
		--         -> playerController:Update(dt)（把 inputX/inputY 积分成坐标）
		-- 少了这一步，Update 永不执行，摇杆输入无法变成位移 —— 角色纹丝不动。
		self:_registerUpdate()

		-- 预热特效资源（异步，不阻塞主线程）：
		-- 未预热时首次命中会因为资源还没加载完而丢失那一次表现。
		VFXManager.Preload(VFXConfig.AllPaths())
	end
end

---切换楼层：重置本层战斗状态，进入下一层
-- 与 Init(config) 的区别（关键）：
--   Init 会 Destroy 再重建所有子系统，PlayerController:Init 会把 hp 重置回满，
--   这与「血量跨层保留、不自动回满」的设定冲突（埋骨渊方案.md 附录 M.2）。
--   因此切层只用 LoadFloor 做【定向重置】：清敌/重置波次/复位坐标/重置计时，
--   保留玩家 hp、等级、经验与攻防属性。
---@param cfg table { duration=本层时长(秒), waves=SpawnSystem 波次时间轴 }
function BattleManager:LoadFloor(cfg)
	cfg = cfg or {}

	self.maxTime = cfg.duration or self.maxTime
	self.elapsedTime = 0
	-- 脚步尘基准点必须复位：否则切层后第一次判定用的是上一层坐标，
	-- 会瞬间触发一次（甚至连续触发）尘土。
	self._lastFootstepX = nil
	self._lastFootstepY = nil
	self.killCount = 0
	self.isBossFloor = (cfg.boss == true)

	-- 清场：EnemyManager:Init() 本身即完整重置（敌人表/索引/网格/ID计数器）
	if self.enemyManager then self.enemyManager:Init() end
	if self.bulletManager then self.bulletManager:Init() end
	if self.dropSystem then self.dropSystem:Reset() end
	if self.weaponSystem then self.weaponSystem:ResetCombatPresentation() end

	-- 刷怪分流：
	--   有 cfg.spawn → 下潜模式，走 SpawnDirector 持续怪潮（含 Elite / Boss）
	--   无 cfg.spawn → 沿用 SpawnSystem 波次时间轴（非下潜的普通战斗仍可用）
	if cfg.spawn then
		if not self.spawnDirector then
			local SpawnDirector = require "Game.Dungeon.SpawnDirector"
			self.spawnDirector = SpawnDirector.New()
		end
		self.spawnDirector:Init({
			floor    = cfg.floor,
			duration = self.maxTime,
			spawn    = cfg.spawn,
			boss     = cfg.boss,
			bossId   = cfg.bossId,
		}, self.enemyManager)
		self.useDirector = true
	else
		self.useDirector = false
		-- 重置刷怪：SpawnSystem:Init 会重置波次进度与出怪计时器
		if self.spawnSystem then
			self.spawnSystem:Init(cfg.waves or {}, self.enemyManager)
		end
	end

	-- 复位玩家坐标与输入（内部刻意不碰 hp/level/属性）
	if self.playerController then self.playerController:ResetTransform() end

	-- 确保帧驱动仍在（幂等）
	self:_registerUpdate()

	-- 回到运行态：Update 与 _checkEndCondition 都只在 Running 下工作
	self:_setPhase(BattleManager.Phase.Running)
end

-- 注册帧驱动。幂等：Start/Init 重复调用不会导致 N 重驱动
function BattleManager:_registerUpdate()
	if self._updateRegistered then return end

	local ok, err = pcall(function()
		UpdateManager:GetInstance():AddUpdate(function(dt) self:Update(dt) end, self)
	end)

	if not ok then
		Logger.Error("BattleManager", "Register UpdateManager failed: %s", tostring(err))
		return
	end

	self._updateRegistered = true
end

-- 注销帧驱动。幂等
function BattleManager:_unregisterUpdate()
	if not self._updateRegistered then return end

	pcall(function()
		UpdateManager:GetInstance():RemoveUpdateByTarget(self)
	end)

	self._updateRegistered = false
end

function BattleManager:Pause()
	if self.phase == BattleManager.Phase.Running then
		self:_setPhase(BattleManager.Phase.Paused)
	end
end

function BattleManager:Resume()
	if self.phase == BattleManager.Phase.Paused then
		self:_setPhase(BattleManager.Phase.Running)
	end
end

function BattleManager:Update(dt)
	if self.phase ~= BattleManager.Phase.Running then return end
	if not self.playerController then return end

	self.elapsedTime = self.elapsedTime + dt

	self.playerController:Update(dt)
	self.buffSystem:Update(dt)

	-- 刷怪分流：下潜走怪潮导演，普通战斗走波次时间轴
	if self.useDirector and self.spawnDirector then
		self.spawnDirector:Update(dt, self.elapsedTime)
	elseif self.spawnSystem then
		self.spawnSystem:Update(dt, self.elapsedTime)
	end

	local px, py = self.playerController:GetPosition()
	self.enemyManager:Update(dt, px, py)

	-- 角色脚步尘（按累计移动距离触发，不是按帧）
	self:_updateFootstepVFX(px, py)

	self.weaponSystem:Update(dt)
	self.bulletManager:Update(dt)
	self.collisionSystem:Update(dt)

	-- 掉落物：玩家靠近自动拾取（武器即时进武器库，材料/道具累计）
	if self.dropSystem then
		local ppx, ppy = self.playerController:GetPosition()
		self.dropSystem:Update(dt, ppx, ppy, 1.2)
	end

	self.enemyManager:Cleanup()
	self.bulletManager:Cleanup()

	self:_checkEndCondition()
end

---玩家脚步尘：每移动 FOOTSTEP_DISTANCE 距离生成一次
-- 按距离而非按帧触发，保证快慢角色的尘土节奏一致，也避免原地站着不停冒烟。
local FOOTSTEP_DISTANCE = 1.2

function BattleManager:_updateFootstepVFX(px, py)
	if not VFXConfig.Common.footstepDust then return end

	if self._lastFootstepX == nil then
		self._lastFootstepX, self._lastFootstepY = px, py
		return
	end

	local dx = px - self._lastFootstepX
	local dy = py - self._lastFootstepY
	if dx * dx + dy * dy >= FOOTSTEP_DISTANCE * FOOTSTEP_DISTANCE then
		self._lastFootstepX, self._lastFootstepY = px, py
		VFXManager.Spawn(VFXConfig.Common.footstepDust, px, py, BattleLayers.Footstep, 1.0)
	end
end

function BattleManager:_checkEndCondition()
	if self.phase ~= BattleManager.Phase.Running then return end

	-- Boss 层：必须【击杀 Boss】才清层，不按时间结束。
	-- 否则时间一到就清层，Boss 白打（P2 决策 #1）。
	if self.isBossFloor then
		-- boss 层若没有 spawnDirector（配了 boss=true 却没配 waves/spawn），
		-- IsBossDead 永远不成立、又被这里短路掉了时间轴判定 → 战斗永不结束。
		-- 兜底：改用「场上已无存活敌人」判定。
		local bossDown = false
		if self.spawnDirector then
			bossDown = self.spawnDirector:IsBossDead()
		else
			local count = 1
			if self.enemyManager and self.enemyManager.GetAliveCount then
				count = self.enemyManager:GetAliveCount()
			end
			bossDown = (count == 0)
		end

		if bossDown then
			self:_setPhase(BattleManager.Phase.Victory)
			if self.onBattleEnd then
				self.onBattleEnd(true, self.killCount, self.elapsedTime)
			end
			return
		end
	elseif self.elapsedTime >= self.maxTime then
		self:_setPhase(BattleManager.Phase.Victory)
		if self.onBattleEnd then
			self.onBattleEnd(true, self.killCount, self.elapsedTime)
		end
		return
	end

	if self.playerController:IsDead() then
		self:_setPhase(BattleManager.Phase.Defeat)
		if self.onBattleEnd then
			self.onBattleEnd(false, self.killCount, self.elapsedTime)
		end
	end
end

function BattleManager:OnEnemyKilled(enemy)
	self.killCount = self.killCount + 1

	-- 击杀掉落：按兵种分类
	--   enemy（持武敌人） → 掉落它携带的武器
	--   monster（怪物）    → 只掉落材料
	if self.dropSystem and enemy then
		if enemy.category == "enemy" and enemy.weaponId then
			self.dropSystem:SpawnWeaponDrop(enemy.weaponId, enemy.x, enemy.y)
		elseif enemy.category == "monster" and enemy.materialId then
			self.dropSystem:SpawnMaterialDrop(enemy.materialId, enemy.x, enemy.y)
		end
	end

	if self.onEnemyKilled then
		self.onEnemyKilled(enemy and enemy.id, self.killCount)
	end
end

function BattleManager:OnExpGained(exp)
	self.expTotal = self.expTotal + exp

	if self.playerController then
		-- 【P2-2】AddExp 返回的是「升级级数」(number)，不是 boolean。
		-- Lua 里 0 是真值，故必须显式 levels > 0；写成 if levels then
		-- 会让每一颗经验球都触发一次升级弹窗。
		local levels = self.playerController:AddExp(exp)
		if levels and levels > 0 then
			self:OnLevelUp(levels)
		end
	end
end

---升级回调：暂停战斗并透传本次连升级数
---@param levels number|nil 本次连升级数（默认 1）
function BattleManager:OnLevelUp(levels)
	self:Pause()
	if self.onLevelUp then
		self.onLevelUp(levels or 1)
	end
end

function BattleManager:_setPhase(phase)
	local oldPhase = self.phase
	if oldPhase == phase then return end
	self.phase = phase
	if self.weaponSystem and (phase == BattleManager.Phase.Paused or phase == BattleManager.Phase.Running) then
		self.weaponSystem:SetCombatPaused(phase == BattleManager.Phase.Paused)
	end
	if self.weaponSystem and (phase == BattleManager.Phase.Victory or phase == BattleManager.Phase.Defeat) then
		self.weaponSystem:ResetCombatPresentation()
	end
	if self.onPhaseChanged then
		self.onPhaseChanged(oldPhase, phase)
	end
end

function BattleManager:GetStats()
	return {
		elapsedTime = self.elapsedTime,
		maxTime = self.maxTime,
		killCount = self.killCount,
		expTotal = self.expTotal,
		phase = self.phase,
	}
end

function BattleManager:Destroy()
	-- 必须先注销帧驱动：否则对象已销毁、回调却仍留在 UpdateManager 里被调用，
	-- Update 内部访问到已被置 nil 的子系统会直接报错
	self:_unregisterUpdate()

	-- 特效池跨局无意义（且会持有上一局的实例），战斗销毁时一并释放；
	-- ClearCache 还会清掉 prefabCache 与「资源缺失黑名单」，
	-- 让换局/补资源后能重新解析路径。
	VFXManager.ClearCache()

	if self.playerController then self.playerController:Destroy() end
	if self.weaponSystem then self.weaponSystem:Destroy() end
	if self.bulletManager then self.bulletManager:Destroy() end
	if self.enemyManager then self.enemyManager:Destroy() end
	if self.spawnSystem then self.spawnSystem:Destroy() end
	if self.upgradeSystem then self.upgradeSystem:Destroy() end
	if self.spawnDirector then self.spawnDirector:Destroy() end
	if self.buffSystem then self.buffSystem:Destroy() end
	if self.collisionSystem then self.collisionSystem:Destroy() end
	if self.damageSystem then self.damageSystem:Destroy() end
	if self.dropSystem then self.dropSystem:Destroy() end

	self.playerController = nil
	self.weaponSystem = nil
	self.bulletManager = nil
	self.enemyManager = nil
	self.spawnSystem = nil
	self.upgradeSystem = nil
	self.spawnDirector = nil
	self.dropSystem = nil
	self.useDirector = false
	self.isBossFloor = false
	self.buffSystem = nil
	self.collisionSystem = nil
	self.damageSystem = nil
end

return BattleManager
