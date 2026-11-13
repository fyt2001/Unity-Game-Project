--[[
=============================================================================
GMCommands.lua - 数据驱动的作弊指令表（核心，可无限扩展）
=============================================================================
说明：
  - 仿 H02 GameTest/GameTestMain.lua 的 {["按钮名"]=函数} 数据驱动范式。
  - 每个指令 fn() 返回 string 作为执行反馈；内部已做「未进入战斗」等守卫。
  - 全部走 GameMain 暴露的 BattleManager / DungeonManager，单机无后端。

S4 改造（规格：design_tmp/gm_panel/04_tech_design.md §十一）：
  1. 命令数 11 -> 10：「升1级」+「加10级」合并为 role.level_up（参数 n: int 1~20, default 10）。
  2. role.invincible 改为 toggle + getter + persist（PlayerController 是 Lua 类，
     pc.isInvincible 可直接读写，无需任何桥接）。
  3. 守卫前移到 available()：每条命令返回 false, reason => 行置灰 + 说明区显示原因。
  4. 剪贴板 SystemCopy：4096 截断 + Set 后立刻读回比对 + 失败写日志（X9 三条硬要求）。
  5. 元信息补全：id / desc / alias / available / runMode / persist / params / quick / danger / tip。
  6. Normalize()：旧 {group,label,fn} 结构零改动跑起来的适配层（§11.4）。

S7 新增（规格：design_tmp/gm_panel/04_tech_design.md §十二）：
  1. 第 11 条命令 advanced.run_lua（group = "※高级"，devOnly + danger）。本文件只提供
     【能力】，真正的隔离分三道：注册/加载层 VisibleList() 过滤、执行层 devOnly 门禁与
     3.5s 二次确认（都在 UIGMController）、显示层 m_EnvTag 的 DEV/RELEASE 角标（S6）。
  2. VisibleList()：devOnly 过滤的唯一出口，Model 与 View 都只吃这张表 ——
     「Model 过滤了、View 又直接遍历 GMCommands.list」会让 release 包照样露出危险通道。
  3. SaveCodeSnapshot()：每次执行前把代码原文落盘到 persistentDataPath，做事后证据。

红线：levelUpN 内部必须 for _ = 1, n do bm:OnExpGained(pc.expToNext) end 分 N 次调用。
      直接 pc:AddExp(n * expToNext) 会绕过升级回调 => 不弹三选一、不发奖励 => 假通过。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"

local GMCommands = {}

local function GetBM()
	local GameMain = require("Game.GameMain")
	return GameMain.GetBattleManager()
end

-- 取主界面（HUD）的 Model + View，用于改金币/钻石并刷新显示
-- 注意：Home 窗口在 RegisterHomePanel 注册名为 "HomePanel"（不是 "Home"）
local function GetHomeMV()
	local GameMain = require("Game.GameMain")
	local ui = GameMain.GetUIManager()
	if not ui then return nil, nil end
	local win = ui:GetWindow("HomePanel")
	if not win then return nil, nil end
	return win:GetModel(), win:GetView()
end

local function GetDM()
	local GameMain = require("Game.GameMain")
	return GameMain.GetDungeonManager()
end

-- 守卫原因文案（available() 返回 false 时交给 UI 说明区显示）
local REASON_BATTLE = "需先进入战斗（开始下潜）"
local REASON_HOME   = "Home 未打开（先回主界面）"
local REASON_DIVING = "未在下潜中（请先开始下潜）"

-- 守卫助手（§11.5）：返回 ok, reason；ok 为真时 reason 为 nil
local function _inBattle(reason)
	if GetBM() ~= nil then return true end
	return false, reason
end

local function _homeOpen(reason)
	local m = GetHomeMV()
	if m ~= nil then return true end
	return false, reason
end

local function _diving(reason)
	if GetDM() ~= nil then return true end
	return false, reason
end

-- 参数校验（§11.3 ③）：非法/越界一律返回错误串，**不再静默改默认值**
-- 原实现 tonumber(v) or 1000 会在非法输入时偷偷兜底，故这里 nil/"" 才走 default。
local function parseInt(v, name, min, max, default)
	if v == nil or v == "" then
		if default == nil then return nil, name .. " 不能为空" end
		return default
	end
	local n = tonumber(v)
	if n == nil then
		return nil, string.format("%s 需为整数（收到：%s）", name, tostring(v))
	end
	if n < min or n > max then
		return nil, string.format("%s 需在 %d ~ %d 之间（收到：%s）", name, min, max, tostring(v))
	end
	return math.floor(n)
end

-- 武器 --------------------------------------------------------------------
local function grantAllWeapons()
	local bm = GetBM()
	if not bm then return REASON_BATTLE end
	local ws = bm.weaponSystem
	local BuildConfig = require("Game.Build.BuildConfig")
	local owned = {}
	for _, w in ipairs(ws:GetAllWeapons()) do owned[w.id] = true end
	local added = 0
	for _, cfg in ipairs(BuildConfig.Weapons) do
		if not owned[cfg.id] then ws:AddWeapon(cfg); added = added + 1 end
	end
	return string.format("解锁 %d 把（共 %d）", added, #BuildConfig.Weapons)
end

-- wid 枚举选项（12 项 + 随机）：取自 BuildConfig，不硬编码第二份武器名
local WID_RANDOM = "__random__"
local _widOptions
local function weaponWidOptions()
	if _widOptions then return _widOptions end
	local options = {}
	local ok, BuildConfig = pcall(require, "Game.Build.BuildConfig")
	if ok and BuildConfig and BuildConfig.Weapons then
		for _, cfg in ipairs(BuildConfig.Weapons) do
			options[#options + 1] = { value = cfg.id, label = (cfg.name or cfg.id) .. "/" .. cfg.id }
		end
	end
	_widOptions = options
	return options
end

local function randomWeapon(v)
	local bm = GetBM()
	if not bm then return REASON_BATTLE end
	local ws = bm.weaponSystem
	local BuildConfig = require("Game.Build.BuildConfig")
	local owned = {}
	for _, w in ipairs(ws:GetAllWeapons()) do owned[w.id] = true end
	local pool = {}
	for _, cfg in ipairs(BuildConfig.Weapons) do
		if not owned[cfg.id] then pool[#pool + 1] = cfg end
	end
	if #pool == 0 then return "已拥有全部武器" end
	local wid = tostring(v or ""):match("^%s*(.-)%s*$")
	local cfg = nil
	if wid ~= "" and wid ~= WID_RANDOM then
		for _, c in ipairs(pool) do
			if c.id == wid then cfg = c; break end
		end
		if not cfg then return string.format("未知武器 id（可选随机或已拥有的）：%s", wid) end
	else
		cfg = pool[math.random(#pool)]
	end
	ws:AddWeapon(cfg)
	return "获得：" .. (cfg.name or cfg.id)
end

-- 角色 --------------------------------------------------------------------
local function invincibleGetter()
	local bm = GetBM()
	local pc = bm and bm.playerController
	return (pc and pc.isInvincible) or false
end

local function toggleInvincible()
	local bm = GetBM()
	if not bm then return REASON_BATTLE end
	local pc = bm.playerController
	pc.isInvincible = not pc.isInvincible
	pc.invincibleTimer = pc.isInvincible and 1e9 or 0
	return "无敌：" .. (pc.isInvincible and "开" or "关")
end

local function healFull()
	local bm = GetBM()
	if not bm then return REASON_BATTLE end
	local pc = bm.playerController
	pc:Heal(pc.maxHp)
	return "已回满血"
end

-- 【P2-2】升级指令必须走 bm:OnExpGained，不能直接调 pc:AddExp。
-- 直接调 pc:AddExp 会绕过 BattleManager 的升级回调 -> 既不弹三选一、也不发升级奖励，
-- 用它验证升级流程只会得到「假的通过」。改为走正式链路后，本指令
-- 同时也是三选一弹窗（含连升多级）的验证入口。
local function levelUpN(v)
	local bm = GetBM()
	if not bm then return REASON_BATTLE end
	local n, err = parseInt(v, "级数 n", 1, 20, 10)
	if not n then return err end
	local pc = bm.playerController
	-- 分 N 次给经验（红线）：每级都走一次 OnExpGained -> 弹一次三选一
	for _ = 1, n do bm:OnExpGained(pc.expToNext) end
	return string.format("已连升 %d 级 → Lv.%d", n, pc.level)
end

-- 敌人 --------------------------------------------------------------------
local function killAll()
	local bm = GetBM()
	if not bm then return REASON_BATTLE end
	local em = bm.enemyManager
	local n = 0
	for _, e in ipairs(em.enemies) do
		if not e.isDead then em:TakeDamage(e.id, 1e9, false); n = n + 1 end
	end
	return "秒杀 " .. n .. " 个敌人"
end

-- 关卡 --------------------------------------------------------------------
local function nextFloor()
	local dm = GetDM()
	if not dm then return REASON_DIVING end
	dm:NextFloor()
	return "进入第 " .. dm.currentFloor .. " 层"
end

-- 货币 --------------------------------------------------------------------
-- 带输入框的命令：fn(value)，value 为输入框解析出的数值（nil 时用 params.default）。
local function addGold(v)
	if require("Game.Save.SaveData").IsOnline() then
		return "在线金币由服务器管理", "online_authority"
	end
	local m, vw = GetHomeMV()
	if not m then return REASON_HOME end
	local n, err = parseInt(v, "金币数量", 1, 99999999, 1000)
	if not n then return err end
	local inventory = require("Game.Save.SaveData").Get().inventory
	inventory.gold = (inventory.gold or 0) + n
	m:RefreshCurrency()
	if vw and vw.SetGold then vw:SetGold(m:GetGold()) end
	return string.format("金币 +%d（%d）", n, m:GetGold())
end

local function addDiamond(v)
	local m, vw = GetHomeMV()
	if not m then return REASON_HOME end
	local n, err = parseInt(v, "钻石数量", 1, 99999999, 100)
	if not n then return err end
	m:SetCurrency(m:GetGold(), m:GetDiamond() + n)
	if vw and vw.SetDiamond then vw:SetDiamond(m:GetDiamond()) end
	return string.format("钻石 +%d（%d）", n, m:GetDiamond())
end

-- 跳到指定层数（直接走 DungeonManager:EnterFloor，绕过事件弹窗流程，纯调试用）
local function gotoFloor(v)
	local dm = GetDM()
	if not dm then return REASON_DIVING end
	local n, err = parseInt(v, "层数", 1, 999, 10)
	if not n then return err end
	dm:EnterFloor(n)
	return "跳到第 " .. n .. " 层"
end

-- ---------------------------------------------------------------------------
-- 剪贴板（§11.6 / X9 三条硬要求）
--   1) Set 之后立刻 Get 读回比对，不相等判失败；
--   2) 待复制文本先 4096 截断（超了 systemCopyBuffer 会静默丢尾）；
--   3) 失败必须写日志，不静默。
-- ---------------------------------------------------------------------------
local COPY_LIMIT = 4096
local TRUNC_TAG  = "…(已截断)"

local function systemCopy(text)
	local s = tostring(text or "")
	if #s > COPY_LIMIT then s = s:sub(1, COPY_LIMIT) .. TRUNC_TAG end
	if not CS.UnityEngine.GUIUtility then return false, "GUIUtility 不可用" end
	local ok = pcall(function() CS.UnityEngine.GUIUtility.systemCopyBuffer = s end)
	if not ok then return false, "写入抛异常" end
	local back = CS.UnityEngine.GUIUtility.systemCopyBuffer
	if tostring(back) ~= s then return false, "写后读回不一致" end
	return true
end

---把日志/文本复制到系统剪贴板（S6 的「复制日志」按钮接线点；本轮只提供能力，不碰 UI）
function GMCommands.CopyLog(text)
	local s = tostring(text or "")
	-- 空串直接判拒绝：日志还没落地（GMLog 缓冲是空的）时 systemCopy 会把空串写进剪贴板，
	-- 然后照样走「已复制 %d 字」这条成功分支 —— UI 上看着像复制成功、剪贴板其实空了。
	-- 提前挡掉，免得「复制日志」这个按钮给用户一个假的成功回执。
	if #s == 0 then return "日志为空，无可复制内容" end
	if #s > COPY_LIMIT then s = s:sub(1, COPY_LIMIT) .. TRUNC_TAG end
	local ok, why = systemCopy(s)
	if not ok then
		Logger.Warn("GM", "剪贴板写入失败（%s），请手动选中复制", tostring(why))
		return "剪贴板写入失败，请手动选中复制"
	end
	Logger.Info("GM", "已复制 %d 字到剪贴板", #s)
	return string.format("已复制日志（%d 字）", #s)
end

-- ---------------------------------------------------------------------------
-- 代码快照落盘（§12.3）
--   主证据：persistentDataPath / GM_CodeSnapshot_<unixTs>.lua（每次执行一条，累加）
--   便捷看：同一目录 GM_LastCode.lua（覆盖），方便 IDE 直接打开
--   指针：  PlayerPrefs 只存文件名而不是代码本身（代码最多 2000 字，Windows 下
--           PlayerPrefs 走注册表，塞大文本会拖慢读写）
-- 为什么用 System.IO.File 而不是 io.open：XLua 的 io 库在裁剪 / IL2CPP 构建里不一定带，
-- 而快照只是「事后证据」，绝不能因为它写失败就挡住危险通道；统一 pcall 兜底、失败只记日志。
-- 注意命名空间必须是 CS.System.IO.File，不能写成 CS.UnityEngine.System.IO.File ——
-- 后者在运行时是 No such type，会连带把整个 SaveCodeSnapshot 打挂（真机探针踩过）。
-- ---------------------------------------------------------------------------
local Unity_App   = CS.UnityEngine.Application
local Unity_Prefs = CS.UnityEngine.PlayerPrefs
-- 顶到底只解一次类型，别在热路径上反复 CS.xxx 取元表
local Unity_File   = CS.System.IO.File
local SNAP_LAST, SNAP_FILE_KEY = "GM_LastCode.lua", "GM_LastCodeFile"

local function _writeText(path, text)
	local ok, err = pcall(function()
		Unity_File.WriteAllText(path, text)
	end)
	if ok then return true end
	return false, tostring(err)
end

-- 文件名撞车避让（S7 收口③）：名字里的时间戳只到秒，而二次确认窗口有 3.5s，
-- 手快的用户「点一下、再点一下」完全可能落在同一秒内 —— 那样两条证据会写进同一个文件，
-- 后一条把前一条盖掉，主证据就丢了（文档 §12.3 要求「每次执行一条、累加」）。
-- 所以写之前先看 Exists，同名就退到 .1 / .2 / … 直到空位。
local function _uniqueSnapshotPath(dir, base)
	local path = string.format("%s/%s", dir, base)
	if not Unity_File.Exists(path) then return path end
	for n = 1, 99 do
		path = string.format("%s/%s.%d", dir, base, n)
		if not Unity_File.Exists(path) then return path end
	end
	return string.format("%s/%s.%d", dir, base, os.time() % 100000)
end

---把代码原文落盘，返回主证据文件路径（写失败返回 nil，绝不抛）
function GMCommands.SaveCodeSnapshot(code)
	local dir = tostring(Unity_App.persistentDataPath or "")
	if dir == "" then return nil end
	local text = tostring(code or "")
	local ts = os.time() or 0
	local mainPath = _uniqueSnapshotPath(dir, string.format("GM_CodeSnapshot_%d.lua", ts))
	_writeText(mainPath, text)
	_writeText(dir .. "/" .. SNAP_LAST, text)
	pcall(function()
		Unity_Prefs.SetString(SNAP_FILE_KEY, tostring(ts) .. "|" .. SNAP_LAST)
		Unity_Prefs.Save()
	end)
	return mainPath
end

-- ---------------------------------------------------------------------------
-- advanced.run_lua（§12）：把输入框里的文本当一整段 Lua chunk 跑
--
-- 隔离四件套（02_design 7.2）：devOnly 过滤 + danger 与 3.5s 二次确认（UIGMController）
-- + 每次执行落盘代码快照 + 独立「※高级」分类。本函数只负责「执行 + 出回执」。
--
-- fn 的取值形态：全表统一走 fn(value)（单参标量），advanced.run_lua 的 value 就是代码原文；
-- 待确认态（点第一下）由 Controller 拦在 fn 之前，这里不会在第一次点击时被调用。
-- ---------------------------------------------------------------------------
local CODE_LIMIT = 2000   -- 与 params[1].max 同源；见 §11.2 run_lua.code.limit

local function runLuaCode(v)
	if require("Game.Save.SaveData").IsOnline() then
		return "在线模式不可执行 Lua", "online_authority"
	end
	local code = tostring(v or ""):gsub("^%s*(.-)%s*$", "%1")
	if code == "" then return "代码为空（限 1 ~ 2000 字）" end
	if #code > CODE_LIMIT then
		return string.format("代码超长（%d 字 > %d 字），未执行", #code, CODE_LIMIT)
	end

	-- 落盘先行：就算下面这行把进程搞崩，事后也能从快照还原「到底跑过什么」。
	local snap = GMCommands.SaveCodeSnapshot(code)

	-- 为什么用 load + pcall，而不是文档 §12.4 里的 CS.XLuaManager.Instance:RunGMCode：
	--   a) SafeDoString 的 catch 会「把异常吞掉后，再拿 UTF8 字节 DoString 一遍」，
	--      同一段有语法错误的代码会被执行两次，错误语义不可控（危险通道上这很要命）；
	--   b) load 能把「编译失败（语法错误）」和「运行失败（运行时错误）」分开报，
	--      错误信息是纯 Lua 串，不用再过一层 C# object[] 转换；
	--   c) 与本项目「抛错只写日志、不外泄到调用方」的 pcall 纪律一致（§12 失败回退点）。
	-- 红线：绝不能裸写 load(code)() —— 语法错误会直接抛穿到 UIGMController 的 pcall 之外。
	-- 另外本项目 Lua 侧只有 load（Lua 5.3 / xLua），loadstring 在 5.3 已被移除，别用。
	local chunk, loadErr = load(code)
	if not chunk then
		return "代码语法错误，未执行（已记入快照）: " .. tostring(loadErr)
	end
	local ok, ret = pcall(chunk)
	if not ok then
		-- §12 失败回退点：抛错只进日志/回执，不让面板崩
		return "Lua 执行异常（已记入代码快照）: " .. tostring(ret)
	end
	-- 回执要短：这句会同时进 m_Summary_Txt 与日志，日志单条上限 1024（R11），
	-- 完整代码在快照文件里，不在这儿复述。
	return string.format("已执行（%d 字%s）", #code, snap and "，快照已落盘" or "，快照未落盘")
end

-- ---------------------------------------------------------------------------
-- 指令表（顺序即面板按钮顺序）
--   input / inputDefault：S2 已验证的 UIGMView 渲染契约，参数类命令必须保留，
--                         同时以 params 承载校验范围（§11.4 适配层）。
-- ---------------------------------------------------------------------------
GMCommands.list = {
	{
		group = "武器", label = "解锁全部武器",
		id = "weapon.unlock_all", desc = "解锁 BuildConfig 里全部未拥有的武器",
		alias = { "解锁全部" },
		available = function() return _inBattle(REASON_BATTLE) end,
		fn = grantAllWeapons,
	},
	{
		group = "武器", label = "随机新武器",
		id = "weapon.random_one", desc = "随机获得一把未拥有武器；可指定 wid 直取",
		alias = { "随机武器", "随机新武器" },
		available = function() return _inBattle(REASON_BATTLE) end,
		fn = randomWeapon,
		-- 12 项武器 + 「随机（默认）」
		params = {
			{ key = "wid", name = "武器", type = "enum", default = WID_RANDOM, options = weaponWidOptions() },
		},
		input = true, inputDefault = WID_RANDOM,
	},
	{
		group = "角色", label = "无敌开关",
		id = "role.invincible", desc = "开关玩家无敌；getter 读回当前状态",
		alias = { "无敌", "无敌开关" },
		runMode = "toggle", persist = true,
		available = function() return _inBattle(REASON_BATTLE) end,
		getter = invincibleGetter,
		fn = toggleInvincible,
	},
	{
		group = "角色", label = "回满血",
		id = "role.heal_full", desc = "把玩家血量回满",
		alias = { "回满血", "加血" },
		available = function() return _inBattle(REASON_BATTLE) end,
		fn = healFull,
	},
	{
		group = "角色", label = "连升 N 级",
		id = "role.level_up", alias = { "升1级", "加10级", "levelUp1", "levelUp10" },
		desc = "连升 n 级（n: 1~20，默认 10）；每级走一次升级回调、弹一次三选一",
		tip = "每级弹一次三选一；连升 n 级需连续选择 n 次（上限 20）",
		danger = true,
		available = function() return _inBattle(REASON_BATTLE) end,
		fn = levelUpN,
		params = {
			{ key = "n", name = "级数", type = "int", default = 10, min = 1, max = 20 },
		},
		quick = { 1, 5, 10, 20 },
		quickLabel = { "1", "5", "10", "20" },
		input = true, inputDefault = "10",
	},
	{
		group = "敌人", label = "秒杀全场",
		id = "enemy.kill_all", desc = "对场上所有存活敌人造成致命伤害",
		alias = { "秒杀全场", "秒杀" },
		danger = true,
		available = function() return _inBattle(REASON_BATTLE) end,
		fn = killAll,
	},
	{
		group = "货币", label = "加金币",
		id = "currency.add_gold", desc = "给 Home 主界面的金币加数量（count: 1~99999999，默认 1000）",
		alias = { "加金币", "金币" },
		available = function() return _homeOpen(REASON_HOME) end,
		fn = addGold,
		params = {
			{ key = "count", name = "数量", type = "int", default = 1000, min = 1, max = 99999999 },
		},
		-- quick 档 = 03_balance.md 的【绝对档位 + 独立标签】，不要拿 default×倍率推
		quick = { 100, 1000, 10000, 100000 },
		quickLabel = { "100", "1K", "10K", "100K" },
		input = true, inputDefault = "1000",
	},
	{
		group = "货币", label = "加钻石",
		id = "currency.add_diamond", desc = "给 Home 主界面的钻石加数量（count: 1~99999999，默认 100）",
		alias = { "加钻石", "钻石" },
		available = function() return _homeOpen(REASON_HOME) end,
		fn = addDiamond,
		params = {
			{ key = "count", name = "数量", type = "int", default = 100, min = 1, max = 99999999 },
		},
		-- 钻石单局产出量级比金币低一档（03_balance.md:464）⇒ 档位整体下移 10×
		quick = { 10, 100, 1000, 10000 },
		quickLabel = { "10", "100", "1K", "10K" },
		input = true, inputDefault = "100",
	},
	{
		group = "关卡", label = "下一层",
		id = "dungeon.next_floor", desc = "推进到下一层",
		alias = { "下一层", "下一关" },
		available = function() return _diving(REASON_DIVING) end,
		fn = nextFloor,
	},
	{
		group = "关卡", label = "跳到层数",
		id = "dungeon.goto_floor", desc = "直接跳到指定层（floor: 1~999，默认 10）",
		alias = { "跳层", "跳到层数" },
		danger = true,
		available = function() return _diving(REASON_DIVING) end,
		fn = gotoFloor,
		params = {
			{ key = "floor", name = "层数", type = "int", default = 10, min = 1, max = 999 },
		},
		quick = { 1, 10, 50, 100 },
		quickLabel = { "1", "10", "50", "100" },
		input = true, inputDefault = "10",
	},
	-- 【S7 第 11 条】任意 Lua 代码执行（§12）。devOnly + danger 双双开启：
	--   * devOnly  = release 包连这一行都不在列表里（注册/加载层过滤，见 VisibleList）；
	--   * danger   = 必须连点两次、间隔 ≤ 3.5s 才真跑（状态机在 UIGMController）。
	{
		group = "※高级", label = "执行 Lua 代码",
		id = "advanced.run_lua",
		devOnly = true, danger = true,
		desc = "把输入框里的 Lua 代码当整段 chunk 执行（1 ~ 2000 字）；需连点两次确认",
		tip = "危险：代码在你当前进程里跑，可以改存档、清进度甚至崩客户端；"
			.. "执行前会把代码原文落盘到 persistentDataPath",
		confirmText = "确认执行？",
		fn = runLuaCode,
		params = {
			{ key = "code", name = "代码", type = "string", default = "", min = 1, max = CODE_LIMIT },
		},
		input = true, inputDefault = "",
	},
}

-- ---------------------------------------------------------------------------
-- devOnly 过滤出口（§12.1 门控第 1 层：注册 / 加载层）
--   release 包（Debug.isDebugBuild == false）里 devOnly 命令连列表都不进 ——
--   搜索也搜不到，因为下层的 Filter 走的本来就是这张表。
--   ★ 全项目只认这一个过滤出口：Model 与 View 都调 VisibleList()，不要再自己遍历
--     GMCommands.list，否则门控会出现「一处漏了、release 包照样露出危险通道」的洞。
--   每次调用现算（最多 11 条，开销可忽略），不做缓存 —— 免得开关翻转后拿到旧表。
-- ---------------------------------------------------------------------------
local GMConfig = require "Game.GM.GMConfig"

function GMCommands.VisibleList()
	local dev = GMConfig.IsDev()
	local out = {}
	for _, cmd in ipairs(GMCommands.list or {}) do
		-- 必须 out[#out+1] 追加：用原表下标 out[i] 会在被过滤掉的那条处留下一个洞，
		-- 下游 ipairs 在第一个洞处就终止 ⇒ release 包列表被静默截断、后面整批命令消失。
		-- 现在只有末条 advanced.run_lua 是 devOnly 恰好没暴露，将来有人在列表中间
		-- 加一条 devOnly 就会立刻踩中。
		if not (cmd.devOnly and not dev) then out[#out + 1] = cmd end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- 旧结构适配层（§11.4）：旧 {group, label, fn} 可零改动先跑起来，回滚友好。
--   id 缺省 -> group .. "." .. (label 里的非 ASCII/空格清理)，退化则 "cmd." .. index
--   desc / alias / danger / devOnly 缺省 -> 留空，不阻塞
-- ---------------------------------------------------------------------------
function GMCommands.Normalize(cmd, index)
	if not cmd then return nil end
	local c = {}
	for k, v in pairs(cmd) do c[k] = v end
	if not c.id then
		local leaf = tostring(c.label or ""):gsub("[^%w_]", ""):lower()
		local group = tostring(c.group or ""):gsub("[^%w_]", ""):lower()
		if group ~= "" and leaf ~= "" then
			c.id = group .. "." .. leaf
		else
			c.id = "cmd." .. tostring(index or 0)
		end
	end
	c.desc    = c.desc or ""
	c.danger  = c.danger or false
	c.devOnly = c.devOnly or false
	return c
end

function GMCommands.NormalizeList()
	local out = {}
	for i, cmd in ipairs(GMCommands.list or {}) do
		out[i] = GMCommands.Normalize(cmd, i)
	end
	return out
end

return GMCommands
