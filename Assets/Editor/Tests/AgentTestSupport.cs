// Shared helpers for EditMode tests (Assembly-CSharp-Editor; no asmdef on purpose, see S12).
using System;
using System.IO;
using UnityEngine;
using XLua;

namespace Game.AgentTests
{
    internal static class AgentTestSupport
    {
        /// <summary>Unity project root with forward slashes ("C:/.../My project").</summary>
        public static string ProjectRoot
        {
            get { return Path.GetFullPath(Path.Combine(Application.dataPath, "..")).Replace('\\', '/'); }
        }

        /// <summary>Lua source root. AGENT_LUA_ROOT overrides it (self-tests point it at a mutated TEMP copy).</summary>
        public static string LuaRoot
        {
            get
            {
                string over = Environment.GetEnvironmentVariable("AGENT_LUA_ROOT");
                if (!string.IsNullOrEmpty(over)) return Path.GetFullPath(over).Replace('\\', '/').TrimEnd('/');
                return ProjectRoot + "/Assets/Game/LuaScripts";
            }
        }

        /// <summary>
        /// Fresh XLua LuaEnv (Lua 5.3, same VM as the game) whose require resolves from LuaRoot first,
        /// with ROOT = project root and os.exit turned into a Lua error so a test can never kill the Editor.
        /// </summary>
        public static LuaEnv CreateLuaEnv(string luaRoot)
        {
            var env = new LuaEnv();
            string root = luaRoot;
            env.AddLoader((ref string module) =>
            {
                string path = root + "/" + module.Replace('.', '/') + ".lua";
                if (!File.Exists(path)) return null;
                module = path;
                return File.ReadAllBytes(path);
            });
            env.Global.Set("ROOT", ProjectRoot);
            env.DoString(
                "package.path = ROOT .. '/Assets/Game/LuaScripts/?.lua;' .. package.path\n" +
                "os.exit = function(code) error('__AGENT_OS_EXIT__' .. tostring(code), 0) end\n",
                "AgentTestSupport.prelude");
            return env;
        }
    }
}
