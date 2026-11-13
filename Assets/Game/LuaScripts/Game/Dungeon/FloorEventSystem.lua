--[[
=============================================================================
FloorEventSystem.lua - 层间事件调度
=============================================================================
Module:     Game/Dungeon/FloorEventSystem
Version:    1.0.0

Description:
	层间事件的调度与注册表（埋骨渊方案.md §9）。

	所有事件实现统一接口，核心系统【不认识】任何具体事件：
		event:Enter(runData, ctx)
		event:GetOptions() -> { {id, text, enabled}, ... }
		event:Select(optionId)
		event:Exit()

	新增事件（诅咒/赌博/NPC/隐藏房/随机传送）只需：
		1) 在 Game/Dungeon/Events/ 下新建一个实现四接口的模块
		2) 在下方 BUILTIN_EVENTS 里登记
	无需改动 DungeonManager 或本文件逻辑。

	ctx = { playerController = ... }：需要改血/读属性的事件通过它访问玩家，
	避免事件反向依赖 BattleManager。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"

local FloorEventSystem = {}

FloorEventSystem._registry = {}

---注册事件
---@param name string 事件名（与 FloorConfig.eventPool 中的字符串一致）
---@param eventClass table 事件类（需有 New() 与四接口）
function FloorEventSystem.Register(name, eventClass)
	if not name or not eventClass then return end
	FloorEventSystem._registry[name] = eventClass
end

---创建事件实例
function FloorEventSystem.Create(name)
	local cls = FloorEventSystem._registry[name]
	if not cls or not cls.New then return nil end
	return cls.New()
end

---按事件池抽取一个事件并执行 Enter
---@param runData table
---@param eventPool table 事件名数组
---@param ctx table|nil { playerController }
---@return table|nil 事件实例（已 Enter）
function FloorEventSystem.Roll(runData, eventPool, ctx)
	if not eventPool or #eventPool == 0 then return nil end

	-- 均匀随机（权重表为预留能力，见设计稿附录 D）
	local name = eventPool[math.random(1, #eventPool)]
	local ev = FloorEventSystem.Create(name)
	if not ev then
		Logger.Warn("FloorEventSystem", "Unknown event: %s", tostring(name))
		return nil
	end

	ev:Enter(runData, ctx or {})
	return ev
end

-- =============================================================================
-- 内置事件登记
-- =============================================================================

local BUILTIN_EVENTS = {
	Chest    = "Game.Dungeon.Events.ChestEvent",
	Shrine   = "Game.Dungeon.Events.ShrineEvent",
	Merchant = "Game.Dungeon.Events.MerchantEvent",
	Trap     = "Game.Dungeon.Events.TrapEvent",
	Empty    = "Game.Dungeon.Events.EmptyEvent",
}

for name, path in pairs(BUILTIN_EVENTS) do
	FloorEventSystem.Register(name, require(path))
end

return FloorEventSystem
