// =============================================================================
// CollectionExtension.cs - 集合扩展方法库（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine
// 升级: 增加更多便捷方法、性能优化
// =============================================================================

using System;
using System.Collections;
using System.Collections.Generic;

/// <summary>
/// 集合扩展方法集合。提供字典遍历、列表便捷操作、类型转换、字符串拼接等API。
/// </summary>
public static class CollectionExtension
{
    /// <summary>
    /// 字典遍历
    /// </summary>
    public static void ForEach<K, V>(this IDictionary<K, V> dict, Action<K, V> act)
    {
        if (dict == null || dict.Count == 0 || act == null) return;

        using (var it = dict.GetEnumerator())
        {
            while (it.MoveNext())
            {
                var pair = it.Current;
                act(pair.Key, pair.Value);
            }
        }
    }

    /// <summary>
    /// 集合遍历
    /// </summary>
    public static void ForEach<T>(this IEnumerable<T> e, Action<T> act)
    {
        if (e == null || act == null) return;

        using (var it = e.GetEnumerator())
        {
            while (it.MoveNext())
            {
                act(it.Current);
            }
        }
    }

    /// <summary>
    /// 列表遍历（带索引）
    /// </summary>
    public static void ForEach<T>(this IList<T> list, Action<int, T> act)
    {
        if (list == null || act == null) return;
        for (int i = 0; i < list.Count; i++)
        {
            act(i, list[i]);
        }
    }

    /// <summary>
    /// 便捷添加：自动创建内层 List
    /// </summary>
    public static void Add<K, V>(this Dictionary<K, List<V>> dict, K k, V v)
    {
        if (!dict.TryGetValue(k, out List<V> list))
        {
            list = new List<V>();
            dict.Add(k, list);
        }
        list.Add(v);
    }

    /// <summary>
    /// 集合是否 null 或空
    /// </summary>
    public static bool IsNullOrEmpty(this ICollection c)
    {
        return c == null || c.Count == 0;
    }

    /// <summary>
    /// 列表是否 null 或空
    /// </summary>
    public static bool IsNullOrEmpty<T>(this IList<T> list)
    {
        return list == null || list.Count == 0;
    }

    /// <summary>
    /// 安全获取列表元素
    /// </summary>
    public static T SafeGet<T>(this IList<T> list, int index, T defaultValue = default(T))
    {
        if (list == null || index < 0 || index >= list.Count)
            return defaultValue;
        return list[index];
    }

    /// <summary>
    /// 安全获取字典值
    /// </summary>
    public static V SafeGet<K, V>(this IDictionary<K, V> dict, K key, V defaultValue = default(V))
    {
        V value;
        if (dict != null && dict.TryGetValue(key, out value))
            return value;
        return defaultValue;
    }

    /// <summary>
    /// 通用类型转换（避免装箱）
    /// </summary>
    public static T ConvertTo<T>(this object src)
    {
        try
        {
            return (T)Convert.ChangeType(src, typeof(T));
        }
        catch (Exception e)
        {
            DebugLogger.Error($"ConvertToException for {src} ---> {e.Message}");
        }
        return default(T);
    }

    /// <summary>
    /// 合并为字符串（字符分隔）
    /// </summary>
    public static string Implode<T>(this IEnumerable<T> e, char separator)
    {
        var sb = new System.Text.StringBuilder();
        bool isFirst = true;
        e.ForEach(s =>
        {
            if (!isFirst) sb.Append(separator);
            else isFirst = false;
            sb.Append(s?.ToString());
        });
        return sb.ToString();
    }

    /// <summary>
    /// 合并为字符串（字符串分隔）
    /// </summary>
    public static string Implode<T>(this IEnumerable<T> e, string separator = "")
    {
        var sb = new System.Text.StringBuilder();
        bool hasSep = !string.IsNullOrEmpty(separator);
        bool isFirst = true;
        e.ForEach(s =>
        {
            if (hasSep)
            {
                if (!isFirst) sb.Append(separator);
                else isFirst = false;
            }
            sb.Append(s?.ToString());
        });
        return sb.ToString();
    }

    /// <summary>
    /// 尝试从字典中移除
    /// </summary>
    public static bool TryRemove<K, V>(this IDictionary<K, V> dict, K key)
    {
        if (dict == null || !dict.ContainsKey(key)) return false;
        dict.Remove(key);
        return true;
    }
}
