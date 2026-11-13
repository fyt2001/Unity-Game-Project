--[[
=============================================================================
BulletView.lua
=============================================================================
子弹表现层（Lua 组件）。

  - Setup(faction, bulletType)：
      * bulletType 在 VFXConfig.Bullet 里有配置时，实例化对应元素弹体
        （Projectiles_frost / fire / magic…）作为子弹本体。
        弹体由 head(弹头) + trail(TrailRenderer 拖尾) 构成，**依赖运动才生效**，
        所以只能挂在会移动的子弹上，不能当静态爆点生成。
      * 否则回退 ViewConfig.bulletPlayer / bulletEnemy，再兜底发光小球。
  - SetPosition：每帧同步坐标，并按移动方向转向（弹头才不会永远朝同一边）。
  - ResetVisual：从对象池复用前调用（清拖尾 + 重播粒子），否则会拉丝 / 没特效。

元素弹体保留素材原色，不按阵营染色（染色会毁掉美术配色）。
=============================================================================
]]

local Class = require "Framework.Core.Class"
local EntityViewFactory = require "Game.Battle.View.EntityViewFactory"
local EntityViewBase = require "Game.Battle.View.EntityViewBase"
local BattleLayers = require "Game.Battle.BattleLayers"
local VFXConfig = require "Game.Battle.VFXConfig"
local Logger = require "Framework.UI.Utils.Logger"

local UnityEngine = CS.UnityEngine

local BulletView = Class.Define("BulletView")

Class.Extend(BulletView, EntityViewBase)

local FACTION_COLOR = {
    player = { 1.0, 0.85, 0.2 },
    enemy  = { 1.0, 0.3, 0.25 },
}

function BulletView:OnCreate(go)
    EntityViewBase.OnCreate(self, go)
    self.faction = "player"
    self.bulletType = "normal"
    self._useVfx = false
end

function BulletView:Setup(faction, bulletType)
    self.faction = faction or "player"
    self.bulletType = bulletType or "normal"

    local cfg = _G.ViewConfig or {}
    local vfxPath = VFXConfig.Bullet and VFXConfig.Bullet[self.bulletType]
    local prefab = nil

    -- 元素弹体：从 Resources 取（Unity 会缓存已加载资源，重复 Load 不额外开销）
    if vfxPath and vfxPath ~= "" then
        prefab = UnityEngine.Resources.Load(vfxPath)
        self._useVfx = prefab ~= nil
    end

    if not prefab then
        self._useVfx = false
        prefab = (self.faction == "enemy") and cfg.bulletEnemy or cfg.bulletPlayer
    end

    if prefab then
        local inst = UnityEngine.Object.Instantiate(prefab)
        inst.transform:SetParent(self.transform, false)
        -- 弹体预制体的根节点自带偏移（如 Projectiles_fire 是 x=1.47，子物体全为 0），
        -- 这是美术在预制体内部挪过整体；挂到子弹上必须归零，
        -- 否则特效会飘在子弹前方 1.47 单位处，看起来跟子弹脱节。
        if self._useVfx then
            inst.transform.localPosition = UnityEngine.Vector3.zero
        end
        self.model = inst
    else
        local sphere = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Sphere)
        sphere.transform:SetParent(self.transform, false)
        sphere.transform.localScale = UnityEngine.Vector3(0.4, 0.4, 0.4)
        self.model = sphere
    end

    self._lastX = nil
    self._lastY = nil

    self:SetFaction(self.faction)
    self.go:SetActive(true)
end

function BulletView:SetFaction(faction)
    self.faction = faction or "player"
    -- 元素弹体保留素材原色，不按阵营染色
    if self._useVfx then return end
    local c = FACTION_COLOR[self.faction] or FACTION_COLOR.player
    EntityViewFactory.Tint(self.go, c[1], c[2], c[3], true)
end

---每帧同步坐标并按移动方向转向（同 EnemyView 约定：atan(dx, dy)，不用 atan2）
function BulletView:SetPosition(x, y, height)
    if not self.transform then return end
    self.transform.position = UnityEngine.Vector3(x, height or BattleLayers.Projectile, y)

    if self._lastX then
        local dx = x - self._lastX
        local dy = y - self._lastY
        if dx * dx + dy * dy > 0.00000001 then
            -- 弹体前向轴是 +X，不是 +Z：
            -- head / head_glow 预旋转了 +90°(绕 Y)，把粒子默认的 +Z 发射方向掰到了 +X。
            -- 所以要让「+X 轴」对齐行进方向，而不是沿用 EnemyView 的 +Z 公式（会偏 90°）。
            -- 绕 Y 转 θ 时，+X(1,0,0) → (cosθ, 0, -sinθ)；
            -- 令其等于行进方向 (dx, 0, dy) ⇒ cosθ=dx, sinθ=-dy ⇒ θ = atan(-dy, dx)。
            local yaw = math.atan(-dy, dx) * 180 / math.pi
            self.transform.rotation = UnityEngine.Quaternion.Euler(0, yaw, 0)
        end
    end

    self._lastX = x
    self._lastY = y
end

---清空所有拖尾。
-- TrailRenderer 不会因 SetActive(false/true) 而重置，会残留上一次飞行路径的点。
-- includeInactive = true：停用的子物体上的拖尾也要清到。
function BulletView:ClearTrails()
    if not self.model then return end

    local ok, err = pcall(function()
        local trails = self.model:GetComponentsInChildren(typeof(UnityEngine.TrailRenderer), true)
        if trails then
            for i = 0, trails.Length - 1 do
                trails[i]:Clear()
            end
        end
    end)

    -- 只报一次：每条子弹都刷屏没意义，但完全静默又会像这次一样查不出问题
    if not ok and not BulletView._trailWarned then
        BulletView._trailWarned = true
        Logger.Warn("BulletView", "ClearTrails failed: %s", tostring(err))
    end
end

---复用整体重置：清转向基准 + 重播粒子 + 清拖尾。
function BulletView:ResetVisual()
    if not self.model then return end
    -- 转向基准点一起清掉，避免复用首帧按旧坐标算出一个错误朝向
    self._lastX = nil
    self._lastY = nil

    -- 一次性粒子（looping:0）复用时不会自动重播，必须手动 Clear + Play
    local ok, err = pcall(function()
        local pss = self.model:GetComponentsInChildren(typeof(UnityEngine.ParticleSystem), true)
        if pss then
            for i = 0, pss.Length - 1 do
                pss[i]:Clear()
                pss[i]:Play()
            end
        end
    end)
    if not ok and not BulletView._psWarned then
        BulletView._psWarned = true
        Logger.Warn("BulletView", "particle restart failed: %s", tostring(err))
    end

    self:ClearTrails()
end

function BulletView:SetActive(v)
    if self.go then self.go:SetActive(v) end
end

function BulletView:OnDestroy()
    EntityViewBase.OnDestroy(self)
    self.model = nil
end

-- 不重写 Destroy：继承基类（注销 tick + 销毁 GameObject）

return BulletView
