// =============================================================================
// AssetBundleUtility.cs - AssetBundle 平台工具类
// =============================================================================

using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

namespace MyAssetBundles
{
    public static class Utility
    {
        public const string AssetBundlesOutputPath = "AssetBundles";

        public static bool RequiresWebRequest(string path)
        {
            return !string.IsNullOrEmpty(path) &&
                (path.StartsWith("http://", System.StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("https://", System.StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("jar:", System.StringComparison.OrdinalIgnoreCase));
        }

        public static string LocalFilePath(string path)
        {
            if (!string.IsNullOrEmpty(path) && path.StartsWith("file://", System.StringComparison.OrdinalIgnoreCase))
                return new System.Uri(path).LocalPath;
            return path;
        }

        // AB 入口文件名（与 ShaoNvClient_H02 一致: game.asset，而非按平台名）
        public static string GetPlatformName()
        {
            return "game.asset";
        }
    }
}
