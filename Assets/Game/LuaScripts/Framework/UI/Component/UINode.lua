--[[
=============================================================================
UINode.lua - 通用 UI 节点包装（对齐 ShaoNvClient_H02，继承 UIBaseComponent）
=============================================================================
Module:     Framework/UI/Component/UINode
Target:     Unity + XLua（My project 的 BaseClass 体系，对齐 H02）

描述：
	用于没有 Button/Text/Image 语义的纯节点（如 Loading、PopUpRoot、PolicyRoot）：
		self.loading = self:AddComponent(UINode, "ContentRoot/m_Loading")
		self.loading:SetActive(false)
=============================================================================
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"

local UINode = BaseClass("UINode", UIBaseComponent)
local base = UIBaseComponent

function UINode:OnCreate()
	base.OnCreate(self)
end

function UINode:GetGameObject()
	return self.gameObject
end

function UINode:OnDestroy()
	base.OnDestroy(self)
end

return UINode
