--[[
=============================================================================
EnemyView.lua
=============================================================================
敌人/怪物表现层（Lua 组件）。
  - OnCreate(go)：仅缓存 GameObject / Transform。
  - Setup(enemy)：Instantiate 人形 prefab（ViewConfig.enemyModel）作子物体，
    按兵种染色 + 缩放；持武敌人（skeleton）额外挂一把武器子模型。
  - SetPosition：每帧同步坐标，并按移动方向转向（面朝玩家）。
  - OnDead：死亡瞬间的小特效。
  - 销毁由 LuaViewBehaviour.OnDestroy 统一处理（销毁 GameObject 即销毁一切）。

兵种外观（全复用现成人形模型，靠颜色+缩放区分）：
  skeleton → 骨白，scale 1.0，挂武器
  slime    → 绿，  scale 0.85
  bat      → 紫，  scale 0.9
  boss     → 红，  scale 1.7
=============================================================================
]]

local Class = require "Framework.Core.Class"
local EntityViewFactory = require "Game.Battle.View.EntityViewFactory"
local EntityViewBase = require "Game.Battle.View.EntityViewBase"
local BattleLayers = require "Game.Battle.BattleLayers"

local UnityEngine = CS.UnityEngine

local EnemyView = Class.Define("EnemyView")

-- 继承视图基类：获得 UpdateManager 驱动的每帧 Update 与自我销毁能力
Class.Extend(EnemyView, EntityViewBase)

-- 各兵种外观参数（颜色 r,g,b / 整体缩放）
local LOOK = {
    skeleton = { r = 0.90, g = 0.90, b = 0.78, scale = 1.0 },
    slime    = { r = 0.82, g = 0.72, b = 0.55, scale = 0.85 },
    bat      = { r = 0.60, g = 0.35, b = 0.90, scale = 0.9 },
    boss     = { r = 0.90, g = 0.20, b = 0.20, scale = 1.7 },
}
local DEFAULT_LOOK = { r = 0.8, g = 0.8, b = 0.8, scale = 1.0 }

function EnemyView:OnCreate(go)
    -- 基类：缓存 go / transform，并向 UpdateManager 注册逐帧 tick
    EntityViewBase.OnCreate(self, go)

    self._lastX = 0
    self._lastY = 0
    self._flashTimer = 0     -- 受击闪红剩余时间
    self._punchTimer = 0     -- 受击缩放脉冲剩余时间
    self._dying = false      -- 进入死亡表现中
    self._deathTimer = 0     -- 死亡表现剩余时间（到点自毁）
    self._deathDuration = 0
    self._deathAnimated = false
    self._prevX = nil        -- 上一帧坐标（用于推算移动速度）
    self._prevY = nil
    self._speed = 0          -- 平滑后的移动速度（喂给 BlendTree）
end

function EnemyView:Setup(enemy)
    enemy = enemy or {}
    self.enemyType = enemy.enemyType
    self.weaponId = enemy.weaponId
    self.look = LOOK[self.enemyType] or DEFAULT_LOOK

    local cfg = _G.ViewConfig or {}

    -- 1) Instantiate 人形模型 prefab（真实预制体，非 C# 几何体）
    if cfg.enemyModel then
        self.model = UnityEngine.Object.Instantiate(cfg.enemyModel)
        self.model.transform:SetParent(self.transform, false)
        EntityViewFactory.Tint(self.model, self.look.r, self.look.g, self.look.b, false)
    else
        -- 兜底占位（ViewConfig 未注入时仍能跑，只是无外观）
        self.model = UnityEngine.GameObject("FallbackBody")
        self.model.transform:SetParent(self.transform, false)
    end

    -- 缓存 Animator：攻击动作（Punch/SwordSlash/Shoot_OneHanded）触发用
    self.animator = self.model and self.model:GetComponent(typeof(UnityEngine.Animator)) or nil

    -- 缓存 Renderer 材质：受击闪红要每帧改色，这里一次性拿好，
    -- 避免每次受击都跑 GetComponentsInChildren（高频，且会反复实例化材质）
    self.materials = {}
    if self.model then
        local rds = self.model:GetComponentsInChildren(typeof(UnityEngine.Renderer))
        if rds then
            for i = 0, rds.Length - 1 do
                local mat = rds[i].material
                if mat then self.materials[#self.materials + 1] = mat end
            end
        end
    end

    -- 整体缩放
    self.transform.localScale = UnityEngine.Vector3(self.look.scale, self.look.scale, self.look.scale)

    -- 2) 持武敌人挂武器子模型
    if self.weaponId then
        self:_attachWeapon(self.weaponId)
    end

    -- 3) 初始坐标 + 朝向
    self._lastX = enemy.x or 0
    self._lastY = enemy.y or 0
    self:SetPosition(enemy.x or 0, enemy.y or 0)
end

---在持武敌人手上挂一把小剑
-- 说明：ViewConfig 里没有 weaponModel 字段（C# InjectViewConfig 未注入，
-- 也不准备为敌人单独做武器 prefab），因此这里统一用几何体组合。
-- 若将来真的接入了武器 prefab，只需在 ViewConfig 注入 weaponModel，
-- 下面的分支会自动生效。
function EnemyView:_attachWeapon(weaponId)
    local cfg = _G.ViewConfig or {}
    local weapon = nil

    if cfg.weaponModel then
        weapon = UnityEngine.Object.Instantiate(cfg.weaponModel)
    else
        weapon = UnityEngine.GameObject("Weapon")
        local blade = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Cube)
        blade.name = "Blade"
        blade.transform:SetParent(weapon.transform, false)
        blade.transform.localScale = UnityEngine.Vector3(0.06, 0.6, 0.06)
        blade.transform.localPosition = UnityEngine.Vector3(0, 0.3, 0)
        local guard = UnityEngine.GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Cube)
        guard.name = "Guard"
        guard.transform:SetParent(weapon.transform, false)
        guard.transform.localScale = UnityEngine.Vector3(0.28, 0.06, 0.06)
        guard.transform.localPosition = UnityEngine.Vector3(0, 0, 0)
        EntityViewFactory.Tint(weapon, 0.7, 0.85, 1.0, false)
    end

    weapon.transform:SetParent(self.transform, false)
    -- 右手位置（人形面向 +Z 时，右手约在 +X 侧）
    weapon.transform.localPosition = UnityEngine.Vector3(0.45, 0.9, 0.15)
    weapon.transform.localRotation = UnityEngine.Quaternion.Euler(0, 0, -35)
    self.weapon = weapon
end

--- 每帧同步坐标并按移动方向转向
function EnemyView:SetPosition(x, y, facingX, facingY, dt)
    if not self.transform then return end
    self.transform.position = UnityEngine.Vector3(x, BattleLayers.Ground, y)

    local dx = facingX or (x - self._lastX)
    local dy = facingY or (y - self._lastY)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0.0001 then
        local yaw = math.atan(dx, dy) * 180 / math.pi
        local target = UnityEngine.Quaternion.Euler(0, yaw, 0)
        self.transform.rotation = dt and UnityEngine.Quaternion.RotateTowards(
            self.transform.rotation, target, 360 * dt) or target
    end
    self._lastX = x
    self._lastY = y
end

--- 播放一次性动作（Punch / Shoot_OneHanded / Hit …）。
-- ⚠ 不要在这里手动“播完再切回某个状态”：这些状态【自带出边】回到 Locomotion，
--   额外强制切换只会打断 crossfade。没有出边的状态（如 Death）另作处理。
---@return boolean 是否真的播了（控制器里没有该状态则为 false）
function EnemyView:_playOneShot(stateName)
    if not self.animator then return false end

    local ok, played = pcall(function()
        if not self.animator:HasState(0, UnityEngine.Animator.StringToHash(stateName)) then
            return false
        end
        self.animator:Play(stateName, 0, 0)
        return true
    end)

    return ok and played
end

--- 触发攻击动作（type: "Punch" 徒手 / "SwordSlash" 剑斩 / "Shoot_OneHanded" 射击）
function EnemyView:PlayAttack(attackType)
    if not self.animator then return end
    local name = attackType or "Punch"
    if not self:_playOneShot(name) then
        pcall(function() self.animator:Play(name) end)
    end
end

-- =============================================================================
-- 受击 / 死亡表现
-- C# LuaViewBehaviour 只派发 OnCreate/OnDestroy、不带 Update；
-- 逐帧驱动由基类 EntityViewBase 通过 UpdateManager 完成，
-- 逻辑层（EnemyManager / BattleManager）不需要、也不应该再喂 dt。
-- =============================================================================

local FLASH_TIME  = 0.12   -- 闪红持续
local FLASH_COLOR = { r = 1.0, g = 0.35, b = 0.35 }
local PUNCH_TIME  = 0.15   -- 缩放脉冲持续
local PUNCH_SCALE = 0.18   -- 脉冲峰值放大比例

--- BlendTree 的混合参数名，必须与 ViewPrefabBuilder.LocoParam 一致
local LOCOMOTION_PARAM = "Speed"

--- locomotion：用坐标变化推算速度，喂给 BlendTree 的 Speed 参数。
-- 速度为 0 → Stand；到 Run 阈值以上 → 完全跑步。不需要判定「是否在移动」，
-- 由 Animator 按实际速度自动混合（controller 由 Tools/Battle 生成流程建立）。
---@param dt number 帧间隔
function EnemyView:_updateLocomotion(dt)
    if not self.animator or not dt or dt <= 0 then return end

    local dx = self._lastX - (self._prevX or self._lastX)
    local dy = self._lastY - (self._prevY or self._lastY)
    self._prevX, self._prevY = self._lastX, self._lastY

    local dist = math.sqrt(dx * dx + dy * dy)
    local speed = dist / dt

    -- 平滑：否则单帧抖动会让 Stand/Walk 之间反复横跳
    local k = math.min(1, dt * 12)
    self._speed = self._speed + (speed - self._speed) * k

    pcall(function() self.animator:SetFloat(LOCOMOTION_PARAM, self._speed) end)
end

--- 每帧驱动：由基类 EntityViewBase 的 Tick 自动调用，
-- 不再需要 EnemyManager 喂 dt —— 否则敌人死亡与战斗结束同帧发生时
-- （Boss 死亡即 Victory）没人再推进，尸体的收尾会整个卡住。
function EnemyView:Update(dt)
    if not self.transform then return end

    -- 死亡表现：自己走计时，到点自己销毁
    if self._dying then
        self:_tickDeath(dt)
        return
    end

    self:_updateLocomotion(dt)

    if self._flashTimer > 0 then
        self._flashTimer = self._flashTimer - dt
        if self._flashTimer <= 0 then
            self._flashTimer = 0
            self:_tint(self.look.r, self.look.g, self.look.b)
        end
    end

    if self._punchTimer > 0 then
        self._punchTimer = self._punchTimer - dt
        local k = math.max(0, self._punchTimer / PUNCH_TIME)
        if k <= 0 then
            self:_setUniformScale(self.look.scale)
        else
            self:_setUniformScale(self.look.scale * (1 + PUNCH_SCALE * k))
        end
    end
end

--- 受击反馈：闪红 + 缩放脉冲（EnemyManager:TakeDamage 未致死时调用）
---@param isHeavy boolean|nil 精英 / Boss：额外播美术的受击动作（RecieveHit）。
--   普通怪刻意不播：受击过于频繁，每次都打断移动动画会抽搐。
function EnemyView:FlashHit(isHeavy)
    if not self.transform or self._dying then return end
    self._flashTimer = FLASH_TIME
    self._punchTimer = PUNCH_TIME
    self:_tint(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b)

    if isHeavy then self:_playOneShot("Hit") end
end

---死亡姿态（体量越大倒得越夸张：tan=横向膨胀 / squash=纵向压扁 / sink=下沉 / tilt=侧倒角）
EnemyView.DEATH_STYLE = {
    normal = { time = 0.45, tilt = 85,  sink = 0.35, bulge = 0.5, squash = 0.50 },
    elite  = { time = 0.70, tilt = 95,  sink = 0.45, bulge = 0.7, squash = 0.40 },
    boss   = { time = 1.30, tilt = 110, sink = 0.80, bulge = 0.9, squash = 0.35 },
}

---播放美术的死亡动作（首选方案）
-- 前提是 EnemyModel 用的控制器里有 Death 状态（由 Tools/Battle 的生成流程补齐，
-- 动作来自 BaseCharacter.fbx 自带的 Death clip，非手写动画）。
---@return number|nil 动画时长（秒）；nil=没有可用死亡动作，调用方应回退到程序化塌陷
function EnemyView:_playDeathAnim()
    if not self.animator then return nil end

    local ok, len = pcall(function()
        -- 控制器里没这个状态（美术未导入 / 用了旧 prefab）就直接放弃
        if not self.animator:HasState(0, UnityEngine.Animator.StringToHash("Death")) then
            return nil
        end
        self.animator:Play("Death", 0, 0)

        -- 取 clip 长度作为「多久后销毁」：动画播完才消失，避免动作被截断
        local ctrl = self.animator.runtimeAnimatorController
        if ctrl and ctrl.animationClips then
            for i = 0, ctrl.animationClips.Length - 1 do
                local clip = ctrl.animationClips[i]
                local name = clip and clip.name or ""
                if name:lower():sub(-5) == "death" then return clip.length end
            end
        end
        return nil
    end)

    if ok then return len end
    return nil
end

---进入死亡表现：优先播死亡动画，没有才退回程序化塌陷。
-- 时长由视图自己持有并在 _tickDeath 里倒计时，播完自毁，
-- 不依赖外部有没有人继续喂 dt。
---@param kind string|nil "normal" | "elite" | "boss"，缺省 normal
function EnemyView:OnDead(kind)
    -- 同帧会被触发两次：TakeDamage 里一次、随后 _flushRemoved 又一次。
    -- 没有这个守卫，Death 动画会从头重播、销毁计时被重置（尸体残留翻倍）。
    if self._dying or self._destroyed then return end
    if not self.transform then return end
    self._dying = true

    local animLen = self:_playDeathAnim()
    if animLen and animLen > 0 then
        self._deathAnimated = true
        self._deathTimer = animLen
        self._deathDuration = animLen
        return
    end

    -- 兜底：没有死亡动画时才用塌陷
    self._deathAnimated = false
    self._deathStyle = EnemyView.DEATH_STYLE[kind] or EnemyView.DEATH_STYLE.normal
    self._deathTimer = self._deathStyle.time
    self._deathDuration = self._deathTimer
end

---死亡倒计时（由基类 Tick 每帧驱动）
function EnemyView:_tickDeath(dt)
    self._deathTimer = self._deathTimer - dt

    -- 播了美术的 Death 动画时不再叠加塌陷，让动作自己播完整
    if not self._deathAnimated then
        self:SetDeathProgress(math.max(0, self._deathTimer / self._deathDuration))
    end

    if self._deathTimer <= 0 then
        self:Destroy()
    end
end

---死亡塌陷进度：t 从 1 → 0（收缩 + 下沉 + 侧倒）
function EnemyView:SetDeathProgress(t)
    if not self.transform then return end

    t = math.max(0, math.min(1, t or 0))
    local st = self._deathStyle or EnemyView.DEATH_STYLE.normal

    -- e = 消亡程度 0→1，取 1-t²：刚死的一瞬变化最快，末尾趋于平缓（失重倒下的手感）
    local e = 1 - t * t
    local k = 1 - t
    local s = self.look.scale * t

    local bulge  = 1 + k * st.bulge
    local squash = st.squash + (1 - st.squash) * t
    local sink   = -e * st.sink
    local tilt   = e * st.tilt

    pcall(function()
        self.transform.localScale = UnityEngine.Vector3(
            self.look.scale * bulge, s * squash, self.look.scale * bulge
        )
        self.transform.rotation = UnityEngine.Quaternion.Euler(
            0, self.transform.rotation.eulerAngles.y, tilt
        )
        self.transform.position = UnityEngine.Vector3(
            self._lastX, sink, self._lastY
        )
    end)
end

--- 批量设置材质颜色（直接用 Setup 阶段缓存的材质）
function EnemyView:_tint(r, g, b)
    if not self.materials then return end
    pcall(function()
        for _, mat in ipairs(self.materials) do
            mat.color = UnityEngine.Color(r, g, b, 1)
        end
    end)
end

function EnemyView:_setUniformScale(s)
    if not self.transform then return end
    pcall(function()
        self.transform.localScale = UnityEngine.Vector3(s, s, s)
    end)
end

function EnemyView:OnDestroy()
    -- 基类：注销 UpdateManager 的 tick（子类覆盖了 OnDestroy，必须显式回调）
    EntityViewBase.OnDestroy(self)

    self.model = nil
    self.weapon = nil
    self.materials = nil
end

-- 不重写 Destroy：直接继承基类实现（注销 tick + 销毁 GameObject），
-- 避免「子类只删了 GameObject、tick 却还留着」的泄漏。

return EnemyView
