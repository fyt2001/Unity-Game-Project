--[[
=============================================================================
GMRuntimeStats.lua - GM 调试面板【运行态采样器】
=============================================================================
职责：
  - 给 GM 面板 / 老 HUD 提供一份【统一口径】的运行态快照，共 7 个字段（一个不砍）：
        scene       场景名（GameMain.GetCurrentScene()）
        dungeon     下潜状态 + 层数（DungeonManager:GetState() / GetCurrentFloor()）
        enemies     敌人【存活数】（EnemyManager:GetAliveCount()，不是生成总数）
        bullets     活跃子弹数（BulletManager:GetActiveCount()）
        battleTime  战斗已用时间 / 总时长（BattleManager:GetStats().elapsedTime / maxTime）
        fps         帧率（本文件自写滑窗平均，口径见下，与老 HUD 故意不同）
        luaGC       Lua GC 占用（collectgarbage("count")，单位 KB）

对外：
  - GMRuntimeStats.Sample()      -> table（上面 7 个 key，全量、无 nil）
  - GMRuntimeStats.SampleText()  -> string（多行，行序与老 HUD 一致，C# 可直接消费）
  - GMRuntimeStats.Start()/Stop()/Fps()   -> 滑窗开关 / 读当前窗口值

【FPS 口径声明（重要，别在别处偷偷换）】
  - 本文件 FPS = 【滑动窗口平均】：近 N 帧的 dt 进环形缓冲（FPS_WINDOW 帧），
    fps = 窗口内帧数 / 窗口内 dt 总和（等价于窗口内所有帧瞬时 FPS 的平均，但不受长尾 dt 拉爆）。
  - 老 HUD（HomeSceneBootstrapper.cs:933）用的是 1f/Time.deltaTime【瞬时值】。
  - 两者【口径故意不同】：瞬时值会把「恰好读 Lua 的这一帧」放大成个位数/几百，
    GM 面板要的是一个稳定可读、能反映体感的数，滑窗平均更平滑。
  - 这不是 bug，也不是回归。若 S5 要求严格复刻老 HUD 的瞬时值，请改 SampleText 的 fps 取值，
    但【本文件的 fps 语义恒为滑窗】，两处都写死注释，别互相覆盖。

【C# 消费约定（S5 要用，本轮 C# 一行都不动）】
  - SampleText() 返回的就是 C# 直接拿去 GUI.Label 的那串文本，C# 侧不要再拼任何后缀
    （老 HUD 现在那句 _hudText += "...FPS=..." 将来就是这里产生的）。
  - 行序固定 6 行：scene / Dungeon / Enemies / Bullets / Time / FPS，
    前 5 行的字段名与老 HUD（HomeSceneBootstrapper.cs:919-929）逐字节一致。

【取数同源 / 纪律】
  - 一律照同目录 GMCommands.lua:14-28 的写法，走 GameMain 暴露的入口
    （GetBattleManager / GetDungeonManager / GetCurrentScene），不另起一套。
  - 全部取数包 pcall：GM 面板可能在【非战斗】【场景未就绪】时被采样，
    C# 每 10 帧调一次，抛异常会刷屏；任一子项失败退化为 "0"/"-"，绝不向上抛。
  - 这里【不出现任何 GetComponent / 组件遍历】：采样器是纯数据层，只做取值。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"

-- 模块表：先声明再定义帧回调，避免闭包在 local 生效前把 GMRuntimeStats 解析成全局
local GMRuntimeStats = {}

-- ---------------------------------------------------------------------------
-- 取数入口（照 GMCommands.lua 的写法）
-- ---------------------------------------------------------------------------

local function _gameMain()
	local ok, m = pcall(require, "Game.GameMain")
	if ok and m then return m end
	return nil
end

local function _bm()
	local m = _gameMain()
	if not m or not m.GetBattleManager then return nil end
	local ok, bm = pcall(m.GetBattleManager)
	if ok then return bm end
	return nil
end

local function _dm()
	local m = _gameMain()
	if not m or not m.GetDungeonManager then return nil end
	local ok, dm = pcall(m.GetDungeonManager)
	if ok then return dm end
	return nil
end

local function _scene()
	local m = _gameMain()
	if not m or not m.GetCurrentScene then return "?" end
	local ok, name = pcall(m.GetCurrentScene)
	if ok then return tostring(name) end
	return "?"
end

-- 敌人数：统一【存活口径】。
-- 老 HUD 用的是 #b.enemyManager.enemies（列表长度），那是「未走 _flushRemoved 的列表长度」，
-- 会把已 isDead 但还在列表里的算进去；这里明确取 EnemyManager:GetAliveCount()。
local function _aliveEnemies()
	local bm = _bm()
	if not bm or not bm.enemyManager then return 0 end
	local em = bm.enemyManager
	if not em.GetAliveCount then return 0 end
	local ok, n = pcall(em.GetAliveCount, em)
	if ok and type(n) == "number" then return n end
	return 0
end

-- 子弹数：BulletManager:GetActiveCount()（= #bullets，池里的不算）
local function _activeBullets()
	local bm = _bm()
	if not bm or not bm.bulletManager then return 0 end
	local bl = bm.bulletManager
	if not bl.GetActiveCount then return 0 end
	local ok, n = pcall(bl.GetActiveCount, bl)
	if ok and type(n) == "number" then return n end
	return 0
end

-- 战斗时间：返回 elapsed / max 两个秒数，取数口是 BattleManager:GetStats()
local function _battleTime()
	local bm = _bm()
	if not bm or not bm.GetStats then return 0, 0 end
	local ok, st = pcall(bm.GetStats, bm)
	if not ok or type(st) ~= "table" then return 0, 0 end
	local used = type(st.elapsedTime) == "number" and st.elapsedTime or 0
	local maxT = type(st.maxTime) == "number" and st.maxTime or 0
	return used, maxT
end

-- 下潜状态 + 层数
local function _dungeon()
	local dm = _dm()
	if not dm or not dm.GetState then return "-" end
	local ok, state = pcall(dm.GetState, dm)
	if not ok then return "-" end
	local floor = "-"
	if dm.GetCurrentFloor then
		local ok2, f = pcall(dm.GetCurrentFloor, dm)
		if ok2 then floor = tostring(f) end
	end
	return tostring(state) .. "/" .. floor
end

-- Lua GC：取当前 Lua 堆占用（KB）；collectgarbage("count") 不会触发一次完整 GC
local function _gcText()
	local ok, kb = pcall(collectgarbage, "count")
	if ok and type(kb) == "number" then
		return string.format("%.0fKB", kb)
	end
	return "-"
end

-- ---------------------------------------------------------------------------
-- FPS 滑窗（全仓无现成实现，本文件自写：环形缓冲 + 逐帧 dt）
-- ---------------------------------------------------------------------------

local FPS_WINDOW = 60      -- 滑窗帧数：约 1 秒 @60fps，太长会迟钝、太短会抖
local _dtRing = {}         -- 环形缓冲，固定 FPS_WINDOW 格
local _dtHead = 0          -- 下一个写入下标
local _dtFilled = 0        -- 已填充格数（<= FPS_WINDOW，未满时按已有帧算）
local _dtSum = 0.0         -- 窗口内 dt 总和（滑动时先减掉被顶掉的老值）
local _hooked = false      -- 是否已挂 UpdateManager 帧回调
local _hookTarget = "GMRuntimeStats"

-- 丢弃 dt<=0 的帧（首帧 / 时间源异常），否则窗口会除零
local function _pushDt(dt)
	if type(dt) ~= "number" or dt <= 0 then return end
	local old = _dtRing[_dtHead]
	_dtRing[_dtHead] = dt
	_dtSum = _dtSum - (old or 0) + dt
	_dtHead = (_dtHead + 1) % FPS_WINDOW
	if _dtFilled < FPS_WINDOW then _dtFilled = _dtFilled + 1 end
end

-- 滑窗平均 FPS（不是瞬时 1f/dt）
local function _fpsValue()
	if _dtFilled <= 0 or _dtSum <= 0 then return 0 end
	return math.floor(_dtFilled / _dtSum)
end

local function _onFrame(dt)
	-- UpdateManager 可能被 ClearAll（切场景 / 退战斗），这里自愈补钩
	if not _hooked then GMRuntimeStats.Start() end
	_pushDt(dt)
end

-- ---------------------------------------------------------------------------
-- 模块
-- ---------------------------------------------------------------------------

--- 把帧回调挂到 UpdateManager（幂等：重复调用只会有一次 AddUpdate）
function GMRuntimeStats.Start()
	if _hooked then return end
	local ok, um = pcall(require, "Framework.Core.UpdateManager")
	if not ok or not um then return end
	local ok2, umgr = pcall(um.GetInstance, um)
	if not ok2 or not umgr then return end
	umgr:AddUpdate(_onFrame, _hookTarget)
	_hooked = true
	Logger.Info("GM", "运行态采样器 FPS 滑窗已挂载（窗口 %d 帧）", FPS_WINDOW)
end

--- 摘钩（面板关闭 / 探针 abort 时调用）
function GMRuntimeStats.Stop()
	if not _hooked then return end
	local ok, um = pcall(require, "Framework.Core.UpdateManager")
	if ok and um then
		local ok2, umgr = pcall(um.GetInstance, um)
		if ok2 and umgr then umgr:RemoveUpdateByTarget(_hookTarget) end
	end
	_hooked = false
end

--- 读当前滑窗 FPS（无帧数据时返回 0）
function GMRuntimeStats.Fps()
	return _fpsValue()
end

--- 取一次运行态快照：7 个字段，全量非 nil
function GMRuntimeStats.Sample()
	GMRuntimeStats.Start()
	local used, maxT = _battleTime()
	return {
		scene      = _scene(),
		dungeon    = _dungeon(),
		enemies    = _aliveEnemies(),
		bullets    = _activeBullets(),
		battleTime = string.format("%d/%d", math.floor(used), math.floor(maxT)),
		fps        = _fpsValue(),
		luaGC      = _gcText(),
	}
end

--- 快照文本（6 行，C# 直接消费，不再另拼）
function GMRuntimeStats.SampleText()
	local s = GMRuntimeStats.Sample()
	return string.format(
		"scene=%s\nDungeon=%s\nEnemies=%d\nBullets=%d\nTime=%s\nFPS=%d (F1 开关HUD)",
		tostring(s.scene),
		tostring(s.dungeon),
		tonumber(s.enemies) or 0,
		tonumber(s.bullets) or 0,
		tostring(s.battleTime),
		tonumber(s.fps) or 0)
end

return GMRuntimeStats
