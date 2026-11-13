--[[
=============================================================================
GMUnlock.lua - 开发环境的「连点版本号」解锁（纯逻辑，零 prefab 零 C#）
=============================================================================
说明：
  - 为什么单独一个文件：解锁是「UI 事件 + 全局开关副作用」的组合，把计数与窗口整体放本文件，
    Login 侧只做一行转发，GM 模块不侵入 Login 模块（回滚只删本文件 + 一处 prefab 改动）。
  - 解锁落点：GMConfig.SetEnabled(true) 复用现成 PlayerPrefs 键 GM_Enabled，
    **不新建第二套开关**（否则 QA 会在面板开关上看到两个互相打架的真值源）。
	  - 只有开发环境且 dev 通道启用时受理点击，正式包始终拒绝。
=============================================================================
]]

local GMConfig   = require "Game.GM.GMConfig"
local GMUIConfig = require "Game.GM.GMUIConfig"
local Logger     = require "Framework.UI.Utils.Logger"

local Time = CS.UnityEngine.Time

local GMUnlock = {}

-- 连点计数：taps = 当前序列内已点数，lastTs = 上一次点击的 realtimeSinceStartup。
-- 两者都是模块级内存态，重启进游戏后自然从 0 开始（不需要额外清理）。
local taps, lastTs = 0, 0

local TapUnlock = GMUIConfig.TapUnlock
local Window, Need = TapUnlock.windowSec, TapUnlock.taps   -- 1.5 s / 5 次

---注册/重置连点计数。由 GMUI.Init() 调用一次；切通道或退出登录时可再调来清零。
function GMUnlock.Init()
	taps, lastTs = 0, 0
	if not GMConfig.IsDev() or GMUIConfig.Channel.dev ~= "①" then return end
end

---版本号热区被点了一下。返回 true 表示本次点「解锁成功」，false 表示还没到数/通道未开。
-- 第 5 次命中后立刻清零计数，之后继续点会重新从 1 数起，不会误重试。
function GMUnlock.OnVersionTapped()
	if not GMConfig.IsDev() or GMUIConfig.Channel.dev ~= "①" then return false end
	local now = Time.realtimeSinceStartup
	-- 相邻间隔超窗口 ⇒ 视为新序列，重新从 1 数起
	taps = (now - lastTs <= Window) and (taps + 1) or 1
	lastTs = now

	if taps < Need then
		Logger.Info("GM", "版本号连点 %d/%d（窗口 %.1fs，超时或重启计数）", taps, Need, Window)
		return false
	end

	-- 第 Need 次：解锁（落盘走 GM_Enabled，内存标记走 IsUnlockedByTaps）
	taps, lastTs = 0, 0
	GMConfig._SetUnlockedByTaps(true)
	GMConfig.SetEnabled(true)
	Logger.Info("GM", "GM 已启用（版本号连点解锁），按 Ctrl+G 打开 GM 面板")
	return true
end

---当前是否已通过连点解锁（与 GMConfig.IsUnlockedByTaps() 同义，给业务侧读）
function GMUnlock.IsUnlocked()
	return GMConfig.IsUnlockedByTaps()
end

---清零连点计数（退出登录等场景可选调用；不重置解锁标记本身）
function GMUnlock.Reset()
	taps, lastTs = 0, 0
end

return GMUnlock
