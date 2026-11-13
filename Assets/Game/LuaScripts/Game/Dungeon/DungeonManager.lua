--[[
=============================================================================
DungeonManager.lua - 下潜 Run 状态机（P1）
=============================================================================
Module:     Game/Dungeon/DungeonManager
Version:    1.0.0

Description:
	管理「一整局下潜 Run」：连续楼层、清层、奖励、死亡回城。
	位于 BattleManager 之上（单层战斗引擎），不重造战斗逻辑。

	P1 范围：连续下潜 + 清层 + 奖励 + 死亡回城。
	不含：事件内容(P3)、回城卷轴/结算(P4)、存档/Meta(P5)、Mod(P6)。

	清层与死亡判定【不新写】：复用 BattleManager 已有的
	_checkEndCondition —— 时间到→Victory、玩家死→Defeat，
	并通过 bm.onBattleEnd 回调拿结果。

	帧驱动说明：P1 的楼层计时完全由 BattleManager 驱动（其 elapsedTime
	已达 maxTime 即 Victory）。本文件的 Update 只做 RunData 同步，
	留作 P2/P3 的事件计时/卷轴冷却使用。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"
local UpdateManager = require "Framework.Core.UpdateManager"
local GameMain = require "Game.GameMain"
local FloorGenerator = require "Game.Dungeon.FloorGenerator"
local FloorEventSystem = require "Game.Dungeon.FloorEventSystem"
local RunResult = require "Game.Dungeon.RunResult"
local SaveData = require "Game.Save.SaveData"
local MetaSystem = require "Game.Save.MetaSystem"
local ModSystem = require "Game.Mod.ModSystem"
local BuildSystem = require "Game.Build.BuildSystem"
-- P2-4：读取 BattleManager.Phase 判定「是否已有别的模态占用了 Pause」
local BattleManager = require "Game.Battle.BattleManager"
local OnlineSession = require "Game.Online.OnlineSession"

local DungeonManager = Class.Define("DungeonManager")

-- 层间事件弹窗无响应时的自动选择兜底（秒）。
-- 防止 UIManager 存在但弹窗未接回调，导致 Run 永久停在 FloorEvent、下一层永不触发。
local FLOOR_EVENT_TIMEOUT = 20   -- 玩家用 C# 面板选择时的兜底超时（秒）

-- 撤离确认框无响应时的兜底（秒）。
-- 与升级弹窗不同，这里【不能自动确认】（会消耗唯一稀缺资源），
-- 一律按「取消」放行：取消不消耗任何东西，是最安全的分支。
local EXTRACT_CONFIRM_TIMEOUT = 60

---Run 状态（埋骨渊方案.md §3）
DungeonManager.RunState = {
	None = "None",
	Preparing = "Preparing",
	Fighting = "Fighting",
	FloorClear = "FloorClear",
	FloorReward = "FloorReward",
	FloorEvent = "FloorEvent",
	PreparingNextFloor = "PreparingNextFloor",
	Boss = "Boss",
	Extracting = "Extracting",
	Dead = "Dead",
	Result = "Result",
}

function DungeonManager:Ctor()
	self.state = DungeonManager.RunState.None
	self.runData = nil
	self.battleManager = nil
	self.itemSystem = nil
	self.buildSystem = nil
	self.lastResult = nil
	self.currentFloor = 0
	self.currentFloorCfg = nil
	self.onStateChanged = nil
	self._started = false
	self._settled = false          -- P2-1：本局是否已结算（幂等守卫）
	self._onlineRunId = nil
	self._settlementStatus = nil
	self._settlementOutcome = nil
	self._settlementBusy = false
	self._generation = 0
	-- P2-2：升级三选一弹窗状态
	self._levelUpOptions = nil     -- 非 nil 表示弹窗正在展示这批候选
	self._levelUpPending = 0       -- 待选次数（一次经验可能连升多级）
	self._levelUpTimer = 0         -- 弹窗无响应兜底计时
	-- P2-4：玩家主动暂停 / 撤离二次确认
	self._userPaused = false           -- 暂停菜单是否由玩家主动打开（决定 Resume 归属）
	self._extractConfirming = false    -- 撤离确认框是否正在展示（此时战斗 Paused）
	self._extractConfirmTimer = 0      -- 确认框无响应兜底计时
	self._updateRegistered = false
	self._runModifiersApplied = false
	self.derived = nil
end

-- =============================================================================
-- RunData（本局临时数据，方案 §4.1）
-- =============================================================================

function DungeonManager:_newRunData()
	return {
		runId = os.time(),
		floor = 1,
		player = { hp = 100, maxHp = 100, level = 1, exp = 0 },
		build = { weapons = {}, skills = {}, relics = {} },
		mods = { weapon = {}, skill = {}, frame = {} },
		loot = { gold = 0, items = {}, materials = {} },
		-- max = 携带上限（不是当前持有数）。
		-- 若写成 {1, 1} 则卷轴包一开始就是满的，MerchantEvent 永远买不了卷轴。
		scroll = { current = 1, max = 3 },
		buffs = {},
		events = {},
		statistics = { killCount = 0, eliteKillCount = 0, damage = 0, time = 0 },
	}
end

-- =============================================================================
-- 生命周期
-- =============================================================================

---开始一局下潜
---@param config table|nil 预留（P6 起用于传入 Mod 配装等初始数据）
function DungeonManager:StartRun(config)
	config = config or {}
	if self._started then
		Logger.Warn("DungeonManager", "StartRun ignored: run already started")
		return false, "run_already_started"
	end
	if OnlineSession.IsSelected() and (not OnlineSession.IsReady()
		or not config.onlineRunId or config.onlineRunId ~= OnlineSession.GetRunId()) then
		Logger.Warn("DungeonManager", "Online run start denied: session/run mismatch")
		return false, "online_run_required"
	end
	self._generation = self._generation + 1
	self._onlineRunId = OnlineSession.IsSelected() and config.onlineRunId or nil
	self._settlementStatus = nil
	self._settlementOutcome = nil
	self._settlementBusy = false

	self._started = true
	self._settled = false   -- 新一局，重置结算标记（P2-1）
	self._levelUpOptions = nil   -- 新一局，重置升级弹窗状态（P2-2）
	self._levelUpPending = 0
	self._levelUpTimer = 0
	self._userPaused = false        -- P2-4：暂停菜单状态
	self._extractConfirming = false
	self._extractConfirmTimer = 0
	self.runData = self:_newRunData()
	if self._onlineRunId then
		self.runData.runId = self._onlineRunId
		self.runData.onlineRunId = self._onlineRunId
	end

	-- 卷轴统一入口（P4）：收敛 P3 里 MerchantEvent 直接改 RunData.scroll 的做法
	if not self.itemSystem then
		local ItemSystem = require "Game.Dungeon.ItemSystem"
		self.itemSystem = ItemSystem.New()
	end
	self.itemSystem:Init(self.runData)

	-- Meta 天赋生效（P5）：初始卷轴等
	MetaSystem.ApplyToRun(self.runData)
	-- Mod 派生属性（P6）：先算好，等 PlayerController 创建后再作用到玩家
	self.derived = ModSystem.ApplyLoadout(self.runData)
	self._runModifiersApplied = false

	-- Build（P7）：武器 / 技能 / 遗物
	if not self.buildSystem then
		self.buildSystem = BuildSystem.New()
	end
	self.buildSystem:Init(self.runData)
	self.buildSystem:SetDerived(self.derived)

	self:_setState(DungeonManager.RunState.Preparing)
	self:_registerUpdate()

	Logger.Info("DungeonManager", "Run started (id=%s)", tostring(self.runData.runId))
	self:EnterFloor(1)
	return true
end

---进入指定楼层
function DungeonManager:EnterFloor(floor)
	if self._settled then return end
	local cfg = FloorGenerator.Generate(floor)
	self.currentFloor = floor
	self.currentFloorCfg = cfg

	local bm = self:_ensureBattleManager(cfg)
	if not bm then
		Logger.Error("DungeonManager", "EnterFloor(%d) failed: BattleManager unavailable", floor)
		return
	end

	-- 定向重置竞技场（不重建子系统、不重置玩家 hp/等级）
	-- spawn 存在 → BattleManager 走 SpawnDirector 怪潮模式（含 Elite / Boss）
	bm:LoadFloor({
		duration = cfg.duration,
		waves    = FloorGenerator.BuildWaves(cfg),   -- 非下潜模式兜底
		spawn    = FloorGenerator.BuildSpawnConfig(cfg),
		floor    = floor,
		boss     = cfg.boss,
		bossId   = cfg.bossId,
	})

	if self.runData then self.runData.floor = floor end

	-- Meta + Mod 对玩家生效（P5/P6）：每局只应用一次，避免每层重复叠加
	self:_applyRunModifiers()

	self:_setState(cfg.boss and DungeonManager.RunState.Boss or DungeonManager.RunState.Fighting)

	Logger.Info("DungeonManager",
		"Enter floor %d (duration=%ss, enemyLevel=%s, boss=%s)",
		floor, tostring(cfg.duration), tostring(cfg.enemyLevel), tostring(cfg.boss))
end

---Meta 天赋 + Mod 派生属性应用到玩家（P5 / P6）
-- 每局【只应用一次】：maxHp / atk 这类加成若每层都加会不断叠加。
function DungeonManager:_applyRunModifiers()
	if self._runModifiersApplied then return end

	local pc = self.battleManager and self.battleManager.playerController
	if not pc then return end

	self._runModifiersApplied = true
	MetaSystem.ApplyToPlayer(pc)
	ModSystem.ApplyToPlayer(pc, self.derived)
	if self.battleManager.weaponSystem then
		self.battleManager.weaponSystem:SetModDerived(self.derived)
	end
	-- 起手武器（P7）：没有武器就完全没有输出手段
	if self.buildSystem then
		self.buildSystem:GrantStartingWeapon(self.battleManager)
	end
end

---确保 BattleManager 存在并接管其结束回调
function DungeonManager:_ensureBattleManager(floorCfg)
	local bm = GameMain.GetBattleManager()

	if not bm then
		GameMain.StartBattle(self:_buildBattleConfig(floorCfg))
		bm = GameMain.GetBattleManager()
	end
	if not bm then return nil end

	self.battleManager = bm

	bm.onBattleEnd = function(isWin, kills, elapsed)
		self:_onBattleEnd(isWin, kills, elapsed)
	end

	-- P7：升级回调。BattleManager:OnLevelUp 会 Pause，
	-- 若不挂回调并在选完后 Resume，战斗会【永久冻结】。
	-- P2-2：levels 是本次连升级数（AddExp 返回值，见 PlayerController:AddExp）。
	bm.onLevelUp = function(levels)
		self:_onLevelUp(levels)
	end

	return bm
end

-- =============================================================================
-- 升级三选一（P2-2）
-- =============================================================================

-- 升级弹窗无响应时的兜底超时（秒）。
-- 与 FLOOR_EVENT_TIMEOUT 同理：面板「存在但回调没接上」（或 prefab 缺失导致窗口
-- 静默没开）时，绝不能让处于 Pause 的战斗永久冻住 —— 这比白给一级严重得多。
local LEVELUP_TIMEOUT = 30

---升级入口（由 BattleManager:OnLevelUp 经 bm.onLevelUp 回调）。
---此时 BattleManager 已经 Pause()，本函数负责「把玩家选完之前的时间撑住」。
---@param levels number|nil 本次连升级数（AddExp 可能一次升多级）
function DungeonManager:_onLevelUp(levels)
	levels = tonumber(levels) or 1
	if levels < 1 then levels = 1 end

	-- 已结算（撤离/阵亡）后不再弹升级窗：此时战斗已被 _freezeBattle 冻结、
	-- 结算面板正在展示，再弹一个需要玩家抉择的窗口会把玩家困在已结束的一局里。
	-- 战斗已经是 Paused，这里既不需要也不能 Resume。
	if self._settled then
		Logger.Warn("DungeonManager", "已结算，忽略升级三选一（%d 级）", levels)
		return
	end

	-- 一次经验可能连升多级：累积待选次数，选完一次自动续下一次
	self._levelUpPending = (self._levelUpPending or 0) + levels
	if self._levelUpOptions then
		return   -- 弹窗已在展示，选完会自动续
	end
	self:_showNextLevelUp()
end

---展示下一次升级选择；无法展示时一律兜底自动选（绝不停在 Pause）
function DungeonManager:_showNextLevelUp()
	local bm = self.battleManager
	if not bm or not self.buildSystem then
		self:_finishLevelUp()
		return
	end

	local ok, options = pcall(function() return self.buildSystem:GenerateChoices(bm, 3) end)
	if not ok then
		Logger.Warn("DungeonManager", "GenerateChoices failed: %s", tostring(options))
		options = nil
	end

	-- 空池兜底：候选为空也必须放行，否则战斗停在 Pause 永久冻结。
	-- （清空 _levelUpPending 是为了不逐级重试 -> 避免「重开 -> 又空 -> 再重开」死循环）
	if not options or #options == 0 then
		Logger.Warn("DungeonManager", "升级候选为空，跳过本次选择（战斗照常恢复）")
		self._levelUpPending = 0
		self:_finishLevelUp()
		return
	end

	self._levelUpOptions = options
	self._levelUpTimer = 0

	if self:_openLevelUpPopup(options) then
		return
	end

	-- 面板打不开：退化成自动选，保证这一局不卡死
	self:_autoPickLevelUp()
end

---打开升级弹窗
---@param options table 候选列表（每项含 name/desc/type）
---@return boolean 是否成功交给 UI
function DungeonManager:_openLevelUpPopup(options)
	local ok, opened = pcall(function()
		local ui = GameMain.GetUIManager()
		if not ui or not ui.Open then return false end
		ui:Open("LevelUpPopup", options, self._levelUpPending)
		return true
	end)
	if not ok then
		Logger.Warn("DungeonManager", "openLevelUpPopup failed: %s", tostring(opened))
		return false
	end
	return opened == true
end

---UI 不可用时的退化：自动选一个，保证战斗能恢复
function DungeonManager:_autoPickLevelUp()
	local options = self._levelUpOptions
	pcall(function()
		local ui = GameMain.GetUIManager()
		if ui and ui.Close then ui:Close("LevelUpPopup", "Unavailable") end
	end)
	self._levelUpOptions = nil
	self._levelUpTimer = 0

	if self.buildSystem and self.battleManager then
		local ok, err = pcall(function()
			self.buildSystem:AutoPickFallback(self.battleManager, options)
		end)
		if not ok then
			Logger.Warn("DungeonManager", "AutoPickFallback failed: %s", tostring(err))
		end
	end
	self:_finishLevelUp()
end

---玩家在弹窗选择了第 index 个选项（由 UILevelUpController 回调）
---与 SelectFloorEventOption 同形：UI 只回传意图，不反向驱动流程。
function DungeonManager:SelectLevelUpOption(index)
	if self._settled then return end
	local options = self._levelUpOptions
	local bm = self.battleManager
	if not options or not options[index] then return end
	self._levelUpOptions = nil
	self._levelUpTimer = 0

	local opt = options and options[index]
	if not opt then
		Logger.Warn("DungeonManager", "SelectLevelUpOption(%s) 无效索引", tostring(index))
	elseif bm and self.buildSystem then
		local ok, err = pcall(function()
			self.buildSystem:ApplyLevelUpChoice(bm, opt)
		end)
		if ok then
			Logger.Info("DungeonManager", "升级选择: %s", tostring(opt.name or opt.stat))
		else
			Logger.Warn("DungeonManager", "应用升级选项失败: %s", tostring(err))
		end
	end

	pcall(function()
		local ui = GameMain.GetUIManager()
		if ui and ui.IsOpen and ui:IsOpen("LevelUpPopup") then
			ui:Close("LevelUpPopup", "Selected")
		end
	end)

	self:_finishLevelUp()
end

---升级流程唯一出口：保证 Resume【恰好一次】。
---一次连升多级时 _levelUpPending 仍 > 0，则继续下一次选择（战斗保持 Pause）。
function DungeonManager:_finishLevelUp()
	if self._settled then return end
	if (self._levelUpPending or 0) > 0 then
		self._levelUpPending = self._levelUpPending - 1
	end

	if self._levelUpPending > 0 then
		self:_showNextLevelUp()
		return
	end
	self._levelUpPending = 0

	-- 关键：BattleManager:OnLevelUp 已 Pause，任何路径都必须恢复一次
	if self.battleManager and self.battleManager.Resume then
		pcall(function() self.battleManager:Resume() end)
	end
end

---结算时收掉未处理的升级弹窗（否则它会盖在结算面板上并占住 pending）
function DungeonManager:_clearLevelUpPopup()
	self._levelUpOptions = nil
	self._levelUpPending = 0
	self._levelUpTimer = 0

	pcall(function()
		local ui = GameMain.GetUIManager()
		if ui and ui.IsOpen and ui:IsOpen("LevelUpPopup") then
			ui:Close("LevelUpPopup", "Settled")
		end
	end)
end

---首次创建战斗用的配置（后续楼层走 LoadFloor，不再走 Init）
function DungeonManager:_buildBattleConfig(floorCfg)
	return {
		maxTime = floorCfg.duration,
		waves = FloorGenerator.BuildWaves(floorCfg),
		player = { maxHp = 100 },
	}
end

-- =============================================================================
-- 战斗结束回调（清层 / 死亡）
-- =============================================================================

function DungeonManager:_onBattleEnd(isWin, kills, elapsed)
	if not self.runData or self._settled then return end

	self.runData.statistics.killCount = self.runData.statistics.killCount + (kills or 0)
	self.runData.statistics.time = self.runData.statistics.time + (elapsed or 0)

	if isWin then
		self:OnFloorClear()
	else
		self:OnPlayerDead()
	end
end

function DungeonManager:OnFloorClear()
	if not self.runData or self._settled then return end
	self:_setState(DungeonManager.RunState.FloorClear)
	Logger.Info("DungeonManager", "Floor %d cleared", self.currentFloor)

	self:GrantFloorReward()
	self:RollFloorEvent()
end

---发放楼层奖励
-- 只给金币 + 回血；经验刻意【不走】AddExp：
-- BattleManager:OnLevelUp 会 Pause 战斗等待升级弹窗（P3 才有 UI），
-- P1 直接给经验会导致战斗卡在 Paused。经验仍由击杀自然产出。
function DungeonManager:GrantFloorReward()
	self:_setState(DungeonManager.RunState.FloorReward)

	local cfg = self.currentFloorCfg
	if not cfg then return end

	local reward = cfg.reward or {}
	self.runData.loot.gold = self.runData.loot.gold + (reward.gold or 0)

	-- Boss 层额外发 Boss 奖励
	-- modPool 字段已就位，但 Mod 系统在 P6，届时接「Boss 必掉 mod」
	if cfg.boss and cfg.bossId then
		local BossConfig = require "Game.Dungeon.BossConfig"
		local tpl = BossConfig.Get(cfg.bossId)
		local bossGold = (tpl.rewards and tpl.rewards.gold) or 0
		self.runData.loot.gold = self.runData.loot.gold + bossGold
		Logger.Info("DungeonManager", "Boss reward +%d gold (%s)", bossGold, tostring(cfg.bossId))

		-- Boss 必掉 Mod（设计稿 §10.5 / §12）：Mod 是永久资产，直接进背包
		local ModInventory = require "Game.Mod.ModInventory"
		local pool = tpl.rewards and tpl.rewards.modPool
		local got = not self._onlineRunId and ModInventory.GrantRandom(pool)
		if got then
			-- P3-1 起【不再自动装配】：掉落的 Mod 只进背包，
			-- 等玩家回主城在配装面板自己装（否则玩家不知道自己被动改了配装，
			-- 而且自动装配的极性/容量判定玩家看不见）。
			Logger.Info("DungeonManager", "Boss dropped mod uid=%d (id=%d) -> 进背包，待玩家主城装配",
				got.uid, got.id)
		end
	end

	-- 把战斗中拾取的材料/道具并入本局渊获（武器已在拾取时即时进武器库，不在此处理）
	local ds = self.battleManager and self.battleManager.dropSystem
	if ds then
		local loot = ds:GetCollectedLoot()
		for id, c in pairs(loot.materials or {}) do
			self.runData.loot.materials[id] = (self.runData.loot.materials[id] or 0) + c
		end
		for id, c in pairs(loot.items or {}) do
			self.runData.loot.items[id] = (self.runData.loot.items[id] or 0) + c
		end
	end

	-- 每 5 层保底 +1 卷轴（设计稿 §11 ⭐E；受 max 容量限制，满了就跳过）
	if self.itemSystem then
		self.itemSystem:TryGrantFloorScroll(self.currentFloor)
	end

	-- 清层回血 10% maxHp（附录 M.2：血量跨层保留，不自动回满）
	local pc = self.battleManager and self.battleManager.playerController
	if pc then
		pc:Heal(pc.maxHp * 0.10)
		self.runData.player.hp = pc.hp
		self.runData.player.maxHp = pc.maxHp
		Logger.Info("DungeonManager", "Reward +%d gold, hp now %d/%d",
			reward.gold or 0, pc.hp, pc.maxHp)
	end
end

---层间事件（P3：接 FloorEventSystem）
-- 事件池来自当前楼层的 FloorConfig.eventPool。
-- ctx 只带 playerController，避免事件反向依赖 BattleManager。
function DungeonManager:RollFloorEvent()
	self:_setState(DungeonManager.RunState.FloorEvent)

	-- 进入事件时冻结战斗：避免 8 秒计时器继续走而重触发清层回调（P8 实测 bug）
	if self.battleManager then self.battleManager:Pause() end

	if not self.runData then
		self:NextFloor()
		return
	end

	local cfg = self.currentFloorCfg
	local pool = (cfg and cfg.eventPool) or {}
	if #pool == 0 then
		self:NextFloor()
		return
	end

	local ctx = {
		playerController = self.battleManager and self.battleManager.playerController,
		itemSystem = self.itemSystem,   -- 让事件走卷轴统一入口，而不是直接改 RunData
	}

	local ev = FloorEventSystem.Roll(self.runData, pool, ctx)
	if not ev then
		self:NextFloor()
		return
	end

	local opts = ev:GetOptions()
	if not opts or #opts == 0 then
		ev:Exit()
		self:NextFloor()
		return
	end

	self._pendingEvent = ev
	self._pendingOptions = opts
	self._floorEventTimer = 0   -- 启动兜底计时，防止卡死

	-- P8：优先弹窗让玩家选；UI 不可用时才退化成自动选（保证流程不卡死）
	if self:_openEventPopup(ev, opts) then
		return
	end

	self:_autoSelectEvent()
end

---层间事件弹窗开关。
-- 使用规范的 Unity 弹窗（UIFloorEventView/Model/Prefab + MVC），玩家在弹窗内点击选项抉择。
local ENABLE_FLOOR_EVENT_POPUP = true

---打开事件弹窗
---@param ev table 事件实例（用于取真实展示文案 GetDisplay）
---@param opts table 选项列表 { {id,text,enabled}, ... }
function DungeonManager:_openEventPopup(ev, opts)
	if not ENABLE_FLOOR_EVENT_POPUP then return false end
	local ok, opened = pcall(function()
		local GameMain = require "Game.GameMain"
		local ui = GameMain.GetUIManager()
		if not ui or not ui.Open then return false end

		-- 取事件真实文案；事件未实现 GetDisplay 时回退占位串
		local title, body = "层间事件", "选择你的命运"
		if ev and ev.GetDisplay then
			local d = ev:GetDisplay() or {}
			title = d.title or title
			body = d.body or body
		end

		ui:Open("FloorEventPopup", title, body, opts)
		return true
	end)
	if not ok then
		-- 此前这里静默降级到「自动选择」，任何打开失败都查不到原因。
		Logger.Warn("DungeonManager", "openEventPopup failed: %s", tostring(opened))
		return false
	end
	if opened == false then
		Logger.Warn("DungeonManager", "openEventPopup returned false (UIManager unavailable?)")
	end
	return opened
end

---UI 不可用时的退化：自动选，保证下潜不被卡住
function DungeonManager:_autoSelectEvent()
	local ev = self._pendingEvent
	local opts = self._pendingOptions
	self._pendingEvent = nil
	self._pendingOptions = nil

	if not ev then
		self:NextFloor()
		return
	end

	local pick = opts and opts[1]
	if pick then ev:Select(pick.id) end
	ev:Exit()
	self:NextFloor()
end

---玩家点了弹窗右上角关闭（由 UIFloorEventController 回调）：等同超时兜底，立即自动选择。
---与 Update 里的 FLOOR_EVENT_TIMEOUT 兜底走同一条 _autoSelectEvent 路径，行为一致；
---加状态守卫，防止弹窗已不在等待态时误触发。
function DungeonManager:AutoSelectFloorEvent()
	if self.state ~= DungeonManager.RunState.FloorEvent or not self._pendingEvent then return end
	self:_autoSelectEvent()
end

---玩家在弹窗选择了第 index 个选项（由 UIFloorEventController 回调）
function DungeonManager:SelectFloorEventOption(index)
	if self._settled then return end
	Logger.Info("DungeonManager", "SelectFloorEventOption(%s)", tostring(index))
	local ev = self._pendingEvent
	local opts = self._pendingOptions
	self._pendingEvent = nil
	self._pendingOptions = nil

	if ev and opts then
		local opt = opts[index]
		if opt then ev:Select(opt.id) end
		ev:Exit()
	end

	pcall(function()
		local GameMain = require "Game.GameMain"
		local ui = GameMain.GetUIManager()
		if ui and ui.Close then ui:Close("FloorEventPopup", "EventSelected") end
	end)

	self:NextFloor()
end

---是否有可使用的回城卷轴（供 HUD 按钮可见性判断）
function DungeonManager:CanUseReturnScroll()
	if not self.itemSystem then return false end
	return self.itemSystem:CanUseReturnScroll()
end

function DungeonManager:NextFloor()
	if self._settled then return end
	self:_setState(DungeonManager.RunState.PreparingNextFloor)
	self:EnterFloor(self.currentFloor + 1)
end

function DungeonManager:OnPlayerDead()
	if not self.runData then return end

	-- 已结算（结算面板展示中）就不再处理死亡（P2-1）。
	-- 撤离结算后战斗若未及时冻结，玩家可能再次死亡走到这里，
	-- 会把 state 从 Result 覆盖成 Dead，并触发重复结算。
	if self._settled then return end

	self:_setState(DungeonManager.RunState.Dead)
	Logger.Info("DungeonManager", "Player dead at floor %d", self.currentFloor)

	-- 死亡结算：渊获清空，只留记忆碎片（设计稿 §13）
	self:_settle(RunResult.Outcome.Death)
end

-- =============================================================================
-- P2-4：玩家暂停 与 撤离二次确认
-- =============================================================================
--
-- 为什么这两件事放在一起做：
-- 	回城卷轴是本局【唯一稀缺资源】。改动前点 HUD 按钮直接 ConsumeReturnScroll，
-- 	一次误触就毁掉一局且毫无提示（总序 P2-4）。加了二次确认后需要一个「让玩家
-- 	能停下来看清局势」的地方，暂停菜单于是成了它的天然宿主 —— 所以撤离入口有二：
-- 	HUD 卷轴按钮、暂停菜单的撤离按钮，二者共用 RequestExtract()。
--
-- 【本轮最大的风险：谁来 Resume】
-- 	战斗 Pause 一旦发生，必须且只能由【一个收口】恢复，否则：
-- 		漏 Resume → 战斗永久冻结（P2-2 已踩过）
-- 		重复 Resume → 双重恢复
-- 	这里的做法是给每个占用 Pause 的模态一个排他标记，并用 phase == Running
-- 	作为前置条件，使升级弹窗 / 层间事件 / 结算面板 / 暂停菜单 / 撤离确认
-- 	【同一时刻只会有一个占用 Pause】，各自收各自的口。
-- =============================================================================

---关闭一个可能开着的窗口；窗口不存在时静默跳过。
-- 写成 local 而非冒号方法：函数体不用 self，写成 self:xxx 会被
-- luacheck 判 unused argument 'self'。
local function closeWindowIfOpen(name, reason)
	pcall(function()
		local ui = GameMain.GetUIManager()
		if ui and ui.IsOpen and ui:IsOpen(name) then
			ui:Close(name, reason)
		end
	end)
end

---是否可以接受玩家的主动暂停。
-- 判据只有一条：BattleManager.phase 是否还是 Running。
-- phase 一旦不是 Running，说明已有别的模态（升级弹窗 / 层间事件 / 结算面板 /
-- 撤离确认）占用了 Pause —— 此时再放行会造成两个收口互相打架。
---@return boolean
function DungeonManager:CanPlayerPause()
	if self._settled then return false end
	if self._extractConfirming then return false end
	local bm = self.battleManager
	if not bm then return false end

	-- 例外：暂停菜单【自己】占住的这个 Pause 允许原地换页（暂停菜单 → 撤离确认）。
	-- 判据只认 phase == Running 会把这条路径误杀 —— 玩家在暂停菜单里点「撤离」时
	-- 战斗早已是 Paused，结果请求被静默拒绝、按钮看起来像失灵。
	if self._userPaused then return true end

	-- 否则必须是 Running：phase 一旦不是 Running，说明已有别的模态
	-- （升级弹窗 / 层间事件 / 结算面板）占用了 Pause，放行会造成两个 Resume 收口打架
	return bm.phase == BattleManager.Phase.Running
end

---战斗恢复的唯一出口（所有 Resume 都经过这里，便于日志追责）
---@param reason string 便于追查是谁触发的恢复
function DungeonManager:_resumeBattle(reason)
	if self._settled then return end
	local bm = self.battleManager
	if bm and bm.Resume then
		pcall(function() bm:Resume() end)
	end
	Logger.Info("DungeonManager", "Battle resumed (reason=%s)", tostring(reason))
end

---玩家主动暂停：暂停战斗 + 打开暂停菜单
---@return boolean 是否真的暂停成功（false 表示被拒绝，战斗状态未变）
function DungeonManager:PauseGame()
	if not self.runData then return false end
	if self._userPaused then return false end   -- 已在暂停中：重复点击直接忽略
	if not self:CanPlayerPause() then
		Logger.Warn("DungeonManager", "PauseGame rejected: phase=%s settled=%s confirming=%s",
			tostring(self.battleManager and self.battleManager.phase),
			tostring(self._settled), tostring(self._extractConfirming))
		return false
	end

	local bm = self.battleManager
	if bm and bm.Pause then
		pcall(function() bm:Pause() end)
	end
	self._userPaused = true

	-- UI 若打不开必须立刻退回去：战斗已 Paused 而没有任何面板能把它恢复，
	-- 结果是【永久冻结】—— 这比「暂停用不了」严重得多。
	if not self:_openPausePanel() then
		self._userPaused = false
		self:_resumeBattle("PausePanelUnavailable")
		return false
	end

	Logger.Info("DungeonManager", "Paused by player at floor %d", self.currentFloor)
	return true
end

---恢复战斗并收掉暂停菜单（暂停菜单的「继续」/ 右上角关闭 / 场景离开共用）
---@param reason string
function DungeonManager:ResumeGame(reason)
	if not self._userPaused then return end
	self._userPaused = false
	closeWindowIfOpen("PausePanel", "PauseResolved")
	self:_resumeBattle(reason or "ResumeGame")
end

---本局快照（暂停菜单展示用；纯读取，不改任何状态）
---@return table { floor, killCount, scrollCount, elapsed, canExtract }
function DungeonManager:GetPauseSnapshot()
	local scrollCount = 0
	local canExtract = false
	if self.itemSystem then
		scrollCount = self.itemSystem:GetScrollCount() or 0
		canExtract = self.itemSystem:CanUseReturnScroll() and true or false
	end

	local stats = (self.runData and self.runData.statistics) or {}
	-- BattleManager 的 elapsedTime / killCount 是【本层】值（LoadFloor 时清零），
	-- runData.statistics 存的是【已累计】值。快照要把本层加上才是玩家看到的真实进度。
	local killCount = stats.killCount or 0
	local elapsed = stats.time or 0

	local bm = self.battleManager
	if bm and bm.GetStats then
		local ok, s = pcall(function() return bm:GetStats() end)
		if ok and s then
			killCount = killCount + (s.killCount or 0)
			elapsed = elapsed + (s.elapsedTime or 0)
		end
	end

	return {
		floor = self.currentFloor or 0,
		killCount = killCount,
		scrollCount = scrollCount,
		elapsed = elapsed,
		canExtract = canExtract,
	}
end

---撤离收益预览（确认框展示用；纯读取，不消耗任何资源）
--
-- 刻意复用 RunResult.Build（outcome 固定为 Extract），而不是另写一套估算：
-- 只有这样才能保证「确认框上显示的数字」与「真正确认后结算的数字」同源，
-- 不会出现预览 340、结算 300 这种最伤信任的偏差。
---@return table|nil { scrollBefore, gold, fragments, floor, killCount }
function DungeonManager:BuildExtractPreview()
	if not self.runData then return nil end

	local snap = self:GetPauseSnapshot()
	local previewData = {
		floor = self.currentFloor or 0,
		loot = self.runData.loot,
		statistics = {
			killCount = snap.killCount,
			time = snap.elapsed,
		},
	}

	local result = RunResult.Build(previewData, RunResult.Outcome.Extract)
	return {
		scrollBefore = snap.scrollCount,
		gold = result.gold or 0,
		fragments = result.fragments or 0,
		floor = result.floor or 0,
		killCount = result.killCount or 0,
	}
end

---请求撤离：HUD 卷轴按钮 与 暂停菜单的撤离按钮【共用】这一个入口。
--
-- 刻意【不在这里消耗卷轴】：必须等玩家在确认框里明确点头。
-- UI 若在那一刻就把卷轴扣了，后续结算一旦失败就会「卷轴没了、收益也没了」。
---@return boolean 是否弹出了确认框（false = 请求被拒绝，或 UI 不可用已直接兜底撤离）
function DungeonManager:RequestExtract()
	if not self.runData then return false end
	if self._settled then return false end
	if self._extractConfirming then return false end   -- 已在确认中，别重复弹

	local st = self.state
	local allowed = (st == DungeonManager.RunState.Fighting)
		or (st == DungeonManager.RunState.Boss)
		or (st == DungeonManager.RunState.PreparingNextFloor)
	if not allowed then
		Logger.Warn("DungeonManager", "Extract rejected: bad state %s", tostring(st))
		return false
	end

	if not self.itemSystem or not self.itemSystem:CanUseReturnScroll() then
		Logger.Warn("DungeonManager", "Extract rejected: no return scroll")
		return false
	end

	if not self:CanPlayerPause() then
		Logger.Warn("DungeonManager",
			"Extract rejected: another modal is holding the pause (phase=%s)",
			tostring(self.battleManager and self.battleManager.phase))
		return false
	end

	-- 暂停菜单与确认框互斥：同一屏不叠两个模态，玩家意图才不会有歧义
	closeWindowIfOpen("PausePanel", "PauseResolved")
	self._userPaused = false

	local bm = self.battleManager
	if bm and bm.Pause then
		pcall(function() bm:Pause() end)
	end

	self._extractConfirming = true
	self._extractConfirmTimer = 0

	if not self:_openExtractConfirm() then
		-- UI 不可用时的取舍：直接按原语义执行撤离，而不是停在 Pause。
		-- 冻结会让整局卡死，远比「少了一次确认提示」严重（P2-2 的结论）。
		self._extractConfirming = false
		Logger.Warn("DungeonManager",
			"ExtractConfirmPopup unavailable -> executing extract directly")
		self:UseReturnScroll()
		return false
	end

	Logger.Info("DungeonManager", "Extract confirmation pending at floor %d", self.currentFloor)
	return true
end

---玩家在确认框点了「确认撤离」：此刻才真正扣卷轴并结算
---@return boolean
function DungeonManager:ConfirmExtract()
	if not self._extractConfirming then return false end

	self._extractConfirming = false
	self._extractConfirmTimer = 0
	closeWindowIfOpen("ExtractConfirmPopup", "ExtractResolved")

	-- UseReturnScroll 内部会走到 _settle -> _freezeBattle，本局结束，
	-- 因此这里【不需要也不应该】再 Resume。
	return self:UseReturnScroll()
end

---玩家取消撤离（确认框的「继续战斗」/ 右上角关闭 / 超时兜底）：恢复战斗
---@param reason string
---@return boolean
function DungeonManager:CancelExtract(reason)
	if not self._extractConfirming then return false end

	self._extractConfirming = false
	self._extractConfirmTimer = 0
	closeWindowIfOpen("ExtractConfirmPopup", "ExtractResolved")
	self:_resumeBattle(reason or "ExtractCancelled")
	return true
end

-- =============================================================================
-- P2-4：战斗模态面板的开关与清理
-- =============================================================================

function DungeonManager:_openPausePanel()
	local ok, err = pcall(function()
		local ui = GameMain.GetUIManager()
		assert(ui and ui.Open, "UIManager 不可用")
		ui:Open("PausePanel", self:GetPauseSnapshot())
	end)
	if not ok then
		Logger.Warn("DungeonManager", "打开 PausePanel 失败: %s", tostring(err))
		return false
	end
	return true
end

function DungeonManager:_openExtractConfirm()
	local ok, err = pcall(function()
		local ui = GameMain.GetUIManager()
		assert(ui and ui.Open, "UIManager 不可用")
		ui:Open("ExtractConfirmPopup", self:BuildExtractPreview())
	end)
	if not ok then
		Logger.Warn("DungeonManager", "打开 ExtractConfirmPopup 失败: %s", tostring(err))
		return false
	end
	return true
end

-- =============================================================================
-- 只关面板状态、不 Resume：调用方处于结算流程，战斗必须保持冻结。
function DungeonManager:_clearBattleModals()
	self._userPaused = false
	self._extractConfirming = false
	self._extractConfirmTimer = 0
	closeWindowIfOpen("PausePanel", "PauseResolved")
	closeWindowIfOpen("ExtractConfirmPopup", "ExtractResolved")
end

---使用回城卷轴撤离
-- 仅 Fighting / Boss / PreparingNextFloor 可用；
-- Dead / Result / Extracting 下不允许（P4 缺口 #4）
function DungeonManager:UseReturnScroll()
	if not self.runData then return false end

	local st = self.state
	local allowed = (st == DungeonManager.RunState.Fighting)
		or (st == DungeonManager.RunState.Boss)
		or (st == DungeonManager.RunState.PreparingNextFloor)

	if not allowed then
		Logger.Warn("DungeonManager", "Cannot extract in state: %s", tostring(st))
		return false
	end

	if not self.itemSystem or not self.itemSystem:CanUseReturnScroll() then
		Logger.Warn("DungeonManager", "No return scroll available")
		return false
	end

	self.itemSystem:ConsumeReturnScroll()
	self:_setState(DungeonManager.RunState.Extracting)
	Logger.Info("DungeonManager", "Extracting from floor %d", self.currentFloor)

	-- 撤离不会触发 BattleManager.onBattleEnd（那是清层/战败才走的路径），
	-- 因此本层的击杀/用时必须先手动并入，否则结算界面恒显示 0（P2-1）。
	self:_absorbCurrentFloorStats()

	-- 撤离结算：渊获入账（设计稿 §13）
	self:_settle(RunResult.Outcome.Extract)
	return true
end

---结算唯一出口：撤离与死亡都走这里，避免两处各写一份导致规则不一致
function DungeonManager:_settle(outcome)
	if not self.runData then return end

	-- 幂等守卫（P2-1）：一局只能结算一次。
	-- 场景：撤离结算后面板仍在展示（切场景已延后到玩家点确认），战斗若未停，
	-- 玩家会再次死亡并触发 OnPlayerDead -> _settle，造成重复入账。
	-- 原实现之所以没暴露：_settle 结尾立刻 SwitchScene，场景卸载让玩家没机会再死。
	if self._settled then
		Logger.Warn("DungeonManager", "已结算过，忽略重复结算: %s", tostring(outcome))
		return
	end
	self._settled = true
	self:_freezeBattle()
	self:_clearLevelUpPopup()   -- P2-2：收掉可能开着的升级弹窗，避免盖在结算面板上
	self:_clearBattleModals()   -- P2-4：同理，收掉暂停菜单 / 撤离确认框
	self._pendingEvent = nil
	self._pendingOptions = nil
	closeWindowIfOpen("FloorEventPopup", "Settled")

	local result = RunResult.Build(self.runData, outcome)
	self.lastResult = result
	self:_setState(DungeonManager.RunState.Result)
	if self._onlineRunId then
		self._settlementOutcome = outcome == RunResult.Outcome.Extract and "extract" or "death"
		result.online = true
		result.runId = self._onlineRunId
		result.gold, result.fragments, result.lootLost = nil, nil, nil
		result.items, result.materials = {}, {}
		self._settlementStatus = "pending"
		self:_requestOnlineSettlement()
		return
	end

	if outcome == RunResult.Outcome.Extract then
		SaveData.ApplyExtract(result)
	else
		SaveData.ApplyDeath(result)
	end
	SaveData.Commit()   -- 落盘（P5）

	self._settlementStatus = "confirmed"

	Logger.Info("DungeonManager", "Settled: outcome=%s floor=%d gold=%d fragments=%d",
		tostring(outcome), result.floor, result.gold, result.fragments)

	-- 先展示结算面板，玩家确认后再回主城（P2-1）。
	-- 此前是直接 SwitchScene，死亡/撤离时画面毫无过渡地跳走，体感像闪退，
	-- 且玩家看不到本局下了几层、捞了多少、赚了多少记忆碎片。
	self:_openResultPanel(result)
end

function DungeonManager:HasUnconfirmedSettlement()
	return self._onlineRunId ~= nil and self._settled and self._settlementStatus ~= "confirmed"
end

function DungeonManager:_requestOnlineSettlement()
	if self._settlementBusy or not self:HasUnconfirmedSettlement() then return false end
	local result = self.lastResult
	if OnlineSession.IsBusy() then
		self._settlementStatus = "failed"
		result.settlementStatus, result.reason = "failed", "online_busy"
		result.busy = false
		self:_openResultPanel(result)
		return false
	end
	self._settlementBusy = true
	self._settlementStatus = "pending"
	result.settlementStatus, result.reason, result.busy = "pending", nil, true
	self:_openResultPanel(result)
	local generation, runId = self._generation, self._onlineRunId
	local completed = false
	local function onSettled(ok, reason, receipt)
		if completed then return end
		completed = true
		if generation ~= self._generation or runId ~= self._onlineRunId then return end
		self._settlementBusy = false
		result.busy = false
		local valid = type(receipt) == "table" and receipt.outcome == self._settlementOutcome
			and type(receipt.gold) == "number" and receipt.gold >= 0
			and type(receipt.fragments) == "number" and receipt.fragments >= 0
		if ok and valid then
			self._settlementStatus = "confirmed"
			result.settlementStatus, result.reason = "confirmed", nil
			result.outcome = receipt.outcome == "extract" and RunResult.Outcome.Extract or RunResult.Outcome.Death
			result.gold, result.fragments = receipt.gold, receipt.fragments
		else
			self._settlementStatus = "failed"
			result.settlementStatus, result.reason = "failed", reason or "invalid_receipt"
			Logger.Warn("DungeonManager", "Online settlement failed: %s", tostring(result.reason))
		end
		self:_openResultPanel(result)
	end
	if OnlineSession.GetRunId() ~= runId then
		onSettled(false, "online_run_mismatch")
		return false
	end
	local ok, err = pcall(OnlineSession.Settle, self._settlementOutcome, onSettled)
	if not ok then onSettled(false, tostring(err)) end
	return true
end

function DungeonManager:RetrySettlement()
	return self:_requestOnlineSettlement()
end

---冻结本局战斗与帧驱动（P2-1）。
---刻意【不 Destroy BattleManager】：Destroy 会让场景内实体瞬间消失，观感突兀；
---但必须停推进，否则结算面板展示期间玩家会继续挨打，甚至清层推进到下一层。
function DungeonManager:_freezeBattle()
	if self.battleManager and self.battleManager.Pause then
		pcall(function() self.battleManager:Pause() end)
	end
	self:_unregisterUpdate()
end

---把当前楼层的战斗统计并入 runData.statistics（P2-1）。
---BattleManager 的 elapsedTime / killCount 是【本层】值（LoadFloor 时清零）：
---  死亡路径 -> onBattleEnd 回调里已累加过，这里不能重复加；
---  撤离路径 -> 不会触发 onBattleEnd，必须在这里补，否则用时/击杀恒为 0。
function DungeonManager:_absorbCurrentFloorStats()
	if not self.runData or not self.battleManager then return end

	local ok, stats = pcall(function() return self.battleManager:GetStats() end)
	if not ok or not stats then return end

	self.runData.statistics.time = (self.runData.statistics.time or 0) + (stats.elapsedTime or 0)
	self.runData.statistics.killCount = (self.runData.statistics.killCount or 0) + (stats.killCount or 0)
end

---打开结算面板（P2-1）
---UI 不可用时直接回主城，避免玩家卡在已结束的战斗场景里。
---@param result table RunResult.Build 的产物
function DungeonManager:_openResultPanel(result)
	local ok, err = pcall(function()
		local ui = GameMain.GetUIManager()
		assert(ui and ui.Open, "UIManager 不可用")
		if ui:IsOpen("RunResultPanel") then
			ui:Refresh("RunResultPanel", result)
		else
			assert(ui:Open("RunResultPanel", result), "RunResultPanel unavailable")
		end
	end)

	if not ok then
		Logger.Warn("DungeonManager", "打开 RunResultPanel 失败: %s", tostring(err))
		if not self:HasUnconfirmedSettlement() then self:BackToHome() end
	end
end

---结算面板「返回主城」回调：本局的唯一退出口。
---关面板 + 切场景 + 释放 BattleManager 集中在此，避免两处各写一份导致规则不一致。
function DungeonManager:BackToHome()
	if self:HasUnconfirmedSettlement() then return false, "settlement_unconfirmed" end
	self:_clearBattleModals()   -- P2-4：面板可能在玩家点确认前还开着

	local ok, err = pcall(function()
		local ui = GameMain.GetUIManager()
		if ui and ui.IsOpen and ui:IsOpen("RunResultPanel") then
			ui:Close("RunResultPanel", "Confirmed")
		end
	end)
	if not ok then
		Logger.Warn("DungeonManager", "关闭 RunResultPanel 失败（忽略，继续回主城）: %s", tostring(err))
	end

	local accepted, reason = GameMain.SwitchScene("Home")
	if accepted == false then return false, reason end
	self.battleManager = nil   -- SwitchScene 已同步销毁 BattleManager
	return true
end

-- =============================================================================
-- 帧驱动（P1 仅同步 RunData）
-- =============================================================================

function DungeonManager:_registerUpdate()
	if self._updateRegistered then return end

	local ok, err = pcall(function()
		UpdateManager:GetInstance():AddUpdate(function(dt) self:Update(dt) end, self)
	end)
	if not ok then
		Logger.Warn("DungeonManager", "Register UpdateManager failed: %s", tostring(err))
		return
	end
	self._updateRegistered = true
end

function DungeonManager:_unregisterUpdate()
	if not self._updateRegistered then return end
	pcall(function()
		UpdateManager:GetInstance():RemoveUpdateByTarget(self)
	end)
	self._updateRegistered = false
end

function DungeonManager:Update(dt)
	if not self.runData then return end

	-- 层间事件兜底：弹窗无回调时自动选择，避免 Run 永久卡在 FloorEvent
	if self.state == DungeonManager.RunState.FloorEvent and self._pendingEvent then
		self._floorEventTimer = (self._floorEventTimer or 0) + dt
		if self._floorEventTimer >= FLOOR_EVENT_TIMEOUT then
			Logger.Warn("DungeonManager", "FloorEvent 弹窗 %ds 无响应，自动选择（避免卡死）", FLOOR_EVENT_TIMEOUT)
			self:_autoSelectEvent()
		end
	end

	-- Only time out a missing popup, never the player's reading/selection time.
	if self._levelUpOptions then
		local ok, visible = pcall(function()
			local ui = GameMain.GetUIManager()
			return ui and ui.IsOpen and ui:IsOpen("LevelUpPopup")
		end)
		self._levelUpTimer = (ok and visible) and 0 or ((self._levelUpTimer or 0) + dt)
		if self._levelUpTimer >= LEVELUP_TIMEOUT then
			Logger.Warn("DungeonManager", "升级弹窗 %ds 无响应，自动选择（避免卡死）", LEVELUP_TIMEOUT)
			self:_autoPickLevelUp()
		end
	end

	-- 撤离确认框兜底（P2-4）：确认框展示期间战斗处于 Pause，回调若始终不来
	-- 必须放行。这里【不能自动确认】（会白白消耗唯一稀缺资源），一律按「取消」
	-- 处理 —— 取消不消耗任何东西，是唯一安全的分支。
	if self._extractConfirming then
		self._extractConfirmTimer = (self._extractConfirmTimer or 0) + dt
		if self._extractConfirmTimer >= EXTRACT_CONFIRM_TIMEOUT then
			Logger.Warn("DungeonManager",
				"撤离确认框 %ds 无响应，按取消处理（避免战斗永久冻结）", EXTRACT_CONFIRM_TIMEOUT)
			self:CancelExtract("ConfirmTimeout")
		end
	end

	local bm = self.battleManager
	if not bm then return end

	local pc = bm.playerController
	if pc then
		self.runData.player.hp = pc.hp
		self.runData.player.maxHp = pc.maxHp
		self.runData.player.level = pc.level
		self.runData.player.exp = pc.exp
	end
end

-- =============================================================================
-- 状态与销毁
-- =============================================================================

function DungeonManager:_setState(s)
	local old = self.state
	if old == s then return end
	self.state = s
	if self.onStateChanged then self.onStateChanged(old, s) end
	Logger.Debug("DungeonManager", "State: %s -> %s", tostring(old), tostring(s))
end

function DungeonManager:Dispose()
	self._generation = self._generation + 1
	self._settlementBusy = false
	self:_unregisterUpdate()
	self:_clearBattleModals()   -- P2-4：实例销毁前收掉战斗模态面板
	if self.battleManager then self.battleManager.onBattleEnd = nil end
	self.battleManager = nil
	if self.itemSystem then self.itemSystem:Clear() end
	self.itemSystem = nil
	self.buildSystem = nil
	self.runData = nil
	self.currentFloorCfg = nil
	self._started = false
	self._settled = false
	self:_setState(DungeonManager.RunState.None)
	Logger.Info("DungeonManager", "Disposed")
end

-- =============================================================================
-- Getters
-- =============================================================================

function DungeonManager:GetRunData() return self.runData end
function DungeonManager:GetState() return self.state end
function DungeonManager:GetCurrentFloor() return self.currentFloor end

return DungeonManager
