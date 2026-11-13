--[[
=============================================================================
UIHomeView.lua - 主界面视图（主城菜单 + 摇杆，对齐 H02：继承 UIView 组件容器）

	P2-3「战斗 HUD 归位」后本 View 只负责主城：
		玩家名 / 等级 / 金币 / 宝石 / 奖杯 / 商店按钮 / 配装按钮 / 摇杆
	（战斗按钮已下线：玩法入口统一改为场景内的洞口，见 _bindCenterArea 注释）
	HP 条、回城卷轴、等级的实时战斗刷新连同采样逻辑一并迁到
	Game/UI/Battle/UIBattleHudView + UIBattleHudController。

	摇杆在这里保留：主城模式同样靠它移动（HomeSceneBootstrapper.Update 的
	else 分支 UpdateLocalMove 是主城的正式移动方式），不是战斗专属控件。
=============================================================================
Module:     Game/UI/Home/UIHomeView
Version:    4.0.0
Description:
	严格继承 UIView 基类，遵循 MVC 组件思想：
		- OnCreate：一次性绑定所有 UI 组件引用
		- OnOpen：根据参数初始化 UI 显示
		- OnDestroy：释放所有引用（由 UIView 自动 Delete 子组件）
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"
local UpdateManager = require "Framework.Core.UpdateManager"
local CJKFont = require "Framework.UI.Utils.CJKFont"

local UIHomeView = BaseClass("UIHomeView", UIView)
local base = UIView

-- =============================================================================
-- 生命周期：OnCreate（一次性绑定）
-- =============================================================================

function UIHomeView:OnCreate()
	base.OnCreate(self)

	local tr = self.gameObject.transform
	if not tr then return end

	self:_bindTopBar(tr)
	self:_bindCenterArea(tr)
	self:_bindBottomBar(tr)
	self:_bindJoystick(tr)
	CJKFont.ApplyAll(tr)
end

-- =============================================================================
-- 生命周期：OnOpen（初始化显示）
-- =============================================================================

function UIHomeView:OnOpen(name, level, gold, diamond)
	-- 切场景 / 传送后复位摇杆到中性：摇杆组件随 HomePanel 持久化复用，
	-- 若不复位，上一场景的「按住方向」会带入新场景，导致角色自动移动。
	if self._joystick and self._joystick.Reset then
		self._joystick:Reset()
	end

	-- 重新把摇杆交给【当前场景】的 Bootstrapper：HomePanel 跨场景复用，
	-- OnCreate 里绑定的可能是上一场景已销毁的 Bootstrapper 残引用。
	self:_rebindJoystick()

	self:SetPlayerName(name or "")
	self:SetLevel(level or 1)
	self:SetGold(gold or 0)
	self:SetDiamond(diamond or 0)
	self._opened = true
	self._layoutKey = nil
	self:_adaptLayout()
	if not self._layoutUpdateId then
		self._layoutUpdateId = UpdateManager:GetInstance():AddUpdate(function()
			if self._opened then self:_adaptLayout() end
		end, self)
	end
end

-- =============================================================================
-- 生命周期：OnDestroy（释放引用）
-- =============================================================================

function UIHomeView:OnClose()
	self._opened = false
	self:_setJoystickEnabled(false)
	if self._layoutUpdateId then
		UpdateManager:GetInstance():RemoveUpdate(self._layoutUpdateId)
		self._layoutUpdateId = nil
	end
	if self._joystick then self._joystick:Reset() end
	-- 通知 C# 解除摇杆引用（输入改由 C# 轮询，无需 RemoveListener）
	if self._bootstrapper then
		pcall(function() self._bootstrapper:BindJoystick(nil) end)
		self._bootstrapper = nil
	end
end

function UIHomeView:_setJoystickEnabled(enabled)
	if not self._joystick then return end
	self._joystick:Reset()
	self._joystick.enabled = enabled
end

function UIHomeView:OnFocus()
	if self._opened then self:_setJoystickEnabled(true) end
end

function UIHomeView:OnBlur()
	self:_setJoystickEnabled(false)
end

function UIHomeView:OnHide()
	self:_setJoystickEnabled(false)
end

function UIHomeView:OnDestroy()
	self:OnClose()
	self._nameText = nil
	self._levelText = nil
	self._goldText = nil
	self._gemText = nil
	self._trophyText = nil
	self._shopBtn = nil
	self._modBtn = nil
	self._joystick = nil
	self._bootstrapper = nil
	self._joystickOnMove = nil
	base.OnDestroy(self)
end

-- =============================================================================
-- 组件绑定：TopBar
-- =============================================================================

function UIHomeView:_bindTopBar(tr)
	local topBar = tr:Find("TopBar")
	if not topBar then return end

	self._nameText  = self:_getText(self:_findTransform(topBar, "m_Profile/m_PlayerName"))
	self._levelText = self:_getText(self:_findTransform(topBar, "m_Profile/m_Level"))
	self._goldText  = self:_getText(self:_findTransform(topBar, "m_Currency/m_Gold"))
	self._gemText   = self:_getText(self:_findTransform(topBar, "m_Gem"))
end

-- =============================================================================
-- 组件绑定：CenterArea
-- =============================================================================

function UIHomeView:_bindCenterArea(tr)
	local center = tr:Find("CenterArea")
	if not center then return end

	self._trophyText = self:_getText(self:_findTransform(center, "m_Trophy"))
	-- 战斗按钮已下线：进入玩法统一走场景内的洞口
	--（Portal:Cave Portal，走近或左键点击 → HomeSceneBootstrapper.TeleportToScene
	--  → GameMain.StartDungeonRun）。CenterArea 现在只剩奖杯。）
end

-- =============================================================================
-- 组件绑定：BottomBar
-- =============================================================================

function UIHomeView:_bindBottomBar(tr)
	local bottom = tr:Find("BottomBar")
	if not bottom then return end

	self._shopBtn = self:_getButton(bottom, "m_ShopBtn")
	-- 配装入（P3-1）：与商店按钮同排、贴其左侧，由 MCP 补进 prefab
	self._modBtn = self:_getButton(bottom, "m_ModBtn")
end

-- =============================================================================
-- 组件绑定：摇杆（C# VirtualJoystick → HomeSceneBootstrapper 桥接）
-- =============================================================================

function UIHomeView:_bindJoystick(tr)
	local joystickBg = self:_findTransform(tr, "BottomBar/JoystickArea/m_JoystickBg")
	if not joystickBg then
		print("[UIHomeView] Joystick not found in prefab, skip binding")
		return
	end

	if Game_VirtualJoystick then
		self._joystick = joystickBg:GetComponent(typeof(Game_VirtualJoystick))
	end

	if not self._joystick then
		print("[UIHomeView] VirtualJoystick component not found, skip binding")
		return
	end

	-- 首次创建时即把摇杆交给当前场景的 Bootstrapper；
	-- 场景切换后 OnOpen 会再次调用 _rebindJoystick 重新定位。
	self:_rebindJoystick()
end

---把摇杆交给当前场景的 Bootstrapper（C# 每帧轮询 GetOutput）。
-- 用 pcall 兜底：HomePanel 跨场景复用（CacheOnClose），若 self._bootstrapper 仍是
-- 上一个已销毁场景的残引用，调用 BindJoystick 会经 XLua wrap 抛 NullReferenceException，
-- 进而中断 HomePanel 打开、连带跳过下潜启动。这里吞掉该异常，
-- 真正的绑定由 C# 侧 HomeSceneBootstrapper:EnsureJoystick 在 Update 中兜底完成。
function UIHomeView:_rebindJoystick()
	if not self._joystick then return end

	local bootstrapper = nil
	if Game_HomeSceneBootstrapper then
		bootstrapper = Object.FindObjectOfType(typeof(Game_HomeSceneBootstrapper))
	end

	if not bootstrapper then
		print("[UIHomeView] HomeSceneBootstrapper not found, joystick input will not reach PlayerController")
		return
	end

	local ok, err = pcall(function()
		bootstrapper:BindJoystick(self._joystick)
	end)
	if ok then
		self._bootstrapper = bootstrapper
		print("[UIHomeView] Joystick handed to Bootstrapper (C# polling mode)")
	else
		print("[UIHomeView] BindJoystick failed: " .. tostring(err) .. " (C# EnsureJoystick will recover)")
	end
end

-- =============================================================================
-- 显示更新 API（由 Controller 调用）
-- =============================================================================

function UIHomeView:SetPlayerName(v)
	if self._nameText then self._nameText.text = v end
end

function UIHomeView:SetLevel(_)
	-- No persistent player-level source exists yet; show the current hub instead.
	if self._levelText then self._levelText.text = "主城" end
end

function UIHomeView:SetGold(v)
	local value = math.max(0, math.floor(tonumber(v) or 0))
	local formatted = tostring(value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	if self._goldText then self._goldText.text = formatted end
end

function UIHomeView:_adaptLayout()
	local screen = CS.UnityEngine.Screen
	local root = self.transform:GetComponent(typeof(CS.UnityEngine.RectTransform))
	local parent = root.parent:GetComponent(typeof(CS.UnityEngine.RectTransform))
	local width, height = parent.rect.width, parent.rect.height
	local sw, sh = screen.width, screen.height
	if width <= 0 or height <= 0 or sw <= 0 or sh <= 0 then return end
	local safe = screen.safeArea
	local key = table.concat({ width, height, sw, sh, safe.x, safe.y, safe.width, safe.height }, ":")
	if key == self._layoutKey then return end
	self._layoutKey = key
	local scale = math.min(width, height) / 720
	local safeWidth, safeHeight = width * safe.width / sw, height * safe.height / sh
	root.anchorMin = CS.UnityEngine.Vector2(0.5, 0.5)
	root.anchorMax = CS.UnityEngine.Vector2(0.5, 0.5)
	root.pivot = CS.UnityEngine.Vector2(0.5, 0.5)
	root.sizeDelta = CS.UnityEngine.Vector2(safeWidth / scale, safeHeight / scale)
	root.localScale = CS.UnityEngine.Vector3(scale, scale, scale)
	root.anchoredPosition = CS.UnityEngine.Vector2(
		width * ((safe.x + safe.width / 2) / sw - 0.5),
		height * ((safe.y + safe.height / 2) / sh - 0.5))
	local logicalWidth = safeWidth / scale
	local top = self.transform:Find("TopBar")
	local profile = top:Find("m_Profile"):GetComponent(typeof(CS.UnityEngine.RectTransform))
	local currency = top:Find("m_Currency"):GetComponent(typeof(CS.UnityEngine.RectTransform))
	local profileWidth = math.min(360, logicalWidth * 0.50)
	local currencyWidth = math.min(290, logicalWidth * 0.40)
	profile.sizeDelta = CS.UnityEngine.Vector2(profileWidth, 100)
	profile.anchoredPosition = CS.UnityEngine.Vector2(28 + profileWidth / 2, 0)
	currency.sizeDelta = CS.UnityEngine.Vector2(currencyWidth, 76)
	currency.anchoredPosition = CS.UnityEngine.Vector2(-28 - currencyWidth / 2, 0)
	local nameRect = top:Find("m_Profile/m_PlayerName"):GetComponent(typeof(CS.UnityEngine.RectTransform))
	local levelRect = top:Find("m_Profile/m_Level"):GetComponent(typeof(CS.UnityEngine.RectTransform))
	nameRect.sizeDelta = CS.UnityEngine.Vector2(profileWidth - 110, 38)
	levelRect.sizeDelta = nameRect.sizeDelta
	nameRect.anchoredPosition = CS.UnityEngine.Vector2(100 + nameRect.sizeDelta.x / 2, 19)
	levelRect.anchoredPosition = CS.UnityEngine.Vector2(100 + nameRect.sizeDelta.x / 2, -20)
	local goldRect = top:Find("m_Currency/m_Gold"):GetComponent(typeof(CS.UnityEngine.RectTransform))
	goldRect.sizeDelta = CS.UnityEngine.Vector2(currencyWidth - 78, 44)
	goldRect.anchoredPosition = CS.UnityEngine.Vector2(68 + goldRect.sizeDelta.x / 2, 0)
	if self._joystick then self._joystick:Reset() end
end

function UIHomeView:SetDiamond(v)
	if self._gemText then self._gemText.text = tostring(v) end
end

function UIHomeView:SetTrophy(v)
	if self._trophyText then self._trophyText.text = tostring(v) end
end

-- =============================================================================
-- Getter API（供 Controller 获取组件引用）
-- =============================================================================

function UIHomeView:GetButton(name)
	if name == "Shop" then return self._shopBtn
	elseif name == "Mod" then return self._modBtn
	end
end

function UIHomeView:GetJoystick()
	return self._joystick
end

function UIHomeView:GetBootstrapper()
	return self._bootstrapper
end

-- =============================================================================
-- 组件查找辅助方法
-- =============================================================================

function UIHomeView._findTransform(_, parent, path)
	if not parent then return nil end
	return parent:Find(path)
end

function UIHomeView._getText(_, tr)
	if not tr then return nil end
	if Unity_TMP_Text then
		local tmp = tr:GetComponent(typeof(Unity_TMP_Text))
		if tmp then return tmp end
	end
	return tr:GetComponent(typeof(Unity_Text))
end

function UIHomeView:_getButton(parent, path)
	local tr = self:_findTransform(parent, path)
	if not tr then return nil end
	return tr:GetComponent(typeof(Unity_Button))
end

function UIHomeView:_getSlider(parent, path)
	local tr = self:_findTransform(parent, path)
	if not tr then return nil end
	return tr:GetComponent(typeof(Unity_Slider))
end

return UIHomeView
