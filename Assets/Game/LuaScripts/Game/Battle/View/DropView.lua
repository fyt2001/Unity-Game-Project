--[[
=============================================================================
DropView.lua
=============================================================================
掉落物表现层（Lua 组件）。武器 / 材料 / 道具三种模型各不相同，便于一眼区分。
  - weapon  → 青色小剑（刀身+护手）
  - material→ 彩色宝石球（按材料 id 给不同色）
  - item    → 金色方块
优先使用 ViewConfig.dropXxx prefab（Editor 工具生成）；缺失时按几何体兜底。
  - Update(dt)：每帧做上下浮动 + 旋转，提示可拾取（由基类 Tick 驱动）。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local EntityViewFactory = require "Game.Battle.View.EntityViewFactory"
local EntityViewBase = require "Game.Battle.View.EntityViewBase"
local BattleLayers = require "Game.Battle.BattleLayers"

local UnityEngine = CS.UnityEngine

local DropView = Class.Define("DropView")

-- 继承视图基类：浮动/旋转由 UpdateManager 全局驱动，
-- 不再依赖 DropSystem 每帧喂 dt（战斗 Pause/结束时掉落物会僵住）
Class.Extend(DropView, EntityViewBase)

local MATERIAL_COLOR = {
    m_wing = { 0.6, 0.4, 0.9 },
}

function DropView:OnCreate(go)
    EntityViewBase.OnCreate(self, go)
    self.baseY = BattleLayers.Drop
end

function DropView:Setup(drop)
    drop = drop or {}
    self.kind = drop.kind or "material"
    self.x = drop.x or 0
    self.y = drop.y or 0
    self.bobPhase = (self.x + self.y) * 1.7

    local cfg = _G.ViewConfig or {}
    local prefab
    if self.kind == "weapon" then
        prefab = cfg.dropWeapon
    elseif self.kind == "item" then
        prefab = cfg.dropItem
    else
        prefab = cfg.dropMaterial
    end

    if prefab then
        local inst = UnityEngine.Object.Instantiate(prefab)
        inst.transform:SetParent(self.transform, false)
        self.model = inst
    else
        self.model = self:_buildFallback(self.kind, drop.refId)
        self.model.transform:SetParent(self.transform, false)
    end

    self:Update(0)
end

--- 兜底几何体（仅在对应 prefab 缺失时使用）
function DropView:_buildFallback(kind, refId)
    local go = UnityEngine.GameObject("DropModel")
    if kind == "weapon" then
        local blade = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Cube)
        blade.transform:SetParent(go.transform, false)
        blade.transform.localScale = UnityEngine.Vector3(0.12, 0.7, 0.12)
        blade.transform.localPosition = UnityEngine.Vector3(0, 0.35, 0)
        local guard = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Cube)
        guard.transform:SetParent(go.transform, false)
        guard.transform.localScale = UnityEngine.Vector3(0.4, 0.1, 0.1)
        EntityViewFactory.Tint(go, 0.5, 0.9, 1.0, true)
    elseif kind == "item" then
        local box = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Cube)
        box.transform:SetParent(go.transform, false)
        box.transform.localScale = UnityEngine.Vector3(0.5, 0.5, 0.5)
        EntityViewFactory.Tint(go, 1.0, 0.85, 0.2, true)
    else
        local m = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Sphere)
        m.transform:SetParent(go.transform, false)
        m.transform.localScale = UnityEngine.Vector3(0.45, 0.45, 0.45)
        local c = MATERIAL_COLOR[refId] or { 0.3, 0.9, 0.4 }
        EntityViewFactory.Tint(go, c[1], c[2], c[3], true)
    end
    return go
end

---每帧浮动 + 旋转（由基类 Tick 驱动）
function DropView:Update(dt)
    if not self.transform then return end
    local t = UnityEngine.Time.time
    local y = self.baseY + math.sin(t * 3 + (self.bobPhase or 0)) * 0.15
    self.transform.position = UnityEngine.Vector3(self.x or 0, y, self.y or 0)
    self.transform:Rotate(UnityEngine.Vector3(0, 60 * dt, 0))
end

function DropView:OnDestroy()
    EntityViewBase.OnDestroy(self)
    self.model = nil
end

-- 不重写 Destroy：继承基类（注销 tick + 销毁 GameObject）

return DropView
