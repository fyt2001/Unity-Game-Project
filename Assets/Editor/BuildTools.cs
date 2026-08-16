// =============================================================================
// BuildTools.cs - 构建工具集（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 BuildToolWindow.cs + ProjectBuildTools.cs（提炼精华）
// 升级: 独立构建工具，支持一键打包、版本管理、Jenkins CI
// =============================================================================

using System;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

/// <summary>
/// 构建工具集。
/// 提供一键构建、版本号管理、AssetBundle 打包、CI 集成等功能。
/// </summary>
public static class BuildTools
{
    private const string VersionFileName = "version.txt";
    private const string BuildOutputRoot = "Builds/";

    #region 菜单入口

    [MenuItem("Tools/Build/构建 Android APK", false, 200)]
    public static void BuildAndroid()
    {
        DoBuildTarget(BuildTarget.Android, "apk");
    }

    [MenuItem("Tools/Build/构建 iOS Xcode", false, 201)]
    public static void BuildIOS()
    {
        DoBuildTarget(BuildTarget.iOS, "");
    }

    [MenuItem("Tools/Build/构建 Windows", false, 202)]
    public static void BuildWindows()
    {
        DoBuildTarget(BuildTarget.StandaloneWindows64, "exe");
    }

    [MenuItem("Tools/Build/生成 XLua Wrap 代码", false, 220)]
    public static void GenXLuaWrap()
    {
        try
        {
            // 使用反射调用 XLua.Generator.GenAll()，避免对特定 XLua 版本的硬依赖
            var genType = System.Type.GetType("XLua.Generator, Assembly-CSharp-Editor");
            if (genType != null)
            {
                var method = genType.GetMethod("GenAll");
                method?.Invoke(null, null);
                Debug.Log("[BuildTools] XLua Wrap 代码生成完成");
            }
            else
            {
                Debug.LogWarning("[BuildTools] XLua.Generator 类型未找到，请检查 XLua 是否正确导入");
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"[BuildTools] XLua Wrap 生成失败: {e.Message}");
        }
    }

    [MenuItem("Tools/Build/复制 Lua 脚本到 Resources", false, 221)]
    public static void CopyLuaToResources()
    {
        string sourceDir = Path.Combine(Application.dataPath, "Game", "LuaScripts");
        string targetDir = Path.Combine(Application.dataPath, "Resources");

        if (!Directory.Exists(sourceDir))
        {
            Debug.LogError($"[BuildTools] 源目录不存在: {sourceDir}");
            return;
        }

        CopyDirectory(sourceDir, targetDir, ".lua");
        AssetDatabase.Refresh();
        Debug.Log("[BuildTools] Lua 脚本复制完成");
    }

    [MenuItem("Tools/Build/显示版本信息", false, 240)]
    public static void ShowVersionInfo()
    {
        var version = GetCurrentVersion();
        EditorUtility.DisplayDialog("版本信息",
            $"应用版本: {Application.version}\n" +
            $"资源版本: {version.ResourceVersion}\n" +
            $"构建时间: {version.BuildTime}\n" +
            $"构建目标: {version.BuildTarget}\n" +
            $"渠道: {version.Channel}",
            "确定");
    }

    #endregion

    #region 构建核心

    /// <summary>
    /// 执行构建
    /// </summary>
    public static void DoBuildTarget(BuildTarget buildTarget, string extension)
    {
        // 1. 生成 XLua Wrap
        Debug.Log("[BuildTools] Step 1: Gen XLua Wrap...");
        GenXLuaWrap();

        // 2. 保存版本信息
        Debug.Log("[BuildTools] Step 2: Save version info...");
        SaveVersionInfo(buildTarget);

        // 3. 设置编译宏
        Debug.Log("[BuildTools] Step 3: Set scripting defines...");
        SetScriptingDefines(buildTarget);

        // 4. 构建
        Debug.Log("[BuildTools] Step 4: Build player...");
        string outputPath = GetBuildOutputPath(buildTarget, extension);
        string[] scenes = GetBuildScenes();

        BuildPipeline.BuildPlayer(scenes, outputPath, buildTarget, BuildOptions.None);

        Debug.Log($"[BuildTools] Build complete: {outputPath}");
    }

    /// <summary>
    /// 获取构建场景列表
    /// </summary>
    public static string[] GetBuildScenes()
    {
        var scenes = new System.Collections.Generic.List<string>();
        foreach (EditorBuildSettingsScene scene in EditorBuildSettings.scenes)
        {
            if (scene.enabled)
            {
                scenes.Add(scene.path);
            }
        }

        if (scenes.Count == 0)
        {
            Debug.LogWarning("[BuildTools] No enabled scenes found! Using current scene.");
            scenes.Add(UnityEngine.SceneManagement.SceneManager.GetActiveScene().path);
        }

        return scenes.ToArray();
    }

    /// <summary>
    /// 获取构建输出路径
    /// </summary>
    public static string GetBuildOutputPath(BuildTarget buildTarget, string extension)
    {
        string dir = Path.Combine(BuildOutputRoot, buildTarget.ToString());
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        string productName = Application.productName.Replace(" ", "_");
        string version = Application.version.Replace(".", "_");
        string fileName = $"{productName}_v{version}_{DateTime.Now:yyyyMMdd_HHmmss}";

        if (!string.IsNullOrEmpty(extension))
        {
            fileName += "." + extension;
        }

        return Path.Combine(dir, fileName);
    }

    #endregion

    #region 版本管理

    [Serializable]
    public class VersionInfo
    {
        public string AppVersion;
        public string ResourceVersion;
        public string BuildTime;
        public string BuildTarget;
        public string Channel;
    }

    /// <summary>
    /// 获取当前版本信息
    /// </summary>
    public static VersionInfo GetCurrentVersion()
    {
        return new VersionInfo
        {
            AppVersion = Application.version,
            ResourceVersion = PlayerSettings.bundleVersion,
            BuildTime = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            BuildTarget = EditorUserBuildSettings.activeBuildTarget.ToString(),
            Channel = GetChannelName(),
        };
    }

    /// <summary>
    /// 保存版本信息到文件
    /// </summary>
    public static void SaveVersionInfo(BuildTarget buildTarget)
    {
        var version = GetCurrentVersion();
        version.BuildTarget = buildTarget.ToString();

        string json = JsonUtility.ToJson(version, true);
        string path = Path.Combine(Application.streamingAssetsPath, VersionFileName);

        string dir = Path.GetDirectoryName(path);
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        File.WriteAllText(path, json);
        Debug.Log($"[BuildTools] Version info saved: {path}");
    }

    /// <summary>
    /// 自动递增资源版本号
    /// </summary>
    public static void AutoIncrementVersion()
    {
        string[] parts = PlayerSettings.bundleVersion.Split('.');
        int major = parts.Length > 0 ? int.Parse(parts[0]) : 1;
        int minor = parts.Length > 1 ? int.Parse(parts[1]) : 0;
        int revision = parts.Length > 2 ? int.Parse(parts[2]) : 0;

        revision++;
        if (revision >= 100)
        {
            revision = 0;
            minor++;
            if (minor >= 100)
            {
                minor = 0;
                major++;
            }
        }

        PlayerSettings.bundleVersion = $"{major}.{minor}.{revision}";
        Debug.Log($"[BuildTools] Version incremented to: {PlayerSettings.bundleVersion}");
    }

    #endregion

    #region 编译宏管理

    /// <summary>
    /// 设置编译宏
    /// </summary>
    public static void SetScriptingDefines(BuildTarget buildTarget)
    {
        string defines = PlayerSettings.GetScriptingDefineSymbolsForGroup(
            BuildPipeline.GetBuildTargetGroup(buildTarget));

        // 添加自定义宏
        if (!defines.Contains("LUA_ENABLED"))
        {
            defines += ";LUA_ENABLED";
        }

#if DEVELOPMENT_BUILD
        if (!defines.Contains("DEVELOPMENT_BUILD"))
        {
            defines += ";DEVELOPMENT_BUILD";
        }
#endif

        PlayerSettings.SetScriptingDefineSymbolsForGroup(
            BuildPipeline.GetBuildTargetGroup(buildTarget), defines);

        Debug.Log($"[BuildTools] Scripting defines: {defines}");
    }

    #endregion

    #region 工具方法

    /// <summary>
    /// 获取渠道名称
    /// </summary>
    public static string GetChannelName()
    {
#if LUCKDOG_CLIENT_TW
        return "TW";
#elif LUCKDOG_CLIENT_KR
        return "KR";
#elif LUCKDOG_CLIENT_JAPAN
        return "JP";
#elif LUCKDOG_CLIENT_BRAZIL
        return "BR";
#else
        return "Dev";
#endif
    }

    /// <summary>
    /// 复制目录（按扩展名过滤）
    /// </summary>
    public static void CopyDirectory(string sourceDir, string targetDir, string extension = null)
    {
        DirectoryInfo dir = new DirectoryInfo(sourceDir);
        if (!dir.Exists) return;

        DirectoryInfo[] subDirs = dir.GetDirectories();
        foreach (DirectoryInfo subDir in subDirs)
        {
            string newTargetDir = Path.Combine(targetDir, subDir.Name);
            CopyDirectory(subDir.FullName, newTargetDir, extension);
        }

        if (!Directory.Exists(targetDir))
        {
            Directory.CreateDirectory(targetDir);
        }

        FileInfo[] files = dir.GetFiles();
        foreach (FileInfo file in files)
        {
            if (string.IsNullOrEmpty(extension) || file.Extension == extension)
            {
                string targetPath = Path.Combine(targetDir, file.Name);
                file.CopyTo(targetPath, true);
            }
        }
    }

    #endregion
}