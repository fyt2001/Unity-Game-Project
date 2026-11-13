// =============================================================================
// BuildAssetBundles.cs - AssetBundle 构建与菜单（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 ThirdParty/AssetBundleManager/Editor/BuildScript.cs
//       + AssetbundlesMenuItems.cs
// 功能:
//   1. Assets/AssetBundles/Simulation Mode — 切换 Editor 模拟模式
//   2. Tools/Build AssetBundles — 构建 AB 包到 StreamingAssets
// =============================================================================

using UnityEngine;
using UnityEditor;
using UnityEditor.Build;
using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using MyAssetBundles;

namespace MyProject.Editor
{
    public static class BuildAssetBundles
    {
        private const string SIMULATION_MODE_MENU = "Assets/AssetBundles/Simulation Mode (0:AB  1:Local)";
        private const string BUILD_MENU = "Tools/Build AssetBundles";

        // ---- Lua 脚本打包 ----
        private const string LuaSourceRoot = "Assets/Game/LuaScripts";   // Lua 源目录
        private const string LuaStageRoot = "Assets/Game/LuaBundleSrc";  // 构建期暂存目录（构建后删除）
        public const string LuaBundleName = "lua/scripts.asset";        // Lua AB 名

        // =====================================================================
        // Simulation Mode 开关
        // =====================================================================

        [MenuItem(SIMULATION_MODE_MENU)]
        public static void ToggleSimulationMode()
        {
            AssetBundleManager.SimulateAssetBundleInEditor =
                !AssetBundleManager.SimulateAssetBundleInEditor;
        }

        [MenuItem(SIMULATION_MODE_MENU, true)]
        public static bool ToggleSimulationModeValidate()
        {
            Menu.SetChecked(SIMULATION_MODE_MENU,
                AssetBundleManager.SimulateAssetBundleInEditor);
            return true;
        }

        // =====================================================================
        // 构建 AB 包
        // =====================================================================

        [MenuItem(BUILD_MENU, false, 200)]
        public static void BuildAllAssetBundles()
        {
            string outputPath = BuildForTarget(EditorUserBuildSettings.activeBuildTarget);
            using (var staging = StageForPlayer(outputPath)) staging.KeepStaged();
            Debug.Log($"[BuildAssetBundles] Resources staged for the current target: {outputPath}");
        }

        public static string BuildForTarget(BuildTarget target)
        {
            BuildTools.ValidateBuildTarget(target);
            // Keep the leaf name: Unity names the manifest bundle after its output directory.
            string outputPath = Path.GetFullPath(Path.Combine("Builds", "AssetBundles", target.ToString(),
                DateTime.UtcNow.ToString("yyyyMMdd_HHmmss") + "_" + Guid.NewGuid().ToString("N"),
                Utility.GetPlatformName()));
            Directory.CreateDirectory(outputPath);
            if (Directory.Exists(LuaStageRoot) || File.Exists(LuaStageRoot + ".meta"))
                throw new BuildFailedException($"Lua staging directory already exists; preserve and inspect it: {LuaStageRoot}");
            try
            {
                int luaCount = PrepareLuaBundleSources();
                if (luaCount == 0) throw new BuildFailedException("No Lua scripts were staged.");
                var manifest = BuildPipeline.BuildAssetBundles(outputPath,
                    BuildAssetBundleOptions.ChunkBasedCompression, target);
                if (manifest == null || !File.Exists(Path.Combine(outputPath, Utility.GetPlatformName()))
                    || !manifest.GetAllAssetBundles().Contains(LuaBundleName))
                    throw new BuildFailedException("AssetBundle build failed or the Lua bundle is missing.");
                File.WriteAllText(Path.Combine(Path.GetDirectoryName(outputPath), "build-target.txt"), target.ToString());
                return outputPath;
            }
            finally
            {
                CleanupLuaBundleSources();
                AssetDatabase.Refresh();
            }
        }

        public static BundleStaging StageForPlayer(string source)
        {
            return new BundleStaging(source);
        }

        public sealed class BundleStaging : IDisposable
        {
            private readonly string destination;
            private readonly string backup;
            private readonly string pending;
            private readonly bool hadMeta;
            private bool keep;
            private bool disposed;
            private bool generatedMoved;
            private bool originalRestored;

            public BundleStaging(string source)
            {
                BuildTools.ValidateBuildTarget(EditorUserBuildSettings.activeBuildTarget);
                pending = Path.GetFullPath(Path.Combine("P0_rollback", "bundle_staging.pending"));
                if (File.Exists(pending))
                    throw new BuildFailedException("An earlier resource transaction needs recovery: " + File.ReadAllText(pending));
                source = Path.GetFullPath(source);
                string archiveRoot = Path.GetFullPath(Path.Combine("Builds", "AssetBundles"))
                    + Path.DirectorySeparatorChar;
                if (!source.StartsWith(archiveRoot, StringComparison.OrdinalIgnoreCase)
                    || !File.Exists(Path.Combine(source, Utility.GetPlatformName())))
                    throw new BuildFailedException("Only verified build archive directories can be staged.");
                string targetFile = Path.Combine(Path.GetDirectoryName(source), "build-target.txt");
                if (!File.Exists(targetFile)
                    || File.ReadAllText(targetFile) != EditorUserBuildSettings.activeBuildTarget.ToString())
                    throw new BuildFailedException("AssetBundle archive target does not match the active target.");
                destination = Path.GetFullPath(Path.Combine(Application.streamingAssetsPath,
                    Utility.AssetBundlesOutputPath, Utility.GetPlatformName()));
                string bundleRoot = Path.GetDirectoryName(destination);
                if (Directory.Exists(bundleRoot)
                    && Directory.GetFileSystemEntries(bundleRoot).Any(p =>
                        !string.Equals(p, destination, StringComparison.OrdinalIgnoreCase)
                        && !string.Equals(p, destination + ".meta", StringComparison.OrdinalIgnoreCase)))
                    throw new BuildFailedException("Unexpected files in the AssetBundles root; inspect legacy platform bundles before building.");
                backup = Path.GetFullPath(Path.Combine("P0_rollback", "bundle_staging_" + Guid.NewGuid().ToString("N")));
                hadMeta = File.Exists(destination + ".meta");
                Directory.CreateDirectory(backup);
                var hashes = new System.Collections.Generic.List<string>();
                if (Directory.Exists(destination))
                    foreach (string file in Directory.GetFiles(destination, "*", SearchOption.AllDirectories))
                        hashes.Add(HashFile(file));
                if (hadMeta)
                {
                    File.Copy(destination + ".meta", Path.Combine(backup, "original.meta"));
                    hashes.Add(HashFile(destination + ".meta"));
                }
                File.WriteAllLines(Path.Combine(backup, "hashes.txt"), hashes);
                File.WriteAllText(pending, backup);
                Debug.Log($"[BuildAssetBundles] Resource recovery backup: {backup}");
                if (Directory.Exists(destination)) Directory.Move(destination, Path.Combine(backup, "original"));
                try
                {
                    BuildTools.CopyDirectory(source, destination);
                    AssetDatabase.Refresh();
                }
                catch
                {
                    Dispose();
                    throw;
                }
            }

            public void KeepStaged() { keep = true; }

            private static string HashFile(string path)
            {
                using (var stream = File.OpenRead(path))
                using (var sha = SHA256.Create())
                    return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "") + "  " + path;
            }

            public void Dispose()
            {
                if (disposed) return;
                if (keep)
                {
                    Debug.Log($"[BuildAssetBundles] Previous resources preserved at {backup}");
                    File.Delete(pending);
                    disposed = true;
                    return;
                }
                // Move generated files out instead of deleting any pre-existing resources.
                if (!generatedMoved)
                {
                    if (Directory.Exists(destination)) Directory.Move(destination, Path.Combine(backup, "generated"));
                    generatedMoved = true;
                }
                string original = Path.Combine(backup, "original");
                if (!originalRestored)
                {
                    if (Directory.Exists(original)) Directory.Move(original, destination);
                    originalRestored = true;
                }
                if (hadMeta) File.Copy(Path.Combine(backup, "original.meta"), destination + ".meta", true);
                if (!hadMeta && File.Exists(destination + ".meta"))
                    File.Move(destination + ".meta", Path.Combine(backup, "generated.meta"));
                AssetDatabase.Refresh();
                File.Delete(pending);
                disposed = true;
            }
        }

        // =====================================================================
        // Lua 脚本打包
        // ---------------------------------------------------------------------
        // Unity 只把 .txt/.json/.bytes 等识别为 TextAsset，.lua 会被当作 DefaultAsset，
        // 因此不能把 LuaScripts 原目录直接打进 AB。
        // 做法：构建前把 .lua 加密并签名到暂存目录，追加 .txt 后缀
        // （Unity 会剥离最后一个扩展名，包内资源名仍为 "XXX.lua"），
        // 打上 AB 标签后随本次构建一起打包，构建结束删除暂存目录，不污染工程。
        // =====================================================================

        /// <summary>把 LuaScripts 复制到暂存目录并打上 AB 标签，返回脚本数量。</summary>
        public static int PrepareLuaBundleSources()
        {
            if (!Directory.Exists(LuaSourceRoot))
            {
                Debug.LogWarning($"[BuildAssetBundles] Lua source not found: {LuaSourceRoot}");
                return 0;
            }

            var luaFiles = LuaProtectionBuild.Sources();

            if (luaFiles.Count == 0)
            {
                Debug.LogWarning($"[BuildAssetBundles] No .lua found under {LuaSourceRoot}");
                return 0;
            }

            using (var signer = LuaProtectionBuild.OpenSigner())
            {
                byte[] key = Game.Security.LuaScriptProtection.EncryptionKey();
                foreach (var src in luaFiles)
                {
                    string dst = LuaStageRoot + "/" + src.Key + ".txt";
                    Directory.CreateDirectory(Path.GetDirectoryName(dst));
                    File.WriteAllBytes(dst, Game.Security.ProtectedLuaPayload.EncryptAndSign(
                        File.ReadAllBytes(src.Value), src.Key, key, signer));
                }
            }

            AssetDatabase.Refresh();

            foreach (var src in luaFiles)
            {
                string rel = src.Key;
                string assetPath = (LuaStageRoot + "/" + rel + ".txt").Replace('\\', '/');
                var importer = AssetImporter.GetAtPath(assetPath);
                if (importer == null) throw new BuildFailedException($"Lua importer not found: {assetPath}");
                importer.assetBundleName = LuaBundleName;
                importer.assetBundleVariant = "";
                importer.SaveAndReimport();
            }

            Debug.Log($"[BuildAssetBundles] Staged {luaFiles.Count} encrypted and signed Lua files -> '{LuaBundleName}'");
            return luaFiles.Count;
        }

        /// <summary>删除暂存目录（含 .meta）。</summary>
        public static void CleanupLuaBundleSources()
        {
            if (Directory.Exists(LuaStageRoot))
            {
                Directory.Delete(LuaStageRoot, true);
                string meta = LuaStageRoot + ".meta";
                if (File.Exists(meta)) File.Delete(meta);
            }
        }

        // =====================================================================
        // 构建 Player（含 AB）
        // =====================================================================

        [MenuItem("Tools/Build Player (with AssetBundles)", false, 202)]
        public static void BuildPlayerWithBundles()
        {
            string outputPath = EditorUtility.SaveFolderPanel(
                "Choose Build Output Folder", "", "");
            if (string.IsNullOrEmpty(outputPath)) return;

            string targetName = EditorUserBuildSettings.activeBuildTarget switch
            {
                BuildTarget.StandaloneWindows or BuildTarget.StandaloneWindows64 => "/Game.exe",
                BuildTarget.Android => "/Game.apk",
                BuildTarget.iOS => "/Game",
                _ => "/Game"
            };

            BuildTools.BuildPreparedPlayer(EditorUserBuildSettings.activeBuildTarget,
                outputPath + targetName, EditorUserBuildSettings.development
                    ? BuildOptions.Development
                    : BuildOptions.None);
        }
    }
}
