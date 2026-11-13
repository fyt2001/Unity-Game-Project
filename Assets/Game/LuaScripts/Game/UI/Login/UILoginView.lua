--[[
=============================================================================
UILoginView.lua - 登录面板视图（对齐 ShaoNvClient_H02 UILoginView）
=============================================================================
Module:     Game/UI/Login/UILoginView
Version:    4.0.0（对齐 H02：继承 UIView 组件容器，使用 AddComponent 写法）
Description:
	组件命名对齐 H02 的 m_ 前缀规范。
	组件经 prefab 上 UIComponentBinder 自动绑定（AutoBind 零 Find），
	View 销毁时由 UIView(UIBaseContainer) 自动 Delete 子组件，清理监听。

	Prefab 结构（复制自 ShaoNvClient_H02 UILogin.prefab）:
		UILogin (root)
		├── BgRoot
		├── ContentRoot
		│   ├── m_LoginBtn      (Button)
		│   ├── m_Loading        (Node)
		│   ├── SvrRoot
		│   │   └── m_SvrSelectBtn -> m_SvrText
		│   ├── m_AppVersionText
		│   ├── m_ResVersionText
		│   ├── m_VersionContent
		│   ├── m_BtnTerms
		│   └── m_BtnPrivacy
		├── BgRoot
		└── PopUpRoot
	（注：prefab 无 PolicyRoot 节点，原先的 _policyRoot / SetPolicyRootVisible 已按死代码移除）

	S6 加了一个版本号热区叶子节点 mi_BtnVersion（挂在 m_VersionContent 下，Image alpha 0 + Button）：
	连点 5 次即解锁 GM（release 包没有 dev 角标，这是唯一本地入口），见 _bindVersionHotspot。
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"
local Lang = require "Framework.UI.Utils.Lang"
local Logger = require "Framework.UI.Utils.Logger"
local UIButton = require "Framework.UI.Component.UIButton"
local GMUnlock = require "Game.GM.GMUnlock"
local GMConfig = require "Game.GM.GMConfig"

-- 解锁回显后缀（贴在版本号文本尾部，让玩家/QA 一眼看到「release 也开了」）
local UNLOCK_TAG = "[GM ON]"

local UILoginView = BaseClass("UILoginView", UIView)
local base = UIView

function UILoginView:OnCreate()
	CS.UnityEngine.Debug.Log("[LoginPanel][view] UILoginView:OnCreate 开始")
	base.OnCreate(self)   -- AutoBind 已按 prefab 上 UIComponentBinder 注入的引用零 Find 建好各组件（对齐 H02）
	require("Framework.UI.Utils.CJKFont").ApplyAll(self.gameObject.transform)

	-- 纯 AutoBind（对齐 H02 设计意图）：prefab 已绑定全部组件，直接读注入字段，零 Find
	self._loginBtn       = self.m_LoginBtn_Btn
	self._svrSelectBtn   = self.m_SvrSelectBtn_Btn
	self._btnTerms       = self.m_BtnTerms_Btn
	self._btnPrivacy     = self.m_BtnPrivacy_Btn
	self._closeBtn       = self.m_BtnClose_Btn
	self._svrText        = self.m_SvrText_Txt
	self._appVersionText = self.m_AppVersionText_Txt
	self._resVersionText = self.m_ResVersionText_Txt
	self._versionContent = self.m_VersionContent_Txt
	local legalFont = CS.UnityEngine.Resources.Load("Fonts/EntryLegalSDF", typeof(CS.TMPro.TMP_FontAsset))
	if legalFont then
		local labels = self.gameObject:GetComponentsInChildren(typeof(CS.TMPro.TextMeshProUGUI), true)
		for i = 0, labels.Length - 1 do labels[i].font = legalFont end
	end
	self._loading        = self.m_Loading_Transform
	self._title          = self.m_Title_Txt
	self._charImg        = self.m_Char_RawImg   -- 3D 角色（Spike）经 LaunchScene 的 LoginCharCam 渲染到 RenderTexture，由该 RawImage 显示

	self:_bindVersionHotspot()   -- 版本号热区 → GMUnlock 连点解锁（release 包打开面板的唯一通道）

	self._popupRoot  = self:FindGameObject("PopUpRoot")
	self._bgRoot     = self:FindGameObject("BgRoot")
	CS.UnityEngine.Debug.Log("[LoginPanel][view] UILoginView:OnCreate 完成; _loginBtn=" .. tostring(self._loginBtn))
end

-- =============================================================================
-- 版本号热区：连点 5 次解锁 GM（release 包没有 dev 角标，这是唯一的本地入口）
-- =============================================================================
---绑定版本号热区（三级降级，全为了 prefab 还没打到时也能独立跑通）：
--  ① AutoBind 已注入的 mi_BtnVersion_Btn（prefab 加了 mi_BtnVersion 节点并写进 UICompList 后才有）
--  ② 手动 AddComponent(UIButton, "mi_BtnVersion")（按名字深搜节点，走字符串路径不会把 GO 塞进 __uiComp）
--  ③ 都拿不到 —— prefab 尚未加节点，静默跳过，只 Info 一次，绝不 Warn 刷屏
function UILoginView:_bindVersionHotspot()
	local btn = self.mi_BtnVersion_Btn
	if not btn then
		-- 深搜不到节点时 UIBaseContainer 内部会 assert，包一层 pcall 让「节点还没建」不炸 OnCreate
		local ok, inst = pcall(function() return self:AddComponent(UIButton, "mi_BtnVersion") end)
		btn = ok and inst or nil
	end
	if not btn then
		if not self._versionHotspotMissing then
			self._versionHotspotMissing = true
			Logger.Info("GM", "版本号热区 mi_BtnVersion 未绑定（prefab 未加节点），连点解锁暂不可用")
		end
		return
	end
	-- 走 UIButton:SetOnClick 而不是裸 onClick:AddListener：自带「先 Remove 再 Add」的幂等语义，
	-- 且 OnDestroy 会 RemoveClick —— 连点这种一按就触发的回调不能靠裸 AddListener 累积监听。
	btn:SetOnClick(function() self:_onVersionTapped() end)
end

---版本号被点了一下：转给 GMUnlock 计数，只有解锁成功才回显 UNLOCK_TAG。
function UILoginView:_onVersionTapped()
	local ok, unlocked = pcall(GMUnlock.OnVersionTapped)
	if not ok then unlocked = false end
	if not unlocked then return end
	-- IsUnlockedByTaps 守卫：解锁是持久的，回显只追加一次，再点也不会往上叠
	if not GMConfig.IsUnlockedByTaps() then return end
	if not self._versionContent then return end
	local text = self._versionContent:GetText() or ""
	if not text:find(UNLOCK_TAG, 1, true) then
		self._versionContent:SetText(text .. " " .. UNLOCK_TAG)
	end
end

function UILoginView:OnOpen(serverName, appVersion, resVersion)
	if self._svrText then self._svrText:SetText(serverName) end
	if self._appVersionText then self._appVersionText:SetText(Lang.Get("app_ver") .. (appVersion or "")) end
	if self._resVersionText then self._resVersionText:SetText(Lang.Get("res_ver") .. (resVersion or "")) end
end

-- =============================================================================
-- 组件访问器（返回组件包装实例）
-- =============================================================================
function UILoginView:GetLoginButton()
	return self._loginBtn
end

function UILoginView:GetServerSelectButton()
	return self._svrSelectBtn
end

function UILoginView:GetCloseButton()
	return self._closeBtn
end

function UILoginView:GetTermsButton()
	return self._btnTerms
end

function UILoginView:GetPrivacyButton()
	return self._btnPrivacy
end

function UILoginView:GetPopUpRoot()
	return self._popupRoot
end

-- =============================================================================
-- 状态设置
-- =============================================================================
function UILoginView:SetServerText(text)
	if self._svrText then self._svrText:SetText(text or "") end
end

function UILoginView:SetLoadingVisible(visible)
	if self._loading then self._loading:SetActive(visible) end
	if self._loginBtn then self._loginBtn:SetActive(not visible) end
end

function UILoginView:SetPopUpRootVisible(visible)
	if self._popupRoot then self._popupRoot:SetActive(visible) end
end

function UILoginView:SetVersionText(appVersion, resVersion)
	if self._appVersionText then self._appVersionText:SetText(Lang.Get("app_ver") .. (appVersion or "")) end
	if self._resVersionText then self._resVersionText:SetText(Lang.Get("res_ver") .. (resVersion or "")) end
end

return UILoginView
