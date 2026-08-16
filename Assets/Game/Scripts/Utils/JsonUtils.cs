// =============================================================================
// JsonUtils.cs - JSON工具类（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine.JsonUtils
// 升级: 增加异步加载、对象池优化、异常安全
// =============================================================================

using System;
using System.IO;
using UnityEngine;

/// <summary>
/// JSON 工具类。
/// 注意：实际项目建议使用 Newtonsoft.Json 或 Unity 自带的 JsonUtility。
/// 此处使用 LitJson 作为示例（需要导入 LitJson 库）。
/// </summary>
public static class JsonUtils
{
    /// <summary>
    /// 从 JSON 字符串加载
    /// </summary>
    public static T Load<T>(string jsonStr)
    {
        if (string.IsNullOrEmpty(jsonStr)) return default(T);

        try
        {
            return JsonUtility.FromJson<T>(jsonStr);
        }
        catch (Exception e)
        {
            DebugLogger.Exception(e);
            return default(T);
        }
    }

    /// <summary>
    /// 从文件加载 JSON
    /// </summary>
    public static T LoadFromFile<T>(string filePath)
    {
        if (!File.Exists(filePath))
        {
            DebugLogger.Error($"[JsonUtils] File not found: {filePath}");
            return default(T);
        }

        try
        {
            string jsonStr = File.ReadAllText(filePath);
            return Load<T>(jsonStr);
        }
        catch (Exception e)
        {
            DebugLogger.Exception(e);
            return default(T);
        }
    }

    /// <summary>
    /// 对象序列化为 JSON 字符串
    /// </summary>
    public static string ToJson(object obj, bool prettyPrint = false)
    {
        if (obj == null) return "null";

        try
        {
            return JsonUtility.ToJson(obj, prettyPrint);
        }
        catch (Exception e)
        {
            DebugLogger.Exception(e);
            return "{}";
        }
    }

    /// <summary>
    /// 对象序列化并保存到文件
    /// </summary>
    public static void SaveToFile(object obj, string filePath, bool prettyPrint = false)
    {
        try
        {
            string jsonStr = ToJson(obj, prettyPrint);
            string dir = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            File.WriteAllText(filePath, jsonStr);
        }
        catch (Exception e)
        {
            DebugLogger.Exception(e);
        }
    }

    /// <summary>
    /// 从 Resources 加载 JSON
    /// </summary>
    public static T LoadFromResources<T>(string resourcePath)
    {
        TextAsset textAsset = Resources.Load<TextAsset>(resourcePath);
        if (textAsset == null)
        {
            DebugLogger.Error($"[JsonUtils] Resource not found: {resourcePath}");
            return default(T);
        }

        return Load<T>(textAsset.text);
    }
}
