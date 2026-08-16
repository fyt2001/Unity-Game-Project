// =============================================================================
// LuaGameBootstrap.cs
// =============================================================================
// Module:     Scripts/LuaGameBootstrap
// Version:    1.0.0
// Target:     Unity + XLua
//
// Description:
//     Lua 游戏启动器。挂载到 Unity 场景中的 GameObject 上。
//     负责：
//        1. 初始化 XLua LuaEnv
//        2. 设置 Lua 脚本加载路径
//        3. 加载并执行 Framework + GameMain
//        4. 每帧驱动 UpdateManager（进而驱动整个 Lua 游戏循环）
//
// Usage:
//     1. 在 Unity 场景中创建一个空 GameObject，命名为 "GameBootstrap"
//     2. 将此脚本挂载到 GameBootstrap 上
//     3. 设置 LuaScriptPath 为 Assets 中 Lua 脚本的根目录（如 "Assets/LuaScripts"）
//     4. 运行场景
// =============================================================================

using UnityEngine;
using XLua;
using System.IO;
using System.Collections.Generic;

[LuaCallCSharp]
public class LuaGameBootstrap : MonoBehaviour
{
    [Header("Lua 配置")]
    [Tooltip("Lua 脚本在 Assets 中的相对路径，如 Resources")]
    public string luaScriptPath = "Resources";

    [Tooltip("Lua 主入口 require 路径（不含 .lua），如 Game.GameMain")]
    public string mainEntry = "Game.GameMain";

    [Tooltip("是否在 Awake 时自动启动")]
    public bool autoStart = true;

    [Tooltip("编辑器下是否开启热重载（修改Lua脚本自动重载）")]
    public bool hotReload = true;

    // 内部状态
    private LuaEnv luaEnv;
    private LuaTable gameMain;
    private LuaFunction luaUpdateFunc;    // Lua 层的统一 Update 入口函数
    private bool isRunning = false;

    // =========================================================================
    // Unity 生命周期
    // =========================================================================

    void Awake()
    {
        if (autoStart)
        {
            InitializeLua();
        }

        // 自动挂载战斗可视层（创建地面、玩家 Cube，桥接输入）
        if (autoStart)
        {
            gameObject.AddComponent<BattleView>();
        }
    }

    void Update()
    {
        if (!isRunning) return;

        // 驱动 Lua 游戏循环（通过 Lua 层注册的统一 Update 函数）
        try
        {
            luaUpdateFunc?.Call(Time.deltaTime);
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[LuaGameBootstrap] Update error: {e.Message}\n{e.StackTrace}");
        }
    }

    void LateUpdate()
    {
        if (!isRunning) return;
        try
        {
            luaEnv?.Tick();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[LuaGameBootstrap] LateUpdate error: {e}");
        }
    }

    void OnDestroy()
    {
        ShutdownLua();
    }

    void OnApplicationQuit()
    {
        ShutdownLua();
    }

    // =========================================================================
    // Lua 初始化
    // =========================================================================

    public void InitializeLua()
    {
        if (isRunning) return;

        Debug.Log("[LuaGameBootstrap] Initializing Lua...");

        // 1. 创建 LuaEnv
        luaEnv = new LuaEnv();

        // 2. 设置自定义 Loader（从文件系统加载 .lua 文件）
        luaEnv.AddLoader(CustomLuaLoader);

        // 3. 加载 Framework
        LoadFramework();

        // 4. 加载 GameMain
        LoadGameMain();

        isRunning = true;
        Debug.Log("[LuaGameBootstrap] Lua initialized successfully!");

        // 自动进入战斗 Demo（方便测试，不需要手动点菜单）
        SafeDoString(@"
            local GameMain = require 'Game.GameMain'
            GameMain.StartBattle({})
        ");
    }

    /// <summary>
    /// 加载 Framework 层
    /// </summary>
    private void LoadFramework()
    {
        // 先加载 Framework 入口，它会自动加载 Core 和 UI 模块
        SafeDoString(@"require 'Framework.Framework'");
        Debug.Log("[LuaGameBootstrap] Framework loaded");
    }

    /// <summary>
    /// 加载 GameMain 并初始化
    /// </summary>
    private void LoadGameMain()
    {
        // 规范化 mainEntry：去掉可能的 .lua 后缀和路径分隔符，统一为 require 点号格式
        string entry = mainEntry.Trim().Replace('\\', '/');
        if (entry.EndsWith(".lua", System.StringComparison.OrdinalIgnoreCase))
            entry = entry.Substring(0, entry.Length - 4);
        entry = entry.Replace('/', '.');

        // 加载 GameMain 模块并初始化
        SafeDoString($@"
            _G.GameMain = require '{entry}'
            GameMain.Init()

            -- 注册统一的 Update 函数，C# 层通过此函数驱动整个 Lua 循环
            local UpdateManager = require 'Framework.Core.UpdateManager'
            local TimerManager = require 'Framework.Core.TimerManager'

            _G.__LuaTick = function(dt)
                -- dt 为秒，TimerManager 需要毫秒
                UpdateManager:GetInstance():OnUpdate(dt)
                TimerManager:GetInstance():Update(dt * 1000)
            end
        ");

        // 获取 GameMain 表用于后续调用
        gameMain = luaEnv.Global.Get<LuaTable>("GameMain");

        // 获取统一的 Lua Update 函数
        luaUpdateFunc = luaEnv.Global.Get<LuaFunction>("__LuaTick");
    }

    /// <summary>
    /// 自定义 Lua 文件加载器
    /// 将 Lua 的 require 路径映射到文件系统
    /// </summary>
    private byte[] CustomLuaLoader(ref string filepath)
    {
        // 将 Lua require 路径转换为文件路径
        // 支持 "Framework.Core.Class" 或 "Framework/Core/Class.lua"
        string normalized = filepath.Trim().Replace('\\', '/');
        if (normalized.EndsWith(".lua", System.StringComparison.OrdinalIgnoreCase))
            normalized = normalized.Substring(0, normalized.Length - 4);
        string relativePath = normalized.Replace('.', '/') + ".lua";

        // 尝试多个搜索路径
        List<string> searchPaths = new List<string>
        {
            Path.Combine(Application.dataPath, luaScriptPath, relativePath),
            Path.Combine(Application.dataPath, "Resources", relativePath),
            Path.Combine(Application.dataPath, "NewObject", relativePath),
        };

        // 兜底：去掉可能的 "NewObject." 前缀，直接到 Resources 下查找
        // 兼容 UI 框架内部使用 "NewObject.Framework.UI.xxx" 的 require 写法
        string stripped = relativePath;
        if (stripped.StartsWith("NewObject/", System.StringComparison.OrdinalIgnoreCase))
            stripped = stripped.Substring("NewObject/".Length);
        searchPaths.Add(Path.Combine(Application.dataPath, "Resources", stripped));
        searchPaths.Add(Path.Combine(Application.dataPath, stripped));

        foreach (string fullPath in searchPaths)
        {
            if (File.Exists(fullPath))
            {
                return File.ReadAllBytes(fullPath);
            }
        }

        Debug.LogWarning($"[LuaGameBootstrap] Lua file not found: {filepath}");
        return null;
    }

    // =========================================================================
    // 公共 API
    // =========================================================================

    /// <summary>
    /// 启动战斗（可在 Inspector 或代码中调用）
    /// </summary>
    [ContextMenu("Start Battle")]
    public void StartBattle()
    {
        if (!isRunning)
        {
            InitializeLua();
        }

        // 战斗配置
        string battleConfig = @"
            return {
                mapId = 1,
                maxTime = 300,  -- 5分钟测试
                player = {
                    maxHp = 100,
                    atk = 10,
                    moveSpeed = 5.0,
                    boundsMinX = -15,
                    boundsMaxX = 15,
                    boundsMinY = -10,
                    boundsMaxY = 10,
                },
                waves = {
                    { startTime = 0,   enemyType = 'slime',    count = 10, interval = 0.5, hpMult = 1.0 },
                    { startTime = 30,  enemyType = 'bat',      count = 15, interval = 0.8, hpMult = 1.0 },
                    { startTime = 60,  enemyType = 'skeleton', count = 10, interval = 1.5, hpMult = 1.2 },
                },
            }
        ";

        try
        {
            // 先将配置写入全局变量，再在 Lua 中读取
            luaEnv.Global.Set("__battleConfigStr", battleConfig);

            SafeDoString(@"
                local config = loadstring(__battleConfigStr)()
                local GameMain = require 'Game.GameMain'
                GameMain.StartBattle(config)
            ");

            Debug.Log("[LuaGameBootstrap] Battle started!");
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[LuaGameBootstrap] StartBattle error: {e}");
        }
    }

    /// <summary>
    /// 关闭 Lua 环境
    /// </summary>
    [ContextMenu("Shutdown Lua")]
    public void ShutdownLua()
    {
        if (!isRunning) return;

        Debug.Log("[LuaGameBootstrap] Shutting down Lua...");

        try
        {
            if (gameMain != null)
            {
                var shutdownFunc = gameMain.Get<LuaFunction>("Shutdown");
                shutdownFunc?.Call();
                gameMain.Dispose();
                gameMain = null;
            }
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[LuaGameBootstrap] Shutdown error: {e}");
        }

        luaUpdateFunc?.Dispose();
        luaUpdateFunc = null;

        luaEnv?.Dispose();
        luaEnv = null;
        isRunning = false;

        Debug.Log("[LuaGameBootstrap] Lua shutdown complete");
    }

    /// <summary>
    /// 执行任意 Lua 代码（用于调试）
    /// </summary>
    /// <summary>
    /// 兼容两种 XLua 版本的 DoString（string 或 byte[]）
    /// </summary>
    private object[] SafeDoString(string luaCode)
    {
        // 新版 XLua (v2.1.16+) DoString 接受 byte[]，旧版接受 string
        try
        {
            return luaEnv.DoString(luaCode);
        }
        catch
        {
            return luaEnv.DoString(System.Text.Encoding.UTF8.GetBytes(luaCode));
        }
    }

    public object[] DoLuaString(string luaCode)
    {
        if (luaEnv == null) return null;
        return SafeDoString(luaCode);
    }

    /// <summary>
    /// 获取 LuaEnv（用于高级操作）
    /// </summary>
    public LuaEnv GetLuaEnv() => luaEnv;
}
