local Class = require "Framework.Core.Class"

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
    self.buffSystem = nil
    self.collisionSystem = nil
    self.damageSystem = nil

    self.onPhaseChanged = nil
    self.onEnemyKilled = nil
    self.onLevelUp = nil
    self.onBattleEnd = nil
end

function BattleManager:Init(config)
    config = config or {}

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

    -- 1. 创建所有 System
    self.playerController = PlayerController.New()
    self.weaponSystem = WeaponSystem.New()
    self.bulletManager = BulletManager.New()
    self.enemyManager = EnemyManager.New()
    self.spawnSystem = SpawnSystem.New()
    self.buffSystem = BuffSystem.New()
    self.collisionSystem = CollisionSystem.New()
    self.damageSystem = DamageSystem.New()

    -- 2. 初始化基础 System
    self.playerController:Init(config.player)
    self.enemyManager:Init()
    self.bulletManager:Init()

    -- 3. 注入相互依赖
    self.bulletManager:Inject(self.enemyManager)

    self.weaponSystem:Init(self.playerController)
    self.weaponSystem:Inject(
        self.bulletManager,
        self.enemyManager
    )

    self.enemyManager:SetOnEnemyKilled(function(enemyId)
        self:OnEnemyKilled(enemyId)
    end)

    -- 4. 初始化高层 System
    self.spawnSystem:Init(
        config.waves,
        self.enemyManager
    )

    self.buffSystem:Init(
        self.playerController
    )

    self.damageSystem:Init(
        self.playerController,
        self.enemyManager
    )

    self.collisionSystem:Init(
        self.bulletManager,
        self.enemyManager,
        self.playerController,
        self.damageSystem
    )

    -- 5. 进入 Loading，等待外部 Start()
    self:_setPhase(BattleManager.Phase.Loading)
end

function BattleManager:Start()
    if self.phase == BattleManager.Phase.Loading then
        self:_setPhase(BattleManager.Phase.Running)
    end
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
    if self.phase ~= BattleManager.Phase.Running then
        return
    end

    if not self.playerController
        or not self.weaponSystem
        or not self.bulletManager
        or not self.enemyManager
        or not self.spawnSystem
        or not self.buffSystem
        or not self.collisionSystem
        or not self.damageSystem then
        return
    end

    self.elapsedTime = self.elapsedTime + dt

    -- 1. 玩家输入 + 移动
    self.playerController:Update(dt)

    -- 2. 武器自动攻击
    self.weaponSystem:Update(dt)

    -- 3. 子弹移动
    self.bulletManager:Update(dt)

    -- 4. 敌人 AI + 移动
    local px, py = self.playerController:GetPosition()
    self.enemyManager:Update(
        dt,
        px,
        py
    )

    -- 5. 刷怪
    self.spawnSystem:Update(
        dt,
        self.elapsedTime
    )

    -- 6. Buff 计时
    self.buffSystem:Update(dt)

    -- 7. 统一碰撞
    self.collisionSystem:Update(dt)

    -- 8. 延迟清理
    self.enemyManager:Cleanup()
    self.bulletManager:Cleanup()

    -- 9. 战斗结束
    self:_checkEndCondition()
end

function BattleManager:_checkEndCondition()
    if self.phase ~= BattleManager.Phase.Running then
        return
    end

    if self.elapsedTime >= self.maxTime then
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

function BattleManager:OnEnemyKilled(enemyId)
    self.killCount = self.killCount + 1

    if self.onEnemyKilled then
        self.onEnemyKilled(
            enemyId,
            self.killCount
        )
    end
end

function BattleManager:OnExpGained(exp)
    self.expTotal = self.expTotal + exp
end

function BattleManager:OnLevelUp()
    self:Pause()

    if self.onLevelUp then
        self.onLevelUp()
    end
end

function BattleManager:_setPhase(phase)
    local oldPhase = self.phase

    if oldPhase == phase then
        return
    end

    self.phase = phase

    if self.onPhaseChanged then
        self.onPhaseChanged(
            oldPhase,
            phase
        )
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
    if self.enemyManager then
        self.enemyManager:SetOnEnemyKilled(nil)
    end

    if self.playerController then
        self.playerController:Destroy()
    end

    if self.weaponSystem then
        self.weaponSystem:Destroy()
    end

    if self.bulletManager then
        self.bulletManager:Destroy()
    end

    if self.enemyManager then
        self.enemyManager:Destroy()
    end

    if self.spawnSystem then
        self.spawnSystem:Destroy()
    end

    if self.buffSystem then
        self.buffSystem:Destroy()
    end

    if self.collisionSystem then
        self.collisionSystem:Destroy()
    end

    if self.damageSystem then
        self.damageSystem:Destroy()
    end

    self.playerController = nil
    self.weaponSystem = nil
    self.bulletManager = nil
    self.enemyManager = nil
    self.spawnSystem = nil
    self.buffSystem = nil
    self.collisionSystem = nil
    self.damageSystem = nil

    self.phase = BattleManager.Phase.None
end

return BattleManager
