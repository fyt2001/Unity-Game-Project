--[[
=============================================================================
BuildSystem.lua - Build 管理（武器 / 技能 / 遗物）
=============================================================================
Module:     Game/Build/BuildSystem
Version:    1.0.0

Description:
	管理本局 Run 的 Build（设计稿 §8 三分类），并在升级时产出三选一。

	选项来源：
		① UpgradeSystem 已有的 Stat / WeaponUpgrade（取 2 个）
		② BuildConfig 的新武器 / 技能 / 遗物（取 1 个，排除已拥有）
	共 3 个选项。

	⚠【关键】升级后必须恢复战斗：
	  BattleManager:OnLevelUp() 会 Pause()，若无人 Resume 则战斗【永久冻结】。
	  此前 UpgradeSystem 根本没被 BattleManager 创建，升级即死局（P7 缺口 #1）。

	【P2-2 起】本模块【不再负责 Resume】，也不再静默代选：
	  正常路径 -> DungeonManager 弹 LevelUpPopup，玩家选完由 DungeonManager 恢复战斗；
	  兜底路径 -> AutoPickFallback()（面板打不开 / 选项为空），同样由 DungeonManager 收口。
	  理由：Resume 必须【恰好一次】。若本模块与弹窗回调都各自 Resume，
	  或两条路径都忘了 Resume，就会出现「重复恢复」或「永久冻结」。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local Logger = require "Framework.UI.Utils.Logger"
local BuildConfig = require "Game.Build.BuildConfig"
local MetaSystem = require "Game.Save.MetaSystem"
local VFXConfig = require "Game.Battle.VFXConfig"
local VFXManager = require "Game.Battle.VFXManager"
local BattleLayers = require "Game.Battle.BattleLayers"

local BuildSystem = Class.Define("BuildSystem")

function BuildSystem:Ctor()
	self.runData = nil
	self.derived = nil      -- Mod 派生属性（用于新武器伤害协同）
end

function BuildSystem:Init(runData)
	self.runData = runData
end

---设置 Mod 派生属性（P6 协同）
function BuildSystem:SetDerived(derived)
	self.derived = derived
end

-- =============================================================================
-- 工具
-- =============================================================================

function BuildSystem:_has(list, id)
	for _, v in ipairs(list or {}) do
		if v == id then return true end
		if type(v) == "table" and v.id == id then return true end
	end
	return false
end

function BuildSystem:_build()
	if not self.runData then return nil end
	self.runData.build = self.runData.build or { weapons = {}, skills = {}, relics = {} }
	return self.runData.build
end

---按 Meta M06「武器精通」加权抽取 Build 选项
function BuildSystem:_weightedPick(pool)
	local weaponBonus = MetaSystem.GetWeaponWeight()
	local total = 0
	local weights = {}

	for i, o in ipairs(pool) do
		local w = 1
		if o.type == "BuildWeapon" then w = w + weaponBonus end
		weights[i] = w
		total = total + w
	end

	local r = math.random() * total
	local acc = 0
	for i, o in ipairs(pool) do
		acc = acc + weights[i]
		if r <= acc then return o end
	end
	return pool[#pool]
end

-- =============================================================================
-- 三选一
-- =============================================================================

---生成升级选项
---@param bm table BattleManager
---@param count number 默认 3
function BuildSystem:GenerateChoices(bm, count)
	count = count or 3
	local options = {}

	-- ① UpgradeSystem 的 Stat / WeaponUpgrade
	local us = bm and bm.upgradeSystem
	if us and us.GetRandomOptions then
		local ok, base = pcall(function() return us:GetRandomOptions(2) end)
		if ok and type(base) == "table" then
			for _, o in ipairs(base) do
				if #options < count then options[#options + 1] = o end
			end
		else
			Logger.Warn("BuildSystem", "UpgradeSystem:GetRandomOptions failed")
		end
	end

	-- ② Build 池（排除已拥有）
	local build = self:_build() or {}
	local pool = {}

	for _, w in ipairs(BuildConfig.Weapons) do
		if not self:_has(build.weapons, w.id) then
			pool[#pool + 1] = { type = "BuildWeapon", id = w.id, name = "获得武器：" .. w.name, desc = w.desc }
		end
	end
	for _, s in ipairs(BuildConfig.Skills) do
		if not self:_has(build.skills, s.id) then
			pool[#pool + 1] = { type = "BuildSkill", id = s.id, name = "获得技能：" .. s.name, desc = s.desc }
		end
	end
	for _, r in ipairs(BuildConfig.Relics) do
		if not self:_has(build.relics, r.id) then
			pool[#pool + 1] = { type = "BuildRelic", id = r.id, name = "获得遗物：" .. r.name, desc = r.desc }
		end
	end

	if #pool > 0 and #options < count then
		options[#options + 1] = self:_weightedPick(pool)
	end

	return options
end

---应用选择
function BuildSystem:Apply(bm, option)
	if not option or not bm then return false end

	local build = self:_build()
	if not build then return false end

	if option.type == "BuildWeapon" then
		local cfg = BuildConfig.GetWeapon(option.id)
		if not cfg or not bm.weaponSystem then return false end

		-- WeaponSystem owns modifiers for every acquisition path, including drops.
		bm.weaponSystem:SetModDerived(self.derived)
		local w = {}
		for k, v in pairs(cfg) do w[k] = v end

		bm.weaponSystem:AddWeapon(w)
		build.weapons[#build.weapons + 1] = cfg.id
		Logger.Info("BuildSystem", "New weapon: %s (damage=%s)", cfg.name, tostring(w.damage))
		return true

	elseif option.type == "BuildSkill" or option.type == "BuildRelic" then
		local list = (option.type == "BuildSkill") and BuildConfig.Skills or BuildConfig.Relics
		local def = nil
		for _, d in ipairs(list) do
			if d.id == option.id then def = d break end
		end
		if not def then return false end

		local pc = bm.playerController
		if pc then
			for stat, val in pairs(def.stats or {}) do
				pc:AddStat(stat, val)
			end
		end

		-- 技能/遗物获得特效（玩家处触发；预制体未接入时静默跳过）
		local vfxPath = VFXConfig.GetForBuild(option)
		if vfxPath and pc then
			local px, py = pc:GetPosition()
			VFXManager.Spawn(vfxPath, px, py, BattleLayers.Projectile)
		end

		if option.type == "BuildSkill" then
			build.skills[#build.skills + 1] = def.id
		else
			build.relics[#build.relics + 1] = def.id
		end
		Logger.Info("BuildSystem", "New %s: %s",
			option.type == "BuildSkill" and "skill" or "relic", def.name)
		return true
	end

	-- 其它（Stat / WeaponUpgrade / NewWeapon）交回 UpgradeSystem
	if bm.upgradeSystem then
		bm.upgradeSystem:ApplyOption(option)
		return true
	end

	return false
end

-- =============================================================================
-- 起手武器
-- =============================================================================

---发放起手武器
-- 吸血鬼幸存者式：开局必须有一把武器，否则玩家【完全没有输出手段】
-- （实测：WeaponSystem 初始为空，无武器时只能挨打，必死）。
---@return string|nil 武器 id
function BuildSystem:GrantStartingWeapon(bm)
	if not bm or not bm.weaponSystem then return nil end

	local build = self:_build()
	if not build then return nil end

	-- 已有武器则不重复发放（例如场景 Bootstrapper 预先给了）
	if #bm.weaponSystem:GetAllWeapons() > 0 then return nil end

	local cfg = BuildConfig.Weapons[1]
	if not cfg then return nil end

	self:Apply(bm, { type = "BuildWeapon", id = cfg.id })   -- 复用 Apply，含 Mod 协同
	Logger.Info("BuildSystem", "Starting weapon granted: %s", cfg.name)
	return cfg.id
end

-- =============================================================================
-- 升级入口
-- =============================================================================

---应用一次升级选择，并播放升级光效。
---光效在仍处于 Pause 时触发，Resume 后才可见，因此必须与 Apply 绑在一起，
---否则「玩家选完」与「兜底自动选」两条路径会各写一份光效代码。
---【刻意不 Resume】Resume 由 DungeonManager 收口，见文件头说明。
---@param bm table BattleManager
---@param option table 已选中的候选（由弹窗回调或兜底逻辑给出）
---@return boolean 是否成功应用
function BuildSystem:ApplyLevelUpChoice(bm, option)
	if not bm or not option then return false end

	local applied = self:Apply(bm, option)

	local pc = bm.playerController
	if pc and VFXConfig.Common.levelUp then
		local px, py = pc:GetPosition()
		VFXManager.Spawn(VFXConfig.Common.levelUp, px, py, BattleLayers.GroundHit, 1.2)
	end

	return applied
end

---兜底：无人接管选择时自动选一个并应用（生成 -> 选 -> 应用 + 光效）。
---触发场景：LevelUpPopup 打不开（prefab 缺失/未注册）、或候选为空。
---@param bm table BattleManager
---@param options table|nil 已有候选则直接复用，避免重复抽取
---@return table|nil 实际应用的选项
function BuildSystem:AutoPickFallback(bm, options)
	if not bm then return nil end

	local list = options
	if not list or #list == 0 then
		local ok, generated = pcall(function() return self:GenerateChoices(bm, 3) end)
		list = ok and generated or nil
	end

	-- 优先 Build 项（新武器/技能/遗物）。
	-- 若一律取 options[1]，而 options[1] 恒为 UpgradeSystem 的属性项，
	-- 玩家将【永远拿不到武器/技能/遗物】，Build 池形同虚设。
	local choice, first = nil, nil
	for _, o in ipairs(list or {}) do
		if not first then first = o end
		if type(o.type) == "string" and o.type:sub(1, 5) == "Build" then
			choice = o
			break
		end
	end
	choice = choice or first

	if choice then
		self:ApplyLevelUpChoice(bm, choice)
		Logger.Info("BuildSystem", "LevelUp fallback auto-pick: %s", tostring(choice.name or choice.stat))
	else
		Logger.Warn("BuildSystem", "LevelUp: no option available (nothing applied)")
	end

	return choice
end

return BuildSystem
