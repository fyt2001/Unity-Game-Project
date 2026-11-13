--[[
-- UIScrollRect.lua - Lua 侧 ScrollRect 组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
-- 对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindScrollRect(...)，由 AutoBind 传入
--           UIComponentBinder 收集的 ScrollRect 引用（userdata）时为「零 Find」。
-- 说明：裁剪 H02 对 UnityEngine.UI.Extensions.ScrollRectTweener 的依赖（解耦），
--       保留 normalizedPosition / content 缩放等基础能力。
--]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIScrollRect = BaseClass("UIScrollRect", UIBaseComponent)
local base = UIBaseComponent

function UIScrollRect:OnCreate()
	base.OnCreate(self)
	self.unity_rectScroll = self.__uiComp or UIUtil.FindScrollRect(self.transform)
end

function UIScrollRect:GetScrollRect()
	return self.unity_rectScroll
end

function UIScrollRect:SetNormalizedPosition(x, y)
	if not IsNull(self.unity_rectScroll) then
		self.unity_rectScroll.normalizedPosition = CS.UnityEngine.Vector2(x, y)
	end
end

function UIScrollRect:SetContentNormalizedPosition(x, y)
	self:SetNormalizedPosition(x, y)
end

function UIScrollRect:SetViewScale(floatx, floaty)
	if not IsNull(self.unity_rectScroll) and self.unity_rectScroll.content then
		floatx = floatx or 1
		floaty = floaty or 1
		self.unity_rectScroll.content.transform.localScale = CS.UnityEngine.Vector3(floatx, floaty, 1)
	end
end

function UIScrollRect:OnDestroy()
	self.unity_rectScroll = nil
	base.OnDestroy(self)
end

return UIScrollRect
