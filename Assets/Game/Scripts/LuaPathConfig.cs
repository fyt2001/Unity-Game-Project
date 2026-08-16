// =============================================================================
// LuaPathConfig.cs
// =============================================================================
// 用于在 Inspector 中配置 Lua 搜索路径，挂载到 GameBootstrap 同 GameObject
// =============================================================================

using UnityEngine;

[CreateAssetMenu(fileName = "LuaPathConfig", menuName = "Game/Lua Path Config")]
public class LuaPathConfig : ScriptableObject
{
    [Header("Lua 脚本搜索路径")]
    [Tooltip("相对于 Assets 的路径，如 LuaScripts")]
    public string[] searchPaths = new string[]
    {
        "Assets/LuaScripts",
        "Assets/NewObject",
    };

    [Header("入口文件")]
    [Tooltip("主入口 Lua 文件路径（不含 .lua 后缀）")]
    public string mainEntry = "Game.GameMain";
}
