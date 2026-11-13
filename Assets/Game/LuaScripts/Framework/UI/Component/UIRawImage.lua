--[[
-- UIRawImage.lua - Lua 侧 RawImage 组件包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
-- 对齐要点：OnCreate 使用 self.__uiComp or UIUtil.FindRawImage(...)，由 AutoBind 传入
--           UIComponentBinder 收集的 RawImage 引用（userdata）时为「零 Find」。
-- 说明：裁剪 H02 的异步纹理加载/置灰逻辑（依赖项目资源管理层），仅保留 RawImage 基础 API。
--]]
local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"

local UIRawImage = BaseClass("UIRawImage", UIBaseComponent)
local base = UIBaseComponent

function UIRawImage:OnCreate()
	base.OnCreate(self)
	self.unity_uirawimage = self.__uiComp or UIUtil.FindRawImage(self.transform)
end

function UIRawImage:SetTexture(tex)
	if not IsNull(self.unity_uirawimage) then self.unity_uirawimage.texture = tex end
end

function UIRawImage:GetTexture()
	if not IsNull(self.unity_uirawimage) then return self.unity_uirawimage.texture end
	return nil
end

function UIRawImage:SetNativeSize()
	if not IsNull(self.unity_uirawimage) then self.unity_uirawimage:SetNativeSize() end
end

function UIRawImage:OnDestroy()
	self.unity_uirawimage = nil
	base.OnDestroy(self)
end

return UIRawImage
