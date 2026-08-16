--[[
=============================================================================
HomeView.lua - 主城面板视图
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIView = require "NewObject.Framework.UI.Core.UIView"

local HomeView = Class.Define("HomeView")
Class.Extend(HomeView, UIView)

function HomeView:OnCreate()
    local tr = self.gameObject.transform
    if not tr then return end

    -- 绑定 UI 组件引用
    local headerTr = tr:Find("Header")
    if headerTr then
        local avatarTr = headerTr:Find("Avatar")
        if avatarTr then self._avatarImg = avatarTr:GetComponent(typeof(CS.UnityEngine.UI.Image)) end

        local nameTr = headerTr:Find("Name")
        if nameTr then self._nameText = nameTr:GetComponent(typeof(CS.UnityEngine.UI.Text)) end

        local levelTr = headerTr:Find("Level")
        if levelTr then self._levelText = levelTr:GetComponent(typeof(CS.UnityEngine.UI.Text)) end
    end

    -- 菜单按钮
    local menuTr = tr:Find("MenuButtons")
    if menuTr then
        self._btnBattle = self:_findButton(menuTr, "Btn_Battle")
        self._btnBag = self:_findButton(menuTr, "Btn_Bag")
        self._btnShop = self:_findButton(menuTr, "Btn_Shop")
        self._btnSettings = self:_findButton(menuTr, "Btn_Settings")
    end

    -- 资源栏
    local footerTr = tr:Find("Footer")
    if footerTr then
        local barTr = footerTr:Find("ResourceBar")
        if barTr then
            local goldTr = barTr:Find("Gold")
            if goldTr then self._goldText = goldTr:GetComponent(typeof(CS.UnityEngine.UI.Text)) end

            local diaTr = barTr:Find("Diamond")
            if diaTr then self._diamondText = diaTr:GetComponent(typeof(CS.UnityEngine.UI.Text)) end
        end
    end
end

function HomeView:OnOpen(name, level, gold, diamond)
    if self._nameText and name then
        self._nameText.text = name
    end
    if self._levelText and level then
        self._levelText.text = "Lv." .. tostring(level)
    end
    if self._goldText and gold then
        self._goldText.text = tostring(gold)
    end
    if self._diamondText and diamond then
        self._diamondText.text = tostring(diamond)
    end
end

function HomeView:GetButton(name)
    if name == "Battle" then return self._btnBattle
    elseif name == "Bag" then return self._btnBag
    elseif name == "Shop" then return self._btnShop
    elseif name == "Settings" then return self._btnSettings
    end
end

function HomeView:_findButton(parent, childName)
    local child = parent:Find(childName)
    if child then
        return child:GetComponent(typeof(CS.UnityEngine.UI.Button))
    end
end

return HomeView