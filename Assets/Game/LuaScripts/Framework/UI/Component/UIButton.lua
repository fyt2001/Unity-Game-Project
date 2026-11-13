--[[
=============================================================================
UIButton.lua - Lua 侧按钮组件（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
=============================================================================
Module:     Framework/UI/Component/UIButton
Target:     Unity + XLua（My project 的 BaseClass 体系，对齐 H02）

描述：
	包裹 Unity 原生 Button，提供组件式 API：
		self.login_btn = self:AddComponent(UIButton, "ContentRoot/m_LoginBtn")
		self.login_btn:SetOnClick(function() ... end)
		self.login_btn:SetActive(false)

	关键对齐点：OnDestroy 中 RemoveListener，View 销毁时由 UIBaseContainer 自动 Delete，
	因此点击监听不会泄漏（解决此前 Class 叶子版不清理监听的问题）。

注意：
	- 组件必须挂在目标节点上，其下需有 Unity 原生 Button（或某子孙节点有 Button）
	- SetOnClick 幂等：重复绑定会先移除上一次回调
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIButton = BaseClass("UIButton", UIBaseComponent)
local base = UIBaseComponent

function UIButton:OnCreate()
	base.OnCreate(self)
	self.unity_uibutton = self.__uiComp or UIUtil.FindButton(self.transform)
	self.__onclick = nil
	self.__onclick1 = nil
end

---设置点击回调（幂等：重复设置会先移除旧的）
function UIButton:SetOnClick(handler)
	if IsNull(self.unity_uibutton) or not handler then
		CS.UnityEngine.Debug.Log(string.format(
			"[UIButton] SetOnClick 被忽略: unity_uibutton=%s, handler=%s, go=%s",
			tostring(self.unity_uibutton), tostring(handler), tostring(self.gameObject)))
		return
	end
	if self.__onclick1 then
		self.unity_uibutton.onClick:RemoveListener(self.__onclick1)
		self.__onclick1 = nil
	end
	self.__onclick = handler
	self.__onclick1 = function()
		CS.UnityEngine.Debug.Log("[UIButton] >>> 点击回调被触发")
		self.__onclick()
	end
	self.unity_uibutton.onClick:AddListener(self.__onclick1)
	CS.UnityEngine.Debug.Log("[UIButton] SetOnClick 绑定成功: " .. tostring(self.unity_uibutton))
end

---移除点击回调
function UIButton:RemoveClick()
	if not IsNull(self.unity_uibutton) and self.__onclick1 then
		self.unity_uibutton.onClick:RemoveListener(self.__onclick1)
	end
	self.__onclick1 = nil
	self.__onclick = nil
end

---设置按钮是否可交互
function UIButton:SetEnable(enable)
	if not IsNull(self.unity_uibutton) then self.unity_uibutton.enabled = enable end
end

---返回底层 Unity Button（兼容旧写法）
function UIButton:GetUnityButton()
	return self.unity_uibutton
end

-- 懒查找子节点 Text（按钮常带一个文本子节点）
function UIButton:checkInitText()
	if self.__isInitText == nil then
		self.__isInitText = true
		self.text = UIUtil.FindText(self.transform)
	end
end

function UIButton:SetText(str)
	self:checkInitText()
	if self.text and str then
		self.text.text = tostring(str)
	end
end

function UIButton:GetText()
	self:checkInitText()
	return self.text and self.text.text or ""
end

-- 销毁：移除点击监听，释放引用（由 UIBaseContainer.Delete 触发）
function UIButton:OnDestroy()
	self:RemoveClick()
	self.unity_uibutton = nil
	self.text = nil
	base.OnDestroy(self)
end

return UIButton
