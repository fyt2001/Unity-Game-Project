using System;
using System.Collections.Generic;
using System.Reflection;
using MyAssetBundles;
using UnityEditor;
using UnityEngine;

public static class PlatformLoadingChecks
{
    private static AssetBundleDownloadFromWebOperation failureProbe;

    public static void BeginDownloadFailureCheck()
    {
        if (failureProbe != null) throw new InvalidOperationException("A download check is already active.");
        failureProbe = new AssetBundleDownloadFromWebOperation("verification/missing", "http://127.0.0.1:1/missing.asset");
    }

    public static string PollDownloadFailureCheck()
    {
        if (failureProbe == null) throw new InvalidOperationException("No download check is active.");
        if (failureProbe.Update()) return "Pending";
        bool passed = failureProbe.IsDone() && failureProbe.AssetBundle == null
            && !string.IsNullOrEmpty(failureProbe.Error);
        string error = failureProbe.Error;
        failureProbe = null;
        if (!passed) throw new InvalidOperationException("Download failure did not terminate correctly.");
        return "HTTP failure terminated: " + error;
    }

    [MenuItem("Tools/Build/验证资源加载基础")]
    public static void RunMenu()
    {
        Debug.Log(Run());
    }

    public static string Run()
    {
        int checks = 0;
        Action<bool, string> require = (condition, message) =>
        {
            if (!condition) throw new InvalidOperationException(message);
            checks++;
        };

        require(Utility.RequiresWebRequest("https://example.invalid/game.asset"), "HTTPS routing");
        require(Utility.RequiresWebRequest("http://localhost/game.asset"), "HTTP routing");
        require(Utility.RequiresWebRequest("jar:file:///data/app/base.apk!/assets/game.asset"), "Android APK routing");
        require(!Utility.RequiresWebRequest("C:/game/game.asset"), "Windows routing");
        require(!Utility.RequiresWebRequest("/var/mobile/game.asset"), "Native routing");
        require(!Utility.RequiresWebRequest("file:///tmp/game.asset"), "File URI routing");
        require(Utility.LocalFilePath("file:///tmp/a%20b.asset").EndsWith("a b.asset"), "File URI decoding");
        var scriptPath = typeof(LuaBundleLoader).GetMethod("ScriptPath", BindingFlags.NonPublic | BindingFlags.Static);
        foreach (string input in new[] { "Framework.Framework", "Framework.Framework.lua", "Framework/Framework.lua", "Framework\\Framework.lua" })
            require((string)scriptPath.Invoke(null, new object[] { input }) == "Framework/Framework.lua", "Lua script path: " + input);
        var mode = typeof(GameLaunch).GetMethod("ResolveLuaLoadMode", BindingFlags.NonPublic | BindingFlags.Static);
        require((LuaLoadMode)mode.Invoke(null, new object[] { false, LuaLoadMode.Editor }) == LuaLoadMode.Device, "Player overrides editor Lua mode");
        require((LuaLoadMode)mode.Invoke(null, new object[] { true, LuaLoadMode.Editor }) == LuaLoadMode.Editor, "Editor keeps source mode");
        require((LuaLoadMode)mode.Invoke(null, new object[] { true, LuaLoadMode.Device }) == LuaLoadMode.Device, "Editor keeps bundle test mode");
        string previousURL = AssetBundleManager.BaseDownloadingURL;
        try
        {
            AssetBundleManager.SetSourceAssetBundleDirectory("/#build/AssetBundles");
            require(!AssetBundleManager.BaseDownloadingURL.StartsWith("file://")
                && AssetBundleManager.BaseDownloadingURL.Contains("/#build/AssetBundles"), "Native special-character path");
        }
        finally { AssetBundleManager.BaseDownloadingURL = previousURL; }

        var missingRequest = new AssetBundleDownloadFromFileOperation("missing", null, "missing.asset");
        require(!missingRequest.Update(), "Null request must complete");
        require(missingRequest.IsDone() && !string.IsNullOrEmpty(missingRequest.Error), "Null request must fail");

        // Use a unique synthetic key; never change the active game's bundle entries.
        var field = typeof(AssetBundleManager).GetField("s_downloadErrors", BindingFlags.NonPublic | BindingFlags.Static);
        var errors = (Dictionary<string, string>)field.GetValue(null);
        string key = "verification/" + Guid.NewGuid().ToString("N");
        try
        {
            errors.Add(key, "injected download failure");
            var asset = new AssetBundleLoadAssetOperationFull(key, "missing", typeof(TextAsset));
            require(!asset.Update(), "Failed asset must leave the update queue");
            require(asset.IsDone() && asset.GetAsset<TextAsset>() == null, "Failed asset must terminate its coroutine");
            var manifest = new AssetBundleLoadManifestOperation(key, "AssetBundleManifest", typeof(AssetBundleManifest));
            var manifestField = typeof(AssetBundleManager).GetField("s_assetBundleManifest", BindingFlags.NonPublic | BindingFlags.Static);
            object previousManifest = manifestField.GetValue(null);
            try
            {
                require(!manifest.Update(), "Failed manifest must leave the update queue");
                require(manifest.IsDone(), "Failed manifest must terminate its coroutine");
            }
            finally { manifestField.SetValue(null, previousManifest); }
            var level = new AssetBundleLoadLevelOperation(key, "missing", false);
            require(!level.Update(), "Failed scene must leave the update queue");
        }
        finally
        {
            errors.Remove(key);
        }
        CheckReferences(require);
        return $"Platform loading checks passed: {checks}. Device/Player validation is separate.";
    }

    private static void CheckReferences(Action<bool, string> require)
    {
        Type manager = typeof(AssetBundleManager);
        const BindingFlags flags = BindingFlags.Static | BindingFlags.NonPublic;
        var loaded = (Dictionary<string, LoadedAssetBundle>)manager.GetField("s_loadedAssetBundles", flags).GetValue(null);
        var downloading = (Dictionary<string, int>)manager.GetField("s_downloadingBundles", flags).GetValue(null);
        var failed = (Dictionary<string, int>)manager.GetField("s_failedBundleReferences", flags).GetValue(null);
        var dependencies = (Dictionary<string, string[]>)manager.GetField("s_dependencies", flags).GetValue(null);
        var simulation = manager.GetField("s_simulateAssetBundleInEditor", flags);
        object previousSimulation = simulation.GetValue(null);
        string key = "verification/" + Guid.NewGuid().ToString("N");
        var load = manager.GetMethod("LoadAssetBundleInternal_Legacy", flags);
        var unload = manager.GetMethod("UnloadAssetBundleInternal", flags);
        try
        {
            simulation.SetValue(null, 0);
            loaded.Add(key, new LoadedAssetBundle(null) { m_ReferencedCount = 2 });
            load.Invoke(null, new object[] { key, true, false });
            require(loaded[key].m_ReferencedCount == 3, "Repeated manifest uses existing bundle");
            unload.Invoke(null, new object[] { key });
            require(loaded[key].m_ReferencedCount == 2, "Release retains remaining owners");
            downloading.Add(key + "/pending", 2);
            load.Invoke(null, new object[] { key + "/pending", true, false });
            require(downloading[key + "/pending"] == 3, "Repeated manifest shares pending request");
            failed.Add(key + "/failed", 2);
            unload.Invoke(null, new object[] { key + "/failed" });
            require(failed[key + "/failed"] == 1, "Failed download releases retained demand");
            failed.Add(key + "/owner", 2);
            loaded.Add(key + "/dependency", new LoadedAssetBundle(null) { m_ReferencedCount = 3 });
            dependencies.Add(key + "/owner", new[] { key + "/dependency" });
            AssetBundleManager.UnloadAssetBundle(key + "/owner");
            require(dependencies.ContainsKey(key + "/owner"), "Failed owner retains dependency mapping");
            require(loaded[key + "/dependency"].m_ReferencedCount == 2, "First failed owner releases dependency");
            AssetBundleManager.UnloadAssetBundle(key + "/owner");
            require(!dependencies.ContainsKey(key + "/owner"), "Last failed owner clears dependency mapping");
            require(loaded[key + "/dependency"].m_ReferencedCount == 1, "Second failed owner releases dependency");
        }
        finally
        {
            loaded.Remove(key);
            downloading.Remove(key + "/pending");
            failed.Remove(key + "/failed");
            failed.Remove(key + "/owner");
            loaded.Remove(key + "/dependency");
            dependencies.Remove(key + "/owner");
            simulation.SetValue(null, previousSimulation);
        }
    }
}
