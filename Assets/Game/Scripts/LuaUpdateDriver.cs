// =============================================================================
// LuaUpdateDriver.cs
// =============================================================================
// 挂载到场景中，每帧调用 Lua UpdateManager 驱动所有逻辑。
// 与 LuaGameBootstrap 分离，方便管理 Update 生命周期。
// =============================================================================

using UnityEngine;
using XLua;
using System;

[LuaCallCSharp]
public class LuaUpdateDriver : MonoBehaviour
{
    [Header("Update 配置")]
    [Tooltip("Update 间隔（毫秒），0 表示每帧调用")]
    public int updateIntervalMs = 0;

    [Tooltip("是否启用")]
    public bool enabled_driver = true;

    // Lua 函数引用
    private LuaFunction onUpdateFunc;
    private LuaFunction onLateUpdateFunc;
    private LuaFunction onFixedUpdateFunc;

    private float _timerUpdateAccum = 0f;
    private float _timerIntervalSec = 0f;

    void Start()
    {
        if (updateIntervalMs > 0)
        {
            _timerIntervalSec = updateIntervalMs / 1000f;
        }

        // 从 LuaEnv 获取 UpdateManager 的函数引用
        var luaEnv = FindObjectOfType<LuaGameBootstrap>()?.GetLuaEnv();
        if (luaEnv != null)
        {
            onUpdateFunc = luaEnv.Global.GetInPath<LuaFunction>(
                "Framework.UpdateManager.GetInstance().OnUpdate");
            onLateUpdateFunc = luaEnv.Global.GetInPath<LuaFunction>(
                "Framework.UpdateManager.GetInstance().OnLateUpdate");
            onFixedUpdateFunc = luaEnv.Global.GetInPath<LuaFunction>(
                "Framework.UpdateManager.GetInstance().OnFixedUpdate");
        }
    }

    void Update()
    {
        if (!enabled_driver || onUpdateFunc == null) return;

        try
        {
            if (updateIntervalMs <= 0)
            {
                // 每帧调用
                onUpdateFunc.Call(Time.deltaTime);
            }
            else
            {
                // 定时调用
                _timerUpdateAccum += Time.deltaTime;
                while (_timerUpdateAccum >= _timerIntervalSec)
                {
                    _timerUpdateAccum -= _timerIntervalSec;
                    onUpdateFunc.Call(_timerIntervalSec);
                }
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"[LuaUpdateDriver] Update error: {e.Message}");
        }
    }

    void LateUpdate()
    {
        if (!enabled_driver || onLateUpdateFunc == null) return;
        try
        {
            onLateUpdateFunc.Call(Time.deltaTime);
        }
        catch (Exception e)
        {
            Debug.LogError($"[LuaUpdateDriver] LateUpdate error: {e.Message}");
        }
    }

    void FixedUpdate()
    {
        if (!enabled_driver || onFixedUpdateFunc == null) return;
        try
        {
            onFixedUpdateFunc.Call(Time.fixedDeltaTime);
        }
        catch (Exception e)
        {
            Debug.LogError($"[LuaUpdateDriver] FixedUpdate error: {e.Message}");
        }
    }

    void OnDestroy()
    {
        onUpdateFunc?.Dispose();
        onLateUpdateFunc?.Dispose();
        onFixedUpdateFunc?.Dispose();
    }
}
