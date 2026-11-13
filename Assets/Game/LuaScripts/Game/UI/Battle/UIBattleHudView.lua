--[[
=============================================================================
UIBattleHudView.lua - 战斗 HUD 视图（HP 条 / 等级 / 回城卷轴 / 摇杆）
=============================================================================
Module:     Game/UI/Battle/UIBattleHudView
Version:    1.0.0
Description:
	P2-3「战斗 HUD 归位」：战斗期间显示的 HUD 面板。

	【为什么不用 AutoBind】
		本 prefab 由 MCP 运行时创建，UIComponentBinder 上登记的是从 HomePanel
		继承来的旧绑定项（部分已随节点删除而悬空），不能依赖 self.m_Xxx_Sld
		这类注入字段。改走 FindGameObject + GetComponent，与 UIHomeView 一致。
		（安全性：UIBaseContainer.AutoBind 内部有 `if comp and compName then`
		 的 null 防护，悬空项会被静默跳过，不会报错。）

	【摇杆为什么在这里也有一套】
		摇杆不是战斗专属：主城模式同样靠它移动（HomeSceneBootstrapper.Update
		的 else 分支 UpdateLocalMove 是主城的正式移动方式）。因此摇杆在
		HomePanel 与 BattleHudPanel 各一套，同一时刻只会有一个面板打开。
		CacheOnClose 只是隐藏而非销毁，`FindObjectOfType<VirtualJoystick>`
		不会返回隐藏面板上的实例，不会串台。

	核心设计：
		- OnCreate：一次性绑定所有组件引用
		- OnOpen：复位摇杆到中性 + 重新交给当前场景的 Bootstrapper
		- OnClose：通知 C# 解除摇杆引用
		- OnDestroy：释放所有引用
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"

local UIBattleHudView = BaseClass("UIBattleHudView", UIView)
local base = UIView

-- 组件查找辅助函数。写成 local 而非冒号方法：这些是纯工具，体内不需要 self，
-- 若写成 self:_getXxx 会被 luacheck 判 unused argument 'self'。
local function _findTransform(parent, path)
	if not parent then return nil end
	return parent:Find(path)
end

local function _getText(tr)
	if not tr then return nil end
	if Unity_TMP_Text then
		local tmp = tr:GetComponent(typeof(Unity_TMP_Text))
		if tmp then return tmp end
	end
	return tr:GetComponent(typeof(Unity_Text))
end

local function _getButton(parent, path)
	local tr = _findTransform(parent, path)
	if not tr then return nil end
	return tr:GetComponent(typeof(Unity_Button))
end

local function _getSlider(parent, path)
	local tr = _findTransform(parent, path)
	if not tr then return nil end
	return tr:GetComponent(typeof(Unity_Slider))
end

-- =============================================================================
-- 生命周期：OnCreate（一次性绑定）
-- =============================================================================

function UIBattleHudView:OnCreate()
	base.OnCreate(self)

	local tr = self.gameObject.transform
	if not tr then return end

	self:_bindTopBar(tr)
	self:_bindHpBar(tr)
	self:_bindExpBar(tr)     -- 经验条（HP 条正上方同款细条）
	self:_bindReturnScrollBtn(tr)
	self:_bindPauseBtn(tr)   -- P2-4：暂停入口
	self:_bindJoystick(tr)
	require("Framework.UI.Utils.CJKFont").ApplyAll(tr)
end

-- =============================================================================
-- 生命周期：OnOpen（初始化显示）
-- =============================================================================

function UIBattleHudView:OnOpen(level)
	-- 复位摇杆到中性：否则上一场景按住的方向会带入战斗，角色自动行走
	if self._joystick and self._joystick.Reset then
		self._joystick:Reset()
	end

	-- 重新把摇杆交给【当前场景】的 Bootstrapper：面板跨场景复用时，
	-- OnCreate 里绑的可能是上一场景已销毁的 Bootstrapper 残引用
	self:_rebindJoystick()

	if level then
		self:SetLevel(level)
	end
end

-- =============================================================================
-- 生命周期：OnClose / OnDestroy（清理）
-- =============================================================================

function UIBattleHudView:OnClose()
	-- 通知 C# 解除摇杆引用（输入改由 C# 轮询，无需 RemoveListener）
	if self._bootstrapper then
		self._bootstrapper:BindJoystick(nil)
	end
end

function UIBattleHudView:OnDestroy()
	self._levelText = nil
	self._hpSlider = nil
	self._hpText = nil
	self._expSlider = nil
	self._expText = nil
	self._returnScrollBtn = nil
	self._pauseBtn = nil
	self._joystick = nil
	self._bootstrapper = nil
	base.OnDestroy(self)
end

-- =============================================================================
-- 组件绑定
-- =============================================================================

function UIBattleHudView:_bindTopBar(tr)
	local topBar = _findTransform(tr, "TopBar")
	if not topBar then return end

	self._levelText = _getText(_findTransform(topBar, "m_Level"))
end

function UIBattleHudView:_bindHpBar(tr)
	self._hpSlider = _getSlider(tr, "m_HpBar")
	self._hpText   = _getText(_findTransform(tr, "m_HpBar/m_HpText"))
end

---经验条（HP 条正上方的同款细条；结构与 m_HpBar 一致，内部 Slider 引用由 prefab 承载）
function UIBattleHudView:_bindExpBar(tr)
	self._expSlider = _getSlider(tr, "m_ExpBar")
	self._expText   = _getText(_findTransform(tr, "m_ExpBar/m_ExpText"))
	-- 经验条缺节点不该中断 HUD 打开：只提示，其余控件照常工作
	if not self._expSlider then
		print("[UIBattleHudView] m_ExpBar not found in prefab, exp bar unavailable")
	end
end

---回城卷轴按钮（战斗期间主动撤离）
function UIBattleHudView:_bindReturnScrollBtn(tr)
	-- m_ReturnScrollBtn 是 BattleHudPanel 根节点的直接子物体
	self._returnScrollBtn = _getButton(tr, "m_ReturnScrollBtn")
	if self._returnScrollBtn then
		-- 默认隐藏：仅在战斗中且有卷轴时由 Controller 打开
		self._returnScrollBtn.gameObject:SetActive(false)
	else
		print("[UIBattleHudView] m_ReturnScrollBtn not found in prefab, skip binding")
	end
end

---暂停按钮（P2-4）
-- 与回城卷轴相反，暂停是【任何时候都可用】的操作：
-- 能不能真的暂停由 DungeonManager:PauseGame() 判定（例如升级弹窗/层间事件
-- 已经让战斗处于 Paused 时会被拒绝），View 只负责把点击意图上报。
function UIBattleHudView:_bindPauseBtn(tr)
	self._pauseBtn = _getButton(tr, "m_PauseBtn")
	if not self._pauseBtn then
		print("[UIBattleHudView] m_PauseBtn not found in prefab, pause entry unavailable")
	end
end

function UIBattleHudView:_bindJoystick(tr)
	local joystickBg = _findTransform(tr, "BottomBar/JoystickArea/m_JoystickBg")
	if not joystickBg then
		print("[UIBattleHudView] Joystick not found in prefab, skip binding")
		return
	end

	if Game_VirtualJoystick then
		self._joystick = joystickBg:GetComponent(typeof(Game_VirtualJoystick))
	end

	if not self._joystick then
		print("[UIBattleHudView] VirtualJoystick component not found, skip binding")
		return
	end

	-- 首次创建时即把摇杆交给当前场景的 Bootstrapper；
	-- 场景切换后 OnOpen 会再次调用 _rebindJoystick 重新定位。
	self:_rebindJoystick()
end

---把摇杆交给当前场景的 Bootstrapper（C# 每帧轮询 GetOutput）。
-- 用 pcall 兜底：面板跨场景复用（CacheOnClose），若 self._bootstrapper 仍是
-- 上一个已销毁场景的残引用，调用 BindJoystick 会经 XLua wrap 抛 NRE，
-- 进而中断面板打开、连带跳过下潜启动。这里吞掉异常，
-- 真正的绑定由 C# 侧 HomeSceneBootstrapper:EnsureJoystick 在 Update 中兜底完成。
function UIBattleHudView:_rebindJoystick()
	if not self._joystick then return end

	local bootstrapper = nil
	if Game_HomeSceneBootstrapper then
		bootstrapper = Object.FindObjectOfType(typeof(Game_HomeSceneBootstrapper))
	end

	if not bootstrapper then
		print("[UIBattleHudView] HomeSceneBootstrapper not found, joystick input will not reach PlayerController")
		return
	end

	local ok, err = pcall(function()
		bootstrapper:BindJoystick(self._joystick)
	end)
	if ok then
		self._bootstrapper = bootstrapper
		print("[UIBattleHudView] Joystick handed to Bootstrapper (C# polling mode)")
	else
		print("[UIBattleHudView] BindJoystick failed: " .. tostring(err) .. " (C# EnsureJoystick will recover)")
	end
end

-- =============================================================================
-- 显示更新 API（由 Controller 调用）
-- =============================================================================

function UIBattleHudView:SetLevel(v)
	if self._levelText then self._levelText.text = "Lv." .. tostring(v) end
end

function UIBattleHudView:SetHp(hp, maxHp)
	if self._hpSlider then
		self._hpSlider.value = (maxHp > 0) and (hp / maxHp) or 0
	end
	if self._hpText then
		self._hpText.text = tostring(math.floor(hp)) .. "/" .. tostring(math.floor(maxHp))
	end
end

---经验条刷新（exp / expToNext）
function UIBattleHudView:SetExp(exp, expToNext)
	exp = exp or 0
	expToNext = expToNext or 0
	if self._expSlider then
		self._expSlider.value = (expToNext > 0) and (exp / expToNext) or 0
	end
	if self._expText then
		self._expText.text = tostring(math.floor(exp)) .. "/" .. tostring(math.floor(expToNext))
	end
end

---回城卷轴按钮可见性（由 Controller 根据下潜状态刷新）
function UIBattleHudView:SetReturnScrollVisible(v)
	if self._returnScrollBtn then
		self._returnScrollBtn.gameObject:SetActive(v)
	end
end

function UIBattleHudView:GetReturnScrollButton()
	return self._returnScrollBtn
end

---暂停按钮（供 Controller 绑回调；prefab 缺失时返回 nil）
function UIBattleHudView:GetPauseButton()
	return self._pauseBtn
end

return UIBattleHudView
