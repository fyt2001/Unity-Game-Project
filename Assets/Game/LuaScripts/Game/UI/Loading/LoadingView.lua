--[[
=============================================================================
LoadingView.lua - 加载界面视图（对齐 H02：继承 UIView 组件容器）
=============================================================================
Module:     Game/UI/Loading/LoadingView
Version:     4.0.0
]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIView = require "Framework.UI.Core.UIView"
local Lang = require "Framework.UI.Utils.Lang"

local LoadingView = BaseClass("LoadingView", UIView)
local base = UIView

function LoadingView:OnCreate()
	base.OnCreate(self)
	require("Framework.UI.Utils.CJKFont").ApplyAll(self.gameObject.transform)

	local tr = self.gameObject.transform

	local contentRoot = tr:Find("ContentRoot")
	if not contentRoot then contentRoot = tr end

	local barTr = contentRoot:Find("m_SliderBar")
	if barTr then self._slider = barTr:GetComponent(typeof(Unity_Slider)) end

	local descTr = contentRoot:Find("m_SliderBar/TextGroup/m_LoadingDesc")
	if not descTr then
		descTr = tr:Find("m_SliderBar/TextGroup/m_LoadingDesc")
	end
	if descTr then
		self._descText = Unity_TMP_Text and descTr:GetComponent(typeof(Unity_TMP_Text))
		if not self._descText then
			self._descText = descTr:GetComponent(typeof(Unity_Text))
		end
	end

	local verTr = tr:Find("m_AppVersionText")
	if verTr then
		self._verText = Unity_TMP_Text and verTr:GetComponent(typeof(Unity_TMP_Text))
		if not self._verText then
			self._verText = verTr:GetComponent(typeof(Unity_Text))
		end
	end

	-- 动静分离（参考 H02）：进度条与描述文本每帧/频繁刷新，给它们各自挂一个独立
	-- 嵌套 Canvas，使其重建只影响自身，不污染整个 Loading 窗口的合批与重建。
	-- 默认不传 sortingOrder -> 嵌套 Canvas 继承父级排序，渲染位置不变（零分层风险）。
	if self._slider then self:AddDynamicCanvas(self._slider.gameObject) end
	if self._descText then self:AddDynamicCanvas(self._descText.gameObject) end
end

function LoadingView:OnOpen()
	if self._slider then self._slider.value = 0 end
	if self._descText then self._descText.text = Lang.Get("loading_init") end
end

function LoadingView:OnClose()
	if self._slider then self._slider.value = 0 end
end

function LoadingView:OnDestroy()
	self._slider = nil
	self._descText = nil
	self._verText = nil
	base.OnDestroy(self)
end

function LoadingView:SetProgress(progress, text)
	if self._slider then
		self._slider.value = math.min(math.max(progress or 0, 0), 1)
	end
	if text and self._descText then
		self._descText.text = text
	end
end

function LoadingView:SetVersion(version)
	if self._verText and version then
		self._verText.text = version
	end
end

return LoadingView
