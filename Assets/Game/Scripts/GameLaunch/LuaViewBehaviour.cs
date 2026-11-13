// =============================================================================
// LuaViewBehaviour.cs
// =============================================================================
// 通用「Lua 组件」绑定器：把一个 Lua View 类挂到任意 GameObject 上，
// 由 Lua 直接驱动该实体的表现（模型 / 坐标 / 动画 / 销毁）。
//
// 这是战斗表现层规范化的核心：
//   - 实体 GameObject 上挂一个 LuaViewBehaviour（即「Lua 组件」）
//   - Lua View 类在 OnCreate 里 Instantiate 真实 prefab（人形模型 / 掉落模型 / 子弹）
//   - 逻辑层（EnemyManager / DropSystem / BulletManager）只持有 Lua View 实例，
//     调用 :SetPosition / :OnDead / :Destroy 等方法，不再由 C# 轮询 CreatePrimitive。
//
// 与 Model3DCharacterView 的关系：玩家用 Model3DCharacterView（C# 视图组件 + 模型 prefab）。
// 战斗实体用本通用 Lua 组件，但底层同样 Instantiate 真实 prefab，遵循同一套「预制体 + 组件」规范。
// =============================================================================

using UnityEngine;
using XLua;

namespace Game.View
{
    /// <summary>
    /// 挂在实体 GameObject 上的通用 Lua 组件。Bind 时按类名 require 出 Lua View 类，
    /// 调用其 New() 得到实例，再调用实例的 OnCreate(go, initArgs)。
    /// </summary>
    [LuaCallCSharp]
    public class LuaViewBehaviour : MonoBehaviour
    {
        private LuaTable _luaInstance;

        /// <summary>
        /// 绑定一个 Lua View 类到本 GameObject。OnCreate(go) 仅接收 GameObject；
        /// 业务数据（兵种 / 武器 / 坐标等）由 Lua 侧在创建后直接调用视图的 Setup(...) 传入，
        /// 避免 Lua table 经 C#（LuaTable userdata）往返后无法按字段索引的问题。
        /// </summary>
        /// <param name="className">require 路径，如 "Game.Battle.View.EnemyView"</param>
        public void Bind(string className)
        {
            var env = XLuaManager.Instance != null ? XLuaManager.Instance.GetLuaEnv() : null;
            if (env == null)
            {
                Debug.LogError("[LuaViewBehaviour] LuaEnv is null, cannot bind " + className);
                return;
            }

            try
            {
                object[] clsArr = env.DoString("return require('" + className + "')");
                using var cls = clsArr != null && clsArr.Length > 0 ? clsArr[0] as LuaTable : null;
                if (cls == null)
                {
                    Debug.LogError("[LuaViewBehaviour] class not found: " + className);
                    return;
                }

                using var newFn = cls.Get<LuaFunction>("New");
                if (newFn == null)
                {
                    Debug.LogError("[LuaViewBehaviour] New() missing on " + className);
                    return;
                }

                object[] instArr = newFn.Call(cls);
                _luaInstance = instArr != null && instArr.Length > 0 ? instArr[0] as LuaTable : null;
                if (_luaInstance == null)
                {
                    Debug.LogError("[LuaViewBehaviour] New() returned nil: " + className);
                    return;
                }

                using var onCreate = _luaInstance.Get<LuaFunction>("OnCreate");
                onCreate?.Call(_luaInstance, gameObject);
            }
            catch (System.Exception e)
            {
                Debug.LogError($"[LuaViewBehaviour] Bind {className} error: {e.Message}");
            }
        }

        /// <summary>
        /// 取回绑定的 Lua View 实例（逻辑层持有它来驱动表现）。
        /// </summary>
        public LuaTable GetLuaInstance()
        {
            return _luaInstance;
        }

        private void OnDestroy()
        {
            ReleaseLuaBindings();
        }

        internal void ReleaseLuaBindings()
        {
            var instance = _luaInstance;
            _luaInstance = null;
            if (instance != null)
            {
                try
                {
                    using var onDestroy = instance.Get<LuaFunction>("OnDestroy");
                    onDestroy?.Call(instance);
                }
                catch (System.Exception e)
                {
                    Debug.LogWarning("[LuaViewBehaviour] OnDestroy error: " + e.Message);
                }

                finally { instance.Dispose(); }
            }
        }
    }

    /// <summary>
    /// Lua 侧用来创建「带 Lua 组件的实体」的工厂。Lua 直接调用：
    ///   local view = CS.Game.View.LuaViewFactory.Create("Game.Battle.View.EnemyView")
    ///   view:Setup(enemy)   -- 业务数据由 Lua 直接传入（Lua→Lua，始终为原生 table）
    /// </summary>
    [LuaCallCSharp]
    public static class LuaViewFactory
    {
        /// <summary>
        /// 创建挂了 LuaViewBehaviour 的实体 GameObject，并返回绑定的 Lua View 实例。
        /// </summary>
        public static LuaTable Create(string className)
        {
            var go = new GameObject("LuaView_" + className);
            var beh = go.AddComponent<LuaViewBehaviour>();
            beh.Bind(className);
            return beh.GetLuaInstance();
        }
    }
}
