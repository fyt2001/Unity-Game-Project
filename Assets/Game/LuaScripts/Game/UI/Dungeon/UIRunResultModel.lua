--[[
=============================================================================
UIRunResultModel.lua - 结算面板 Model
=============================================================================
Module:     Game/UI/Dungeon/UIRunResultModel

Description:
	承载「本局结算明细」的展示快照，并把数据转成给玩家看的文案。

	数据源是 DungeonManager:_settle 产出的 RunResult.Build(runData, outcome)，
	规则（记忆碎片公式、死亡清空渊获）一律留在 Game/Dungeon/RunResult.lua，
	Model 只做只读承载 + 格式化，避免 UI 层成为第二套规则源。

	与 UIFloorEventModel 一致：Model 不持有 Run 状态，只保存本次要展示的内容。

	【类系统】Class.Define(name) + Class.Extend(X, UIModel)。
	继承必须显式两步：Class.Define 自 P2-2 起只接受一个参数，
	传第二个参数会在运行期直接 error（不再是静默忽略）。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UIRunResultModel = Class.Define("UIRunResultModel")
Class.Extend(UIRunResultModel, UIModel)
local base = UIModel

function UIRunResultModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self.result = nil
	self.isExtract = false
end

---填充结算数据（由 Controller 在 OnOpen 时调用）
---@param result table RunResult.Build 的产物
function UIRunResultModel:SetResult(result)
	self.result = result or {}
	self.isExtract = (self.result.outcome == "Extract")
end

---标题文案
function UIRunResultModel:GetTitle()
	if self.result.online and self.result.settlementStatus ~= "confirmed" then
		return self.result.busy and "结算处理中" or "结算待确认"
	end
	return self.isExtract and "撤 离 成 功" or "阵 亡"
end

---副标题文案
function UIRunResultModel:GetSubtitle()
	if self.result.online then
		if self.result.settlementStatus == "confirmed" then return "本地联调奖励已确认" end
		return self.result.busy and "正在等待服务器确认" or "奖励未确认，战斗保持暂停"
	end
	if self.isExtract then
		return "渊获已安全带回"
	end
	return "本次下潜中止，渊获全部遗失"
end

function UIRunResultModel:GetConfirmText()
	if self.result.online and self.result.settlementStatus ~= "confirmed" then
		return self.result.busy and "处理中" or "重试结算"
	end
	return "返回主城"
end

---把秒数格式化为 mm:ss
function UIRunResultModel:GetElapsedText()
	local sec = math.floor(tonumber(self.result.elapsed) or 0)
	if sec < 0 then sec = 0 end
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

---战利品摘要。
---items/materials 是 map（id -> 数量，见 DungeonManager:_newRunData 的 loot），
---因此要遍历求和，不能用 # 取长度。
function UIRunResultModel:GetLootText()
	local items = self.result.items or {}
	local mats = self.result.materials or {}

	local itemCount, matKinds = 0, 0
	for _, count in pairs(items) do itemCount = itemCount + (tonumber(count) or 0) end
	for _ in pairs(mats) do matKinds = matKinds + 1 end

	if itemCount == 0 and matKinds == 0 then
		return "无"
	end
	return string.format("物品 %d 件 / 材料 %d 种", itemCount, matKinds)
end

return UIRunResultModel
