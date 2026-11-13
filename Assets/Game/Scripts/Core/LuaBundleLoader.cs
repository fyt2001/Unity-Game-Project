// =============================================================================
// LuaBundleLoader.cs - Lua 脚本 AssetBundle 加载器（多平台）
// =============================================================================
// 背景：
//   XLua 的 CustomLoader 必须【同步】返回 byte[]，不能"用到哪个再异步加载哪个"。
//   因此必须在创建 LuaEnv 之前把 Lua 的 AB 整个加载好，之后由 loader 同步取字节。
//
// 平台差异：
//   - Native local paths: AssetBundle.LoadFromFile.
//   - Android APK URLs / HTTP(S): UnityWebRequestAssetBundle (async).
//   - Mini-game storage still requires the converter's platform adapter.
//
// 热更：优先读 persistentDataPath 下的同名 AB，其次回落到 StreamingAssets 首包 AB。
//
// 说明：本类只负责"把 Lua AB 加载好 + 提供同步取脚本"，不改动现有初始化流程。
//       Editor 下 XLuaManager 仍走 File IO，不影响当前开发体验。
// =============================================================================

using System.Collections;
using System.IO;
using UnityEngine;
using MyAssetBundles;
using UnityEngine.Networking;

public static class LuaBundleLoader
{
    /// <summary>Lua 脚本 AB 名，需与编辑器打包脚本 BuildAssetBundles.LuaBundleName 一致。</summary>
    public const string BundleName = "lua/scripts.asset";

    /// <summary>Lua 源暂存目录（构建期生成，构建后删除）。仅用于兜底匹配 AB 内资源名。</summary>
    private const string StageRoot = "Assets/Game/LuaBundleSrc";

    private static AssetBundle _bundle;
    private static bool _loading;

    /// <summary>Lua AB 是否已加载完成。</summary>
    public static bool IsReady => _bundle != null;

    // =========================================================================
    // 路径
    // =========================================================================

    // 注意：此处必须写全限定名。UnityEngine.Networking 下也存在 Utility 类型，
    // 直接写 Utility 会在 WebGL 构建时产生 CS0104 歧义。
    private static string RelativeBundlePath()
        => (MyAssetBundles.Utility.AssetBundlesOutputPath + "/" +
            MyAssetBundles.Utility.GetPlatformName() + "/" + BundleName)
           .Replace("\\", "/");

    /// <summary>热更目录中的 Lua AB（优先）。</summary>
    private static string PersistentBundlePath()
        => (Application.persistentDataPath + "/" + RelativeBundlePath()).Replace("\\", "/");

    /// <summary>首包内置（StreamingAssets）的 Lua AB。</summary>
    private static string StreamingBundlePath()
        => (Application.streamingAssetsPath + "/" + RelativeBundlePath()).Replace("\\", "/");

    // =========================================================================
    // 加载
    // =========================================================================

    public static IEnumerator LoadAsync()
    {
        while (_loading) yield return null;
        if (_bundle != null) yield break;
        _loading = true;
        try { yield return LoadAsyncInternal(); }
        finally { _loading = false; }
    }

#if (UNITY_WEBGL || UNITY_ANDROID) && !UNITY_EDITOR

    /// <summary>本地缓存或 Android APK / WebGL URL 加载。</summary>
    private static IEnumerator LoadAsyncInternal()
    {
        if (_bundle != null) yield break;

        string[] candidates = { PersistentBundlePath(), StreamingBundlePath() };
        foreach (var p in candidates)
        {
            if (!MyAssetBundles.Utility.RequiresWebRequest(p))
            {
                var localPath = MyAssetBundles.Utility.LocalFilePath(p);
                if (!File.Exists(localPath)) continue;
                _bundle = AssetBundle.LoadFromFile(localPath);
                if (_bundle != null) yield break;
                continue;
            }
            using (var req = UnityWebRequestAssetBundle.GetAssetBundle(p))
            {
                req.timeout = 30;
                yield return req.SendWebRequest();

#if UNITY_2020_1_OR_NEWER
                if (req.result != UnityWebRequest.Result.Success) continue;
#else
                if (req.isNetworkError || req.isHttpError) continue;
#endif

                _bundle = DownloadHandlerAssetBundle.GetContent(req);
                if (_bundle != null)
                {
                    DebugLogger.Info($"[LuaBundleLoader] Loaded (WebGL): {p}");
                    yield break;
                }
            }
        }

        DebugLogger.Error("[LuaBundleLoader] Failed to load Lua AssetBundle from local storage or StreamingAssets URL.");
    }

    /// <summary>
    /// URL 平台统一使用 <see cref="LoadAsync"/>，保留签名供历史调用方编译。
    /// </summary>
    public static bool LoadSync()
    {
        DebugLogger.Warn("[LuaBundleLoader] This platform requires LoadAsync().");
        return false;
    }

#else

    /// <summary>其它平台：同步加载（先 persistent 热更，后 streaming 首包）。</summary>
    public static bool LoadSync()
    {
        if (_bundle != null) return true;

        string[] candidates = { PersistentBundlePath(), StreamingBundlePath() };
        foreach (var p in candidates)
        {
            if (!File.Exists(p)) continue;
            _bundle = AssetBundle.LoadFromFile(p);
            if (_bundle != null)
            {
                DebugLogger.Info($"[LuaBundleLoader] Loaded: {p}");
                return true;
            }
        }

        DebugLogger.Error("[LuaBundleLoader] Lua AssetBundle not found. " +
                          "Run 'Tools/Build AssetBundles' before building the player.");
        return false;
    }

    /// <summary>协程包装，便于与 WebGL 版本统一调用（非 WebGL 下立即完成）。</summary>
    private static IEnumerator LoadAsyncInternal()
    {
        LoadSync();
        yield break;
    }

#endif

    // =========================================================================
    // 取脚本（同步）
    // =========================================================================

    /// <summary>
    /// 按 require 路径取脚本字节。requirePath 形如 "Framework.UI.Core.UIWindow"。
    /// 缺失或验证失败时中止 require，不允许后续明文 searcher 接管。
    /// </summary>
    public static byte[] TryGetScript(string requirePath)
    {
        if (_bundle == null || string.IsNullOrEmpty(requirePath))
            throw new System.InvalidOperationException("Authenticated Lua bundle is not ready or the module path is empty.");

        string rel = Game.Security.ProtectedLuaPayload.CanonicalPath(ScriptPath(requirePath));

        // AB 内资源名可能因打包方式不同而有差异，依次尝试，避免取不到
        string[] names =
        {
            rel,                                // Framework/UI/Core/UIWindow.lua
            StageRoot + "/" + rel + ".txt",     // Assets/Game/LuaBundleSrc/.../UIWindow.lua.txt
        };

        foreach (var n in names)
        {
            var ta = _bundle.LoadAsset<TextAsset>(n);
            if (ta != null) return Game.Security.LuaScriptProtection.Read(ta.bytes, rel);
        }

        throw new System.IO.FileNotFoundException("Authenticated Lua module is missing: " + rel);
    }

    private static string ScriptPath(string path)
    {
        if (path.EndsWith(".lua", System.StringComparison.OrdinalIgnoreCase))
            path = path.Substring(0, path.Length - 4);
        return path.Replace('\\', '/').Replace('.', '/') + ".lua";
    }

    /// <summary>卸载 Lua AB（切换账号/大版本热更后重新加载时使用）。</summary>
    public static void Unload()
    {
        if (_bundle == null) return;
        _bundle.Unload(true);
        _bundle = null;
    }
}
