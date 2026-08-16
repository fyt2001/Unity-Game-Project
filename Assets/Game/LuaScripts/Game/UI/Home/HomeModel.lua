--[[
=============================================================================
HomeModel.lua - 主城面板数据模型
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIModel = require "NewObject.Framework.UI.Core.UIModel"

local HomeModel = Class.Define("HomeModel")
Class.Extend(HomeModel, UIModel)

function HomeModel:Ctor(windowName)
    self.super:Ctor(windowName)
    self.playerName = ""
    self.playerLevel = 1
    self.gold = 0
    self.diamond = 0
end

function HomeModel:SetPlayerInfo(name, level)
    self.playerName = name or ""
    self.playerLevel = level or 1
end

function HomeModel:SetCurrency(gold, diamond)
    self.gold = gold or 0
    self.diamond = diamond or 0
end

return HomeModel