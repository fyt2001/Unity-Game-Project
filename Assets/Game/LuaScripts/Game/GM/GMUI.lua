--[[
=============================================================================
GMUI.lua - GM 调试工具入口（热键触发，面板本体为框架动态窗口）
=============================================================================
说明：
  - GM 面板本体是规范的框架窗口 "GM"（prefab + MVC，见 Game.UI.GM.*，
    由 RegisterGM 注册，UIManager 动态加载）——不挂场景、不手动 new GameObject。
  - 本文件只负责【入口与开关】，不再在场景里直接创建 Canvas / 入口按钮：
      * Ctrl+G：开关 GM 窗口（门控统一走 GMConfig.CanOpenPanel()）
      * Ctrl+Shift+G：持久化翻转 GM 开关（供 QA 出包后启用）
  - 热键用 Input 轮询（不依赖 EventTrigger），通过 UIManager 打开/关闭 "GM" 窗口。
  - 仅保留 EventSystem 兜底（场景没有时补一个全局安全网）；全局安全网之外只额外运行时裸建一个
    dev 角标 GMBadge（见 _ensureBadge），面板本体仍然不挂场景。
  - "能不能开 GM" 只有 CanOpenPanel() 一个出口（GMConfig），本文件不再自己写 IsDev() 判断。
=============================================================================
]]

local Logger   = require "Framework.UI.Utils.Logger"
local GMConfig = require "Game.GM.GMConfig"
local GMUnlock = require "Game.GM.GMUnlock"

local Input      = CS.UnityEngine.Input
local Object     = CS.UnityEngine.Object
local GameObject = CS.UnityEngine.GameObject
local UIButton   = CS.UnityEngine.UI.Button
local UIText     = CS.UnityEngine.UI.Text
local ES         = CS.UnityEngine.EventSystems

-- Explicit enums avoid reflection choosing a stripped string overload in Players.
local KeyCode = CS.UnityEngine.KeyCode
local KC_LEFTCTRL, KC_RIGHTCTRL, KC_LEFTSHIFT, KC_G =
	KeyCode.LeftControl, KeyCode.RightControl, KeyCode.LeftShift, KeyCode.G

local GMUI = {}

local _inited = false

-- dev 角标：运行时裸建的 GO + Image + Button + Text（不建 prefab、不走 AB、不挂场景）
local _badgeGO, _badgeImg = nil, nil
local _closingWindow = nil

-- 取 UIManager 单例（GameMain 已初始化 UI 后才轮询到）
local function _getUI()
	local ok, gm = pcall(require, "Game.GameMain")
	if ok and gm then return gm.GetUIManager() end
	return nil
end

local function _getUpdateManager()
	local UpdateManager = require "Framework.Core.UpdateManager"
	return UpdateManager:GetInstance()
end

-- EventSystem 兜底：场景没 EventSystem 时补一个（全局安全网，非面板本身）
local function _ensureEventSystem()
	local ok = pcall(function()
		if Object.FindObjectOfType(typeof(ES.EventSystem)) then return end
		local go = GameObject("GMEventSystem")
		assert(go:AddComponent(typeof(ES.EventSystem)), "EventSystem creation failed")
		assert(go:AddComponent(typeof(ES.StandaloneInputModule)), "Input module creation failed")
		Object.DontDestroyOnLoad(go)
	end)
	if not ok then
		Logger.Warn("GM", "EventSystem 自动创建失败，依赖场景自带 EventSystem")
	end
end

-- ---------------------------------------------------------------------------
-- dev 角标（D3 定稿：固定角标、不可拖拽，语义只有「开关 GM 面板」一种）
-- ---------------------------------------------------------------------------
-- Popup 层根 Transform：UI 层由 UILayerManager 在 UIRoot 下建好并挂 Canvas，
-- 直接从 UIManager 的 layerManager 取，比「开一次 GM 窗口再取它的父节点」更轻（不产生开门副作用）。
-- 拿不到就返回 nil，由 _ensureBadge 下一拍重试。
local function _getPopupRoot()
	local ui = _getUI()
	if not ui then return nil end
	local ok, root = pcall(function()
		local layerMgr = ui.layerManager
		if not layerMgr or not layerMgr:HasLayer("Popup") then return nil end
		return layerMgr:GetLayer("Popup").root
	end)
	if ok then return root end
	return nil
end

---角标高亮：面板开着时底色从 a=0.85 加深到 1.0（纯视觉变化）。
-- 文案恒为 "GM"，不做 ×/✓ 态切换 —— 角标同时是「入口」和「开关」，再加一套收起态会语义打架。
local function _refreshBadgeVisual()
	if not _badgeImg or IsNull(_badgeImg) then return end
	local ui = _getUI()
	local open = ui and ui:IsOpen("GM") and true or false
	_badgeImg.color = CS.UnityEngine.Color(0.06, 0.07, 0.1, open and 1.0 or 0.85)
end

---创建 / 复用 dev 角标（幂等：重复调用只会有一帧建 GO）。
-- 解锁发生在 Login 面板，与 GMUI.Init() 的先后不确定，所以由 _onUpdate 每拍调，
-- 拿得到 Popup 层就建、拿不到就安静地等下一拍，绝不抛错打断主循环。
local function _ensureBadge()
	if _badgeGO and not IsNull(_badgeGO) then
		_badgeGO:SetActive(true)
		_refreshBadgeVisual()
		return
	end
	local root = _getPopupRoot()
	if not root then return end

	-- GO 建在 pcall 外面：失败时 finally 要能 DestroyImmediate 掉这个半成品 GO
	local go = GameObject("GMBadge")
	_badgeGO, _badgeImg = go, nil

	local ok, err = pcall(function()
		local cs = go:AddComponent(typeof(CS.UnityEngine.Canvas))
		cs.renderMode = CS.UnityEngine.RenderMode.ScreenSpaceOverlay
		go:AddComponent(typeof(CS.UnityEngine.UI.GraphicRaycaster))

		local rt = go:GetComponent(typeof(CS.UnityEngine.RectTransform))
		rt.sizeDelta = CS.UnityEngine.Vector2(88, 88)
		rt:SetParent(root, false)

		local img = go:AddComponent(typeof(CS.UnityEngine.UI.Image))
		_badgeImg = img
		img.color = CS.UnityEngine.Color(0.06, 0.07, 0.1, 0.85)
		local btn = go:AddComponent(typeof(UIButton))
		btn.targetGraphic = img
		-- 点角标 = 开关面板（角标自己不关自己，关/折叠交给面板的 mi_BtnClose / mi_BtnFold）
		btn.onClick:AddListener(function() GMUI.TogglePanel() end)

		-- 文案必须挂在【子节点】上：UnityEngine.UI.Text 与 Image 同为 Graphic 子类，
		-- Unity 禁止同一 GO 并存两个 Graphic —— 同节点直接挂会被 AddComponent 静默拒（只打日志返 nil，
		-- 不抛异常），表现是白字渲染不出来、只剩深底方块（真机复现过，别改回同节点）。
		local tGo = GameObject("GMText")
		local tRt = tGo:AddComponent(typeof(CS.UnityEngine.RectTransform))
		tRt:SetParent(rt, false)          -- fill parent：撑满父级 88x88 的点击/渲染区
		tRt.anchorMin = CS.UnityEngine.Vector2(0, 0)
		tRt.anchorMax = CS.UnityEngine.Vector2(1, 1)
		tRt.offsetMin = CS.UnityEngine.Vector2(0, 0)
		tRt.offsetMax = CS.UnityEngine.Vector2(0, 0)
		local t = tGo:AddComponent(typeof(UIText))
		-- 运行时 AddComponent 出来的 Text 字体是 null（一句都不渲染），必须补一个内置字体
		local font = CS.UnityEngine.Resources.GetBuiltinResource(typeof(CS.UnityEngine.Font), "Arial.ttf")
		if font then t.font = font end
		t.text = "GM"
		t.fontSize = 28
		t.color = CS.UnityEngine.Color(1, 1, 1, 1)
		t.alignment = CS.UnityEngine.TextAnchor.MiddleCenter
	end)

	if not ok then
		-- 关键：必须把 _badgeGO 清 nil，否则下一拍走幂等分支直接 return，永远重试不出来
		_badgeGO = nil
		_badgeImg = nil
		Object.DestroyImmediate(go)      -- 半成品 GO 会重复参与 raycast
		Logger.Warn("GM", "dev 角标创建失败，下一拍重试：%s", tostring(err))
		return
	end

	go:SetActive(true)
	_refreshBadgeVisual()
end

-- ---------------------------------------------------------------------------
-- 开关 GM 框架窗口（面板由 UIManager 动态加载，不挂场景）
-- ---------------------------------------------------------------------------
local function _isClosingPanel()
	if not _closingWindow then return false end
	if _closingWindow:IsClosed() or _closingWindow:IsDestroyed() then
		_closingWindow = nil
		return false
	end
	return true
end

function GMUI.OpenPanel()
	if not GMConfig.CanOpenPanel() or _isClosingPanel() then return end
	local ui = _getUI()
	if ui and not ui:IsOpen("GM") then ui:Open("GM") end
end

function GMUI.ClosePanel()
	local ui = _getUI()
	if not ui or not ui:IsOpen("GM") or _isClosingPanel() then return end
	local window = ui:GetWindow("GM")
	local ctrl = window and window:GetController()
	if ctrl and ctrl.OnPanelClosing then ctrl:OnPanelClosing() end
	_closingWindow = window
	ui:Close("GM")
end

function GMUI.TogglePanel()
	if not GMConfig.IsDev() then return end
	local ui = _getUI()
	if not ui then return end
	if ui:IsOpen("GM") then GMUI.ClosePanel() else GMUI.OpenPanel() end
end

function GMUI.SetPanelOpen(open)
	if open then GMUI.OpenPanel() else GMUI.ClosePanel() end
end

-- ---------------------------------------------------------------------------
-- 每帧轮询：热键（不再处理入口按钮拖拽/点击，那是场景挂载，已移除）
-- ---------------------------------------------------------------------------
local function _onUpdate()
	-- Reconcile the new gate in this frame, including a disable hotkey.
	if Input.GetKey(KC_LEFTCTRL)
	   and Input.GetKey(KC_LEFTSHIFT)
	   and Input.GetKeyDown(KC_G) then
		GMConfig.ToggleEnabled()
		Logger.Info("GM", "GM 已" .. (GMConfig.IsEnabled() and "启用" or "禁用"))
	end
	-- Ctrl+G：开关 GM 窗口（仅启用时）
	if GMConfig.CanOpenPanel()
	   and Input.GetKey(KC_LEFTCTRL)
	   and not Input.GetKey(KC_LEFTSHIFT)
	   and Input.GetKeyDown(KC_G) then
		GMUI.TogglePanel()
	end
	-- 门控为真的每一拍都复查角标（幂等）：解锁发生在 Login 面板，早于/晚于 Init 都不确定，
	-- 而且场景切换会连带把角标 GO 销毁，每拍重试才能自愈。
	if GMConfig.CanOpenPanel() then
		_ensureBadge()
	else
		if _badgeGO and not IsNull(_badgeGO) then _badgeGO:SetActive(false) end
		-- Do not route incomplete/loading windows through the cache-on-close path.
		GMUI.ClosePanel()
	end
end

local function _registerHotkey()
	local updateMgr = _getUpdateManager()
	if not updateMgr then return end
	updateMgr:AddUpdate(_onUpdate, "GMHotkey")
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------
function GMUI.Init()
	if _inited then return end
	if not GMConfig.IsDev() then return end
	_inited = true
	_ensureEventSystem()
	GMUnlock.Init()
	_registerHotkey()        -- 热键无条件注册，Ctrl+G 的「能不能开」在 _onUpdate 里统一走 CanOpenPanel
	Logger.Info("GM", "GM 工具已初始化（Ctrl+G 开关面板，Ctrl+Shift+G 切换启用；面板为框架动态窗口，不挂场景）")
end

return GMUI
