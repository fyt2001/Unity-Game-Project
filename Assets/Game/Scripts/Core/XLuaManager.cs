// =============================================================================
// XLuaManager.cs - XLua管理器（腾讯级生产标准）
// =============================================================================

using System;
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
    private LuaFunction _updateFunc;
    private LuaFunction _lateUpdateFunc;
    private Func<string, LuaTable> _requireFunc;
    private bool _disposed;

    public bool HasGameStarted => _gameMain != null;
    public LuaLoadMode LoadMode { get; set; } = LuaLoadMode.Editor;
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

    public void InitLuaEnv(Action onComplete = null)
    {
        if (_luaEnv != null) { onComplete?.Invoke(); return; }

        DebugLogger.Info("[XLuaManager] Initializing LuaEnv...");
        TimeProfiler.Start("InitLuaEnv");

        _luaEnv = new LuaEnv();
        _luaEnv.AddLoader(CustomLoader);

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
        onComplete?.Invoke();
    }

    /// <summary>注意：GameMain 在 GameLaunch 中由外部 Lua 脚本创建并注入</summary>
    public void SetGameMain(LuaTable gameMain)
    {
        _gameMain = gameMain;
        if (_gameMain != null)
            DebugLogger.Info("[XLuaManager] GameMain bound");

        // 获取 Lua 层的 Update 函数，确保场景切换后 Update 循环不中断
        if (_luaEnv != null)
        {
            _updateFunc = _luaEnv.Global.Get<LuaFunction>("__LuaTick");
            _lateUpdateFunc = _luaEnv.Global.Get<LuaFunction>("__LuaLateTick");
            if (_updateFunc != null)
                DebugLogger.Info("[XLuaManager] Lua update tick bound");
        }
    }

    public void StartGame()
    {
        if (_luaEnv == null) { DebugLogger.Error("[XLuaManager] Cannot start: LuaEnv is null"); return; }
        DebugLogger.Info("[XLuaManager] Game started");

        if (_gameMain != null)
        {
            try
            {
                var startFunc = _gameMain.Get<LuaFunction>("StartGame");
                if (startFunc != null)
                {
                    startFunc.Call();
                    startFunc.Dispose();
                }
                else
                {
                    DebugLogger.Warn("[XLuaManager] GameMain.StartGame not found");
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
            _updateFunc?.Call(Time.deltaTime);
        }
        catch (Exception e) { DebugLogger.Exception(e); }
    }

    private void LateUpdate()
    {
        if (_luaEnv == null || _disposed) return;
        try { _lateUpdateFunc?.Call(Time.deltaTime); }
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
        TryCall("OnApplicationQuit");
        Dispose();
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
            var func = _gameMain.Get<LuaFunction>(method);
            func?.Call(args);
        }
        catch (Exception e) { DebugLogger.Warn($"[XLuaManager] TryCall({method}): {e.Message}"); }
    }

    // =========================================================================
    // 销毁
    // =========================================================================

    public override void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        SceneManager.sceneLoaded -= OnSceneLoaded;

        // 释放 LuaFunction 引用
        _updateFunc?.Dispose(); _updateFunc = null;
        _lateUpdateFunc?.Dispose(); _lateUpdateFunc = null;
        _requireFunc = null;
        _gameMain?.Dispose(); _gameMain = null;

        System.GC.Collect();
        System.GC.WaitForPendingFinalizers();

        if (_luaEnv != null)
        {
            try { _luaEnv.Dispose(); }
            catch (Exception e) { DebugLogger.Warn($"[XLuaManager] Dispose: {e.Message}"); }
            _luaEnv = null;
        }

        DebugLogger.Info("[XLuaManager] Disposed");
        base.Dispose();
    }

    // =========================================================================
    // CustomLoader
    // =========================================================================

    public byte[] CustomLoader(ref string filepath)
    {
        filepath = filepath.Replace(".", "/") + ".lua";
        return LoadMode == LuaLoadMode.Editor ? LoadFromFileSystem(filepath) : LoadFromBundle(filepath);
    }

    private byte[] LoadFromFileSystem(string filepath)
    {
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
    }

    private byte[] LoadFromBundle(string filepath)
    {
        var ta = Resources.Load<TextAsset>(filepath.Replace(".lua", ""));
        return ta != null ? ta.bytes : null;
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
        var t = _luaEnv?.Global.GetInPath<LuaTable>(module);
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