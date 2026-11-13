// =============================================================================
// AssetBundleManager.cs - AssetBundle 管理器（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 ThirdParty/AssetBundleManager/AssetBundleManager.cs
// 适配: 去除 FirstDownLoadManager 耦合，保留核心 AB 加载/依赖/卸载逻辑
// 设计:
//   - SimulateAssetBundleInEditor: 编辑器下跳过 AB 打包直接读取 AssetDatabase
//   - LoadAssetAsync: 异步加载，支持协程 yield
//   - 引用计数 + 依赖追踪: 防止重复加载和过早卸载
//   - Update 驱动: 轮询所有进行中的操作，简化生命周期管理
// =============================================================================

using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif
using System.Collections.Generic;

namespace MyAssetBundles
{
    public class LoadedAssetBundle
    {
        public AssetBundle m_AssetBundle;
        public int m_ReferencedCount;

        public LoadedAssetBundle(AssetBundle assetBundle)
        {
            m_AssetBundle = assetBundle;
            m_ReferencedCount = 1;
        }
    }

    public class AssetBundleManager : MonoBehaviour
    {
        public enum LogMode { All, JustErrors }
        public enum LogType { Info, Warning, Error }

        private static LogMode s_logMode = LogMode.All;
        private static string s_baseDownloadingURL = "";
        private static AssetBundleManifest s_assetBundleManifest;

#if UNITY_EDITOR
        private static int s_simulateAssetBundleInEditor = -1;
        private const string kSimulateAssetBundles = "SimulateAssetBundles";
#endif

        private static Dictionary<string, LoadedAssetBundle> s_loadedAssetBundles =
            new Dictionary<string, LoadedAssetBundle>();

        private static Dictionary<string, int> s_downloadingBundles =
            new Dictionary<string, int>();

        private static readonly Dictionary<string, string> s_downloadErrors =
            new Dictionary<string, string>();
        private static readonly Dictionary<string, int> s_failedBundleReferences =
            new Dictionary<string, int>();

        private static List<AssetBundleLoadOperation> s_inProgressOperations =
            new List<AssetBundleLoadOperation>();

        private static Dictionary<string, string[]> s_dependencies =
            new Dictionary<string, string[]>();

        private static string[] s_allBundleNames;

        // =====================================================================
        // 公开属性
        // =====================================================================

        public static string BaseDownloadingURL
        {
            get { return s_baseDownloadingURL; }
            set { s_baseDownloadingURL = value; }
        }

        public static AssetBundleManifest AssetBundleManifestObject
        {
            set { s_assetBundleManifest = value; }
        }

#if UNITY_EDITOR
        public static bool SimulateAssetBundleInEditor
        {
            get
            {
                if (s_simulateAssetBundleInEditor == -1)
                    s_simulateAssetBundleInEditor = EditorPrefs.GetBool(kSimulateAssetBundles, true) ? 1 : 0;
                return s_simulateAssetBundleInEditor != 0;
            }
            set
            {
                int newValue = value ? 1 : 0;
                if (newValue != s_simulateAssetBundleInEditor)
                {
                    s_simulateAssetBundleInEditor = newValue;
                    EditorPrefs.SetBool(kSimulateAssetBundles, value);
                }
            }
        }
#endif

        // =====================================================================
        // 日志
        // =====================================================================

        private static void Log(LogType logType, string text)
        {
            if (logType == LogType.Error)
                Debug.LogError($"[AssetBundleManager] {text}");
            else if (s_logMode == LogMode.All)
                Debug.Log($"[AssetBundleManager] {text}");
        }

        // =====================================================================
        // URL / 路径设置
        // =====================================================================

        public static void SetSourceAssetBundleURL(string absolutePath)
        {
            if (!absolutePath.EndsWith("/"))
                absolutePath += "/";
            s_baseDownloadingURL = absolutePath;
        }

        public static void SetSourceAssetBundleDirectory(string relativePath)
        {
            string basePath = Application.isEditor
                ? System.Environment.CurrentDirectory.Replace("\\", "/")
                : Application.streamingAssetsPath;
            s_baseDownloadingURL = basePath.TrimEnd('/', '\\') + "/" + relativePath.TrimStart('/', '\\');
        }

        // =====================================================================
        // 查询
        // =====================================================================

        public static LoadedAssetBundle GetLoadedAssetBundle(string assetBundleName, out string error)
        {
            error = null;
            if (s_downloadErrors.TryGetValue(assetBundleName, out error)) return null;
            LoadedAssetBundle bundle = null;
            s_loadedAssetBundles.TryGetValue(assetBundleName, out bundle);
            if (bundle == null) return null;

            string[] dependencies = null;
            if (!s_dependencies.TryGetValue(assetBundleName, out dependencies))
                return bundle;

            foreach (var dependency in dependencies)
            {
                if (s_downloadErrors.TryGetValue(dependency, out error)) return null;
                LoadedAssetBundle dependentBundle;
                if (!s_loadedAssetBundles.TryGetValue(dependency, out dependentBundle))
                    return null;
            }

            return bundle;
        }

        public static string[] GetAllDependencies(string assetBundleName)
        {
            if (s_assetBundleManifest != null)
                return s_assetBundleManifest.GetAllDependencies(assetBundleName);
            return new string[0];
        }

        public static bool IsAssetBundleLoaded(string assetBundleName)
        {
            return s_loadedAssetBundles.ContainsKey(assetBundleName);
        }

        // =====================================================================
        // 初始化
        // =====================================================================

        public static AssetBundleLoadManifestOperation Initialize()
        {
            return Initialize(Utility.GetPlatformName());
        }

        public static AssetBundleLoadManifestOperation Initialize(string manifestAssetBundleName)
        {
#if UNITY_EDITOR
            Log(LogType.Info, $"Simulation Mode: {(SimulateAssetBundleInEditor ? "Enabled" : "Disabled")}");

            if (SimulateAssetBundleInEditor)
                return null;
#endif
            var abm = FindObjectOfType<AssetBundleManager>();
            if (abm == null)
            {
                var go = new GameObject("AssetBundleManager", typeof(AssetBundleManager));
                DontDestroyOnLoad(go);
            }

            LoadAssetBundleInternal_Legacy(manifestAssetBundleName, true);
            var operation = new AssetBundleLoadManifestOperation(
                manifestAssetBundleName, "AssetBundleManifest", typeof(AssetBundleManifest));
            s_inProgressOperations.Add(operation);
            return operation;
        }

        // =====================================================================
        // 加载 AssetBundle
        // =====================================================================

        private static void LoadAssetBundle_Legacy(string assetBundleName)
        {
            LoadAssetBundleInternal_Legacy(assetBundleName, false);
        }

        private static void LoadAssetBundleInternal_Legacy(string assetBundleName, bool isLoadingManifest, bool loadDependencies = true)
        {
#if UNITY_EDITOR
            if (SimulateAssetBundleInEditor) return;
#endif
            if (!isLoadingManifest)
            {
                if (s_assetBundleManifest == null)
                {
                    Log(LogType.Error, "Please call AssetBundleManager.Initialize() first.");
                    s_downloadErrors[assetBundleName] = "AssetBundle manifest is not initialized.";
                    return;
                }
            }

                LoadedAssetBundle existingBundle = null;
                s_loadedAssetBundles.TryGetValue(assetBundleName, out existingBundle);
                if (existingBundle != null)
                {
                    existingBundle.m_ReferencedCount++;
                    if (!isLoadingManifest && loadDependencies) LoadDependencies(assetBundleName);
                    return;
                }

                if (s_downloadingBundles.ContainsKey(assetBundleName))
                {
                    s_downloadingBundles[assetBundleName]++;
                    if (!isLoadingManifest && loadDependencies) LoadDependencies(assetBundleName);
                    return;
                }

            string url = s_baseDownloadingURL;
            if (!url.EndsWith("/")) url += "/";
            url += assetBundleName;

            s_downloadErrors.Remove(assetBundleName);
            if (Utility.RequiresWebRequest(url))
                s_inProgressOperations.Add(new AssetBundleDownloadFromWebOperation(assetBundleName, url));
            else
                s_inProgressOperations.Add(new AssetBundleDownloadFromFileOperation(assetBundleName,
                    AssetBundle.LoadFromFileAsync(Utility.LocalFilePath(url)), url));
            int failedReferences;
            s_failedBundleReferences.TryGetValue(assetBundleName, out failedReferences);
            s_failedBundleReferences.Remove(assetBundleName);
            s_downloadingBundles.Add(assetBundleName, failedReferences + 1);

            if (!isLoadingManifest && loadDependencies)
                LoadDependencies(assetBundleName);
        }

        private static void LoadDependencies(string assetBundleName)
        {
            if (s_assetBundleManifest == null)
            {
                Log(LogType.Warning, "Manifest is null, skipping dependency load.");
                return;
            }

            string[] dependencies = s_assetBundleManifest.GetAllDependencies(assetBundleName);
            if (dependencies.Length == 0) return;

            if (s_dependencies.ContainsKey(assetBundleName))
                s_dependencies[assetBundleName] = dependencies;
            else
                s_dependencies.Add(assetBundleName, dependencies);

            foreach (var dep in dependencies)
                LoadAssetBundleInternal_Legacy(dep, false, false);
        }

        // =====================================================================
        // 卸载
        // =====================================================================

        public static void UnloadAssetBundle(string assetBundleName)
        {
#if UNITY_EDITOR
            if (SimulateAssetBundleInEditor) return;
#endif
            UnloadAssetBundleInternal(assetBundleName);
            UnloadDependencies_Legacy(assetBundleName);
        }

        private static void UnloadDependencies_Legacy(string assetBundleName)
        {
            string[] dependencies = null;
            if (!s_dependencies.TryGetValue(assetBundleName, out dependencies)) return;

            foreach (var dep in dependencies)
                UnloadAssetBundleInternal(dep);

            int failedReferences;
            s_failedBundleReferences.TryGetValue(assetBundleName, out failedReferences);
            if (!s_loadedAssetBundles.ContainsKey(assetBundleName) && !s_downloadingBundles.ContainsKey(assetBundleName)
                && failedReferences == 0)
                s_dependencies.Remove(assetBundleName);
        }

        private static void UnloadAssetBundleInternal(string assetBundleName)
        {
            LoadedAssetBundle bundle;
            s_loadedAssetBundles.TryGetValue(assetBundleName, out bundle);
            if (bundle == null)
            {
                if (s_downloadingBundles.ContainsKey(assetBundleName))
                    s_downloadingBundles[assetBundleName] = System.Math.Max(0, s_downloadingBundles[assetBundleName] - 1);
                if (s_failedBundleReferences.ContainsKey(assetBundleName))
                    s_failedBundleReferences[assetBundleName] = System.Math.Max(0, s_failedBundleReferences[assetBundleName] - 1);
                return;
            }

            if (--bundle.m_ReferencedCount == 0)
            {
                bundle.m_AssetBundle.Unload(false);
                s_loadedAssetBundles.Remove(assetBundleName);
                Log(LogType.Info, $"{assetBundleName} has been unloaded successfully.");
            }
        }

        // =====================================================================
        // 资源加载（核心 API）
        // =====================================================================

        public static AssetBundleLoadAssetOperation LoadAssetAsync(
            string assetBundleName, string assetName, System.Type type)
        {
#if UNITY_EDITOR
            if (SimulateAssetBundleInEditor)
            {
                string[] assetPaths = AssetDatabase.GetAssetPathsFromAssetBundleAndAssetName(
                    assetBundleName, assetName);

                // 主路径找不到时，尝试降级兜底方案
                if (assetPaths.Length == 0)
                {
                    // 兜底 1：通过 FindAssets 按 t:Prefab + 名称搜索
                    string[] guids = AssetDatabase.FindAssets($"{assetName} t:Prefab");
                    if (guids.Length > 0)
                    {
                        foreach (string guid in guids)
                        {
                            string path = AssetDatabase.GUIDToAssetPath(guid);
                            AssetImporter importer = AssetImporter.GetAtPath(path);
                            if (importer != null && importer.assetBundleName == assetBundleName)
                            {
                                assetPaths = new[] { path };
                                break;
                            }
                        }
                    }

                    // 兜底 2：通过 GetAssetPathsFromAssetBundle 按 AB 名 + 名称过滤
                    if (assetPaths.Length == 0)
                    {
                        string[] allInBundle = AssetDatabase.GetAssetPathsFromAssetBundle(assetBundleName);
                        foreach (string p in allInBundle)
                        {
                            if (System.IO.Path.GetFileNameWithoutExtension(p) == assetName)
                            {
                                assetPaths = new[] { p };
                                break;
                            }
                        }
                    }

                    // 兜底 3：终极降级 —— 按 Prefab 名全局搜索（不依赖 AB 标签已刷新）
                    // 适用于 .meta 文件被手动修改后 AssetDatabase 尚未刷新的场景
                    if (assetPaths.Length == 0)
                    {
                        string[] allGuids = AssetDatabase.FindAssets($"{assetName} t:Prefab");
                        foreach (string g in allGuids)
                        {
                            string p = AssetDatabase.GUIDToAssetPath(g);
                            if (System.IO.Path.GetFileNameWithoutExtension(p) == assetName)
                            {
                                assetPaths = new[] { p };
                                Log(LogType.Warning,
                                    $"Asset \"{assetName}\" found by GUID search (AB label may not be refreshed). " +
                                    $"Run 'Tools/Setup Loading Prefab AB Label' to set the AB label properly.");
                                break;
                            }
                        }
                    }
                }

                if (assetPaths.Length == 0)
                {
                    Log(LogType.Error,
                        $"There is no asset with name \"{assetName}\" in {assetBundleName}.\n" +
                        "Troubleshooting:\n" +
                        "  1. Run 'Tools/Setup Loading Prefab AB Label' in Editor menu\n" +
                        "  2. Ensure the prefab's .meta assetBundleName matches the bundle name\n" +
                        "  3. Right-click the prefab → Reimport, then retry");
                    return null;
                }

                Object target = AssetDatabase.LoadMainAssetAtPath(assetPaths[0]);
                if (target == null)
                {
                    Log(LogType.Error,
                        $"Asset found at \"{assetPaths[0]}\" but failed to load as {type.Name}.");
                    return null;
                }

                return new AssetBundleLoadAssetOperationSimulation(target);
            }
#endif
            LoadAssetBundle_Legacy(assetBundleName);
            var operation = new AssetBundleLoadAssetOperationFull(assetBundleName, assetName, type);
            s_inProgressOperations.Add(operation);
            return operation;
        }

        public static AssetBundleLoadOperation LoadLevelAsync(
            string assetBundleName, string levelName, bool isAdditive)
        {
#if UNITY_EDITOR
            if (SimulateAssetBundleInEditor)
                return new AssetBundleLoadLevelSimulationOperation(assetBundleName, levelName, isAdditive);
#endif
            LoadAssetBundle_Legacy(assetBundleName);
            var operation = new AssetBundleLoadLevelOperation(assetBundleName, levelName, isAdditive);
            s_inProgressOperations.Add(operation);
            return operation;
        }

        // =====================================================================
        // Update 驱动
        // =====================================================================

        private void Update()
        {
            for (int i = 0; i < s_inProgressOperations.Count;)
            {
                var operation = s_inProgressOperations[i];
                if (operation.Update())
                {
                    i++;
                }
                else
                {
                    s_inProgressOperations.RemoveAt(i);
                    ProcessFinishedOperation(operation);
                }
            }
        }

        private void ProcessFinishedOperation(AssetBundleLoadOperation operation)
        {
            var download = operation as AssetBundleDownloadOperation;
            if (download == null) return;

            if (string.IsNullOrEmpty(download.Error))
            {
                int refCount = s_downloadingBundles[download.AssetBundleName];
                if (refCount == 0)
                {
                    download.AssetBundle.m_AssetBundle.Unload(false);
                    s_downloadingBundles.Remove(download.AssetBundleName);
                    return;
                }

                download.AssetBundle.m_ReferencedCount = refCount;
                s_loadedAssetBundles.Add(download.AssetBundleName, download.AssetBundle);
            }
            else
            {
                s_downloadErrors[download.AssetBundleName] = download.Error;
                s_failedBundleReferences[download.AssetBundleName] = s_downloadingBundles[download.AssetBundleName];
                Log(LogType.Error,
                    $"Failed downloading bundle {download.AssetBundleName} " +
                    $"from {download.GetSourceURL()}: {download.Error}");
            }

            s_downloadingBundles.Remove(download.AssetBundleName);
        }
    }
}
