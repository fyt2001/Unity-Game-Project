// =============================================================================
// MissingGlyphWatcher.cs
// =============================================================================
// 运行时缺字监视器 —— 捕获「静态字集没覆盖到」的文案，供补齐字符集使用。
//
// 【为什么要另起一套，而不是直接复用 H02 的 TMPLackCharListener】
//   H02 旧项目那份 TMPLackCharListener 实际是断链的死代码：
//     * 它的入口 TriggerLack(object) 在整个 H02 工程里没有任何调用点；
//     * 它依赖的 LackCharData 类型在 Assets 下根本不存在；
//     * 它配合的 COLLECT_CHAR 宏只有「开关」与「打包时定义」，没有任何 #if 使用处。
//   也就是说那套运行时监听从未真正工作过。H02 真正起作用的是编辑器侧扫描工具。
//
// 【本实现的挂钩点】
//   TMP 3.0.6 没有公开的「缺字事件」API（TMP_Text 只有 OnPreRenderText）。
//   唯一可靠的信号是 TMP 渲染缺字时打印的原生警告（TMPro_Private.cs:1197 /
//   TMPro_UGUI_Private.cs:1271）：
//     "The character with Unicode value \uXXXX was not found in the [FONT] font asset
//      or any potential fallbacks. It was replaced by Unicode character \uYYYY
//      in text object [OBJ]."
//   该警告携带：缺字码位、字体资产名、**出问题的 GameObject 名** —— 定位信息足够。
//
//   ⚠ 前提：TMP Settings 的 m_warningsDisabled 必须为 0（关闭警告会让本监视器失效）。
//
// 【定位能力】
//   在此基础上补齐 TMP 警告没给的信息：当前场景名、Transform 层级路径、发生时间、重复次数。
// =============================================================================

#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class MissingGlyphWatcher
{
    public sealed class Record
    {
        public string scene;
        public string objectPath;
        public string fontAsset;
        public char character;
        public int count;
        public string firstAt;
        public string lastAt;
    }

    // "…Unicode value \uXXXX was not found in the [FONT] font asset…"
    static readonly Regex s_MissingRx = new Regex(
        @"Unicode value \\[uU](?<code>[0-9A-Fa-f]{4,8}) was not found in the \[(?<font>.+?)\] font asset",
        RegexOptions.Compiled);

    // "…in text object [OBJ]."
    static readonly Regex s_ObjectRx = new Regex(
        @"text object \[(?<obj>.+?)\]",
        RegexOptions.Compiled);

    static readonly Dictionary<string, Record> s_Records = new Dictionary<string, Record>();
    static bool s_Installed;
    static bool s_WriteFile = true;
    static string s_LogPath;

    public static int Count { get { return s_Records.Count; } }

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    static void Install()
    {
        if (s_Installed) return;
        s_Installed = true;
        s_Records.Clear();
        s_LogPath = Path.Combine(Application.persistentDataPath, "missing_glyphs.log");
        Application.logMessageReceived += OnLogReceived;
        Debug.Log("[MissingGlyphWatcher] 已挂载 —— 监听 TMP 缺字警告（依赖 TMP Settings.m_warningsDisabled = 0）。");
    }

    static void OnLogReceived(string message, string stackTrace, LogType type)
    {
        if (type != LogType.Warning && type != LogType.Error) return;
        if (string.IsNullOrEmpty(message)) return;
        if (message.IndexOf("was not found in the", StringComparison.Ordinal) < 0) return;

        var m = s_MissingRx.Match(message);
        if (!m.Success) return;

        int code;
        if (!int.TryParse(m.Groups["code"].Value, NumberStyles.HexNumber,
                CultureInfo.InvariantCulture, out code)) return;

        var ch = (char)code;
        var fontName = m.Groups["font"].Value;
        var objName = "<?>";
        var om = s_ObjectRx.Match(message);
        if (om.Success) objName = om.Groups["obj"].Value;

        var sceneName = SceneManager.GetActiveScene().name;
        var now = DateTime.Now.ToString("HH:mm:ss");
        var key = sceneName + "|" + objName + "|" + code.ToString("X4");

        Record r;
        if (s_Records.TryGetValue(key, out r))
        {
            r.count++;
            r.lastAt = now;
        }
        else
        {
            r = new Record
            {
                scene = sceneName,
                objectPath = ResolvePath(objName),
                fontAsset = fontName,
                character = ch,
                count = 1,
                firstAt = now,
                lastAt = now,
            };
            s_Records[key] = r;

            var line = string.Format(
                "[MissingGlyphWatcher] 缺字 '{0}' (U+{1:X4}) | 场景={2} | 对象={3} | 字体={4}",
                ch, code, sceneName, r.objectPath, fontName);
            Debug.LogError(line);
            AppendLine(line + (string.IsNullOrEmpty(stackTrace) ? "" : "\n" + stackTrace));
        }
    }

    /// <summary>把 GameObject 名解析成 Transform 层级路径（编辑器下才做，避免运行时遍历开销）。</summary>
    static string ResolvePath(string objName)
    {
#if UNITY_EDITOR
        if (string.IsNullOrEmpty(objName) || objName == "<?>") return objName;
        var scene = SceneManager.GetActiveScene();
        if (!scene.IsValid()) return objName;
        var roots = scene.GetRootGameObjects();
        for (int i = 0; i < roots.Length; i++)
        {
            var all = roots[i].GetComponentsInChildren<Transform>(true);
            for (int j = 0; j < all.Length; j++)
            {
                if (all[j].name == objName) return BuildPath(all[j]);
            }
        }
#endif
        return objName;
    }

    static string BuildPath(Transform t)
    {
        var sb = new StringBuilder(t.name);
        var p = t.parent;
        while (p != null) { sb.Insert(0, p.name + "/"); p = p.parent; }
        return sb.ToString();
    }

    static void AppendLine(string text)
    {
        if (!s_WriteFile || string.IsNullOrEmpty(s_LogPath)) return;
        try { File.AppendAllText(s_LogPath, text + "\n", new UTF8Encoding(false)); }
        catch { s_WriteFile = false; }
    }

    /// <summary>汇总当前所有缺字记录（去重后的清单）。</summary>
    public static string Dump()
    {
        if (s_Records.Count == 0)
        {
            return "[MissingGlyphWatcher] 本次运行未捕获到缺字。";
        }

        var sb = new StringBuilder();
        sb.AppendFormat("[MissingGlyphWatcher] 共 {0} 条缺字记录：\n", s_Records.Count);

        var chars = new HashSet<char>();
        foreach (var kv in s_Records)
        {
            var r = kv.Value;
            chars.Add(r.character);
            sb.AppendFormat("  '{0}' U+{1:X4} x{2} | {3} | {4} | {5}~{6} | 字体={7}\n",
                r.character, (int)r.character, r.count, r.scene, r.objectPath, r.firstAt, r.lastAt, r.fontAsset);
        }

        var sorted = new List<char>(chars);
        sorted.Sort();
        var all = new StringBuilder();
        foreach (var c in sorted) all.Append(c);
        sb.AppendFormat("涉及到的去重字符（{0} 个）：{1}\n", sorted.Count, all);
        sb.AppendFormat("完整日志：{0}", s_LogPath);
        return sb.ToString();
    }

    public static List<Record> GetAll()
    {
        return new List<Record>(s_Records.Values);
    }

    public static void Clear()
    {
        s_Records.Clear();
    }
}
#endif
