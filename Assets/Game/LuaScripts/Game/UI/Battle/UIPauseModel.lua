--[[
=============================================================================
UIPauseModel.lua - 暂停菜单 Model
=============================================================================
Module:     Game/UI/Battle/UIPauseModel

Description:
	P2-4「撤离/死亡二次确认 + 暂停」的产物。

	暂停面板只展示【本局快照】：当前层数 / 击杀 / 剩余卷轴。
	这些数据由 DungeonManager 在打开面板时一次性喂入，UI 层不反向查询
	战斗层，也不持有 Run 状态。

	为什么不在 View 里定时刷新：
		暂停期间战斗已 Paused，数据本来就不会变；再来一个定时器纯属浪费，
		而且会和 UIBattleHudController 的采样定时器抢同一份数据源。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIModel = require "Framework.UI.Core.UIModel"

local UIPauseModel = Class.Define("UIPauseModel")
Class.Extend(UIPauseModel, UIModel)
local base = UIModel

---@param windowName string 由 UIWindowFactory 传入（ModelClass.New(window:GetName())）
function UIPauseModel:Ctor(windowName)
	base.Ctor(self, windowName)
	self.floor = 0
	self.killCount = 0
	self.scrollCount = 0
	self.elapsed = 0
	self.canExtract = false
end

---由 Controller 在打开时填充（数据来自 DungeonManager:GetPauseSnapshot()）
---@param snapshot table { floor, killCount, scrollCount, elapsed, canExtract }
function UIPauseModel:SetSnapshot(snapshot)
	snapshot = snapshot or {}
	self.floor = snapshot.floor or 0
	self.killCount = snapshot.killCount or 0
	self.scrollCount = snapshot.scrollCount or 0
	self.elapsed = snapshot.elapsed or 0
	self.canExtract = snapshot.canExtract and true or false
end

---面板上要展示的几行信息。
---刻意放在 Model 而不是 View：文案组装属于「数据 → 展示数据」的一步，
---View 只负责把字符串塞进 TMP，方便后续换 View 实现时不被复制走这份逻辑。
---@return table string[] 每行一条
function UIPauseModel:GetInfoLines()
	local secs = math.floor(self.elapsed or 0)
	local mm = math.floor(secs / 60)
	local ss = secs % 60

	return {
		string.format("当前层数：第 %d 层", self.floor),
		string.format("击杀总数：%d", self.killCount),
		string.format("剩余卷轴：%d", self.scrollCount),
		string.format("本局用时：%02d:%02d", mm, ss),
	}
end

return UIPauseModel
