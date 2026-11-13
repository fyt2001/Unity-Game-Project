--[[
=============================================================================
RunResult.lua - 结算明细
=============================================================================
Module:     Game/Dungeon/RunResult
Version:    1.0.0

Description:
	一局 Run 结束（撤离 / 死亡）时的结算明细。

	规则（设计稿 §13）：
		撤离 → 渊获(gold/items/materials) 入账
		死亡 → 渊获【清空】，只留记忆碎片

	记忆碎片公式（P4 缺口 #3，§15 只规定「按层数+击杀」）：
		fragments = floor + floor(killCount / 50)
=============================================================================
]]

local RunResult = {}

RunResult.Outcome = {
	Extract = "Extract",
	Death = "Death",
}

---每多少击杀折算 1 点记忆碎片
local KILLS_PER_FRAGMENT = 50

---计算记忆碎片
function RunResult.CalcFragments(floor, killCount)
	local byFloor = math.floor(floor or 0)
	local byKill = math.floor((killCount or 0) / KILLS_PER_FRAGMENT)
	return byFloor + byKill
end

---构建结算明细
---@param runData table
---@param outcome string RunResult.Outcome.Extract | Death
---@return table
function RunResult.Build(runData, outcome)
	runData = runData or {}
	local loot = runData.loot or {}
	local stats = runData.statistics or {}

	local isExtract = (outcome == RunResult.Outcome.Extract)
	local floor = runData.floor or 0
	local killCount = stats.killCount or 0

	return {
		outcome = outcome,
		floor = floor,
		killCount = killCount,
		elapsed = stats.time or 0,

		-- 撤离才保住渊获；死亡全部归零
		gold = isExtract and (loot.gold or 0) or 0,
		items = isExtract and (loot.items or {}) or {},
		materials = isExtract and (loot.materials or {}) or {},

		-- 死亡时损失的金币（仅用于日志/结算界面展示）
		lootLost = (not isExtract) and (loot.gold or 0) or 0,

		fragments = RunResult.CalcFragments(floor, killCount),
	}
end

return RunResult
