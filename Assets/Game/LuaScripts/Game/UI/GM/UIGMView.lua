--[[
=============================================================================
UIGMView.lua - GM 调试工作台视图
=============================================================================
Module:     Game.UI.GM.UIGMView

字段来源（不再手写 FindGameObject）：
  GMPanel.prefab 根节点挂 UIComponentBinder，S1 已写入 UICompList、S2 起用 Unity 侧
  binder:Bind() 填实 Comp 引用；运行时用 BindFieldNilCount 核验。UIBaseContainer:AutoBind 按
  「子节点名_类型缩写」把 Lua 组件实例注入 self，本文件直接用：
      m_Title_Txt / m_EnvTag_Txt / m_Summary_Txt_Txt / m_LogTip_Txt ...  -> UIText（含 TMP）
      mi_BtnMaster_Btn / mi_BtnFold_Btn / mi_BtnClose_Btn ...            -> UIButton
      m_Search_Ipt_Ipt / m_HitCount_Txt / mi_BtnClearSearch_Btn ...
      m_CategoryList_Srt / m_CategoryList_Slb_Slb                        -> UIScrollRect / UIScrollbar
      m_CmdList_Srt / m_CmdList_Slb_Slb
      m_*_Img                                                            -> UIImage

点击接法（B2 返工项，团队硬约束）：
  - 每个【item GO 实例】只在首次刷新时建一次组件 + 绑一次按钮（_cmdCompCache 以
    GetInstanceID 做标记），之后 SetOnRefresh 回调只更新 index 映射 / 文案 / 参数值，
    禁止 AddListener、禁止重复 AddComponent；
  - 一律走 UIButton:SetOnClick（内部先 RemoveListener 再 Add，幂等；OnDestroy 自动 RemoveClick）。
  - item prefab（CmdItem / CategoryItem）没挂 binder，其 UIButton / UIText / UIInputField
    必须把【真实 unity 组件】当第二参传 AddComponent（传 GameObject 会把 GO 塞进
    __uiComp，SetText 直接抛错），见下方 textComp / inputComp / btnComp。
  - 注意 UIBaseContainer.components 是「节点名 -> 类 -> 组件」扁平表，同名子节点只能注册一个
    实例，故 MUST 按 item GO 缓存，不能每次刷新都 AddComponent。

组件遍历纪律：一律「先 transform:Find 到节点，再 GetComponent(typeof(T))」，不走 GetComponentInChildren。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"
local UIButton = require "Framework.UI.Component.UIButton"
local UIText = require "Framework.UI.Component.UIText"
local UIInputField = require "Framework.UI.Component.UIInputField"
local UIListView = require "Framework.UI.Component.UIListView"
local Logger = require "Framework.UI.Utils.Logger"
local GMCommands = require "Game.GM.GMCommands"
local GMUIConfig = require "Game.GM.GMUIConfig"
local GMLog = require "Game.GM.GMLog"
local GMConfig = require "Game.GM.GMConfig"
local GMRuntimeStats = require "Game.GM.GMRuntimeStats"
local TimerManager = require "Framework.Core.TimerManager"
local UpdateManager = require "Framework.Core.UpdateManager"
-- S9：AB 实机路径下 prefab 里的 TMP 材质丢 atlas 纹理（bundle 内拷贝的 font 与
-- Resources 字体不是同一对象、mainTexture 为空）=> 全部换 Resources 字体（CJKFont
-- 统一入口，与七个业务面板同一条修复路径）。全局 fallback 不救这个：那是缺字回落，
-- 这是主字体材质本身没纹理。
local CJKFont = require "Framework.UI.Utils.CJKFont"

local UIGMView = BaseClass("UIGMView", UIView)
local base = UIView

local CMD_ITEM_PATH = "UI/GM/GMPanelCmdItem"
local CAT_ITEM_PATH = "UI/GM/GMPanelCategoryItem"

local CMD_ITEM_H, CMD_ITEM_GAP = 68, 4
local CAT_ITEM_H, CAT_ITEM_GAP = 56, 4

local ALL_GROUP = "全部"

-- 取子节点 GO（组件遍历只走这一条路径：先 Find 节点，再 GetComponent）
local function child(go, name)
	if not go then return nil end
	local t = go.transform:Find(name)
	return t and t.gameObject or nil
end

-- 按 "/ " 分隔的多级路径逐级 Find（S7 真机探针查出的问题，勿改回单级）
-- 症状：S1 重建 prefab 后 m_Param_Ipt 被收进了 m_ParamSlot 容器，item 根下已经没有
-- 同名直接子节点；此时 _cmdComp 用 child(go, 'm_Param_Ipt') 拿不到东西 ⇒ c.ipt 恒为 nil
-- ⇒ _readParamValue 读不到输入框 ⇒ advanced.run_lua 无论敲多少字都被判「代码为空」，
-- 而且全程没有一条报错（_refreshCmdItem 里的 `if showIpt and c.ipt` 天然跳过）——
-- 典型的只静默不抛错，属于必须按路径找、不能用 Find 单级的场景。
local function childPath(go, path)
	if not go then return nil end
	local t = go.transform
	for name in string.gmatch(path, "[^/]+") do
		if not t then return nil end
		t = t:Find(name)
	end
	return t and t.gameObject or nil
end

-- =============================================================================
-- item 子节点上的 Unity 组件取法
--
-- 背景（真机探针实测，勿改回）：AddComponent(cls, childGO) 会把 childGO 这个
-- GameObject 原样塞进 UIBaseComponent.__uiComp，导致 UIButton / UIText /
-- UIInputField 的 OnCreate 里 `self.__uiComp or UIUtil.FindXxx(...)` 直接命中这个
-- GO，于是 unity_uibutton = GameObject / unity_uitext = GameObject，
-- 一调 SetText 就抛 "cannot set text, no such field"。
-- 结论：手动 AddComponent 时必须把【真实 unity 组件】当第二个参数传进去，
-- 不能传 GO。这里统一用「先 Find 节点、再 GetComponent(typeof)」取组件
-- （纪律同 UIUtil.FindText：绝不从 root 走 GetComponentInChildren）。
-- =============================================================================
local UI_TEXT = CS.UnityEngine.UI.Text
local UI_INPUTFIELD = CS.UnityEngine.UI.InputField
local TMP_TEXT = (CS.TMPro ~= nil) and CS.TMPro.TextMeshProUGUI or nil

local function textComp(go)
	local tr = go and go.transform
	if not tr then return nil end
	local c = tr:GetComponent(typeof(UI_TEXT))
	if c then return c end
	if TMP_TEXT then c = tr:GetComponent(typeof(TMP_TEXT)) end
	return c
end

local function inputComp(go)
	local tr = go and go.transform
	if not tr then return nil end
	return tr:GetComponent(typeof(UI_INPUTFIELD))
end

local function btnComp(go)
	local tr = go and go.transform
	if not tr then return nil end
	return tr:GetComponent(typeof(CS.UnityEngine.UI.Button))
end

-- AutoBind 应当注入、S2 会用到的字段（真机探针拿它算 nilCount，必须为 0）
local EXPECT_FIELDS = {
	"m_Title_Txt", "m_EnvTag_Txt",
	"mi_BtnMaster_Btn", "mi_BtnFold_Btn", "mi_BtnClose_Btn",
	"m_Search_Ipt_Ipt", "m_HitCount_Txt", "mi_BtnClearSearch_Btn",
	"m_CategoryList_Srt", "m_CategoryList_Slb_Slb",
	"m_CmdList_Srt", "m_CmdList_Slb_Slb",
	"m_Summary_Txt_Txt", "mi_BtnLogClear_Btn", "mi_BtnLogCopy_Btn", "mi_BtnLogFold_Btn",
}

-- 危险态（§12.2）：不新增图，只改执行键的底色 + 文案
local DANGER_BTN_TEXT = "确认执行？"
local NORMAL_BTN_TEXT = "执行"   -- 与 GMPanelCmdItem.prefab 里 m_TxtExec 的 m_text 一致
local COLOR_DANGER = CS.UnityEngine.Color(0.8, 0.2, 0.2, 1)   -- #CC3333
local COLOR_SELECTED = CS.UnityEngine.Color(0.086, 0.486, 0.439, 1)
local COLOR_CAT_LABEL = CS.UnityEngine.Color(0.78, 0.80, 0.82, 1)
local COLOR_CAT_SELECTED_LABEL = CS.UnityEngine.Color(1, 1, 1, 1)

-- GM-only correction: top-pivot ScrollRect moves content UP with positive y.
-- Assign to each list instance; the framework's listener calls self:Refill().
local function refillTopList(list)
	if not list.pool or IsNull(list.content) or IsNull(list.viewport) then return end
	local n, step = list.itemCount, list.itemHeight + list.itemSpacing
	local height = list.viewport.rect.height
	local maxY = math.max(0, list.content.sizeDelta.y - height)
	local y = math.max(0, math.min(list.content.anchoredPosition.y, maxY))
	local first = math.floor(y / step)
	local startIndex = math.max(0, first - 2)
	local endIndex = math.min(n - 1, first + math.ceil(height / step) + 3)
	for index, go in pairs(list.activeItems) do
		if index < startIndex or index > endIndex then
			list.pool:Release(go)
			list.activeItems[index] = nil
		end
	end
	for index = startIndex, endIndex do
		if not list.activeItems[index] then
			local go = list.pool:Get()
			list.activeItems[index] = go
			go.transform.anchoredPosition = CS.UnityEngine.Vector2(0,
				-(index * step + list.itemHeight * 0.5))
			if list.onRefresh then list.onRefresh(go, index) end
		end
	end
end

-- 分组只认 VisibleList：release 包里「⚠高级」这个分类项不该出现（里面一条命令都没有）
local function collectGroups()
	local order, seen = {}, {}
	for _, cmd in ipairs(GMCommands.VisibleList()) do
		local g = cmd.group or "其他"
		if not seen[g] then seen[g] = true; order[#order + 1] = g end
	end
	return order
end

local function groupOf(cmd)
	return (cmd and cmd.group) or "其他"
end

-- 经 AssetBundleProvider 拿资源提供者（与 UIManager 同一实例，共享 AB 缓存）
local function getProvider()
	local ok, GameMain = pcall(require, "Game.GameMain")
	if ok and GameMain and GameMain.GetUIResourceProvider then
		return GameMain.GetUIResourceProvider()
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- 生命周期
-- ---------------------------------------------------------------------------
function UIGMView:OnCreate()
	base.OnCreate(self)   -- 基类已执行 AutoBind，把 UIComponentBinder 的字段注入 self

	self._curGroup = ALL_GROUP
	self._groups = collectGroups()
	self._shownCmds = {}
	self._cmdList = nil
	self._catList = nil
	self._idxOfGO = {}      -- item GO:GetInstanceID() -> 列表 index（点击时回查）
	self._pendingCmdId = nil  -- S7：当前处于「待二次确认」的危险命令 id（Controller 驱动）
	self._cmdCompCache = {} -- item GO:GetInstanceID() -> {name,desc,ipt,exec,fav}（组件+按钮只建一次）
	self._catCompCache = {} -- cat GO:GetInstanceID() -> {txt}
	self._cmdPrefab = nil
	self._catPrefab = nil
	self._drafts = {}
	self._ownedItemComps = {}
	self._loadGeneration = 0
	self._listState = "loading"

	self:_initHeader()
	self:_initLists()
	self:_loadItemPrefabs()

	CJKFont.ApplyAll(self.transform)   -- S9：修 AB 材质丢纹理（面板级 TMP 全覆盖）
end

function UIGMView:OnOpen()
	base.OnOpen(self)
	self._opened = true
	self._layoutParentW, self._layoutParentH = nil, nil
	self:_adaptLayout()
	self.m_Title_Txt:SetText("GM 调试面板")
	self.m_EnvTag_Txt:SetText(GMConfig.IsDev() and "开发环境" or "发布环境")
	self.m_Summary_Txt_Txt:SetText("就绪")
	-- 面板是 CacheOnClose：重开时先让 Controller 清掉上一次残留的待确认态，
	-- 否则上一轮 3.5s 没确认完就关了面板，回来时按钮还红着、点一下就直接跑代码
	local ctrl = self:GetController()
	if ctrl and ctrl.OnViewOpened then ctrl:OnViewOpened() end
	self:_refreshLists()
	self:RefreshLog()
	self:_ensureRuntimeTimer()
end

function UIGMView:OnRefresh()
	base.OnRefresh(self)
	self:OnOpen()
end

function UIGMView:_refreshRuntime()
	self:_adaptLayout()
	local ok, sample = pcall(GMRuntimeStats.Sample)
	local fields = {
		m_ValScene_Txt = "scene", m_ValDungeon_Txt = "dungeon",
		m_ValEnemy_Txt = "enemies", m_ValBullet_Txt = "bullets",
		m_ValTime_Txt = "battleTime", m_ValFps_Txt = "fps", m_ValGc_Txt = "luaGC",
	}
	for field, key in pairs(fields) do
		local value = ok and type(sample) == "table" and sample[key] or nil
		local text = value ~= nil and tostring(value) or "采样不可用"
		if text == "" or text == "?" or text == "nil" then text = "未就绪" end
		if key == "fps" and value == 0 then text = "采样中" end
		if self[field] then self[field]:SetText(text) end
	end
end

function UIGMView:_adaptLayout()
	local root = self.transform and self.transform:GetComponent(typeof(CS.UnityEngine.RectTransform))
	local parent = root and root.parent and root.parent:GetComponent(typeof(CS.UnityEngine.RectTransform))
	if not parent then return end
	local width, height = parent.rect.width, parent.rect.height
	if width <= 0 or height <= 0 then return end
	if width == self._layoutParentW and height == self._layoutParentH then return end
	local scale = math.min(width / 1280, height / 720)
	root.anchorMin = CS.UnityEngine.Vector2(0.5, 0.5)
	root.anchorMax = CS.UnityEngine.Vector2(0.5, 0.5)
	root.pivot = CS.UnityEngine.Vector2(0.5, 0.5)
	root.sizeDelta = CS.UnityEngine.Vector2(width * 0.88 / scale, math.min(height * 0.90 / scale, 900))
	root.localScale = CS.UnityEngine.Vector3(scale, scale, scale)
	root.anchoredPosition = CS.UnityEngine.Vector2(0, 0)
	self._layoutParentW, self._layoutParentH = width, height
	for _, list in ipairs({ self._catList, self._cmdList }) do
		list:Refill()
		list:RefreshAll()
	end
	self:_showSelectedCategory()
end

function UIGMView:_ensureRuntimeTimer()
	self:_refreshRuntime()
	if self._runtimeTimerId then return end
	self._runtimeTimer = TimerManager.New()
	self._runtimeTimerId = self._runtimeTimer:AddLoop(500, function()
		if self._opened and not self._destroyed then self:_refreshRuntime() end
	end)
	self._runtimeUpdateId = UpdateManager:GetInstance():AddUpdate(function()
		if self._opened and not self._destroyed then
			self._runtimeTimer:Update(CS.UnityEngine.Time.unscaledDeltaTime * 1000)
		end
	end, self)
end

function UIGMView:_stopRuntimeTimer()
	if self._runtimeUpdateId then
		UpdateManager:GetInstance():RemoveUpdate(self._runtimeUpdateId)
		self._runtimeUpdateId = nil
	end
	if self._runtimeTimerId then self._runtimeTimer:Remove(self._runtimeTimerId) end
	self._runtimeTimerId, self._runtimeTimer = nil, nil
end

function UIGMView:OnClose()
	self._opened = false
	self:_stopRuntimeTimer()
	base.OnClose(self)
end

-- 顶栏 / 搜索 / 日志区按钮（AutoBind 字段，SetOnClick 自身幂等）
function UIGMView:_initHeader()
	self.mi_BtnMaster_Btn:SetOnClick(function()
		if self._listState == "error" then self:_loadItemPrefabs() end
	end)
	self.mi_BtnMaster_Btn:SetActive(false)
	self.mi_BtnFold_Btn:SetActive(false)
	self.mi_BtnLogFold_Btn:SetActive(false)
	self.m_Search_Ipt_Ipt:SetOnChanged(function()
		if self._destroyed then return end
		local ctrl = self:GetController()
		if ctrl and ctrl.OnGroupChanged then ctrl:OnGroupChanged() end
		self:_refreshLists()
	end)
	self.mi_BtnClose_Btn:SetOnClick(function()
		local ctrl = self:GetController()
		if ctrl and ctrl.OnCloseClicked then ctrl:OnCloseClicked() end
	end)
	self.mi_BtnClearSearch_Btn:SetOnClick(function()
		self.m_Search_Ipt_Ipt:SetText("", true)
		local ctrl = self:GetController()
		if ctrl and ctrl.OnGroupChanged then ctrl:OnGroupChanged() end
		self:_refreshLists()
	end)
	self.mi_BtnLogClear_Btn:SetOnClick(function() self:OnLogClearClicked() end)
	self.mi_BtnLogCopy_Btn:SetOnClick(function() self:OnLogCopyClicked() end)
end

function UIGMView:_initLists()
	self._catList = self:AddComponent(UIListView, self.m_CategoryList_Srt:GetScrollRect())
	self._catList.Refill = refillTopList
	self._catList:SetItemSize(CAT_ITEM_H, CAT_ITEM_GAP)
	self._catList:SetOnRefresh(function(go, index) self:_refreshCatItem(go, index) end)

	self._cmdList = self:AddComponent(UIListView, self.m_CmdList_Srt:GetScrollRect())
	self._cmdList.Refill = refillTopList
	self._cmdList:SetItemSize(CMD_ITEM_H, CMD_ITEM_GAP)
	self._cmdList:SetOnRefresh(function(go, index) self:_refreshCmdItem(go, index) end)
end

-- ---------------------------------------------------------------------------
-- item prefab（AB 侧资源，异步；两个都到齐后才建列表）
-- ---------------------------------------------------------------------------
function UIGMView:_loadItemPrefabs()
	if self._destroyed or self._loading then return end
	self._loading = true
	self._listState = "loading"
	self._loadGeneration = self._loadGeneration + 1
	local generation = self._loadGeneration
	self:_updateListState()
	local provider = getProvider()
	if not provider or not provider.LoadAsync then
		Logger.Warn("GM", "拿不到资源提供者，列表将为空")
		self._loading = false
		self._listState = "error"
		self:_updateListState()
		return
	end

	local pending = 2
	local assets, finished = {}, {}
	local function done(key, asset)
		if self._destroyed or generation ~= self._loadGeneration or finished[key] then return end
		finished[key], assets[key] = true, asset
		pending = pending - 1
		if pending == 0 then
			self._loading = false
			if IsNull(assets.cmd) or IsNull(assets.cat) then
				self._listState = "error"
				self:_updateListState()
			else
				self._cmdPrefab, self._catPrefab = assets.cmd, assets.cat
				self._listState = "ready"
				self:_applyPrefabs()
			end
		end
	end
	local function load(path, key)
		local ok, err = pcall(function()
			provider:LoadAsync(path, function(asset) done(key, asset) end)
		end)
		if not ok then Logger.Warn("GM", tostring(err)); done(key, nil) end
	end
	load(CMD_ITEM_PATH, "cmd")
	load(CAT_ITEM_PATH, "cat")
end

function UIGMView:_updateListState()
	local empty = self.transform:Find("m_Body/m_CmdList/m_Empty")
	local text = ""
	if self._listState == "loading" then text = "正在加载命令…"
	elseif self._listState == "error" then text = "命令加载失败，请点击重试"
	elseif #self._shownCmds == 0 then text = "没有匹配的命令" end
	if empty then
		empty.gameObject:SetActive(text ~= "")
		local tmp = TMP_TEXT and empty:GetComponent(typeof(TMP_TEXT))
		if tmp then tmp.text = text end
	end
	self.mi_BtnMaster_Btn:SetActive(self._listState == "error")
	if self._listState == "error" then self.mi_BtnMaster_Btn:SetText("重试") end
	if self._listState ~= "ready" then
		self.m_HitCount_Txt:SetText(self._listState == "error" and "加载失败" or "加载中")
	end
end

function UIGMView:_applyPrefabs()
	if self._destroyed then return end
	if self._cmdPrefab then self._cmdList:SetItemPrefab(self._cmdPrefab) end
	if self._catPrefab then self._catList:SetItemPrefab(self._catPrefab) end
	self._cmdList:SetItemSize(CMD_ITEM_H, CMD_ITEM_GAP)
	self._catList:SetItemSize(CAT_ITEM_H, CAT_ITEM_GAP)
	self.m_HitCount_Txt:SetText("")
	self:_refreshLists()
end

-- ---------------------------------------------------------------------------
-- 列表刷新
-- ---------------------------------------------------------------------------
function UIGMView:_showSelectedCategory()
	local list = self._catList
	if not list or not list.content or not list.viewport then return end
	local height = list.viewport.rect.height
	if height <= 0 then return end
	local index = 0
	for i, group in ipairs(self._groups or {}) do
		if group == self._curGroup then index = i; break end
	end
	local top = index * (CAT_ITEM_H + CAT_ITEM_GAP)
	local bottom = top + CAT_ITEM_H
	local y = list.content.anchoredPosition.y
	if top < y then y = top end
	if bottom > y + height then y = bottom - height end
	y = math.max(0, math.min(y, math.max(0, list.content.sizeDelta.y - height)))
	list.content.anchoredPosition = CS.UnityEngine.Vector2(list.content.anchoredPosition.x, y)
	list:Refill()
	list:RefreshAll()
end

function UIGMView:_refreshLists()
	if self._destroyed then return end
	local keyword = tostring(self.m_Search_Ipt_Ipt:GetText() or ""):lower()
	self._groups = collectGroups()
	if self._curGroup ~= ALL_GROUP then
		local found = false
		for _, group in ipairs(self._groups) do if group == self._curGroup then found = true end end
		if not found then self._curGroup = ALL_GROUP end
	end

	self._shownCmds = {}
	local matched = 0
	-- 渲染走 VisibleList（§12.1 第 1 层门控）：devOnly 命令在 release 包连列表都不进
	--
	-- 容量上限 cmdListMaxItems=500（§8.1）：列表最多装 500 条。就地截断而不是「全量
	-- 装进来再让 UIListView 自己裁」—— 前者 _syncDangerBtn / _idxOfGO / _cmdCompCache
	-- 全都只认前 500 条，不会出现「命中 800 条但只有 500 条能点」；后者还会白建
	-- 500 份以上用不上的 index 映射。matched 仍然数全量命中，好让 HitCount 说清楚
	-- 「共 N 条（仅显示前 500）」，而不是把数字悄悄改成 500 骗人。
	local capItems = GMUIConfig.Capacity.cmdListMaxItems
	for _, cmd in ipairs(GMCommands.VisibleList()) do
		if self._curGroup == ALL_GROUP or groupOf(cmd) == self._curGroup then
			local matches = keyword == ""
			for _, field in ipairs({ "label", "id", "group", "desc" }) do
				if tostring(cmd[field] or ""):lower():find(keyword, 1, true) then matches = true end
			end
			if matches then
				if matched < capItems then self._shownCmds[matched + 1] = cmd end
				matched = matched + 1
			end
		end
	end

	local shown = math.min(matched, capItems)
	self._idxOfGO = {}
	if self._cmdList.content then
		self._cmdList.content.anchoredPosition = CS.UnityEngine.Vector2(self._cmdList.content.anchoredPosition.x, 0)
	end
	self._catList:SetCount(#self._groups + 1)
	self._cmdList:SetCount(shown)
	-- SetCount → Refill 只给【新取出的】item 回调 onRefresh（UIListView.lua:134-141），
	-- 被复用的旧 item 不回调 —— 于是「全部(11条) → ⚠高级(1条)」时 index 0 那条是复用出来的，
	-- 它身上的 InputField 还留着 prefab 的 m_CharacterLimit=3，用户在这行敲代码最多只能敲 3 个字
	-- （真机探针：limit 停在 3、SetText 读回来是 'loc'），advanced.run_lua 唯一的数据通路直接废掉。
	-- 每次换分类/换搜索词后把所有可视 item 重刷一遍，复用行也拿回本条命令该有的外观与参数值。
	self._cmdList:RefreshAll()
	self._catList:RefreshAll()
	self:_showSelectedCategory()
	self.m_HitCount_Txt:SetText(matched > capItems
		and string.format("共 %d 条（仅显示前 %d）", matched, capItems)
		or ("共 " .. shown .. " 条"))
	self:_updateListState()
end

-- ============================================================================
-- item 组件「只建一次」缓存（真机探针实证，勿改回）
--
-- UIBaseContainer.components 是「节点名 -> 组件类 -> 组件实例」的扁平表，
-- RecordComponent 对同名节点直接 assert（Already exist component_class : UIText, name:m_CmdName）。
-- 虚拟列表里【两个不同 item GO 的子节点同名】（都叫 m_CmdName / mi_BtnExec / m_Desc），
-- 若每次 _refreshCmdItem 都 self:AddComponent(...)，第二个 item 必然炸。
-- 因此：每个 item GO 首次刷新时把它的组件 AddComponent 一次并存起来，之后
-- RefreshAll / Refill 反复调用只「更新值」、不再 AddComponent —— 顺带保证
-- SetOnClick 每个 item GO 只绑一次（_cmdCompCache 同时也是「只绑一次」的标记表）。
--
-- 上面那一段只解决「同一个 GO 别重复建」，还差一刀：AddComponent 自己会撞。
-- 面板级 components 是「节点名 -> 类 -> 实例」的扁平表，同名同类只许记一次，
-- 而虚拟列表里每个 item GO 的子节点【同名】，所以从第 2 个 item 起
-- self:AddComponent 必定撞上 RecordComponent 的 assert
-- （Already exist component_class : UIText, name:m_CmdName）。
-- 本文件里【所有】item 子节点的 AddComponent 一律走 UIGMView:_ownComp，
-- 别再直接写 self:AddComponent（五处复制粘贴正是这次事故的踩坑方式）。
-- 面板初始化里的 self:AddComponent(UIListView, ...) 不在此列 —— 那是面板级常驻组件。
-- ============================================================================
function UIGMView:_ownComp(cls, unityComp)
	-- 组件是按 GO 记的：先看这条记录是不是【本 GO】自己的，是就直接复用。
	-- 不能不加判断就取 —— 同名子节点（每个 item GC 都叫 m_CmdName / m_Desc /
	-- mi_BtnExec / mi_BtnFav / m_Param_Ipt / m_CatLabel）在面板级 components 里
	-- 只有一格，直接 GetComponent 拿到的可能是【上一行 item】的壳子，它的
	-- __uiComp 指向别行的 Text，拿它 SetText 等于把文字写到错误的行 ——
	-- 比 assert 炸掉更阴，是静默错。
	local go = unityComp and unityComp.gameObject
	if not go then return nil end
	local got = self:GetComponent(go.name, cls)
	if got and got.gameObject == go then return got end
	-- 记录属于别的 GO（或压根没有）：先把这一格腾空，再按当前 GO 重新注册。
	-- 摘记录不能走 RemoveComponent —— 它会 Delete 旧组件对象，而被 PrefabPool
	-- 回收复用的 GO 的 _cmdCompCache 还指着这个半死的壳子（OnDestroy 把
	-- __uiComp 清了，SetText 会当场抛）。这里只把登记清掉，对象留着不删。
	local rec = self.components and self.components[go.name]
	if rec then rec[cls] = nil end
	local comp = self:AddComponent(cls, unityComp)
	self._ownedItemComps[#self._ownedItemComps + 1] = comp
	return comp
end

function UIGMView:_cmdComp(go)
	local id = go:GetInstanceID()
	local c = self._cmdCompCache[id]
	if c then return c end
	c = {}
	self._cmdCompCache[id] = c
	CJKFont.ApplyAll(go.transform)   -- S9：item 内 TMP 同样丢纹理，建组件时一并换字体

	local nameGO = child(go, "m_CmdName")
	local nameComp = nameGO and textComp(nameGO)
	if nameComp then c.name = self:_ownComp(UIText, nameComp) end

	local descGO = child(go, "m_Desc")
	local descComp = descGO and textComp(descGO)
	if descComp then c.desc = self:_ownComp(UIText, descComp) end

	local iptGO = childPath(go, "m_ParamSlot/m_Param_Ipt")
	local iptComp = iptGO and inputComp(iptGO)
	if iptComp then
		c.ipt = self:_ownComp(UIInputField, iptComp)
		c.ipt:SetOnChanged(function(value)
			if not self._destroyed and c.cmdId then self._drafts[c.cmdId] = tostring(value or "") end
		end)
	end

	local execGO = child(go, "mi_BtnExec")
	local execComp = execGO and btnComp(execGO)
	if execComp then
		c.exec = self:_ownComp(UIButton, execComp)
		if c.exec then c.exec:SetOnClick(function() self:_execById(id) end) end
	end

	local favGO = child(go, "mi_BtnFav")
	if favGO then favGO:SetActive(false) end

	return c
end

-- 分类项文案
-- Root Button callback follows the current group when the GO is reused.
function UIGMView:_refreshCatItem(go, index)
	if not go then return end
	local name = index == 0 and ALL_GROUP or (self._groups[index] or "?")
	local id = go:GetInstanceID()
	local c = self._catCompCache[id]
	if not c then
		c = {}
		self._catCompCache[id] = c
		local labelGO = child(go, "m_CatLabel")
		local labelComp = labelGO and textComp(labelGO)
		if labelComp then
			CJKFont.Apply(labelComp)   -- S9：分类项 TMP 换 Resources 字体
			c.txt = self:_ownComp(UIText, labelComp)
		end
		local button = btnComp(go)
		if button then
			c.btn = self:_ownComp(UIButton, button)
			c.color0 = button.image and button.image.color
			c.btn:SetOnClick(function()
				if not self._destroyed then self:SelectGroup(c.group) end
			end)
		end
	end
	c.group = name
	if c and c.txt then c.txt:SetText(name) end
	local label = c.txt and c.txt:GetUnityText()
	if label then label.color = name == self._curGroup and COLOR_CAT_SELECTED_LABEL or COLOR_CAT_LABEL end
	local btn = c.btn and c.btn:GetUnityButton()
	if btn and btn.image then btn.image.color = name == self._curGroup and COLOR_SELECTED or c.color0 end
end

-- ---------------------------------------------------------------------------
-- 危险行「执行键」的两态外观（§12.2）
--   pending：底色 #CC3333 + 文案「确认执行？」；常态：还原 prefab 原色 + 「执行」
-- Only update button visuals here; drafts and row mappings stay intact.
-- Cache the original image color before entering confirmation.
-- ---------------------------------------------------------------------------
local function execImageOf(c)
	local btn = c and c.exec and c.exec.GetUnityButton and c.exec:GetUnityButton()
	return (btn and btn.image) or nil
end

-- Explicit input lengths, independent from numeric range validation.
local function _charLimitOf(cmd)
	local p = cmd and cmd.params and cmd.params[1]
	if p and p.type == "string" then return math.max(1, tonumber(p.max) or 2000) end
	-- Numeric max is a value bound, never a character count (sign/decimal allowed).
	if p and (p.type == "int" or p.type == "number" or p.type == "float") then return 64 end
	return 2000
end

-- 写成模块级局部函数而不是方法：它只操作 item 组件缓存里的那几个引用，不碰 self，
-- 而 luacheck 会给每个 `function Class:xxx()` 误插一个隐式 self 并报 unused-argument。
local function _applyExecVisual(c, isPending)
	if not c or not c.exec then return end
	local img = execImageOf(c)
	if isPending then
		if c.execColor0 == nil and img then c.execColor0 = img.color end
		c.exec:SetText(DANGER_BTN_TEXT)
		if img and c.execColor0 then img.color = COLOR_DANGER end
	else
		if img and c.execColor0 then img.color = c.execColor0 end
		c.exec:SetText(NORMAL_BTN_TEXT)
	end
end

---Controller 在「进入 / 退出待确认」时调，把所有危险行刷成目标态（条目数 ≤ 11，全量刷便宜）
function UIGMView:_syncDangerBtn()
	for listIndex, cmd in ipairs(self._shownCmds or {}) do
		if cmd then
			local go = self._cmdList and self._cmdList:GetItem(listIndex - 1)
			local c = go and self._cmdCompCache[go:GetInstanceID()]
			_applyExecVisual(c, cmd.danger and cmd.id == self._pendingCmdId)
		end
	end
end

-- ---------------------------------------------------------------------------
-- 日志区（S8 容量上限 §8.1）
-- m_LogTip keeps its binder name under m_LogScroll/Content; the prefab's
-- ScrollRect and ContentSizeFitter provide scrolling and preferred height.
-- ---------------------------------------------------------------------------
function UIGMView:RefreshLog()
	if not self.m_LogTip_Txt then return end
	local lines = GMLog.GetTextLines(GMUIConfig.Capacity.logDisplayMax)
	self.m_LogTip_Txt:SetText(#lines > 0 and table.concat(lines, "\n") or "暂无执行记录")
end

---Controller 通知：某条危险命令进入待确认（按钮变红 + 文案改「确认执行？」）
function UIGMView:SetExecPending(cmdId)
	self._pendingCmdId = cmdId
	self:_syncDangerBtn()
end

---Controller 通知：超时 / 切分类 / 关面板 / 已执行 ⇒ 回常态
function UIGMView:SetExecNormal()
	self._pendingCmdId = nil
	self:_syncDangerBtn()
end

-- 指令项刷新：只更新 index 映射 / 文案 / 参数控件值（禁 AddListener）
function UIGMView:_refreshCmdItem(go, index)
	if not go then return end
	local cmd = self._shownCmds[index + 1]
	if not cmd then return end

	self._idxOfGO[go:GetInstanceID()] = index

	local c = self:_cmdComp(go)
	c.cmdId = cmd.id
	if c.name then c.name:SetText(cmd.label or "?") end
	if c.desc then c.desc:SetText(cmd.desc or groupOf(cmd)) end

	-- 参数控件：按 cmd.input 决定是否显示输入框（GMCommands 未声明 toggle/slider，不擅自加语义）
	local showIpt = cmd.input ~= nil and cmd.input ~= false
	local slotGO = child(go, "m_ParamSlot")
	if slotGO then slotGO:SetActive(showIpt) end
	local iptGO = childPath(go, "m_ParamSlot/m_Param_Ipt")
	if iptGO then iptGO:SetActive(showIpt) end
	if showIpt and c.ipt then
		-- Set the limit first: Unity truncates text immediately on assignment.
		local lim = _charLimitOf(cmd)
		c.ipt:SetCharacterLimit(lim)
		local value = self._drafts[cmd.id]
		if value == nil then
			local p = cmd.params and cmd.params[1]
			value = cmd.inputDefault
			if value == nil and p then value = p.default end
			if value == nil then value = type(cmd.input) == "string" and cmd.input or "" end
		end
		c.ipt:SetText(tostring(value), true)
		self._drafts[cmd.id] = tostring(c.ipt:GetText() or "")
	end

	-- 危险行：item 被虚拟列表回收重刷时，也要把「待确认」态带过去，不能刷成常态
	_applyExecVisual(c, cmd.danger and cmd.id == self._pendingCmdId)
end

function UIGMView:_execById(id)
	if self._destroyed or not self._opened then return end
	local index = self._idxOfGO[id]
	local cmd = index ~= nil and self._shownCmds and self._shownCmds[index + 1]
	if not cmd then return end
	local go = self._cmdList and self._cmdList:GetItem(index)
	if not go or go:GetInstanceID() ~= id then return end
	local value, err = self:_readParamValue(index)
	if err then
		local ctrl = self:GetController()
		if ctrl and ctrl.OnGroupChanged then ctrl:OnGroupChanged() end
		self:SetStatus(err)
		return
	end
	local ctrl = self:GetController()
	if ctrl and ctrl.Execute then ctrl:Execute(cmd, value) end
end

---取第 index 个 item 上输入框里解析出的参数值（无输入框返回 nil，由 cmd.fn 内部兜底）
-- 复用 _cmdComp 缓存里的 InputField：不重新 AddComponent（同名子节点会撞 assert），
-- 也不要把 GameObject 当 var_arg 传进去（会把 GO 塞进 __uiComp，GetText 恒返回 ""）
--
-- Only explicitly numeric types are parsed; enum/raw/code keep their text.
function UIGMView:_readParamValue(index)
	local cmd = self._shownCmds and self._shownCmds[index + 1]
	if not cmd or not cmd.input then return nil end
	local go = self._cmdList and self._cmdList:GetItem(index)
	local c = go and self._cmdCompCache[go:GetInstanceID()]
	local ipt = c and c.ipt
	if not ipt or c.cmdId ~= cmd.id then return nil, "参数输入框不可用" end
	local txt = tostring(ipt:GetText() or "")
	self._drafts[cmd.id] = txt
	local p = cmd and cmd.params and cmd.params[1]
	if not p or (p.type ~= "int" and p.type ~= "number" and p.type ~= "float") then return txt end
	local value = tonumber(txt)
	if not value or value ~= value or value == math.huge or value == -math.huge
		or (p.type == "int" and value % 1 ~= 0) then return nil, "请输入有效" .. (p.type == "int" and "整数" or "数值") end
	if (p.min and value < p.min) or (p.max and value > p.max) then return nil, "参数超出允许范围" end
	return value
end


-- ---------------------------------------------------------------------------
-- 分组选择
-- ---------------------------------------------------------------------------
function UIGMView:SelectGroup(name)
	if self._curGroup == name then return end
	self._curGroup = name
	-- 切分类立即取消待确认（§12.2 取消时机之一）：换分类后那行按钮所在的列表就要重建，
	-- 不主动回常态的话「再点一次」会命中已经被刷掉的 item，状态与画面对不上
	local ctrl = self:GetController()
	if ctrl and ctrl.OnGroupChanged then ctrl:OnGroupChanged() end
	self:_refreshLists()
end

---Controller 回写执行反馈（字段来自 AutoBind，零 Find）
function UIGMView:SetStatus(msg)
	if self._destroyed then return end
	local text = tostring(msg or "")
	self.m_Summary_Txt_Txt:SetText(text)
	if text ~= "" then GMLog.Append("info", "GM", "状态", text) end
	self:RefreshLog()
end

-- Clearing must leave the buffer empty, so its UI feedback is not appended.
function UIGMView:OnLogClearClicked()
	GMLog.Clear()
	self:RefreshLog()
	self.m_Summary_Txt_Txt:SetText("日志已清空")
end

-- Copy the data source, even if the displayed text has not refreshed yet.
function UIGMView:OnLogCopyClicked()
	local text = table.concat(GMLog.GetTextLines(GMUIConfig.Capacity.logDisplayMax), "\n")
	local msg = GMCommands.CopyLog(text)
	self:SetStatus(msg or "复制失败")
end

-- ---------------------------------------------------------------------------
-- 探针辅助（真机注入脚本用）
-- ---------------------------------------------------------------------------
---AutoBind 漏绑的字段数，必须为 0
function UIGMView:BindFieldNilCount()
	local hit = 0
	for _, name in ipairs(EXPECT_FIELDS) do
		if self[name] == nil then hit = hit + 1 end
	end
	return hit
end

---已建过组件的 item GO 实例数（用来断言「只建/只绑一次」）
function UIGMView:ItemBoundCount()
	local n = 0
	for _ in pairs(self._cmdCompCache or {}) do n = n + 1 end
	return n
end

function UIGMView:OnDestroy()
	self._destroyed = true
	self._opened = false
	self._loadGeneration = (self._loadGeneration or 0) + 1
	self:_stopRuntimeTimer()
	-- _ownComp detaches same-name registrations during reuse: delete all owned
	-- wrappers once, including those no longer reachable by the base container.
	for _, comp in ipairs(self._ownedItemComps or {}) do
		local rec = self.components and self.components[comp.gameObject.name]
		if rec then
			for cls, registered in pairs(rec) do if registered == comp then rec[cls] = nil end end
		end
		comp:Delete()
	end
	self._ownedItemComps = {}
	self._cmdCompCache = {}
	self._catCompCache = {}
	self._idxOfGO = {}
	base.OnDestroy(self)
end

return UIGMView
