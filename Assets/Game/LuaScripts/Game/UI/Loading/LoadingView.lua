--[[
=============================================================================
LoadingView.lua - 加载界面视图（Prefab 模式，继承 UIView）
=============================================================================
Module:     Game/UI/Loading/LoadingView
Version:    2.1.0
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"
local UIView = require "Framework.UI.Core.UIView"

local LoadingView = Class.Define("LoadingView", UIView)

function LoadingView:OnCreate()
    -- 缓存子节点的组件引用，避免每帧 GetComponent
    local tr = self.gameObject.transform
    local barTr = tr:Find("m_SliderBar")
    if barTr then self._slider = barTr:GetComponent(typeof(Unity_Slider)) end

    local descTr = tr:Find("Background/Container/m_LoadingDesc")
    if descTr then self._descText = descTr:GetComponent(typeof(Unity_Text)) end

    local verTr = tr:Find("Background/m_VersionText")
    if verTr then self._verText = verTr:GetComponent(typeof(Unity_Text)) end
end

function LoadingView:OnOpen()
    if self._slider then self._slider.value = 0 end
    if self._descText then self._descText.text = "正在初始化..." end
end

function LoadingView:OnClose()
    if self._slider then self._slider.value = 0 end
end

function LoadingView:OnDestroy()
    self._slider = nil
    self._descText = nil
    self._verText = nil
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
