// =============================================================================
// TimeProfiler.cs - 轻量级性能计时器（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine.TimeProfiler
// 升级: 增加统计功能、自动Dump、支持多次计时
// =============================================================================

using System.Collections.Generic;
using System.Text;

/// <summary>
/// 轻量级性能计时器。基于 DateTime.Ticks 实现纳秒级精度。
/// 用法:
///   TimeProfiler.Start("LoadConfig");
///   // ... do work ...
///   TimeProfiler.End("LoadConfig");
///   TimeProfiler.Dump();
/// </summary>
public static class TimeProfiler
{
    private static readonly Dictionary<string, long> _startTicks = new Dictionary<string, long>();
    private static readonly Dictionary<string, List<long>> _costsHistory = new Dictionary<string, List<long>>();

    /// <summary>
    /// 开始计时
    /// </summary>
    public static void Start(string name)
    {
        _startTicks[name] = System.DateTime.Now.Ticks;
    }

    /// <summary>
    /// 结束计时，返回耗时（毫秒）
    /// </summary>
    public static double End(string name)
    {
        long startTick;
        if (_startTicks.TryGetValue(name, out startTick))
        {
            long cost = System.DateTime.Now.Ticks - startTick;
            double ms = cost * 0.0001; // 1 tick = 100ns = 0.0001ms

            if (!_costsHistory.ContainsKey(name))
            {
                _costsHistory[name] = new List<long>();
            }
            _costsHistory[name].Add(cost);

            _startTicks.Remove(name);
            return ms;
        }

        return -1;
    }

    /// <summary>
    /// 输出所有计时统计
    /// </summary>
    public static string Dump()
    {
        var sb = new StringBuilder();
        sb.AppendLine("========== TimeProfiler Report ==========");

        foreach (var kvp in _costsHistory)
        {
            string name = kvp.Key;
            List<long> costs = kvp.Value;

            if (costs.Count == 0) continue;

            double totalMs = 0;
            double minMs = double.MaxValue;
            double maxMs = double.MinValue;
            foreach (long cost in costs)
            {
                double ms = cost * 0.0001;
                totalMs += ms;
                if (ms < minMs) minMs = ms;
                if (ms > maxMs) maxMs = ms;
            }

            double avgMs = totalMs / costs.Count;
            sb.AppendLine($"  {name}: count={costs.Count}, avg={avgMs:F2}ms, min={minMs:F2}ms, max={maxMs:F2}ms, total={totalMs:F2}ms");
        }

        sb.AppendLine("==========================================");
        return sb.ToString();
    }

    /// <summary>
    /// 清除所有计时数据
    /// </summary>
    public static void Clear()
    {
        _startTicks.Clear();
        _costsHistory.Clear();
    }
}
