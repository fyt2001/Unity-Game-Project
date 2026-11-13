--[[
-- UIInputField.lua - Lua 侧 InputField 组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
-- 对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindInputField(...)，由 AutoBind 传入
--           UIComponentBinder 收集的 InputField 引用（userdata）时为「零 Find」。
-- 说明：裁剪 H02 的 logUIComp 告警（My project 框架无此全局），回退时静默 Find。
--]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIInputField = BaseClass("UIInputField", UIBaseComponent)
local base = UIBaseComponent

function UIInputField:OnCreate()
	base.OnCreate(self)
	self.unity_uiinput = self.__uiComp or UIUtil.FindInputField(self.transform)
	self.__onchanged = nil
end

function UIInputField:GetText()
	if not IsNull(self.unity_uiinput) then return self.unity_uiinput.text end
	return ""
end

-- withoutNotify=true 时不触发 onValueChanged 回调
function UIInputField:SetText(text, withoutNotify)
	if not IsNull(self.unity_uiinput) then
		if withoutNotify then
			self.unity_uiinput:SetTextWithoutNotify(text)
		else
			self.unity_uiinput.text = text
		end
	end
end

function UIInputField:SetOnChanged(handler)
	if IsNull(self.unity_uiinput) or not handler then return end
	if self.__onchanged then
		self.unity_uiinput.onValueChanged:RemoveListener(self.__onchanged)
	end
	self.__onchanged = function(v) handler(v) end
	self.unity_uiinput.onValueChanged:AddListener(self.__onchanged)
end

function UIInputField:SetCharacterLimit(count)
	if not IsNull(self.unity_uiinput) then self.unity_uiinput.characterLimit = count end
end

function UIInputField:GetCharacterLimit()
	if not IsNull(self.unity_uiinput) then return self.unity_uiinput.characterLimit end
	return 0
end

function UIInputField:OnDestroy()
	if self.__onchanged and not IsNull(self.unity_uiinput) then
		self.unity_uiinput.onValueChanged:RemoveListener(self.__onchanged)
	end
	self.__onchanged = nil
	self.unity_uiinput = nil
	base.OnDestroy(self)
end

return UIInputField
