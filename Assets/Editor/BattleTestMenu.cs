// =============================================================================
// BattleTestMenu.cs
// =============================================================================
// Unity Editor 菜单扩展，提供一键启动/停止战斗的快捷操作。
// 放在 Assets/Editor/ 下。
// =============================================================================

#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

public class BattleTestMenu
{
    [MenuItem("Game/Start Battle", false, 100)]
    public static void StartBattle()
    {
        var bootstrap = Object.FindObjectOfType<LuaGameBootstrap>();
        if (bootstrap == null)
        {
            Debug.LogError("[BattleTestMenu] LuaGameBootstrap not found in scene!");
            EditorUtility.DisplayDialog("Error", 
                "场景中没有找到 LuaGameBootstrap 组件。\n请先按照搭建指南创建测试场景。", "OK");
            return;
        }

        bootstrap.StartBattle();
    }

    [MenuItem("Game/Start Battle", true)]
    public static bool StartBattleValidate()
    {
        return Application.isPlaying;
    }

    [MenuItem("Game/Shutdown Lua", false, 101)]
    public static void ShutdownLua()
    {
        var bootstrap = Object.FindObjectOfType<LuaGameBootstrap>();
        if (bootstrap != null)
        {
            bootstrap.ShutdownLua();
        }
    }

    [MenuItem("Game/Shutdown Lua", true)]
    public static bool ShutdownLuaValidate()
    {
        return Application.isPlaying;
    }

    [MenuItem("Game/Execute Lua...", false, 200)]
    public static void ExecuteLua()
    {
        // 简单示例：弹窗输入 Lua 代码执行
        // 生产环境可以接入更完善的 Lua REPL
        Debug.Log("[BattleTestMenu] 请在 Console 中使用 LuaGameBootstrap.DoLuaString() 方法");
    }
}
#endif