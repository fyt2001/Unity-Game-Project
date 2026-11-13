--[[
=============================================================================
UIGMController.lua - GM 调试面板控制器（S2）
=============================================================================
Module:     Game.UI.GM.UIGMController

职责：
  - Execute(cmd, value)：item 上「执行」键的唯一入口（View 只回传 cmd + 解析后的参数）。
    pcall 包裹 cmd.fn(value)，结果回写 View 反馈行并打一条日志 —— 一次点击只打一条，
    虚拟列表滚动多少次都不会重复（按钮按 item GO 实例绑一次，见 UIGMView:_ensureItemButtons）。
  - OnCloseClicked()：经 GameMain 的 UIManager 关闭 "GM" 窗口。
  - 具体作弊逻辑全部在 Game.GM.GMCommands（数据驱动表），本类不耦合业务。

S7 新增（规格：design_tmp/gm_panel/04_tech_design.md §12.2）：
  - 危险通道二次确认状态机（3.5s 窗口）挂在这一层，理由：
      1) UIGMView:_execById 只认 ctrl:Execute 这一个出口，确认态「点第一下不跑」的
         判断必须落在 fn 之前，View 又不能碰业务执行，Controller 是唯一的夹缝；
      2) 确认态超时后还要让「按钮回退常态」，Controller 本来就有 GetView() 通路
         （View 侧只暴露 SetExecPending / SetExecNormal 两个小口子），
         若把状态放到 GMCommands（纯数据表），反而要反向 require 到 View，形成环。
  - 计时用 Framework.Core.TimerManager:AddDelay（C# LuaGameBootstrap 每帧驱动
    TimerManager:Update，全项目既有用法，见 UIBattleHudController），
    不用 UpdateManager 轮询：一个 3.5s 的单次延迟没必要挂一整帧回调。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local UIController = require "Framework.UI.Core.UIController"
local Logger = require "Framework.UI.Utils.Logger"
local GMConfig = require "Game.GM.GMConfig"

---二次确认窗口：验收口径取 3.5s（§12.2 正文写 3s，验收清单写 3.5s，取大的那个）
local DANGER_CONFIRM_MS = 3500
local CONFIRM_TEXT = "确认执行？"
local TIMEOUT_TEXT = "已取消（超时）"   -- 超时后反馈行的文案（别写成「已执行」，一次都不跑）

local UIGMController = Class.Define("UIGMController")
Class.Extend(UIGMController, UIController)

-- ---------------------------------------------------------------------------
-- 危险通道二次确认（§12.2）
--
-- 状态机：_pending = { cmdId, value, timerId } 或 nil
--   Execute 第一下（cmd.danger 且当前没有指向它的 _pending）-> _enterConfirm，直接 return
--   Execute 第二下（_pending 已指向同一条 cmd）           -> _cancelConfirm + 真跑
--   超时 / 切分类 / 关面板 / 面板重开                      -> _cancelConfirm
--
-- 只保留「一条」待确认：中途去点别的 danger 命令，旧的会被顶掉并撤回常态，
-- 不会出现「第一行还红着、第二行已经跑了」这种双risk。
-- ---------------------------------------------------------------------------

function UIGMController:Ctor(model)
	self.super:Ctor(model)
	self._pending = nil
	self._closed = true
	self._closeRequested = false
	self._destroyed = false
end

---当前是否已经有一条危险命令在等确认（且就是 cmd 自己）
function UIGMController:_isPending(cmd, value)
	local p = self._pending
	return p ~= nil and cmd ~= nil and p.cmd == cmd and p.cmdId == cmd.id
		and p.value == value and CS.UnityEngine.Time.realtimeSinceStartup < p.expiresAt
end

---进入待确认：改按钮外观 + 起一个 3.5s 超时定时器，【一个字都不执行】
function UIGMController:_enterConfirm(cmd, value)
	self:_cancelConfirm()

	-- cmd 一并存进 pending：超时回调要把反馈行那句「确认执行？」换成「已取消（超时）」，
	-- _status 需要 label，而超时那一刻 _pending 就要被摘掉了（计时器是单帧异步回来的，
	-- 等它回来再查 self._pending 已经是 nil，只能靠进待确认时先存一份）
	local p = { cmdId = cmd.id, value = value, timerId = nil, cmd = cmd,
		expiresAt = CS.UnityEngine.Time.realtimeSinceStartup + DANGER_CONFIRM_MS / 1000 }
	local TimerManager = require("Framework.Core.TimerManager")
	local tm = TimerManager and TimerManager.GetInstance and TimerManager:GetInstance()
	if not tm then
		-- 计时器都拿不到就没法保证「超时自动回退」，宁可这次不进待确认、也不直接跑，
		-- 绝不允许「点一下就跑」——那等于把这道门拆了。
		Logger.Warn("GM", "二次确认计时器不可用，已取消本次执行：%s", tostring(cmd.id))
		return
	end
	p.timerId = tm:AddDelay(DANGER_CONFIRM_MS, function()
		if self._pending == p and not self._closed then self:_onConfirmTimeout() end
	end)
	self._pending = p

	local view = self:GetView()
	if view and view.SetExecPending then view:SetExecPending(cmd.id) end
	self:_status(cmd, cmd.confirmText or CONFIRM_TEXT)
	Logger.Info("GM", "[%s] 进入二次确认（%.1fs 内再点一次才执行）",
		tostring(cmd.id), DANGER_CONFIRM_MS / 1000)
end

---超时：待确认作废，按钮回常态（验收点「等 3.5s 回退」）
---反馈行也要跟着换掉：_cancelConfirm 只把执行键回常态，反馈行还留着上一句「确认执行？」，
---用户看到的画面是「按钮变回『执行』、反馈行却还在催我确认」，实际这次已经作废不执行了。
function UIGMController:_onConfirmTimeout()
	if not self._pending then return end
	-- 先取出来再摘：_cancelConfirm 会把 self._pending 置 nil，而 _status 要拿 cmd label 打日志
	local cmd = self._pending.cmd
	Logger.Info("GM", "[%s] 二次确认超时，已取消", tostring(self._pending.cmdId))
	self:_cancelConfirm()
	if cmd then self:_status(cmd, TIMEOUT_TEXT) end
end

---退出待确认：摘定时器 + 清状态 + 按钮回常态
function UIGMController:_cancelConfirm()
	local p = self._pending
	self._pending = nil
	if p and p.timerId then
		pcall(function()
			local TimerManager = require("Framework.Core.TimerManager")
			local tm = TimerManager and TimerManager.GetInstance and TimerManager:GetInstance()
			if tm then tm:Remove(p.timerId) end
		end)
	end
	local view = self:GetView()
	if view and view.SetExecNormal then view:SetExecNormal() end
end

-- ---------------------------------------------------------------------------
-- 执行
-- ---------------------------------------------------------------------------

function UIGMController:Execute(cmd, value)
	if self._closed or self._destroyed then return end
	if not cmd or not cmd.fn then return end
	if not GMConfig.CanOpenPanel() then
		self:_cancelConfirm()
		self:_status(cmd, "GM 已禁用")
		return
	end

	-- 执行层 devOnly 门禁（§12.1 第 2 层）：注册层 VisibleList 已经过滤过一次，
	-- 这里再拦一次 —— 万一有人绕过 View 直接拿 GMCommands.list 调 fn，release 包也不该中招。
	if cmd.devOnly and not GMConfig.IsDev() then
		self:_cancelConfirm()
		Logger.Warn("GM", "devOnly 命令在 release 包被拦：%s", tostring(cmd.id))
		self:_status(cmd, "该命令仅开发包可用（当前 release 包）")
		return
	end

	-- 危险通道：第一下只进待确认，业务代码一点都不碰
	local valueType = type(value)
	if cmd.danger and valueType ~= "nil" and valueType ~= "number"
	   and valueType ~= "string" and valueType ~= "boolean" then
		self:_cancelConfirm()
		self:_status(cmd, "不支持的确认参数类型")
		return
	end
	if cmd.danger and not self:_isPending(cmd, value) then
		self:_enterConfirm(cmd, value)
		return
	end
	if cmd.danger then value = self._pending.value end
	self:_cancelConfirm()
	self:_doExecute(cmd, value)
end

function UIGMController:_doExecute(cmd, value)
	local ok, msg = pcall(function() return cmd.fn(value) end)
	if not ok then
		msg = "执行失败: " .. tostring(msg)
	end
	self:_status(cmd, tostring(msg))
end

---回写反馈行 + 打一条日志（一次点击只打一条）
function UIGMController:_status(cmd, msg)
	local view = self:GetView()
	if view and view.SetStatus then
		view:SetStatus(msg)
	end
	Logger.Info("GM", "[%s] %s", tostring((cmd and cmd.label) or "?"), tostring(msg))
end

---面板被 CacheOnClose 缓存后重新打开：清掉上一次可能残留的待确认态
-- （关面板前点了一下执行、3.5s 内没点第二下，回来时按钮还红着且点一下就直接跑）
function UIGMController:OnViewOpened()
	if self._destroyed or self._closeRequested then return end
	self._closed = not GMConfig.CanOpenPanel()
	self:_cancelConfirm()
end

function UIGMController:OnOpen(...)
	self.super:OnOpen(...)
	self:OnViewOpened()
end

function UIGMController:OnRefresh(...)
	self.super:OnRefresh(...)
	self:OnViewOpened()
end

function UIGMController:OnPanelClosing()
	self._closeRequested = true
	self._closed = true
	self:_cancelConfirm()
end

function UIGMController:OnClose()
	self:OnPanelClosing()
	self._closeRequested = false
	self.super:OnClose()
end

function UIGMController:OnDestroy()
	self._destroyed = true
	self:OnPanelClosing()
	self.super:OnDestroy()
end

---切分类 / 搜索词变化导致列表重建：立刻作废待确认（§12.2 取消时机）
function UIGMController:OnGroupChanged()
	self:_cancelConfirm()
end

function UIGMController:OnCloseClicked()
	if not self._closed then self:OnPanelClosing() end
	require("Game.GM.GMUI").ClosePanel()
end

return UIGMController
