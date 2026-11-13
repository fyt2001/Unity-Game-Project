--[[
-- UIToggle.lua - Lua 侧 Toggle 组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
-- 对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindToggle(...)，由 AutoBind 传入
--           UIComponentBinder 收集的 Toggle 引用（userdata）时为「零 Find」。
--]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIToggle = BaseClass("UIToggle", UIBaseComponent)
local base = UIBaseComponent

function UIToggle:OnCreate()
	base.OnCreate(self)
	self.unity_uitoggle = self.__uiComp or UIUtil.FindToggle(self.transform)
	self.__onclick = nil
end

-- 懒初始化 Toggle 下的文本（对齐 H02 checkInitText）
function UIToggle:checkInitText()
	if self.__isInitText == nil then
		self.__isInitText = true
		self.text = UIUtil.FindText(self.transform)
	end
end

function UIToggle:IsOn()
	return self.unity_uitoggle and self.unity_uitoggle.isOn
end

-- withoutNotify=true 时不触发 onValueChanged 回调
function UIToggle:SetCheck(bool, withoutNotify)
	if not IsNull(self.unity_uitoggle) then return end
	if withoutNotify then
		self.unity_uitoggle:SetIsOnWithoutNotify(bool)
	else
		self.unity_uitoggle.isOn = bool
	end
end

function UIToggle:SetInteractable(check)
	if not IsNull(self.unity_uitoggle) then self.unity_uitoggle.interactable = check end
end

function UIToggle:SetText(str)
	self:checkInitText()
	if self.text and str then self.text.text = str end
end

-- 设置状态变化回调（handler 签名为 function(isOn)）
function UIToggle:SetOnValueChanged(handler)
	if not IsNull(self.unity_uitoggle) or not handler then return end
	if self.__onclick then
		self.unity_uitoggle.onValueChanged:RemoveListener(self.__onclick)
	end
	self.__onclick = function(isOn) handler(isOn) end
	self.unity_uitoggle.onValueChanged:AddListener(self.__onclick)
end

function UIToggle:OnDestroy()
	if self.__onclick and self.unity_uitoggle then
		self.unity_uitoggle.onValueChanged:RemoveListener(self.__onclick)
	end
	self.__onclick = nil
	self.unity_uitoggle = nil
	self.text = nil
	base.OnDestroy(self)
end

return UIToggle
