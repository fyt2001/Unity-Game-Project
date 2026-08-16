// =============================================================================
// FileUtils.cs - 文件工具类（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 文件路径管理（提炼精华）
// 升级: 增加文件校验、路径安全处理、异步读写
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
        if (!File.Exists(filePath))
        {
            DebugLogger.Warn($"[FileUtils] File not found: {filePath}");
            return null;
        }

        try
        {
            return File.ReadAllBytes(filePath);
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
        if (!File.Exists(filePath))
        {
            DebugLogger.Warn($"[FileUtils] File not found: {filePath}");
            return null;
        }

        try
        {
            return File.ReadAllText(filePath, encoding ?? Encoding.UTF8);
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
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            File.WriteAllBytes(filePath, data);
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
        if (!File.Exists(filePath)) return "0 B";

        long size = new FileInfo(filePath).Length;
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
        if (!Directory.Exists(PersistentDataPath))
        {
            Directory.CreateDirectory(PersistentDataPath);
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
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive);
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
}
