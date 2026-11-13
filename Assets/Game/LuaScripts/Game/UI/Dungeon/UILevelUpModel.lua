--[[
=============================================================================
UILevelUpModel.lua - 升级三选一 Model
=============================================================================
Module:     Game/UI/Dungeon/UILevelUpModel

Description:
	承载本次升级候选的展示快照，并把候选项转成玩家能看懂的文案。

	与 UIFloorEventModel / UIRunResultModel 一致：Model 不持有游戏状态。
	候选由 DungeonManager 通过 BuildSystem:GenerateChoices 生成并持有，
	Model 只做只读承载 + 格式化，避免 UI 层成为第二套数据源。

	候选条目有两种形态（见 Game/Build/UpgradeSystem.lua 与 Game/Build/BuildSystem.lua）：
		- UpgradeSystem 产出：{ type = 数字, stat = "atk", name = "攻击力+10", value = 10, desc = "..." }
		- BuildSystem 产出：  { type = "BuildWeapon"|"BuildSkill"|"BuildRelic", id = "...", name = "...", desc = "..." }
	  因此文案取值一律走「name or stat」兜底，不假设字段一定存在。

	【类系统】Class.Define(name) + Class.Extend(X, UIModel)。
	继承必须显式两步：Class.Define 自 P2-2 起只接受一个参数，
	传第二个参数会在运行期直接 error（不再是静默忽略）。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UILevelUpModel = Class.Define("UILevelUpModel")
Class.Extend(UILevelUpModel, UIModel)
local base = UIModel

---@param windowName string 所属 Window 名称
function UILevelUpModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self.options = {}
	self.pending = 1              -- 本次还剩几次选择（一次经验可能连升多级）
	self.title = "升 级"          -- 作为数据而非硬编码，将来做「第 N 次强化」等变体时无需改 View
end

---由 Controller 在 OnOpen 时填充
---@param options table 候选列表
---@param pending number|nil 待选次数（含本次）
function UILevelUpModel:SetOptions(options, pending)
	self.options = options or {}
	self.pending = tonumber(pending) or 1
	if self.pending < 1 then self.pending = 1 end
end

---候选数量（View 用它决定显示几个按钮）
function UILevelUpModel:GetCount()
	return #self.options
end

---取原始候选项（Controller 回传索引后由 DungeonManager 按索引取，这里仅供 View 展示）
function UILevelUpModel:GetOption(index)
	return self.options[index]
end

---主标题
function UILevelUpModel:GetTitle()
	return self.title or "升 级"
end

---副标题：连升多级时告知还剩几次，避免玩家以为「选完就没了」
function UILevelUpModel:GetSubtitle()
	if self.pending > 1 then
		return string.format("选择一项强化（连续升级，还剩 %d 次）", self.pending)
	end
	return "选择一项强化"
end

---选项主文案
function UILevelUpModel:GetOptionName(index)
	local o = self.options[index]
	if not o then return "" end
	return tostring(o.name or o.stat or "?")
end

---选项副文案；候选项没带 desc 时按类型给一句兜底说明
function UILevelUpModel:GetOptionDesc(index)
	local o = self.options[index]
	if not o then return "" end
	if o.desc and o.desc ~= "" then return tostring(o.desc) end

	if type(o.type) == "string" then
		if o.type == "BuildWeapon" then return "新武器：改变攻击方式" end
		if o.type == "BuildSkill"  then return "新技能：强化战斗能力" end
		if o.type == "BuildRelic"  then return "新遗物：改变规则" end
		return "Build 强化"
	end
	return "属性强化"
end

return UILevelUpModel
