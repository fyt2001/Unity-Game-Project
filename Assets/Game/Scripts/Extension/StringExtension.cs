// =============================================================================
// StringExtension.cs - 字符串扩展方法库（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine
// 升级: 增加更多实用方法，安全空检查，性能优化
// =============================================================================

using System.Text.RegularExpressions;

/// <summary>
/// 字符串扩展方法集合。提供空检查、正则操作、格式化、类型转换等便捷API。
/// </summary>
public static class StringExtension
{
    /// <summary>
    /// 字符串是否 null 或空
    /// </summary>
    public static bool IsNullOrEmpty(this string str)
    {
        return string.IsNullOrEmpty(str);
    }

    /// <summary>
    /// Trim 后是否为空
    /// </summary>
    public static bool IsEmpty(this string str)
    {
        return str != null && string.IsNullOrEmpty(str.Trim());
    }

    /// <summary>
    /// 忽略大小写比较
    /// </summary>
    public static bool EqualsIgnoreCase(this string a, string b)
    {
        return string.Compare(a, b, true) == 0;
    }

    /// <summary>
    /// 去除 Unity 实例化产生的 "(Clone)" 后缀
    /// </summary>
    public static string TrimClone(this string str)
    {
        if (str.EndsWith("(Clone)"))
        {
            return str.Substring(0, str.Length - "(Clone)".Length);
        }
        return str;
    }

    #region 正则表达式

    /// <summary>
    /// 正则匹配（返回所有匹配）
    /// </summary>
    public static MatchCollection RegMatches(this string str, string pattern, RegexOptions option = RegexOptions.None)
    {
        if (str.IsNullOrEmpty()) return null;
        return new Regex(pattern, option).Matches(str);
    }

    /// <summary>
    /// 正则匹配（返回第一个匹配）
    /// </summary>
    public static Match RegMatch(this string str, string pattern, RegexOptions option = RegexOptions.None)
    {
        if (str.IsNullOrEmpty()) return null;
        return new Regex(pattern, option).Match(str);
    }

    /// <summary>
    /// 正则替换
    /// </summary>
    public static string RegReplace(this string str, string pattern, string replacement, RegexOptions option = RegexOptions.None)
    {
        if (str.IsNullOrEmpty()) return str;
        return str.RegReplace(new Regex(pattern, option), replacement);
    }

    /// <summary>
    /// 正则替换（替换值由函数生成）
    /// </summary>
    public static string RegReplace(this string str, string pattern, System.Func<string, string> replaceFunc, RegexOptions option = RegexOptions.None)
    {
        if (str.IsNullOrEmpty() || replaceFunc == null) return str;
        return str.RegReplace(new Regex(pattern, option), replaceFunc);
    }

    public static string RegReplace(this string str, Regex reg, string replacement)
    {
        if (str.IsNullOrEmpty() || reg == null) return str;

        string matchStr = reg.Match(str).Value;
        if (!string.IsNullOrEmpty(matchStr))
        {
            return str.Replace(matchStr, replacement);
        }
        return str;
    }

    public static string RegReplace(this string str, Regex reg, System.Func<string, string> replaceFunc)
    {
        if (str.IsNullOrEmpty() || reg == null || replaceFunc == null) return str;

        string matchStr = reg.Match(str).Value;
        if (!string.IsNullOrEmpty(matchStr))
        {
            return str.Replace(matchStr, replaceFunc(matchStr));
        }
        return str;
    }

    #endregion

    /// <summary>
    /// 检测是否包含中文字符
    /// </summary>
    public static bool HasChinese(this string s)
    {
        return !string.IsNullOrEmpty(s) && new Regex("[\u4e00-\u9fa5]").IsMatch(s);
    }

    /// <summary>
    /// 安全的 string.Format（带异常捕获）
    /// </summary>
    public static string Fill(this string format, params object[] args)
    {
        if (format.IsNullOrEmpty()) return format;

        try
        {
            return string.Format(format, args);
        }
        catch (System.FormatException e)
        {
            DebugLogger.Error($"Fail to Fill: {format}  Exception: {e.Message}");
        }

        return format;
    }

    /// <summary>
    /// 安全转 int
    /// </summary>
    public static int ToInt(this string s)
    {
        int i = 0;
        if (s != null) int.TryParse(s.Trim(), out i);
        return i;
    }

    /// <summary>
    /// 安全转 float
    /// </summary>
    public static float ToFloat(this string s)
    {
        float f = 0;
        if (s != null) float.TryParse(s.Trim(), out f);
        return f;
    }

    /// <summary>
    /// 安全转 bool
    /// </summary>
    public static bool ToBool(this string s)
    {
        bool b = false;
        if (s != null) bool.TryParse(s.Trim(), out b);
        return b;
    }

    /// <summary>
    /// 分割字符串并移除空条目
    /// </summary>
    public static string[] SplitWithoutEmpty(this string s, params char[] separator)
    {
        return !string.IsNullOrEmpty(s) ? s.Split(separator, System.StringSplitOptions.RemoveEmptyEntries) : null;
    }

    /// <summary>
    /// 时间字符串格式化
    /// </summary>
    public static string ToTimeString(this string timeStr, string format = "yyyy-MM-dd HH:mm:ss", string timeZone = "zh-CN")
    {
        if (string.IsNullOrEmpty(timeStr)) return "";
        System.DateTime dt;
        if (System.DateTime.TryParse(timeStr, out dt))
        {
            System.Globalization.CultureInfo info = System.Globalization.CultureInfo.CreateSpecificCulture(timeZone);
            return dt.ToString(format, info);
        }
        return "";
    }

    /// <summary>
    /// 截取子串中某字符之前的部分
    /// </summary>
    public static string Before(this string str, string from)
    {
        if (string.IsNullOrEmpty(str) || string.IsNullOrEmpty(from)) return str;
        int pos = str.IndexOf(from);
        return pos > -1 ? str.Substring(0, pos) : str;
    }

    /// <summary>
    /// 截取子串中某字符之后的部分
    /// </summary>
    public static string After(this string str, string from)
    {
        if (string.IsNullOrEmpty(str) || string.IsNullOrEmpty(from)) return str;
        int pos = str.LastIndexOf(from);
        return pos > -1 ? str.Substring(pos + from.Length) : str;
    }

    /// <summary>
    /// 获取文件扩展名（小写）
    /// </summary>
    public static string GetExt(this string file)
    {
        if (string.IsNullOrEmpty(file)) return "";
        return System.IO.Path.GetExtension(file).ToLower();
    }

    /// <summary>
    /// 反斜杠转正斜杠
    /// </summary>
    public static string Slash(this string s)
    {
        return !string.IsNullOrEmpty(s) ? s.Replace('\\', '/') : s;
    }

    /// <summary>
    /// 截取前N个字符（安全）
    /// </summary>
    public static string Truncate(this string s, int maxLength)
    {
        if (string.IsNullOrEmpty(s) || s.Length <= maxLength) return s;
        return s.Substring(0, maxLength);
    }
}
