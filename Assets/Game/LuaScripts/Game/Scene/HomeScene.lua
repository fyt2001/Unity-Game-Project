--[[
=============================================================================
HomeScene.lua - 主城场景脚本（参考 ShaoNvClient_H02 精华）
=============================================================================
Module:     Game/Scene/HomeScene
Version:    1.0.0
Description:
    主城场景的 Lua 脚本。由 SceneLoader 在场景加载完成后调用 OnSceneEnter。
    负责：初始化主城 UI、管理主城各功能模块入口、场景切换。

    核心设计：
        - 模块化入口管理：主城各功能（战斗、背包、商城等）通过统一入口调度
        - 场景生命周期：OnSceneEnter / OnSceneLeave 管理资源
        - 事件驱动：通过 EventManager 解耦各模块

    用法：
        由 SceneLoader 自动调用，无需手动调用。
=============================================================================
]]

local HomeScene = {}
HomeScene.__index = HomeScene

-- =============================================================================
-- 场景生命周期
-- =============================================================================

function HomeScene:OnSceneEnter(sceneName, config)
    print(string.format("[HomeScene] Entering scene: %s", sceneName))

    self._sceneName = sceneName
    self._config = config
    self._uiManager = nil

    -- 获取核心管理器引用
    local GameMain = require "Game.GameMain"
    self._uiManager = GameMain.GetUIManager()
    self._eventManager = GameMain.GetEventManager()

    -- 初始化主城 UI
    self:_initHomeUI()

    -- 注册全局事件
    self:_registerEvents()

    print("[HomeScene] Home scene ready")
end

function HomeScene:OnSceneLeave()
    print("[HomeScene] Leaving scene, cleaning up...")

    -- 注销事件
    self:_unregisterEvents()

    -- 关闭主城相关 UI
    if self._uiManager then
        self._uiManager:Close("HomePanel", "SceneLeave")
    end

    self._uiManager = nil
    self._eventManager = nil
end

-- =============================================================================
-- 主城 UI 初始化
-- =============================================================================

function HomeScene:_initHomeUI()
    -- 打开主城面板 Prefab（类似 LoadingPanel 方式，通过 UIManager 加载）
    if self._uiManager then
        self._uiManager:Open("HomePanel", "玩家", 1, 1000, 100)
        print("[HomeScene] HomePanel opened")
    else
        print("[HomeScene] Home UI initialized (placeholder)")
    end
end

-- =============================================================================
-- 事件系统
-- =============================================================================

function HomeScene:_registerEvents()
    if not self._eventManager then return end

    -- 注册场景内事件
    -- self._eventManager:Register("OnBattleStart", self, self.OnBattleStart)
    -- self._eventManager:Register("OnShopOpen", self, self.OnShopOpen)
end

function HomeScene:_unregisterEvents()
    if not self._eventManager then return end

    -- self._eventManager:Unregister("OnBattleStart", self)
    -- self._eventManager:Unregister("OnShopOpen", self)
end

-- =============================================================================
-- 功能入口
-- =============================================================================

---进入战斗
function HomeScene:EnterBattle()
    print("[HomeScene] Entering battle...")
    local GameMain = require "Game.GameMain"
    GameMain.SwitchScene("TestBattle", function(success)
        if success then
            print("[HomeScene] Entered battle scene")
        end
    end)
end

---打开背包
function HomeScene:OpenBag()
    print("[HomeScene] Opening bag...")
    -- if self._uiManager then
    --     self._uiManager:Open("BagPanel")
    -- end
end

---打开商城
function HomeScene:OpenShop()
    print("[HomeScene] Opening shop...")
    -- if self._uiManager then
    --     self._uiManager:Open("ShopPanel")
    -- end
end

return HomeScene