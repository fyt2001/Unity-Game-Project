--[[
=============================================================================
UIModStationModel.lua - 配装面板（ModStation）Model
=============================================================================
Module:     Game/UI/Mod/UIModStationModel

Description:
	配装面板的纯数据层：读 ModSystem / ModInventory / SaveData.loadout，
	产出「三宿主 Tab 状态 / 背包列表 / 宿主槽位 / 容量文案 / 派生属性摘要」。

	【本 Model 不持有玩家状态】
	装备的真相在 SaveData.loadout 与 ModInventory 里，每次 Refresh 都重新读。
	装 / 卸一律走 ModSystem.Install / ModSystem.Uninstall（内部会 Commit 存档），
	不给 UI 层留第二份「当前装备」副本，避免存档与显示打架。

	【为什么是「先选中再点槽」】
	玩家点背包 = 选中（_selectedUid），再点右侧空槽 = 装上。
	目的是让「有效消耗」按【目标槽极性】算 —— 极性不匹配是 ×1.5 惩罚，
	一脚点 AUTO 装进错极性槽会让玩家莫名其妙掉容量，
	先选中就能把该装哪、代价多少摆到明面上。

	【本轮范围】（用户 2026-10-02 拍板「最小可用」）
	含：三宿主切换 / 装 / 卸 / 容量条 / 派生属性摘要。
	不含：金币升级 rank、一键自动装配。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"
local ModSystem = require "Game.Mod.ModSystem"
local ModConfig = require "Game.Mod.ModConfig"
local ModInventory = require "Game.Mod.ModInventory"
local SaveData = require "Game.Save.SaveData"

local UIModStationModel = Class.Define("UIModStationModel")
Class.Extend(UIModStationModel, UIModel)
local base = UIModel

-- 宿主顺序 == Tab 顺序（weapon / skill / frame）
UIModStationModel.HOSTS = { "weapon", "skill", "frame" }

local HOST_LABEL = {
	weapon = "武 器",
	skill = "技 能",
	frame = "框 架",
}

local STAT_LABEL = {
	__capacity = "容量",
	damage = "基础攻击",
	damageMul = "伤害",
	fireRate = "射速",
	projectileCount = "弹数",
	critChance = "暴击率",
	critDamage = "暴伤",
	maxHp = "生命",
	lifeSteal = "吸血",
	range = "射程",
	moveSpeed = "移速",
}

-- =============================================================================
-- 模块级纯函数（不依赖实例状态，做成模块函数而不是方法，省掉 unused self 告警）
-- =============================================================================

---把一张已装实例描述成扁平表（View 直接用，不暴露 ModConfig / ModInventory）
---@return table|nil { uid, id, name, rank, polarity, cost }
local function describeMod(uid, slot)
	local inst = ModInventory.GetByUid(uid)
	if not inst then return nil end

	local cfg = ModConfig.Get(inst.id)
	if not cfg then return nil end

	local rank = inst.rank or 1
	return {
		uid = uid,
		id = inst.id,
		name = cfg.name or tostring(inst.id),
		rank = rank,
		polarity = cfg.polarity,
		cost = ModSystem.EffectiveCost(cfg, rank, slot.polarity),
	}
end

---把 ComputeDerived 的加区 / 乘区翻成中文文案行；空则给一行兜底
local function buildStatLines()
	local derived = ModSystem.ComputeDerived()
	local lines = {}

	local keys = {}
	for stat in pairs(derived.add or {}) do keys[#keys + 1] = stat end
	table.sort(keys)
	for _, stat in ipairs(keys) do
		lines[#lines + 1] = stat == "fireRate" and string.format("射速 +%g%%", derived.add[stat] * 100)
			or string.format("%s +%s", STAT_LABEL[stat] or stat, tostring(derived.add[stat]))
	end

	keys = {}
	for stat in pairs(derived.mul or {}) do keys[#keys + 1] = stat end
	table.sort(keys)
	for _, stat in ipairs(keys) do
		lines[#lines + 1] = string.format("%s x%s", STAT_LABEL[stat] or stat, tostring(derived.mul[stat]))
	end

	if #lines == 0 then lines[#lines + 1] = "暂无-Mod-效果" end
	return lines
end

-- =============================================================================
-- 构造函数
-- =============================================================================

---@param windowName string 由 UIWindowFactory 传入（ModelClass.New(window:GetName())）
function UIModStationModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self._host = "weapon"
	self._selectedUid = nil
	self._feedback = ""
	self._bagItems = {}
	self._slots = {}
	self._capacityText = ""
	self._statLines = {}

	-- 构造函数末尾必须自己 Refresh 一次。
	-- 踩过：View:Render() 只【读】Model，不触发 Refresh，
	-- 而 Controller:OnOpen 直接就 Render —— 首次打开时 Ctor 的默认值还是空的，
	-- 结果面板弹出了一整屏空白（槽位 0 / 背包 0 / 容量文案空）。
	-- 自播种之后，Model 不管被谁拿（Controller / 直接 New）都是自洽的。
	self:Refresh()
end

-- =============================================================================
-- 宿主切换
-- =============================================================================

---切换宿主并整体重读。非法宿主名原样返回 false，不静默改默认值。
---@param hostName string weapon | skill | frame
function UIModStationModel:SetHost(hostName)
	if not hostName then return false end

	for _, h in ipairs(UIModStationModel.HOSTS) do
		if h == hostName then
			self._host = hostName
			self._feedback = ""
			-- 换宿主后上一个选中卡通常不属于这个宿主，选中态一律清掉
			self._selectedUid = nil
			self:Refresh()
			return true
		end
	end
	return false
end

function UIModStationModel:GetHost()
	return self._host
end

function UIModStationModel:GetHostLabel()
	return HOST_LABEL[self._host] or self._host
end

---Tab 列表（顺序与 HOSTS 一致，供 View 按下标取）
function UIModStationModel:GetTabs()
	local tabs = {}
	for _, h in ipairs(UIModStationModel.HOSTS) do
		tabs[#tabs + 1] = {
			host = h,
			label = HOST_LABEL[h] or h,
			active = (h == self._host),
		}
	end
	return tabs
end

-- =============================================================================
-- 选中态
-- =============================================================================

function UIModStationModel:SetSelected(uid)
	self._selectedUid = self._selectedUid ~= uid and uid or nil
	self._feedback = ""
	self:Refresh()
end

local FEEDBACK = {
	select_mod = "尚未选中 Mod", installed = "装配已保存", uninstalled = "卸下已保存",
	duplicate_mod = "同一宿主不能重复装备同一种 Mod", over_capacity = "容量不足",
	category_mismatch = "Mod 类型不适用于当前宿主", core_slot_only = "核心槽只能安装核心 Mod",
	core_mod_only = "核心 Mod 只能安装到核心槽", capacity_dependency = "卸下核心后容量不足",
	save_failed = "保存失败，配装未更改", no_mod = "卡片已不存在", no_cfg = "卡片配置缺失",
	no_slot = "槽位不存在", no_host = "宿主不存在",
}

function UIModStationModel:SetFeedback(reason)
	self._feedback = FEEDBACK[reason] or (reason and "操作未完成" or "")
end

function UIModStationModel:GetFeedback()
	return self._feedback or ""
end

function UIModStationModel:GetSelected()
	return self._selectedUid
end

---该空槽此刻能否接住「已选中的卡」（View 用来高亮可装槽位，Controller 不用）
function UIModStationModel:CanSelectInto(slotIndex)
	if not self._selectedUid then return false end
	local slot = self._slots[slotIndex]
	if not slot then return false end
	return (ModSystem.CanInstall(self._host, self._selectedUid, slotIndex) == true)
end

function UIModStationModel:GetSlotPreview(slotIndex)
	local slot = self._slots[slotIndex]
	local inst = self._selectedUid and ModInventory.GetByUid(self._selectedUid)
	local cfg = inst and ModConfig.Get(inst.id)
	if not slot or not cfg then return nil end
	local allowed, reason = ModSystem.CanInstall(self._host, inst.uid, slotIndex)
	local relation = "标准"
	if cfg.polarity == "Core" or slot.polarity == "Core" then
		relation = "核心"
	elseif cfg.polarity ~= "Neutral" and cfg.polarity == slot.polarity then
		relation = "匹配"
	elseif cfg.polarity ~= "Neutral" and slot.polarity ~= "Neutral" then
		relation = "不匹配"
	end
	local shortReason = {
		core_slot_only = "核心卡专用", core_mod_only = "仅限核心槽",
		duplicate_mod = "同类已装", category_mismatch = "类型不适用",
	}
	return {
		name = cfg.name or tostring(inst.id), uid = inst.uid,
		cost = ModSystem.EffectiveCost(cfg, inst.rank, slot.polarity),
		relation = relation, allowed = allowed, reason = shortReason[reason] or FEEDBACK[reason],
	}
end

-- =============================================================================
-- 数据读取
-- =============================================================================

---重读存档并刷新派生数据。装 / 卸之后 Controller 调一次即可。
function UIModStationModel:Refresh()
	if self._selectedUid and not ModInventory.GetByUid(self._selectedUid) then self._selectedUid = nil end
	self:_readSlots()
	self:_readBag()
	-- 容量消耗是浮点（极性匹配 ×0.5 / 不匹配 ×1.5），用 %g 而不是 %d：
	-- %d 遇到 1.5 这种「无整数表示」的浮点会直接抛 bad argument。
	self._capacityText = string.format("容量 %g / %g",
		ModSystem.TotalUsed(self._host), ModSystem.TotalCapacity(self._host))
	self._statLines = buildStatLines()
	for _, hostName in ipairs(UIModStationModel.HOSTS) do
		if ModSystem.TotalUsed(hostName) > ModSystem.TotalCapacity(hostName) then
			self._statLines[#self._statLines + 1] = (HOST_LABEL[hostName] or hostName) .. "配装超出容量"
		end
	end
	return self
end

function UIModStationModel:GetSlots()
	return self._slots
end

function UIModStationModel:GetBagItems()
	return self._bagItems
end


---详情只读取真实实例，不改变选择和存档。
function UIModStationModel:GetModDetail(uid)
	local inst = uid and ModInventory.GetByUid(uid)
	local cfg = inst and ModConfig.Get(inst.id)
	if not cfg or (string.lower(cfg.category or "") ~= self._host and cfg.category ~= "Universal") then return nil end
	local rank = inst.rank or 1
	local value = (cfg.effect.base or 0) + (cfg.effect.perRank or 0) * rank
	local effect = string.format("%s %s%g", STAT_LABEL[cfg.effect.stat] or cfg.effect.stat,
		cfg.effect.mode == "mul" and "×" or "+", value)
	-- fireRate 加到基础攻速倍率，+0.15 对应基础射速 +15%。
	if cfg.effect.stat == "fireRate" then effect = string.format("射速 +%g%%", value * 100) end
	return { uid = uid, id = inst.id, name = cfg.name, rank = rank, maxRank = cfg.maxRank,
		polarity = cfg.polarity, baseCost = (cfg.baseDrain or 0) + rank - 1, effect = effect }
end

function UIModStationModel:GetCapacityText()
	return self._capacityText
end

function UIModStationModel:GetStatLines()
	return self._statLines
end

-- -----------------------------------------------------------------------------
-- 内部：槽位
-- -----------------------------------------------------------------------------

---逐槽读出极性、占用情况与有效消耗
function UIModStationModel:_readSlots()
	local loadout = SaveData.Get().loadout or {}
	local host = loadout[self._host] or {}
	local slots = host.slots or {}
	local installed = host.installed or {}

	self._slots = {}
	for i = 1, #slots do
		local slot = slots[i]
		local uid = installed[i]
		self._slots[i] = {
			index = i,
			polarity = slot.polarity or ModConfig.Polarity.Neutral,
			empty = (uid == nil),
			item = uid and describeMod(uid, slot) or nil,
		}
	end
end

-- -----------------------------------------------------------------------------
-- 内部：背包
-- -----------------------------------------------------------------------------

---读出全部持有 Mod；已装备的排到后面，同名字典序 + 等级升序
function UIModStationModel:_readBag()
	local loadout = SaveData.Get().loadout or {}
	local host = loadout[self._host] or {}
	local installed = host.installed or {}

	local installedMap = {}
	for _, uid in pairs(installed) do installedMap[uid] = true end

	self._bagItems = {}
	for _, inst in ipairs(ModInventory.GetAll()) do
		local cfg = ModConfig.Get(inst.id)
		if cfg and (string.lower(cfg.category or "") == self._host or cfg.category == "Universal") then
			self._bagItems[#self._bagItems + 1] = {
				uid = inst.uid,
				id = inst.id,
				name = cfg.name or tostring(inst.id),
				rank = inst.rank or 1,
				polarity = cfg.polarity,
				baseCost = (cfg.baseDrain or 0) + ((inst.rank or 1) - 1),
				category = cfg.category,
				installed = (installedMap[inst.uid] == true),
				selected = (self._selectedUid == inst.uid),
				desc = string.format("%s %s%g", STAT_LABEL[cfg.effect.stat] or cfg.effect.stat,
					cfg.effect.mode == "mul" and "x" or "+",
					(cfg.effect.base or 0) + (cfg.effect.perRank or 0) * (inst.rank or 1)),
			}
		end
	end

	-- 相同定义、相同等级合并显示；点击仍选中真实实例。
	local groups, grouped = {}, {}
	for _, item in ipairs(self._bagItems) do
		local key = tostring(item.id) .. ":" .. tostring(item.rank)
		local group = groups[key]
		if not group then
			group = item
			group.count, group.installedCount = 0, 0
			groups[key] = group
			grouped[#grouped + 1] = group
		end
		group.count = group.count + 1
		if item.installed then group.installedCount = group.installedCount + 1 end
		-- 保留已选实例；否则优先未装实例，UID 保证刷新稳定。
		if item.selected or (not group.selected and
			((group.installed and not item.installed) or
			(group.installed == item.installed and item.uid < group.uid))) then
			group.uid, group.installed = item.uid, item.installed
		end
		group.selected = group.selected or item.selected
	end
	self._bagItems = grouped

	table.sort(self._bagItems, function(a, b)
		if a.installed ~= b.installed then return a.installed == false end
		if a.name ~= b.name then return a.name < b.name end
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.uid < b.uid
	end)
end

-- -----------------------------------------------------------------------------
-- 内部：派生属性摘要
-- -----------------------------------------------------------------------------

return UIModStationModel
