// =============================================================================
// TMPRenderProbe.cs  (Editor only)
// =============================================================================
// 运行时 TMP 渲染探针 —— 把「场景里到底画没画出来」变成一次调用。
//
// 为什么不用 TMP_FontAsset.HasCharacter 判定：
//   HasCharacter 只说明字符表里有这个码位，不代表运行时图集真的可用。
//   此前踩过：图集未落盘的资产 HasCharacter 全 true，渲染却抛
//   "m_AtlasTextures ... has not been assigned"。所以这里一律看
//   TMP_TextInfo.characterInfo[i].isVisible —— 最接近「真的画出来了」。
//
// 用法：
//   * Play 模式下：Tools/字体/6. 探测当前场景 TMP 缺字
//   * 代码/注入：Game.EditorTools.TMPRenderProbe.Scan()
// =============================================================================

#if UNITY_EDITOR
using System.Text;
using TMPro;
using UnityEditor;
using UnityEngine;

namespace Game.EditorTools
{
    public static class TMPRenderProbe
    {
        // 只统计 CJK 及以上的字符区，ASCII/空格/换行天然 isVisible=false 会把结果污染
        const char kCjkStart = (char)0x2E80;

        [MenuItem("Tools/字体/6. 探测当前场景 TMP 缺字")]
        public static void ScanMenu()
        {
            Debug.Log(Scan());
        }

        /// <summary>扫描所有 active 且带文本的 TMP，返回统计与缺字明细。</summary>
        public static string Scan()
        {
            var all = Object.FindObjectsOfType<TMP_Text>();
            int withText = 0, cjkTotal = 0, cjkInvisible = 0, asciiInvisible = 0;
            var details = new StringBuilder();
            var samples = new StringBuilder();

            foreach (var t in all)
            {
                if (t == null) continue;
                var go = t.gameObject;
                if (!go.activeInHierarchy) continue;
                if (string.IsNullOrEmpty(t.text)) continue;

                withText++;
                if (samples.Length < 160 && t.text.Length <= 28)
                {
                    samples.Append("[").Append(t.text).Append("]");
                }

                t.ForceMeshUpdate();
                var ti = t.textInfo;
                if (ti == null) continue;

                int bad = 0;
                var bads = new StringBuilder();
                for (int i = 0; i < ti.characterCount; i++)
                {
                    var ci = ti.characterInfo[i];
                    if (ci.character == 0) continue;
                    if (ci.character < kCjkStart)
                    {
                        if (!ci.isVisible) asciiInvisible++;
                        continue;
                    }
                    cjkTotal++;
                    if (!ci.isVisible)
                    {
                        cjkInvisible++;
                        bad++;
                        bads.Append(ci.character);
                    }
                }
                if (bad > 0) details.Append(go.name).Append("[").Append(bads).Append("] ");
            }

            return string.Format(
                "[TMPRenderProbe] tmps={0} withText={1} cjkTotal={2} cjkInvisible={3} asciiInvisible={4}\n"
                + "  缺字节点：{5}\n"
                + "  文本样本：{6}",
                all.Length, withText, cjkTotal, cjkInvisible, asciiInvisible,
                details.Length == 0 ? "none" : details.ToString(),
                samples.ToString());
        }

        /// <summary>打开一个 UI 窗口（供逐面板验证脚本使用）。</summary>
        public static string OpenWindow(string windowName)
        {
            var r = XLuaManager.Instance.SafeDoString(
                "local ui = require('Game.GameMain').GetUIManager() ui:Open('" + windowName + "') return 'ok'");
            return (r != null && r.Length > 0) ? r[0].ToString() : "no-result";
        }

        /// <summary>关闭全部 UI 窗口（逐面板验证前清场）。</summary>
        public static string CloseAll()
        {
            var r = XLuaManager.Instance.SafeDoString(
                "local ui = require('Game.GameMain').GetUIManager() if ui.CloseAll then ui:CloseAll() end return 'ok'");
            return (r != null && r.Length > 0) ? r[0].ToString() : "no-result";
        }
    }
}
#endif
