--[[
=============================================================================
UIImage.lua - Lua 侧图片组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
=============================================================================
Module:     Framework/UI/Component/UIImage
Target:     Unity + XLua（My project 的 BaseClass 体系，对齐 H02）

描述：
	包裹 Unity 原生 Image，提供组件式 API：
		self.icon = self:AddComponent(UIImage, "ContentRoot/m_Icon")
		self.icon:SetSprite(sprite)
		self.icon:SetActive(false)

	对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindImage(...)，
	当由 AutoBind 传入 UIComponentBinder 收集的 Image 引用(userdata)时为「零 Find」。
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIImage = BaseClass("UIImage", UIBaseComponent)
local base = UIBaseComponent

function UIImage:OnCreate()
	base.OnCreate(self)
	self.unity_uiimage = self.__uiComp or UIUtil.FindImage(self.transform)
end

---设置图片
---@param sprite any Sprite
function UIImage:SetSprite(sprite)
	if not IsNull(self.unity_uiimage) and sprite then self.unity_uiimage.sprite = sprite end
end

---设置颜色
---@param r number
---@param g number
---@param b number
---@param a number|nil
function UIImage:SetColor(r, g, b, a)
	if not IsNull(self.unity_uiimage) then
		self.unity_uiimage.color = CS.UnityEngine.Color(r, g, b, a == nil and 1 or a)
	end
end

---返回底层 Image（兼容旧写法）
function UIImage:GetUnityImage()
	return self.unity_uiimage
end

function UIImage:OnDestroy()
	self.unity_uiimage = nil
	base.OnDestroy(self)
end

return UIImage
