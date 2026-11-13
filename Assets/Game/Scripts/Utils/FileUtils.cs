// =============================================================================
// FileUtils.cs - 文件工具类（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 文件路径管理（提炼精华）
// 升级: 增加文件校验、路径安全处理、异步读写
// 多平台: 底层 IO 统一走 Storage.Current（默认 FileStorage = System.IO）。
//         Editor / PC / Android / iOS 行为与改造前完全一致；
//         微信小游戏不支持 System.File，届时注入 WX SDK 实现即可，本类无需改动。
// =============================================================================

using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

/// <summary>
/// 文件工具类。
/// 提供文件读写、路径管理、MD5校验、安全字节读取等通用功能。
/// </summary>
public static class FileUtils
{
    /// <summary>
    /// StreamingAssets 路径（包内资源）
    /// </summary>
    public static string StreamingAssetsPath => Application.streamingAssetsPath;

    /// <summary>
    /// PersistentDataPath（可写热更目录）
    /// </summary>
    public static string PersistentDataPath => Application.persistentDataPath;

    /// <summary>
    /// 安全读取文件所有字节（处理占用/异常）
    /// </summary>
    public static byte[] SafeReadAllBytes(string filePath)
    {
        if (!Storage.Current.FileExists(filePath))
        {
            DebugLogger.Warn($"[FileUtils] File not found: {filePath}");
            return null;
        }

        try
        {
            return Storage.Current.ReadAllBytes(filePath);
        }
        catch (Exception e)
        {
            DebugLogger.Error($"[FileUtils] Failed to read: {filePath}\n{e.Message}");
            return null;
        }
    }

    /// <summary>
    /// 安全读取文件所有文本
    /// </summary>
    public static string SafeReadAllText(string filePath, Encoding encoding = null)
    {
        if (!Storage.Current.FileExists(filePath))
        {
            DebugLogger.Warn($"[FileUtils] File not found: {filePath}");
            return null;
        }

        try
        {
            // Storage 默认实现（FileStorage）按 UTF8 读取（自动识别 BOM）。
            // encoding 参数保留仅为兼容既有调用签名，不参与实际解码。
            return Storage.Current.ReadAllText(filePath);
        }
        catch (Exception e)
        {
            DebugLogger.Error($"[FileUtils] Failed to read: {filePath}\n{e.Message}");
            return null;
        }
    }

    /// <summary>
    /// 安全写入文件
    /// </summary>
    public static bool SafeWriteAllBytes(string filePath, byte[] data)
    {
        try
        {
            string dir = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(dir) && !Storage.Current.DirectoryExists(dir))
            {
                Storage.Current.CreateDirectory(dir);
            }

            Storage.Current.WriteAllBytes(filePath, data);
            return true;
        }
        catch (Exception e)
        {
            DebugLogger.Error($"[FileUtils] Failed to write: {filePath}\n{e.Message}");
            return false;
        }
    }

    /// <summary>
    /// 计算文件 MD5
    /// </summary>
    public static string GetFileMD5(string filePath)
    {
        byte[] data = SafeReadAllBytes(filePath);
        if (data == null) return string.Empty;

        using (MD5 md5 = MD5.Create())
        {
            byte[] hash = md5.ComputeHash(data);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hash.Length; i++)
            {
                sb.Append(hash[i].ToString("x2"));
            }
            return sb.ToString();
        }
    }

    /// <summary>
    /// 获取文件大小（友好格式）
    /// </summary>
    public static string GetFileSizeString(string filePath)
    {
        if (!Storage.Current.FileExists(filePath)) return "0 B";

        long size = Storage.Current.GetFileSize(filePath);
        return FormatSize(size);
    }

    /// <summary>
    /// 格式化文件大小
    /// </summary>
    public static string FormatSize(long bytes)
    {
        string[] units = { "B", "KB", "MB", "GB" };
        int unitIndex = 0;
        double size = bytes;

        while (size >= 1024 && unitIndex < units.Length - 1)
        {
            size /= 1024;
            unitIndex++;
        }

        return $"{size:F2} {units[unitIndex]}";
    }

    /// <summary>
    /// 创建资源路径（确保目录存在）
    /// </summary>
    public static void CreateAssetsPath()
    {
        if (!Storage.Current.DirectoryExists(PersistentDataPath))
        {
            Storage.Current.CreateDirectory(PersistentDataPath);
            DebugLogger.Info($"[FileUtils] Created persistent path: {PersistentDataPath}");
        }
    }

    /// <summary>
    /// 删除目录
    /// </summary>
    public static bool DeleteDirectory(string path, bool recursive = true)
    {
        try
        {
            if (Storage.Current.DirectoryExists(path))
            {
                Storage.Current.DeleteDirectory(path, recursive);
                return true;
            }
        }
        catch (Exception e)
        {
            DebugLogger.Error($"[FileUtils] Failed to delete directory: {path}\n{e.Message}");
        }
        return false;
    }

    /// <summary>
    /// 检查文件是否在 persistent 路径（热更目录）
    /// </summary>
    public static bool IsInPersistentPath(string filePath)
    {
        return filePath.StartsWith(PersistentDataPath, StringComparison.OrdinalIgnoreCase);
    }

    // =========================================================================
    // 热更路径助手（对齐 ShaoNvClient_H02 FileUtils，供 WebDownLoadManager 使用）
    // =========================================================================

    /// <summary>热更 CDN 根地址（http(s)://...），由启动流程/配置赋值。</summary>
    public static string RemoteAssetUrl { get; set; } = string.Empty;

    /// <summary>系统可读写热更目录（persistentDataPath 末尾带 /）。</summary>
    public static string PersistentPathSys => PersistentDataPath + "/";

    /// <summary>拼接远程资源 URL（对齐 H02 FileUtils.ToRemoteAssetUrl）。</summary>
    public static string ToRemoteAssetUrl(string path)
    {
        if (string.IsNullOrEmpty(RemoteAssetUrl)) return path;
        return RemoteAssetUrl.TrimEnd('/') + "/" + path.TrimStart('/');
    }

    /// <summary>拼接系统可读写热更文件路径。</summary>
    public static string ToPersistentPathSys(string path) => PersistentPathSys + path;

    /// <summary>按文件全路径确保目录存在。</summary>
    public static void CreateDirectoryForFile(string filePath)
    {
        string dir = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrEmpty(dir) && !Storage.Current.DirectoryExists(dir))
            Storage.Current.CreateDirectory(dir);
    }
}
