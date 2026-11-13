--[[
-- UISlider.lua - Lua 侧 Slider 组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
-- 对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindSlider(...)，由 AutoBind 传入
--           UIComponentBinder 收集的 Slider 引用（userdata）时为「零 Find」。
-- 说明：裁剪 H02 的 DOTween 动画相关逻辑（解耦），保留核心取值/设值/回调。
--]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UISlider = BaseClass("UISlider", UIBaseComponent)
local base = UIBaseComponent

function UISlider:OnCreate()
	base.OnCreate(self)
	self.unity_uislider = self.__uiComp or UIUtil.FindSlider(self.transform)
	self.maxValue = 1
	self.value = 0
	self.__onchanged = nil
	self._TextCom = nil
end

function UISlider:GetValue()
	if not IsNull(self.unity_uislider) then return self.unity_uislider.value end
	return 0
end

function UISlider:SetValue(value)
	if IsNull(self.unity_uislider) then return end
	self.value = value
	if self._TextCom then
		self._TextCom:SetText(math.floor(self.value) .. "/" .. math.floor(self.maxValue))
	end
	self.unity_uislider.value = self.value
end

function UISlider:SetMaxValue(v)
	self.maxValue = v
	if not IsNull(self.unity_uislider) then self.unity_uislider.maxValue = self.maxValue end
end

function UISlider:GetMaxValue()
	if not IsNull(self.unity_uislider) then return self.unity_uislider.maxValue end
	return self.maxValue
end

function UISlider:SetTextComponent(com)
	self._TextCom = com
end

function UISlider:SetInteractable(state)
	if not IsNull(self.unity_uislider) then self.unity_uislider.interactable = state or false end
end

-- 设置值变化回调（handler 签名为 function(value)）
function UISlider:SetOnValueChanged(handler)
	if IsNull(self.unity_uislider) or not handler then return end
	if self.__onchanged then
		self.unity_uislider.onValueChanged:RemoveListener(self.__onchanged)
	end
	self.__onchanged = function(v) handler(v) end
	self.unity_uislider.onValueChanged:AddListener(self.__onchanged)
end

function UISlider:OnDestroy()
	if self.__onchanged and not IsNull(self.unity_uislider) then
		self.unity_uislider.onValueChanged:RemoveListener(self.__onchanged)
	end
	self.__onchanged = nil
	self.unity_uislider = nil
	self._TextCom = nil
	base.OnDestroy(self)
end

return UISlider
