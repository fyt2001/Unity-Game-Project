// S7-2: run every Lua regression listed in tools/lua_tests.json inside XLua's LuaEnv (Lua 5.3, the
// authoritative VM). verify.ps1 -Fast runs the same "fast" entries with system lua 5.5 as a quick signal.
using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using XLua;

namespace Game.AgentTests
{
    public class LuaSuiteTests
    {
        [Serializable] private class Entry { public string path; public string mode; public string reason; }
        [Serializable] private class Manifest { public Entry[] tests; }

        private const string ExitMarker = "__AGENT_OS_EXIT__";

        public static IEnumerable<TestCaseData> Cases()
        {
            string manifestPath = AgentTestSupport.ProjectRoot + "/tools/lua_tests.json";
            var manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(manifestPath));
            foreach (var e in manifest.tests)
            {
                if (e.mode == "runtime") continue;
                yield return new TestCaseData(e.path, e.mode, e.reason)
                    .SetName("Lua_" + Path.GetFileNameWithoutExtension(e.path));
            }
        }

        [TestCaseSource(nameof(Cases))]
        public void RunsCleanInXLua(string relPath, string mode, string reason)
        {
            if (mode == "quarantine") Assert.Ignore("quarantined: " + reason);
            string full = Path.GetFullPath(Path.Combine(AgentTestSupport.ProjectRoot, relPath));
            Assert.That(File.Exists(full), "missing Lua test " + full);

            using (var env = AgentTestSupport.CreateLuaEnv(AgentTestSupport.LuaRoot))
            {
                env.Global.Set("SOURCE_LOADER", new Func<string, string>(File.ReadAllText));
                try
                {
                    env.DoString(File.ReadAllBytes(full), "@" + full.Replace('\\', '/'));
                }
                catch (LuaException e)
                {
                    string msg = e.Message ?? "";
                    int at = msg.IndexOf(ExitMarker, StringComparison.Ordinal);
                    if (at < 0) Assert.Fail(relPath + " failed in XLua (Lua 5.3): " + msg);
                    string code = msg.Substring(at + ExitMarker.Length).Trim();
                    if (code != "0" && code != "true" && code != "nil")
                        Assert.Fail(relPath + " called os.exit(" + code + ") in XLua (Lua 5.3); see Console for its PASS/FAIL lines.");
                }
                finally
                {
                    env.Global.Set<string, object>("SOURCE_LOADER", null);
                    env.FullGc();
                }
            }
        }
    }
}
