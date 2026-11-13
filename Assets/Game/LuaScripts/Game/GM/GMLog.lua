--[[
=============================================================================
GMLog.lua - GM 调试面板的【日志环形缓冲】（S8）
=============================================================================
Module:     Game.GM.GMLog
规格：      04_tech_design.md §8.1「日志 200 条（环形）；单条 ≤1024 字符；持久化最近 30 条」
对外：
  GMLog.Append(level, group, label, msg)  写一条（含单条截断 + 环形丢最旧）
  GMLog.GetAll()                          按「旧 -> 新」返回全部有效条目
  GMLog.GetTextLines(maxCount)            按「旧 -> 新」返回可直接进日志区的字符串
  GMLog.Clear()                           清空环形缓冲
  GMLog.Persist() / GMLog.Restore()       可选持久化（逐条分 key，见下）

-----------------------------------------------------------------------------
【为什么是独立环形缓冲，而不是「包装 Logger 再截流」】
-----------------------------------------------------------------------------
读 Framework/UI/Utils/Logger.lua 之后的结论：不包装、不替换，各走各的通路。

  1) Logger 是【推模式】，且没有 pull 出口。Logger.Log(...) 一次性做完「级别过滤 ->
     格式串 -> 逐个 sink -> Debug.Log/print」，GMLog 要的是「自己持有最近 200 条、
     随时被 View 拉下去渲染 / 复制」的缓冲，方向正好相反。能借到的唯一钩子是
     Logger.AddSink(sink)，sink 只能拿到 (tag, message) 两个参数，拿不到
     level / group / label 三元组 —— 而 GM 的日志区是按 level 着色、按 group/label
     分组的，丢掉这三个字段等于把日志退化成一行纯文本，再要还原得重新解析。

  2) 级别映射是丢信息的。sink 要靠「被调用了哪个方法」反推 level（sink.info / sink.warn
     / sink.error），只有三个方法；配置里的 success 级别（GMUIConfig.LogLevel.success
     带 "✓ " 前缀）在 sink 上无处安放。

  3) 取值形态本来就不同。Logger 是 (tag, format, ...)，Logger.FormatMessage 是自制的
     「%%spec 逐个吃掉参数」实现，且无参数时原样返回 format（此时 msg 里带 % 不会炸，
     带 %s 也不炸）；GMLog.Append(level, group, label, msg) 是「已拼好的单串」。
     在 GMLog 里再转发一次给 Logger，等于把两条不同语义的格式化叠在一起，出问题的
     时候要多翻一层栈才能定位。

  4) 现在是「GMLog 没人写、Logger 也不归 GM 管」的真空：Logger 是 Framework 的
     Frozen (Public API)，UIGMController / GMCommands 打的都是 Logger.Info("GM", ...)，
     去给它们全量改道成本极高且收益为零（那些日志本来就要进 Unity 控制台）。
     反过来，GMLog 服务的是【面板日志区】这一个特定消费者的特定需求（200 条上限 +
     1024 截断 + 能被拉下来），它跟控制台不是一回事，硬拧到一起才是层叠。

  ⇒ 取舍：GMLog = 面板日志区的数据源，独立环形缓冲、自己做格式化与截断；
    Logger 保持原样，控制台通路完全不受影响。将来若真要让【所有】Logger 输出都进
    环形缓冲，在 GMLog 里挂一个 Logger.AddSink 转发器即可，本文件不用改，
    Logger.lua 也一个字都不用动。

【关于持久化（可选）】
  - 只在 logPersistMode == "perKey" 时生效：把最近 logPersistMax 条逐条写
    PlayerPrefs 的 GM_Log_00 … GM_Log_29（单 key ≤3 KB，不存大 JSON，R12）。
  - 【绝不在 Append 里自动 Persist】：一次 Persist 要写 logPersistMax 个 key，
    跟着 Append 走等于把「打一条日志」变成 N 次磁盘写 —— 这正是这张降级表要防的
    那种病。Persist() 由调用方在「关面板 / 执行结束」这类低频时机显式调。
  - 写失败 / 读失败一律 pcall 兜底：GM 面板是调试工具，日志持久化失败不能把面板打挂。
=============================================================================
]]

local GMUIConfig = require "Game.GM.GMUIConfig"

local GMLog = {}

-- -----------------------------------------------------------------------------
-- 级别（只分三档：info / success 同档，两者都归「正常输出」，颜色与前缀由
-- GMUIConfig.LogLevel 决定，这里不复制一份配色）
-- -----------------------------------------------------------------------------
local LEVEL_RANK = { info = 1, success = 1, warn = 2, error = 3 }
local RANK_INFO = 1

-- 环形缓冲：_ring[_head] 是「下一条要被覆盖的位置」，_count 是当前有效条数
local _ring = {}
local _head = 0
local _count = 0

local function _capacity()
	local c = GMUIConfig and GMUIConfig.Capacity
	return (c and c.logDisplayMax) or 200
end

local function _charLimit()
	local c = GMUIConfig and GMUIConfig.Capacity
	return (c and c.logEntryCharLimit) or 0
end

---单条截断：超过 logEntryCharLimit 就切到上限 + "…"（截断在【写】的时候做，
-- 读的时候不做 —— 读侧再截就是每条都白算一次 #s）
local function _fitText(msg)
	local s = tostring(msg or "")
	local lim = _charLimit()
	if lim > 0 and #s > lim then
		return string.sub(s, 1, lim) .. "…"
	end
	return s
end

-- -----------------------------------------------------------------------------
-- 写
-- -----------------------------------------------------------------------------

---写一条日志
---@param level  string  "info" / "success" / "warn" / "error"（未知级别降级为 info）
---@param group  string  分组（如命令分组）
---@param label  string  标签（如命令 label）
---@param msg    string  正文（已拼好的字符串，本模块不再做格式化）
function GMLog.Append(level, group, label, msg)
	local name = tostring(level or ""):lower()
	local rank = LEVEL_RANK[name]
	if not rank then
		name = "info"
		rank = RANK_INFO
	end

	local cap = _capacity()
	if cap <= 0 then return end

	_ring[_head] = {
		level = name,
		rank  = rank,
		group = tostring(group or ""),
		label = tostring(label or ""),
		text  = _fitText(msg),
	}
	_head = (_head + 1) % cap
	if _count < cap then _count = _count + 1 end
end

-- -----------------------------------------------------------------------------
-- 读
-- -----------------------------------------------------------------------------

---最近 logDisplayMax 条（= 环形缓冲上限），按「旧 -> 新」
function GMLog.GetAll()
	local out = {}
	local cap = _capacity()
	local from = (_head - _count + cap) % cap
	for i = 0, _count - 1 do
		out[#out + 1] = _ring[(from + i) % cap]
	end
	return out
end

---可直接进面板日志区的字符串行，最多 maxCount 行（日志区显示上限就落在这里：
-- 就算环形缓冲里留了 200 条，渲染侧要多少给多少，此处按 maxCount 截）
function GMLog.GetTextLines(maxCount)
	local all = GMLog.GetAll()
	local n = #all
	local take = maxCount and maxCount < n and maxCount or n
	local out = {}
	local levels = GMUIConfig and GMUIConfig.LogLevel or nil
	for i = n - take + 1, n do
		local e = all[i]
		local prefix = ""
		if levels then
			local conf = levels[e.level]
			prefix = (conf and conf.prefix) or ""
		end
		out[#out + 1] = prefix .. tostring(e.text or "")
	end
	return out
end

function GMLog.Clear()
	_ring = {}
	_head = 0
	_count = 0
end

-- -----------------------------------------------------------------------------
-- 可选持久化（逐条分 key，R12）
-- -----------------------------------------------------------------------------

---持久化用的 key 前缀（逐条分 key：GM_Log_00 … GM_Log_29）
local PKEY = "GM_Log_"

---取一条持久化条目（写/读都包 pcall：PlayerPrefs 在离线构建里取不到时不该打挂面板）
local function _readKey(i)
	local ok, v = pcall(function()
		return CS.UnityEngine.PlayerPrefs.GetString(PKEY .. string.format("%02d", i), "")
	end)
	if ok and type(v) == "string" then return v end
	return ""
end

local function _writeKey(i, v)
	return pcall(function()
		CS.UnityEngine.PlayerPrefs.SetString(PKEY .. string.format("%02d", i), v)
		CS.UnityEngine.PlayerPrefs.Save()
	end)
end

---把最近 N 条逐条写 PlayerPrefs（GM_Log_00 … GM_Log_29），返回写入条数；失败返回 -1
function GMLog.Persist()
	local c = GMUIConfig and GMUIConfig.Capacity
	if not c or c.logPersistMode ~= "perKey" then return -1 end
	local maxN = c.logPersistMax or 0
	if maxN <= 0 then return -1 end

	local all = GMLog.GetAll()
	local from = #all > maxN and (#all - maxN + 1) or 1
	local written = 0
	for i = from, #all do
		local e = all[i]
		local ok = _writeKey(written,
			string.format("%s|%s|%s|%s", e.level, e.group, e.label, e.text))
		if not ok then return -1 end
		written = written + 1
	end
	return written
end

---读回持久化条目并追加进环形缓冲（读失败 / 格式不对一律静默跳过，返回读回条数）
function GMLog.Restore()
	local c = GMUIConfig and GMUIConfig.Capacity
	if not c or c.logPersistMode ~= "perKey" then return 0 end
	local maxN = c.logPersistMax or 0
	if maxN <= 0 then return 0 end

	local read = 0
	for i = 0, maxN - 1 do
		local raw = _readKey(i)
		if raw ~= "" then
			local level, group, label, text = raw:match("^(%S*)|([^|]*)|([^|]*)|(.*)$")
			if level then GMLog.Append(level, group, label, text); read = read + 1 end
		end
	end
	return read
end

return GMLog
