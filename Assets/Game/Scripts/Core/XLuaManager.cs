// =============================================================================
// XLuaManager.cs - XLua管理器（腾讯级生产标准）
// =============================================================================

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.SceneManagement;
using XLua;

public enum LuaLoadMode { Editor, Device }

[Hotfix]
[LuaCallCSharp]
public class XLuaManager : MonoSingleton<XLuaManager>
{
    public const string LuaScriptsFolder = "Resources";  // 兼容历史 Wrap 代码

    private LuaEnv _luaEnv;
    private LuaTable _gameMain;
    private Func<string, LuaTable> _requireFunc;
    private bool _disposed;
    private bool _disposing;
    private bool _shutdownStarted;

    public bool HasGameStarted => _gameMain != null;
    private LuaLoadMode _loadMode = LuaLoadMode.Editor;
    public LuaLoadMode LoadMode
    {
        get
        {
#if UNITY_EDITOR
            return _loadMode;
#else
            return LuaLoadMode.Device;
#endif
        }
        set { _loadMode = value; }
    }
    public List<string> SearchPaths { get; set; } = new List<string> { "Game/LuaScripts" };

    // =========================================================================
    // 初始化
    // =========================================================================

    protected override void Init()
    {
        base.Init();
        SceneManager.sceneLoaded += OnSceneLoaded;
    }

    public void OnInit() => InitLuaEnv();  // 兼容历史 Wrap 代码

    /// <summary>
    /// 本地文件同步初始化；Android APK / WebGL URL 使用 <see cref="InitLuaEnvCoroutine"/>。
    /// 保留此签名以兼容 XLua 生成的 Wrap 与历史调用方。
    /// </summary>
    public void InitLuaEnv(Action onComplete = null)
    {
        if (_luaEnv != null) { onComplete?.Invoke(); return; }

        DebugLogger.Info("[XLuaManager] Initializing LuaEnv...");
        TimeProfiler.Start("InitLuaEnv");

        // 真机：XLua 的 loader 是【同步】的，不能"用到才加载"，
        // 必须先把整个 Lua AssetBundle 加载好，之后 CustomLoader 才能从 bundle 同步取字节。
        if (LoadMode == LuaLoadMode.Device)
        {
            if (!LuaBundleLoader.LoadSync())
                throw new InvalidOperationException("Lua AssetBundle is not ready; use the async initialization path.");
        }

        SetupLuaEnv();
        onComplete?.Invoke();
    }

    /// <summary>
    /// 异步初始化（推荐，全平台通用）。
    /// URL 资源异步拉取，必须等 Lua AB 就绪后再创建 LuaEnv。
    /// </summary>
    public IEnumerator InitLuaEnvCoroutine(Action onComplete = null)
    {
        if (_luaEnv != null) { onComplete?.Invoke(); yield break; }

        DebugLogger.Info("[XLuaManager] Initializing LuaEnv (async)...");
        TimeProfiler.Start("InitLuaEnv");

        if (LoadMode == LuaLoadMode.Device)
        {
            yield return LuaBundleLoader.LoadAsync();
            if (!LuaBundleLoader.IsReady)
                throw new InvalidOperationException("Lua AssetBundle failed to load; LuaEnv initialization was stopped.");
        }

        if (_luaEnv == null) SetupLuaEnv();
        onComplete?.Invoke();
    }

    /// <summary>Lua AB 就绪之后的公共初始化流程。</summary>
    private void SetupLuaEnv()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(XLuaManager));
        _luaEnv = new LuaEnv();
        _luaEnv.AddLoader(CustomLoader);
        if (LoadMode == LuaLoadMode.Device)
            Game.Security.LuaScriptProtection.ConfigureDeviceEnvironment(_luaEnv);

        try
        {
#if PB_EXTEND
            _luaEnv.AddBuildin("pb", XLua.LuaDLL.Lua.LoadPb);
#endif
#if RAPIDJSON_EXTEND
            _luaEnv.AddBuildin("rapidjson", XLua.LuaDLL.Lua.LoadRapidJson);
#endif
        }
        catch { }

        _requireFunc = _luaEnv.Global.Get<Func<string, LuaTable>>("require");

        TimeProfiler.End("InitLuaEnv");
        DebugLogger.Info($"[XLuaManager] LuaEnv ready ({TimeProfiler.Dump()})");
    }

    /// <summary>注意：GameMain 在 GameLaunch 中由外部 Lua 脚本创建并注入</summary>
    public void SetGameMain(LuaTable gameMain)
    {
        _gameMain = gameMain;
        if (_gameMain != null)
            DebugLogger.Info("[XLuaManager] GameMain bound");
    }

    public void StartGame()
    {
        if (_luaEnv == null) { DebugLogger.Error("[XLuaManager] Cannot start: LuaEnv is null"); return; }
        DebugLogger.Info("[XLuaManager] Game started");

        if (_gameMain != null)
        {
            try
            {
                using (var startFunc = _gameMain.Get<LuaFunction>("StartGame"))
                {
                    if (startFunc != null) startFunc.Call();
                    else DebugLogger.Warn("[XLuaManager] GameMain.StartGame not found");
                }
            }
            catch (System.Exception e)
            {
                DebugLogger.Exception(e);
            }
        }
    }

    // =========================================================================
    // 帧驱动
    // =========================================================================

    private void Update()
    {
        if (_luaEnv == null || _disposed) return;
        try
        {
            _luaEnv.Tick();
        }
        catch (Exception e) { DebugLogger.Exception(e); }
    }

    // =========================================================================
    // 生命周期事件（通过 LuaTable 引用调用，安全）
    // =========================================================================

    private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        TryCall("OnLevelWasLoaded");
    }

    private void OnApplicationQuit()
    {
        Dispose();
    }

    protected override void OnDestroy()
    {
        Dispose();
        base.OnDestroy();
    }

    private void OnApplicationFocus(bool isFocus)
    {
        if (_gameMain == null) return;
        TryCall("OnApplicationFocus", isFocus);
    }

    /// <summary>对 _gameMain 安全调用方法，失败不抛异常</summary>
    private void TryCall(string method, params object[] args)
    {
        if (_gameMain == null || _disposed) return;
        try
        {
            using (var func = _gameMain.Get<LuaFunction>(method)) func?.Call(args);
        }
        catch (Exception e) { DebugLogger.Warn($"[XLuaManager] TryCall({method}): {e.Message}"); }
    }

    // =========================================================================
    // 销毁
    // =========================================================================

    public override void Dispose()
    {
        if (_disposing || (_disposed && _luaEnv == null)) return;
        _disposing = true;
        try
        {
            if (!_shutdownStarted)
            {
                _shutdownStarted = true;
                // Unity does not guarantee GameLaunch/XLuaManager quit ordering.
                if (_luaEnv != null)
                {
                    GameLaunch.Instance?.ReleaseLuaTicks();
                    foreach (var scene in FindObjectsOfType<HomeSceneBootstrapper>(true)) scene.ReleaseLuaBindings();
                    FindObjectOfType<WebDownLoadManager>()?.ReleaseLuaCallbacks();
                }
                TryCall("OnApplicationQuit");
                // Destroy() is deferred; entity bindings must leave the still-live VM now.
                if (_luaEnv != null)
                    foreach (var view in FindObjectsOfType<Game.View.LuaViewBehaviour>(true)) view.ReleaseLuaBindings();
            }
            _disposed = true;
            SceneManager.sceneLoaded -= OnSceneLoaded;
            _requireFunc = null;
            _gameMain?.Dispose(); _gameMain = null;
            System.GC.Collect();
            System.GC.WaitForPendingFinalizers();
            // Keep the environment on failure so a rejected Dispose is observable/retryable.
            _luaEnv?.Dispose();
            _luaEnv = null;
            DebugLogger.Info("[XLuaManager] Disposed");
            base.Dispose();
        }
        catch (Exception e)
        {
#if UNITY_EDITOR || DEVELOPMENT_BUILD
            Game.Security.OnlinePlayerProbe.ReportCallbackOrigins(_luaEnv);
#endif
            DebugLogger.Exception(e);
        }
        finally { _disposing = false; }
    }

    // =========================================================================
    // CustomLoader
    // =========================================================================

    public byte[] CustomLoader(ref string filepath)
    {
        string requirePath = filepath;
        filepath = filepath.Replace(".", "/") + ".lua";

        if (LoadMode == LuaLoadMode.Device)
            return LuaBundleLoader.TryGetScript(requirePath);

        return LoadFromFileSystem(filepath);
    }

    private byte[] LoadFromFileSystem(string filepath)
    {
#if UNITY_EDITOR
        foreach (string sp in SearchPaths)
        {
            string p = Path.Combine(Application.dataPath, sp, filepath);
            if (File.Exists(p)) return File.ReadAllBytes(p);
            p = Path.Combine(Application.dataPath, filepath);
            if (File.Exists(p)) return File.ReadAllBytes(p);
        }
        string rp = Path.Combine(Path.GetDirectoryName(Application.dataPath), filepath);
        if (File.Exists(rp)) return File.ReadAllBytes(rp);

        // 只在 Debug 模式下输出警告，避免日志刷屏
        // DebugLogger.Warn($"[XLuaManager] Not found: {filepath}");
        return null;
#else
        throw new InvalidOperationException("Filesystem Lua loading is editor-only.");
#endif
    }

    // =========================================================================
    // 公共 API
    // =========================================================================

    public LuaEnv GetLuaEnv() => _luaEnv;

    public object[] SafeDoString(string code)
    {
        if (_luaEnv == null) return null;
        try { return _luaEnv.DoString(code); }
        catch { return _luaEnv.DoString(System.Text.Encoding.UTF8.GetBytes(code)); }
    }

    public void LoadScript(string name) => SafeDoString($"require '{name}'");

    public void ReloadScript(string name)
    {
        SafeDoString($"package.loaded['{name}'] = nil");
        LoadScript(name);
    }

    public LuaFunction GetGlobalFunction(string name) => _luaEnv?.Global.Get<LuaFunction>(name);

    public LuaFunction GetGlobalFunction(string module, string func)
    {
        using (var t = _luaEnv?.Global.GetInPath<LuaTable>(module))
            return t?.GetInPath<LuaFunction>(func);
    }

    public T GetGlobalValue<T>(string key)
    {
        return _luaEnv != null ? _luaEnv.Global.GetInPath<T>(key) : default;
    }

    public LuaTable Require(string path)
    {
        try { return _requireFunc?.Invoke(path); }
        catch (LuaException e) { DebugLogger.Error($"[XLuaManager] Require({path}): {e.Message}"); return null; }
    }

    public void RunGMCode(string code) => SafeDoString(code);
}
