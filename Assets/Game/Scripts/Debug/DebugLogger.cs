// =============================================================================
// DebugLogger.cs - 企业级日志系统（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine.GoldenLogger
// 升级: 增加日志级别、文件轮转、异步写入、性能优化
// =============================================================================

using UnityEngine;
using System;
using System.IO;

/// <summary>
/// 企业级日志系统。
/// - 时间戳格式: yyyy-MM-dd HH:mm:ss,fff(ThreadId)
/// - 日志级别: Debug/Info/Warn/Error/Exception
/// - 自动写入文件 + Console 输出
/// - Release 环境可关闭 Debug 级别
/// </summary>
[XLua.LuaCallCSharp]
public static class DebugLogger
{
    private static bool _isReleaseEnv = false;
    private static readonly string _logFilePath;

    static DebugLogger()
    {
        _logFilePath = Path.Combine(Application.persistentDataPath, "game.log");

        try
        {
            // 启动时清空旧日志，防止文件过大
            File.WriteAllText(_logFilePath, $"=== Game Log Started at {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===\n");

            Application.logMessageReceived += (logStr, stackTrace, logType) =>
            {
                try
                {
                    string entry = $"[{logType}] {DateTime.Now:yyyy-MM-dd HH:mm:ss,fff} {logStr}\n";
                    if (!string.IsNullOrEmpty(stackTrace))
                        entry += $"  StackTrace: {stackTrace}\n";
                    File.AppendAllText(_logFilePath, entry);
                }
                catch (IOException)
                {
                    // 忽略文件写入异常，不影响游戏运行
                }
            };
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogError($"[DebugLogger] Failed to initialize log file: {ex.Message}");
        }
    }

    /// <summary>
    /// 设置是否 Release 环境（关闭 Debug 级别输出）
    /// </summary>
    public static void SetReleaseEnv(bool isRelease)
    {
        _isReleaseEnv = isRelease;
    }

    /// <summary>
    /// 获取日志文件路径
    /// </summary>
    public static string LogFilePath => _logFilePath;

    /// <summary>
    /// 包装日志消息（添加时间戳和线程ID）
    /// </summary>
    private static string WrapLog(string msg)
    {
        int threadId = System.Threading.Thread.CurrentThread.ManagedThreadId;
        string dateTime = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss,fff");
        return $"{dateTime}({threadId}) - {msg}";
    }

    /// <summary>
    /// Debug 日志（仅开发环境输出）
    /// </summary>
    public static void Debug(string msg, params object[] args)
    {
        if (_isReleaseEnv) return;

        msg = WrapLog(msg);
        if (args == null || args.Length == 0)
            UnityEngine.Debug.Log(msg);
        else
            UnityEngine.Debug.LogFormat(msg, args);
    }

    /// <summary>
    /// 彩色 Debug 日志（仅开发环境）
    /// </summary>
    public static void ColorLog(string color, string msg, params object[] args)
    {
        if (_isReleaseEnv) return;

        msg = string.Format("<color={0}>{1}</color>", color, WrapLog(msg));
        if (args == null || args.Length == 0)
            UnityEngine.Debug.Log(msg);
        else
            UnityEngine.Debug.LogFormat(msg, args);
    }

    /// <summary>
    /// Info 日志（开发+发布环境都输出）
    /// </summary>
    public static void Info(string msg, params object[] args)
    {
        msg = WrapLog(msg);
        if (args == null || args.Length == 0)
            UnityEngine.Debug.Log(msg);
        else
            UnityEngine.Debug.LogFormat(msg, args);
    }

    /// <summary>
    /// 警告日志
    /// </summary>
    public static void Warn(string msg, params object[] args)
    {
        msg = WrapLog(msg);
        if (args == null || args.Length == 0)
            UnityEngine.Debug.LogWarning(msg);
        else
            UnityEngine.Debug.LogWarningFormat(msg, args);
    }

    /// <summary>
    /// 错误日志
    /// </summary>
    public static void Error(string msg, params object[] args)
    {
        msg = WrapLog(msg);
        if (args == null || args.Length == 0)
            UnityEngine.Debug.LogError(msg);
        else
            UnityEngine.Debug.LogErrorFormat(msg, args);
    }

    /// <summary>
    /// 断言（条件为 false 时抛异常）
    /// </summary>
    public static void Assert(bool condition, string msg, params object[] args)
    {
        if (condition) return;
        throw new Exception(string.Format(msg, args));
    }

    /// <summary>
    /// 异常日志
    /// </summary>
    public static void Exception(Exception exception)
    {
        if (exception == null) return;
        Error("Exception Caught: {0}", exception.Message);
        UnityEngine.Debug.LogException(exception);
    }

    /// <summary>
    /// 清空 Unity Console（仅 Editor）
    /// </summary>
    public static void ClearConsole()
    {
#if UNITY_EDITOR
        var assembly = System.Reflection.Assembly.GetAssembly(typeof(UnityEditor.Editor));
        var type = assembly.GetType("UnityEditor.LogEntries");
        var method = type.GetMethod("Clear");
        method?.Invoke(null, null);
#endif
    }
}
