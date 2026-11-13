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
//     【canonical 入口 · P0-3 转正】
//     本组件是 BattleScene（Assets/Scenes/BattleScene.unity）上唯一的 Lua 战斗入口，
//     GUID 29e04e69…，挂在名为 "GameBootstrap" 的 GameObject 上。
//     双场景分工：LaunchScene/LoginScene/HomeScene → GameLaunch → XLuaManager（走 Tick 注册）；
//                 BattleScene → 本组件（自驱动 Update/LateUpdate，不经过 Tick）。
//     历史说明：Core/LuaBootstrap.cs 曾作为"替代本组件"的第二入口存在，但从未被任何场景/prefab/代码
//     引用，属孤儿，已于 P0-3 删除。此后本组件为 BattleScene 唯一入口，勿再引入第二入口。
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

    /// <summary>
    /// 只读状态：Lua 是否已由本组件接管。供其它组件（如 HomeSceneBootstrapper）做入口互斥。
    /// </summary>
    public bool IsRunning => isRunning;

    // =========================================================================
    // Unity 生命周期
    // =========================================================================

    void Awake()
    {
        // 【单例保护】启动器全局唯一。
        // 由于下面会 DontDestroyOnLoad，当再次加载含有 GameBootstrap 的场景时
        // （典型场景：登录成功后 SwitchScene("Home") 切回 TestBattle），
        // 场景资源里自带的那个 GameBootstrap 会再次 Awake，
        // 进而二次 InitializeLua()（新建 LuaEnv）并 StartGame() → SwitchScene("Login")，
        // 表现为：刚切到主界面就被立刻弹回登录页。
        // 因此重复的实例必须销毁，只保留最先创建的那个。
        var all = FindObjectsOfType<LuaGameBootstrap>();
        if (all != null && all.Length > 1)
        {
            Debug.Log($"[LuaGameBootstrap] Duplicate instance in scene '{gameObject.scene.name}', destroying self.");
            Destroy(gameObject);
            return;
        }

        // 【关键】Lua 启动器必须跨场景存活。
        // SceneLoader 使用 SceneManager.LoadSceneAsync(level, Single) 切换场景，
        // Single 模式会卸载当前场景。若本组件随场景一起销毁，则：
        //   OnDestroy → ShutdownLua → luaEnv.Dispose()
        // 整个 Lua 层（UI 框架 UIManager/UIRoot/UICamera、战斗系统）都会随之消失，
        // 表现为切到 LoginScene 后 UI 完全不出现。
        // 因此这里 DontDestroyOnLoad，让唯一的启动器贯穿全流程。
        // 【关键修复】My project 由 GameLaunch + XLuaManager 统一驱动 Lua。
        // 若 XLuaManager 已经初始化了 LuaEnv，则本遗留启动器必须跳过，
        // 否则会再次 InitializeLua() 并 StartGame() → SwitchScene("Login")，
        // 导致从 LoginScene 切换到 TestBattle(主界面) 后立刻被踢回登录页。
        // 只要统一的 GameLaunch + XLuaManager 驱动存在，就交给它驱动 Lua，legacy 路径直接跳过。
        // 注意：这里只判断 XLuaManager.Instance 是否存在，而不依赖 GetLuaEnv() 是否非空，
        // 因为 Awake 早于 GameLaunch 创建 LuaEnv 的时序，仅判 LuaEnv 非空会漏判导致二次初始化
        // （再次 InitializeLua() + StartGame() → SwitchScene("Login")，把刚切到主界面的玩家弹回登录页）。
        if (XLuaManager.Instance != null)
        {
            Debug.Log("[LuaGameBootstrap] XLuaManager present; skip legacy init.");
            return;
        }

        DontDestroyOnLoad(gameObject);

        if (autoStart)
        {
            InitializeLua();
        }

        // 【已废弃 → P1-0 已删除】这里原本会自动 AddComponent<BattleView>()。
        // BattleView 是早期的测试用场景可视层，它会自行创建地面/玩家并用 WASD 驱动；
        // 其职责已由 HomeSceneBootstrapper 完全接管（摇杆输入桥接 + 俯视相机跟随 +
        // 玩家 Transform 同步）。BattleView 连同 DebugBattlePanel / TestInputSimulator
        // 已于 P1-0 从工程整体删除（三者全工程 0 挂载、Lua 侧 0 引用）。
        // 保留此注释仅用于记录历史事故——两者并存会导致：
        //   1. 地面与玩家被重复创建一份（场景中出现两套 3D 物件）
        //   2. WASD（BattleView）与摇杆（HomeSceneBootstrapper）同时写 SetInput，输入互相覆盖
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
#if !UNITY_EDITOR
        Game.Security.LuaScriptProtection.ConfigureDeviceEnvironment(luaEnv);
#endif

        // 3. 加载 Framework
        LoadFramework();

        // 4. 加载 GameMain
        LoadGameMain();

        isRunning = true;
        Debug.Log("[LuaGameBootstrap] Lua initialized successfully!");

        // 【修复】这里原本直接 GameMain.StartBattle({}) 绕过场景系统开战斗，
        // 结果 SceneLoader 从不切换场景 —— Init() 只建了 UI 框架，却不启动场景链，
        // 于是永远停在启动场景，LoginPanel / HomePanel 都不会打开。
        // 正确做法：调用 GameMain.StartGame()，由它驱动完整流程：
        //   SwitchScene("Login") → LoginScene(LoginPanel)
        //     → 点击登录 → SwitchScene("Home")，而 Home 已映射到 TestBattle.unity
        //     → HomeScene.lua 打开 HomePanel（摇杆+HUD）
        //     → HomeSceneBootstrapper 创建俯视相机/地面/玩家并启动战斗
        SafeDoString(@"
            local GameMain = require 'Game.GameMain'
            GameMain.StartGame()
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
#if !UNITY_EDITOR
        return LuaBundleLoader.TryGetScript(filepath);
#else
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
            Path.Combine(Application.dataPath, "Game", "LuaScripts", relativePath),
            Path.Combine(Application.dataPath, "Resources", relativePath),
        };

        foreach (string fullPath in searchPaths)
        {
            if (File.Exists(fullPath))
            {
                return File.ReadAllBytes(fullPath);
            }
        }

        Debug.LogWarning($"[LuaGameBootstrap] Lua file not found: {filepath}");
        return null;
#endif
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
