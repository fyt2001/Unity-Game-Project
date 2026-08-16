// =============================================================================
// GameLaunch.cs - 游戏启动流程编排器（参考 ShaoNvClient_H02 InitLoadingNew）
// =============================================================================

using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.UI;
using XLua;

public enum LaunchPhase { None = 0, InitLogger, InitFileSystem, InitResources, InitLua, InitModules, StartGame, Complete }

public class GameLaunch : MonoBehaviour
{
    [Header("基础设置")]
    public LuaLoadMode LuaLoadMode = LuaLoadMode.Editor;
    public bool AutoInitResources = false;

    [Header("启动 Loading 预制体")]
    [Tooltip("拖入 LaunchLoading.prefab")]
    public GameObject LoadingPrefab;
    [Tooltip("预制体实例化到的父节点（可选，默认挂 InitCamera 下）")]
    public RectTransform LoadingRoot;

    [Header("启动进度 UI（自动从预制体查找）")]
    public Slider ProgressSlider;
    public Text ProgressText;
    public bool ShowProgress = true;

    private GameObject _loadingObj;

    public LaunchPhase CurrentPhase { get; private set; } = LaunchPhase.None;
    public float Progress { get; private set; }
    public event Action OnLaunchComplete;
    public event Action<LaunchPhase> OnPhaseChanged;

    private static GameLaunch _instance;
    private bool _isLaunching;
    public static GameLaunch Instance => _instance;

    // =========================================================================
    // Unity 生命周期
    // =========================================================================

    IEnumerator Start()
    {
        _instance = this;
        Screen.sleepTimeout = SleepTimeout.NeverSleep;
        Application.runInBackground = true;

        // 参考旧项目：实例化 Loading 预制体
        // ScreenSpaceOverlay Canvas 直接挂在场景根，不需要挂在 Camera 下
        if (LoadingPrefab != null)
        {
            Transform parent = LoadingRoot != null ? LoadingRoot.transform : transform;
            _loadingObj = Instantiate(LoadingPrefab, parent);
            _loadingObj.name = "LoadingCanvas(Clone)";
            SetLoading(_loadingObj);
        }

        yield return StartCoroutine(LaunchSequence());
    }

    /// <summary>从实例化的预制体中查找 Slider 和 Text，绑定到进度 UI</summary>
    private void SetLoading(GameObject obj)
    {
        if (obj == null) return;

        if (ProgressSlider == null)
            ProgressSlider = obj.GetComponentInChildren<Slider>(true);
        if (ProgressText == null)
            ProgressText = obj.GetComponentInChildren<Text>(true);

        if (ProgressSlider != null) ProgressSlider.value = 0;
        if (ProgressText != null) ProgressText.text = "正在初始化...";
    }

    private void Update() => Tick.OnUpdate();
    private void LateUpdate() => Tick.OnLateUpdate();
    private void FixedUpdate() => Tick.OnFixedUpdate();
    private void OnDestroy() => Tick.Clear();

    // XLuaManager 自身处理 OnApplicationQuit → Dispose，这里只清理 C# 侧
    private void OnApplicationQuit() => Tick.Clear();

    // =========================================================================
    // 启动流程
    // =========================================================================

    private IEnumerator LaunchSequence()
    {
        if (_isLaunching) yield break;
        _isLaunching = true;

        TimeProfiler.Start("TotalLaunch");

        SetPhase(LaunchPhase.InitLogger, 0.05f, "初始化日志...");
        DebugLogger.SetReleaseEnv(!Debug.isDebugBuild);
        yield return null;

        SetPhase(LaunchPhase.InitFileSystem, 0.10f, "检查文件系统...");
        try { var p = Application.persistentDataPath; if (!Directory.Exists(p)) Directory.CreateDirectory(p); }
        catch (Exception e) { DebugLogger.Exception(e); }
        yield return null;

        SetPhase(LaunchPhase.InitResources, 0.20f, "初始化资源...");
        if (AutoInitResources) yield return StartCoroutine(InitResources());
        yield return null;

        SetPhase(LaunchPhase.InitLua, 0.40f, "启动脚本引擎...");
        var lua = XLuaManager.Instance;
        lua.LoadMode = LuaLoadMode;
        lua.InitLuaEnv();
        yield return null;

        SetPhase(LaunchPhase.InitModules, 0.60f, "加载框架...");
        yield return StartCoroutine(InitLuaModules());
        yield return null;

        SetPhase(LaunchPhase.StartGame, 0.90f);
        lua.StartGame();
        yield return null;

        SetPhase(LaunchPhase.Complete, 1.0f, "完成");

        TimeProfiler.End("TotalLaunch");
        DebugLogger.Info($"[GameLaunch] Launch Complete!\n{TimeProfiler.Dump()}");

        _isLaunching = false;
        OnLaunchComplete?.Invoke();
    }

    /// <summary>Phase 5: 加载 Lua 框架 → 创建 GameMain → 注入 XLuaManager</summary>
    private IEnumerator InitLuaModules()
    {
        var lua = XLuaManager.Instance;

        lua.LoadScript("Framework.Framework");
        lua.LoadScript("Common.Define");

        // 创建 GameMain 并注册 Tick
        lua.SafeDoString(@"
            _G.GameMain = require 'Game.GameMain'
            _G.GameMain.Init()
            local UM = require 'Framework.Core.UpdateManager'
            local TM = require 'Framework.Core.TimerManager'
            _G.__LuaTick  = function(dt) UM:GetInstance():OnUpdate(dt) TM:GetInstance():Update(dt * 1000) end
            _G.__LuaLateTick = function(dt) UM:GetInstance():OnLateUpdate(dt) end
        ");

        // 从 Lua 全局提取 GameMain 表，注入 XLuaManager（不再用 DoString 拼接调用）
        var gameMainTable = lua.GetGlobalValue<LuaTable>("GameMain");
        lua.SetGameMain(gameMainTable);

        // 注册 Tick
        var uf = lua.GetGlobalFunction("__LuaTick");
        var lf = lua.GetGlobalFunction("__LuaLateTick");
        if (uf != null) Tick.RegisterUpdate(dt => { try { uf.Call(dt); } catch (Exception e) { DebugLogger.Exception(e); } });
        if (lf != null) Tick.RegisterLateUpdate(dt => { try { lf.Call(dt); } catch (Exception e) { DebugLogger.Exception(e); } });

        SetPhase(LaunchPhase.InitModules, 0.80f, "启动游戏...");
        yield return null;
    }

    protected virtual IEnumerator InitResources() { yield return null; }

    // =========================================================================
    // 进度 UI
    // =========================================================================

    private void SetPhase(LaunchPhase phase, float progress, string desc = "")
    {
        CurrentPhase = phase;
        Progress = progress;
        OnPhaseChanged?.Invoke(phase);
        UpdateProgressUI(progress, desc);
    }

    public void UpdateProgressUI(float progress, string desc = "")
    {
        if (ProgressSlider != null) ProgressSlider.value = progress;
        if (ProgressText != null && !string.IsNullOrEmpty(desc)) ProgressText.text = desc;
    }

    // =========================================================================
    // 调试
    // =========================================================================

    [ContextMenu("Start Battle")]
    public void StartBattle()
    {
        XLuaManager.Instance.SafeDoString("GameMain.StartBattle({})");
    }

    [ContextMenu("Shutdown Lua")]
    public void ShutdownLua()
    {
        XLuaManager.Instance.Dispose();
    }
}
