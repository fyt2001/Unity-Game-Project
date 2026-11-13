// =============================================================================
// UIFontCharsetCollector.cs  (Editor only)
// =============================================================================
// UI 字符集扫描器 —— 移植自 H02 旧项目 Assets/Editor/GameTools/LackCharDetech/CollectChar.cs
//
// 运行方式：Unity 菜单 Tools/字体/1. 扫描 UI 字符集
//
// 与 H02 版本的差异（本工程没有 UILocalize / 本地化配置表，故必须改造）：
//   1. 文本源改为：prefab / scene 的 TMP 文本字段 + Lua、C# 代码里的字符串字面量；
//   2. prefab 扫描包含 inactive 子节点（H02 用 GetComponentsInChildren<TMP_Text>() 只扫 active）；
//   3. 排除 StreamingAssets（已打包 AB 是二进制，误当 UTF-8 读会产出大量假字符）
//      与 TMP 的 LineBreaking Leading/Following Characters.txt（TMP 内部数据，非文案）。
//
// 产出三个文件（均在 Assets/Game/Fonts/Generated/）：
//   charset_scanned.txt        —— 本次扫描到的工程实际字符（去重排序）
//   charset_extra.txt          —— 人工维护的补充字符表（ASCII / GB2312 一级 / 标点），工具不覆盖
//   charset.txt                —— 最终烘焙输入 = scanned ∪ extra
// =============================================================================

#if UNITY_EDITOR
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using TMPro;
using UnityEditor;
using UnityEngine;

namespace Game.EditorTools
{
    public static class UIFontCharsetCollector
    {
        const string kGenDir     = "Assets/Game/Fonts/Generated";
        const string kScannedOut = kGenDir + "/charset_scanned.txt";
        const string kExtraIn    = kGenDir + "/charset_extra.txt";
        const string kMergedOut  = kGenDir + "/charset.txt";

        static readonly string[] kSkipDirPrefixes =
        {
            "Assets/TextMesh Pro/Examples",
            "Assets/TextMesh Pro/Fonts",
            "Assets/ThirdParty",
            "Assets/Spine",
            "Assets/StreamingAssets",
            "Assets/Game/LuaScripts/XLua",
            // 自身产物：charset*.txt 就是本工具的扫描结果，不排除会被扫进自己（自污染，
            // 字符集会从 ~1.2k 虚增到 ~4k）
            "Assets/Game/Fonts/Generated",
        };

        static readonly string[] kSkipFileNames =
        {
            "LineBreaking Leading Characters.txt",
            "LineBreaking Following Characters.txt",
        };

        // 只要「会渲染的字符区段」：CJK 汉字、CJK 标点、全角、破折/引号、罗马数字、圈号、几何、杂项符号、装饰
        // 注意：必须包含 Latin-1 补充区 U+00A1-U+00FF —— × ÷ ° ± · 这类排版符号在中文 UI 里很常见，
        // 曾因遗漏该区段，导致商店页「随机 Mod ×1」的 × 渲染成 □（由 MissingGlyphWatcher 在运行时抓到）。
        static readonly Regex kInteresting = new Regex(
            @"[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef\u2010-\u203f\u2100-\u214f\u2460-\u24ff\u25a0-\u25ff\u2600-\u26ff\u2700-\u27bf"
            + @"\u00a1-\u00ff\u2040-\u209f\u20a0-\u20cf]",
            RegexOptions.Compiled);

        static readonly Regex kLuaString = new Regex(
            "\"(?:[^\"\\\\\\n]|\\\\.)*\"" + "|'(?:[^'\\\\\\n]|\\\\.)*'" + "|\\[(=*)\\[.*?\\]\\1\\]",
            RegexOptions.Singleline | RegexOptions.Compiled);

        static readonly Regex kCsString = new Regex(
            "\"(?:[^\"\\\\\\n]|\\\\.)*\"" + "|@\"(?:[^\"]|\"\")*\"",
            RegexOptions.Singleline | RegexOptions.Compiled);

        static readonly Regex kYamlText = new Regex(
            @"^\s*(?:m_Text|m_text|text|m_LabelText|_text|m_Txt)\s*:\s*(.+)$",
            RegexOptions.Multiline | RegexOptions.Compiled);

        [MenuItem("Tools/字体/1. 扫描 UI 字符集")]
        public static void Scan()
        {
            var chars = new HashSet<char>();
            int prefabCount = 0, sceneCount = 0, codeCount = 0;

            var prefabGuids = AssetDatabase.FindAssets("t:Prefab");
            var sceneGuids  = AssetDatabase.FindAssets("t:Scene");
            int total = prefabGuids.Length + sceneGuids.Length;
            int done = 0;

            try
            {
                foreach (var g in prefabGuids)
                {
                    var path = AssetDatabase.GUIDToAssetPath(g);
                    done++;
                    if (ShouldSkip(path)) continue;
                    if (EditorUtility.DisplayCancelableProgressBar("扫描 UI 字符集", path, (float)done / total)) break;

                    var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                    if (go == null) continue;
                    // true => 含 inactive 子节点
                    foreach (var t in go.GetComponentsInChildren<TMP_Text>(true))
                    {
                        Harvest(t.text, chars);
                    }
                    prefabCount++;
                }

                foreach (var g in sceneGuids)
                {
                    var path = AssetDatabase.GUIDToAssetPath(g);
                    done++;
                    if (ShouldSkip(path)) continue;
                    if (EditorUtility.DisplayCancelableProgressBar("扫描 UI 字符集", path, (float)done / total)) break;
                    HarvestYaml(path, chars);
                    sceneCount++;
                }
            }
            finally
            {
                EditorUtility.ClearProgressBar();
            }

            // 代码里的字符串字面量
            foreach (var f in Directory.GetFiles("Assets", "*.*", SearchOption.AllDirectories))
            {
                var p = f.Replace('\\', '/');
                if (ShouldSkip(p)) continue;
                var ext = Path.GetExtension(p).ToLowerInvariant();
                if (ext != ".lua" && ext != ".cs") continue;

                string s;
                try { s = File.ReadAllText(p, Encoding.UTF8); }
                catch { continue; }

                var re = (ext == ".lua") ? kLuaString : kCsString;
                foreach (Match m in re.Matches(s)) Harvest(m.Value, chars);
                codeCount++;
            }

            Directory.CreateDirectory(kGenDir);
            var scanned = Sorted(chars);
            WriteText(kScannedOut, scanned);

            // 合并（extra 由人工维护，缺失时按空处理）
            var extra = new HashSet<char>();
            if (File.Exists(kExtraIn))
            {
                foreach (var c in File.ReadAllText(kExtraIn, Encoding.UTF8)) extra.Add(c);
            }
            foreach (var c in scanned) extra.Add(c);
            var merged = Sorted(extra);
            WriteText(kMergedOut, merged);

            AssetDatabase.Refresh();

            Debug.Log(string.Format(
                "[UIFontCharsetCollector] prefab={0} scene={1} 代码文件={2}\n  扫描字符={3}\n  合并后(烘焙输入)={4}\n  输出: {5} / {6}",
                prefabCount, sceneCount, codeCount, scanned.Count, merged.Count, kScannedOut, kMergedOut));
        }

        [MenuItem("Tools/字体/打开字符集目录")]
        public static void OpenDir()
        {
            Directory.CreateDirectory(kGenDir);
            EditorUtility.RevealInFinder(kGenDir);
        }

        static void Harvest(string text, HashSet<char> outSet)
        {
            if (string.IsNullOrEmpty(text)) return;
            foreach (var ch in text)
            {
                if (kInteresting.IsMatch(ch.ToString())) outSet.Add(ch);
            }
        }

        static void HarvestYaml(string path, HashSet<char> outSet)
        {
            string s;
            try { s = File.ReadAllText(path, Encoding.UTF8); }
            catch { return; }
            foreach (Match m in kYamlText.Matches(s))
            {
                Harvest(m.Groups[1].Value, outSet);
            }
        }

        static List<char> Sorted(HashSet<char> set)
        {
            var list = new List<char>(set);
            for (int i = 0; i < list.Count; i++)
            {
                if (list[i] == '\n' || list[i] == '\r' || list[i] == '\t') list[i] = ' ';
            }
            list.RemoveAll(c => c == ' ');
            list.Sort();
            return list;
        }

        static void WriteText(string path, List<char> chars)
        {
            var sb = new StringBuilder(chars.Count);
            foreach (var c in chars) sb.Append(c);
            File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
        }

        static bool ShouldSkip(string assetPath)
        {
            var p = assetPath.Replace('\\', '/');
            foreach (var d in kSkipDirPrefixes)
            {
                if (p.StartsWith(d)) return true;
            }
            foreach (var f in kSkipFileNames)
            {
                if (p.EndsWith(f)) return true;
            }
            return false;
        }
    }
}
#endif
