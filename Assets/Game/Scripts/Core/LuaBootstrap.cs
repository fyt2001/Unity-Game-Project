// =============================================================================
// LuaBootstrap.cs - Lua 启动引导器（升级版，使用 XLuaManager + GameLaunch 架构）
// =============================================================================
// 替代原有的 LuaGameBootstrap.cs。
// 使用企业级 XLuaManager + GameLaunch 启动链架构。
// =============================================================================

using UnityEngine;

/// <summary>
/// Lua 启动引导器（简化版）。
/// 挂载到场景 GameObject 上，通过 GameLaunch + XLuaManager 完成完整启动流程。
/// 如果场景中已有 GameLaunch 组件，则不需要此组件。
/// </summary>
public class LuaBootstrap : MonoBehaviour
{
    [Header("启动配置")]
    [Tooltip("Lua 加载模式")]
    public LuaLoadMode LoadMode = LuaLoadMode.Editor;

    [Tooltip("是否在 Awake 时自动启动")]
    public bool AutoStart = true;

    [Tooltip("是否自动启动战斗（编辑器测试用）")]
    public bool AutoStartBattle = false;

    private void Awake()
    {
        if (AutoStart)
        {
            // 检查是否已有 GameLaunch
            if (FindObjectOfType<GameLaunch>() == null)
            {
                var launch = gameObject.AddComponent<GameLaunch>();
                launch.LuaLoadMode = LoadMode;
                launch.AutoInitResources = false;

                if (AutoStartBattle)
                {
                    launch.OnLaunchComplete += () =>
                    {
                        launch.StartBattle();
                    };
                }
            }
        }
    }
}
