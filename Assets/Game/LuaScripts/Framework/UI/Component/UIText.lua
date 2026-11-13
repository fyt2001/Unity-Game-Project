--[[
=============================================================================
UIText.lua - Lua 侧文本组件（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
=============================================================================
Module:     Framework/UI/Component/UIText
Target:     Unity + XLua（My project 的 BaseClass 体系，对齐 H02）

描述：
	包裹 Unity 原生 Text / TextMeshProUGUI，提供组件式 API：
		self.app_version_text = self:AddComponent(UIText, "ContentRoot/m_AppVersionText")
		self.app_version_text:SetText("v1.0.0")
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIText = BaseClass("UIText", UIBaseComponent)
local base = UIBaseComponent

function UIText:OnCreate()
	base.OnCreate(self)
	self.unity_uitext = self.__uiComp or UIUtil.FindText(self.transform)
end

function UIText:SetText(text)
	if not IsNull(self.unity_uitext) and text then
		self.unity_uitext.text = tostring(text)
	end
end

function UIText:GetText()
	if not IsNull(self.unity_uitext) then
		return self.unity_uitext.text
	end
	return ""
end

---返回底层 Text 组件（兼容旧写法）
function UIText:GetUnityText()
	return self.unity_uitext
end

function UIText:OnDestroy()
	self.unity_uitext = nil
	base.OnDestroy(self)
end

return UIText
