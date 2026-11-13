--[[
=============================================================================
EntityViewFactory.lua
=============================================================================
战斗实体的「Lua 组件」工厂。逻辑层（EnemyManager / DropSystem / BulletManager）
通过这里创建挂了 LuaViewBehaviour 的实体 GameObject，拿到 Lua View 实例后调用
:Setup(data) 把业务数据（兵种/武器/坐标…）传入（Lua→Lua，始终是原生 table）。

设计：
  - 实体 GameObject 上挂的是通用 Lua 组件 LuaViewBehaviour（C#）
  - Lua View 类在 OnCreate 里只拿到 GameObject，Setup 里 Instantiate 真实 prefab
    （人形模型 / 掉落模型 / 子弹），全部表现由 Lua 直接驱动，不再有 C# 轮询 CreatePrimitive
=============================================================================
]]

local CS = CS
local UnityEngine = CS.UnityEngine
local Logger = require "Framework.UI.Utils.Logger"

local EntityViewFactory = {}

-- Lua 5.1 用全局 unpack，Lua 5.3+ 用 table.unpack，这里做兼容
local unpack_ = table.unpack or unpack

--- 取得 ViewConfig（C# 在战斗绑定时注入的 prefab 引用表）
local function ViewConfig()
    return _G.ViewConfig or {}
end

--- 统一创建入口：C# 在 LuaEnv 未就绪 / Bind 失败时会返回 nil，
-- 这里必须兜住，否则调用方 view:Setup() 直接崩。返回 nil 时逻辑层按「无表现」降级。
local function createView(className, ...)
    -- 变长参数不能在闭包内直接用 '...'：闭包不是 vararg 函数，会导致模块加载期语法错误
    -- （cannot use '...' outside a vararg function）。必须先收集到局部表，再在闭包内 unpack。
    local args = {...}
    local ok, view = pcall(function()
        return CS.Game.View.LuaViewFactory.Create(className)
    end)
    if not ok or not view then
        Logger.Warn("EntityViewFactory", "create view failed: %s", tostring(className))
        return nil
    end

    local okSetup, err = pcall(function() view:Setup(unpack_(args)) end)
    if not okSetup then
        Logger.Warn("EntityViewFactory", "Setup failed on %s: %s",
            tostring(className), tostring(err))
    end
    return view
end

--- 创建敌人视图（敌人/怪物都复用同一个人形 prefab，靠颜色+缩放区分）
function EntityViewFactory.CreateEnemyView(enemy)
    return createView("Game.Battle.View.EnemyView", enemy)
end

--- 创建掉落物视图（武器/材料/道具，模型各不相同）
function EntityViewFactory.CreateDropView(drop)
    return createView("Game.Battle.View.DropView", drop)
end

--- 创建子弹视图（bulletType 决定元素弹体；无配置时回退按阵营染色的发光小球）
function EntityViewFactory.CreateBulletView(faction, bulletType)
    return createView("Game.Battle.View.BulletView", faction, bulletType)
end

--- 工具：遍历 root 下所有 Renderer 并设置颜色（含发光，便于在暗色战场可见）
function EntityViewFactory.Tint(rootGo, r, g, b, emissive)
    if not rootGo then return end
    local renderers = rootGo:GetComponentsInChildren(typeof(UnityEngine.Renderer))
    if renderers then
        for i = 0, renderers.Length - 1 do
            local rd = renderers[i]
            local mat = rd.material
            if mat then
                mat.color = UnityEngine.Color(r, g, b, 1)
                if emissive then
                    pcall(function()
                        mat:EnableKeyword("_EMISSION")
                        mat:SetColor("_EmissionColor", UnityEngine.Color(r * 0.5, g * 0.5, b * 0.5, 1))
                    end)
                end
            end
        end
    end
end

return EntityViewFactory
