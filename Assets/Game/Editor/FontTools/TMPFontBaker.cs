// =============================================================================
// TMPFontBaker.cs  (Editor only)
// =============================================================================
// TMP 静态字体烘焙器 —— 用扫描出的 UI 字符集预烘焙 TMP_FontAsset。
//
// 运行方式：Unity 菜单
//   Tools/字体/2. 烘焙 TMP 静态字体（主集）   -> Resources/Fonts/AlibabaPuHuiTiSDF.asset
//   Tools/字体/3. 烘焙 TMP 静态字体（精简集） -> Resources/Fonts/AlibabaPuHuiTiSDF_Lite.asset
//
// 设计取舍（相对 H02 旧项目）：
//   * AtlasPopulationMode 最终落为 Static —— 运行时零动态扩容、零掉帧；
//     Static 模式下 TMP 会自动清空 m_SourceFontFile，因此源 .ttf 不进包（源字随包是 H02 的问题之一）。
//     但 m_SourceFontFile_EditorRef 会保留，后续仍可切回 Dynamic 增量补字。
//   * 多图集打开（enableMultiAtlasSupport = true），单页 1024x1024，SDFAA 渲染。
//   * 子资产（图集 Texture2D / 材质）交由 AssetDatabase.CreateAsset 自动挂载，
//     绝不手工 AddObjectToAsset（重复挂载会报 duplicate 并炸资产）。
// =============================================================================

#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using TMPro;
using UnityEditor;
using UnityEngine;
using UnityEngine.TextCore.LowLevel;

namespace Game.EditorTools
{
    public static class TMPFontBaker
    {
        const string kGenDir     = "Assets/Game/Fonts/Generated";
        const string kSourceTtf  = "Assets/Game/Fonts/AlibabaPuHuiTi-3-55-Regular.ttf";
        const string kOutDir     = "Assets/Game/Resources/Fonts";

        // 烘焙参数
        const int    kPointSize   = 48;
        const int    kPadding     = 3;
        const int    kAtlasWidth  = 1024;
        const int    kAtlasHeight = 1024;

        [MenuItem("Tools/字体/2. 烘焙 TMP 静态字体（主集）")]
        public static void BakeFull()
        {
            Bake(kGenDir + "/charset.txt", "AlibabaPuHuiTiSDF");
        }

        [MenuItem("Tools/字体/3. 烘焙 TMP 静态字体（精简集）")]
        public static void BakeLite()
        {
            Bake(kGenDir + "/charset_project_only.txt", "AlibabaPuHuiTiSDF_Lite");
        }

        public static void Bake(string charsetAssetPath, string assetName)
        {
            // ---- 1. 取字符集 ----
            if (!File.Exists(charsetAssetPath))
            {
                Debug.LogError("[TMPFontBaker] 字符集文件不存在：" + charsetAssetPath
                    + "\n请先执行 Tools/字体/1. 扫描 UI 字符集");
                return;
            }
            var chars = File.ReadAllText(charsetAssetPath, Encoding.UTF8);
            chars = chars.Replace("\n", "").Replace("\r", "").Replace("\t", "");
            // 去重
            var set = new HashSet<char>(chars);
            var sb = new StringBuilder(set.Count);
            foreach (var c in set) sb.Append(c);
            chars = sb.ToString();

            // ---- 2. 取源字体 ----
            AssetDatabase.ImportAsset(kSourceTtf, ImportAssetOptions.ForceUpdate);
            var srcFont = AssetDatabase.LoadAssetAtPath<Font>(kSourceTtf);
            if (srcFont == null)
            {
                Debug.LogError("[TMPFontBaker] 源字体加载失败：" + kSourceTtf);
                return;
            }

            var outPath = kOutDir + "/" + assetName + ".asset";

            // ---- 3. 创建字体资产（Dynamic 起手，便于 TryAddCharacters）----
            var fontAsset = TMP_FontAsset.CreateFontAsset(
                srcFont, kPointSize, kPadding, GlyphRenderMode.SDFAA,
                kAtlasWidth, kAtlasHeight, AtlasPopulationMode.Dynamic, true);

            if (fontAsset == null)
            {
                Debug.LogError("[TMPFontBaker] CreateFontAsset 返回 null（源字体不可用？）");
                return;
            }
            fontAsset.name = assetName;

            // ---- 4. 反射调用 TryAddCharacters(string, out string, bool) ----
            string missing = "";
            try
            {
                var mi = typeof(TMP_FontAsset).GetMethod(
                    "TryAddCharacters",
                    new[] { typeof(string), typeof(string).MakeByRefType(), typeof(bool) });
                if (mi == null)
                {
                    Debug.LogError("[TMPFontBaker] 找不到 TryAddCharacters(string, out string, bool) 重载");
                    return;
                }
                var args = new object[] { chars, null, true };
                var ok = (bool)mi.Invoke(fontAsset, args);
                missing = args[1] as string ?? "";
                if (!ok && string.IsNullOrEmpty(missing))
                {
                    Debug.LogWarning("[TMPFontBaker] TryAddCharacters 返回 false 且无缺失清单（可能为图集不足）。");
                }
            }
            catch (Exception e)
            {
                Debug.LogError("[TMPFontBaker] TryAddCharacters 反射调用异常：" + e);
                return;
            }

            // ---- 5. 落盘父对象 ----
            // 保留原 meta（= 保留 guid）：CJKFont.lua 走 Resources.Load 按路径取，不受 guid 影响，
            // 但 TMP Settings 的 m_defaultFontAsset / m_fallbackFontAssets 是按 guid 引用的 ——
            // 直接 DeleteAsset + CreateAsset 会让 guid 漂移，烘焙一次就把全局默认字体与 fallback 打断一次。
            var metaPath = outPath + ".meta";
            var oldMeta = File.Exists(metaPath) ? File.ReadAllText(metaPath) : null;

            if (AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(outPath) != null)
            {
                AssetDatabase.DeleteAsset(outPath);
            }
            Directory.CreateDirectory(kOutDir);
            AssetDatabase.CreateAsset(fontAsset, outPath);

            // ---- 6. 逐个挂载子资产（图集 Texture2D / 材质）----
            // CreateAsset 只写父对象本身，不会把图集与材质纳入本资产。
            // 漏挂的症状：资产读回时 m_AtlasTextures 全是 {fileID: 0}，
            // 而 HasCharacter 依旧返回 true —— 只有真正渲染时才抛
            // "m_AtlasTextures ... has not been assigned"，极易被误判为成功。
            // 注意：同一对象不可重复 AddObjectToAsset（会报 duplicate 并炸资产）。
            int attached = 0;
            if (fontAsset.atlasTextures != null)
            {
                for (int i = 0; i < fontAsset.atlasTextures.Length; i++)
                {
                    var t = fontAsset.atlasTextures[i];
                    if (t == null) continue;
                    if (!AssetDatabase.Contains(t))
                    {
                        AssetDatabase.AddObjectToAsset(t, fontAsset);
                        attached++;
                    }
                }
            }
            if (fontAsset.material != null && !AssetDatabase.Contains(fontAsset.material))
            {
                AssetDatabase.AddObjectToAsset(fontAsset.material, fontAsset);
                attached++;
            }
            AssetDatabase.SaveAssets();

            // ---- 7. 切 Static 并保存 ----
            fontAsset.atlasPopulationMode = AtlasPopulationMode.Static;
            EditorUtility.SetDirty(fontAsset);
            AssetDatabase.SaveAssets();

            // 还原 guid（必须在 SaveAssets 之后、Refresh 之前）
            if (!string.IsNullOrEmpty(oldMeta) && File.Exists(metaPath))
            {
                File.WriteAllText(metaPath, oldMeta);
            }
            AssetDatabase.ImportAsset(outPath, ImportAssetOptions.ForceUpdate);
            AssetDatabase.Refresh();

            // ---- 8. 报告 ----
            var texInfo = new StringBuilder();
            long rawBytes = 0;
            if (fontAsset.atlasTextures != null)
            {
                for (int i = 0; i < fontAsset.atlasTextures.Length; i++)
                {
                    var t = fontAsset.atlasTextures[i];
                    if (t == null) { texInfo.AppendFormat("\n  [{0}] <null>", i); continue; }
                    long raw = (long)t.width * t.height;   // Alpha8 => 1 byte/px
                    rawBytes += raw;
                    texInfo.AppendFormat("\n  [{0}] {1}x{2} fmt={3} readable={4} ~{5:F2}MB",
                        i, t.width, t.height, t.format, t.isReadable, raw / 1048576f);
                }
            }

            int glyphCount = (fontAsset.characterTable != null) ? fontAsset.characterTable.Count : 0;
            var finfo = new FileInfo(outPath);
            double fileMB = finfo.Exists ? finfo.Length / 1048576.0 : -1;

            Debug.Log(string.Format(
                "[TMPFontBaker] 烘焙完成 -> {0}\n" +
                "  字符集输入 : {1} 个\n" +
                "  实际入表   : {2} 个字形\n" +
                "  图集页数   : {3} 页，raw 合计 ~{4:F2}MB\n" +
                "  落盘大小   : {5:F2}MB（.asset 编辑器态文本，构建后剔除文本膨胀）\n" +
                "  挂载子资产 : {6} 个（图集 Texture2D + 材质）\n" +
                "  PopulationMode : {7}    SourceFontFile : {8}\n" +
                "  缺字(源字库也没有): {9}\n" +
                "{10}",
                outPath, set.Count, glyphCount,
                (fontAsset.atlasTextures != null ? fontAsset.atlasTextures.Length : 0),
                rawBytes / 1048576f, fileMB, attached,
                fontAsset.atlasPopulationMode,
                (fontAsset.sourceFontFile != null ? fontAsset.sourceFontFile.name : "<null: Static 已清空>"),
                string.IsNullOrEmpty(missing) ? "无" : missing,
                texInfo.ToString()));
        }

        // ---------------------------------------------------------------------
        // 运行时缺字汇总（Play 模式下由 MissingGlyphWatcher 捕获）
        // ---------------------------------------------------------------------
        [MenuItem("Tools/字体/5. 汇总运行时缺字记录")]
        public static void DumpMissingGlyphs()
        {
            Debug.Log(MissingGlyphWatcher.Dump());
        }

        // ---------------------------------------------------------------------
        // 校验：读回已落盘资产的真实渲染可用性（比 HasCharacter 更接近「画得出来」）
        // ---------------------------------------------------------------------
        [MenuItem("Tools/字体/4. 校验已落盘字体资产")]
        public static void Verify()
        {
            var path = kOutDir + "/AlibabaPuHuiTiSDF.asset";
            var fa = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(path);
            if (fa == null) { Debug.LogError("[TMPFontBaker] 资产不存在：" + path); return; }

            var charsetPath = kGenDir + "/charset.txt";
            var chars = File.ReadAllText(charsetPath, Encoding.UTF8);

            int total = 0, hasChar = 0;
            var lacking = new StringBuilder();
            foreach (var c in chars)
            {
                if (c == '\n' || c == '\r' || c == '\t') continue;
                total++;
                if (fa.HasCharacter(c, false, true)) hasChar++;
                else if (lacking.Length < 200) lacking.Append(c);
            }

            var mu = fa.material;
            var tex = (fa.atlasTextures != null && fa.atlasTextures.Length > 0) ? fa.atlasTextures[0] : null;

            Debug.Log(string.Format(
                "[TMPFontBaker/Verify] {0}\n" +
                "  HasCharacter : {1}/{2}\n" +
                "  缺字 : {3}\n" +
                "  atlasTextures : {4} 页，first={5}\n" +
                "  material : {6}（shader={7}）\n" +
                "  atlasPopulationMode : {8}",
                path, hasChar, total, lacking.Length == 0 ? "无" : lacking.ToString(),
                fa.atlasTextures != null ? fa.atlasTextures.Length : 0,
                tex != null ? string.Format("{0}x{1}/{2}", tex.width, tex.height, tex.format) : "<null>",
                mu != null ? mu.name : "<null>",
                mu != null && mu.shader != null ? mu.shader.name : "<?>",
                fa.atlasPopulationMode));
        }
    }
}
#endif
