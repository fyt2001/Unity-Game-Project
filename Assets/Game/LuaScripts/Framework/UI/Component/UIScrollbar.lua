--[[
-- UIScrollbar.lua - Lua 侧 Scrollbar 组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
-- 对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindScrollbar(...)，由 AutoBind 传入
--           UIComponentBinder 收集的 Scrollbar 引用（userdata）时为「零 Find」。
--]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIScrollbar = BaseClass("UIScrollbar", UIBaseComponent)
local base = UIBaseComponent

function UIScrollbar:OnCreate()
	base.OnCreate(self)
	self.unity_uiscrollbar = self.__uiComp or UIUtil.FindScrollbar(self.transform)
end

function UIScrollbar:SetValue(v)
	if not IsNull(self.unity_uiscrollbar) then self.unity_uiscrollbar.value = v end
end

function UIScrollbar:GetValue()
	if not IsNull(self.unity_uiscrollbar) then return self.unity_uiscrollbar.value end
	return 0
end

function UIScrollbar:SetSize(v)
	if not IsNull(self.unity_uiscrollbar) then self.unity_uiscrollbar.size = v end
end

function UIScrollbar:OnDestroy()
	self.unity_uiscrollbar = nil
	base.OnDestroy(self)
end

return UIScrollbar
