--[[
=============================================================================
HomeController.lua - 主城面板控制器
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIController = require "NewObject.Framework.UI.Core.UIController"

local HomeController = Class.Define("HomeController")
Class.Extend(HomeController, UIController)

function HomeController:Ctor(model)
    self.super:Ctor(model)
end

function HomeController:OnCreate()
    -- 绑定按钮事件
    self:_bindButton("Battle", "HomePanel_OnBattle")
    self:_bindButton("Bag", "HomePanel_OnBag")
    self:_bindButton("Shop", "HomePanel_OnShop")
    self:_bindButton("Settings", "HomePanel_OnSettings")
end

function HomeController:OnOpen(name, level, gold, diamond)
    self.model:SetPlayerInfo(name, level)
    self.model:SetCurrency(gold, diamond)
end

function HomeController:_bindButton(name, eventName)
    local btn = self.view:GetButton(name)
    if btn then
        btn.onClick:AddListener(function()
            print(string.format("[HomePanel] %s clicked", name))
            local FW = require "Framework.Framework"
            FW.Event():Dispatch(eventName)
        end)
    end
end

return HomeController