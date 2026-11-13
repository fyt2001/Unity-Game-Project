using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using Game.Security;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;
using XLua;

namespace MyProject.Editor
{
    public static class LuaProtectionChecks
    {
        private static int assertions;
        private static void Check(bool condition, string label)
        {
            if (!condition) throw new Exception("Lua protection check failed: " + label);
            assertions++;
        }

        private static void Reject(Action action, string label)
        {
            bool rejected = false;
            try { action(); } catch (CryptographicException) { rejected = true; }
            Check(rejected, label);
        }

        [MenuItem("Tools/Security/Verify Lua protection")]
        public static void Run()
        {
            assertions = 0;
            using (var signer = LuaProtectionBuild.OpenSigner())
            {
                byte[] key = LuaScriptProtection.EncryptionKey();
                foreach (var pair in LuaProtectionBuild.Sources())
                {
                    byte[] plain = File.ReadAllBytes(pair.Value);
                    byte[] payload = ProtectedLuaPayload.EncryptAndSign(plain, pair.Key, key, signer);
                    Check(LuaScriptProtection.Read(payload, pair.Key).SequenceEqual(plain), pair.Key);
                    Reject(() => LuaScriptProtection.Read(plain, pair.Key), "plaintext rejected");
                    payload[60] ^= 1;
                    Reject(() => LuaScriptProtection.Read(payload, pair.Key), "tamper rejected");
                }
            }
            LuaProtectionBuild.RejectPlaintextCopies();
            Check(!File.ReadAllText("Assets/Game/Scripts/Security/LuaProtectionKeys.cs").Contains("<D>"), "no RSA private key in client source");
            Debug.Log("[LuaProtectionChecks] PASS " + assertions + " real-source encryption assertions.");
        }

        // Batch methods are synchronous so -quit cannot race delayed editor callbacks.
        [MenuItem("Tools/Security/Build protected Windows Development")]
        public static void BuildWindows()
        {
            BuildPlayer(BuildTarget.StandaloneWindows64);
        }
        public static void BuildWebGL()
        {
            BuildPlayer(BuildTarget.WebGL);
        }
        [MenuItem("Tools/Security/Build protected Windows Release")]
        public static void BuildReleaseWindows()
        {
            BuildPlayer(BuildTarget.StandaloneWindows64, BuildOptions.None);
        }
        public static void BuildReleaseWebGL()
        {
            BuildPlayer(BuildTarget.WebGL, BuildOptions.None);
        }
        private static void BuildPlayer(BuildTarget target, BuildOptions options = BuildOptions.Development)
        {
            Run();
            string directory = Path.GetFullPath(Path.Combine("Builds", "LuaProtection", target.ToString(), DateTime.UtcNow.ToString("yyyyMMdd_HHmmss")
                + (options == BuildOptions.None ? "_release" : "")));
            Directory.CreateDirectory(directory);
            string output = target == BuildTarget.WebGL ? Path.Combine(directory, "Player") : Path.Combine(directory, "Player", "Game.exe");
            BuildTools.BuildPreparedPlayer(target, output, options);
            File.WriteAllText(Path.Combine(directory, "output.txt"), output);
            Debug.Log("[LuaProtectionChecks] Player built: " + output);
        }

        public static void CheckBundle()
        {
            Run();
            string archive = BuildAssetBundles.BuildForTarget(EditorUserBuildSettings.activeBuildTarget);
            int count = LuaProtectionBuild.ValidateBundle(Path.Combine(archive, "lua/scripts.asset"));
            var managerObject = new GameObject("LuaProtectionChecks_Manager");
            var manager = managerObject.AddComponent<XLuaManager>();
            try
            {
                string module = "Game.Battle.EnemyConfig";
                manager.LoadMode = LuaLoadMode.Editor;
                string input = module;
                Check(manager.CustomLoader(ref input).SequenceEqual(File.ReadAllBytes("Assets/Game/LuaScripts/Game/Battle/EnemyConfig.lua")), "editor plaintext unchanged");
                using (var staging = BuildAssetBundles.StageForPlayer(archive))
                {
                    manager.LoadMode = LuaLoadMode.Device;
                    Check(LuaBundleLoader.LoadSync(), "authenticated AB loaded");
                    foreach (var pair in LuaProtectionBuild.Sources())
                        Check(LuaBundleLoader.TryGetScript(pair.Key).SequenceEqual(File.ReadAllBytes(pair.Value)), "runtime AB " + pair.Key);
                    using (var env = new LuaEnv())
                    {
                        env.AddLoader(manager.CustomLoader);
                        LuaScriptProtection.ConfigureDeviceEnvironment(env);
                        var result = env.DoString("local c = require 'Game.Battle.EnemyConfig'; assert(type(c)=='table'); require 'xlua.util'; return true");
                        Check(result.Length == 1 && (bool)result[0], "XLua executes protected gameplay config and vendor module");
                        result = env.DoString("local ok=pcall(require,'security_test_missing'); return not ok");
                        Check((bool)result[0], "missing module aborts require");
                        Check(Resources.Load<TextAsset>("cs_coroutine.lua") != null, "plaintext vendor fallback fixture exists");
                        result = env.DoString("return not pcall(require,'cs_coroutine'), #(package.searchers or package.loaders)==3");
                        Check((bool)result[0] && (bool)result[1], "existing Resources fallback is blocked and searchers restricted");
                    }
                    LuaBundleLoader.Unload();
                }
            }
            finally
            {
                LuaBundleLoader.Unload();
                UnityEngine.Object.DestroyImmediate(managerObject);
            }
            File.WriteAllText("P0_rollback/lua_protection_20261009_114141/editor-result.txt", "PASS " + assertions + " assertions; " + count + " bundle modules; archive=" + archive);
            Debug.Log("[LuaProtectionChecks] PASS " + assertions + " integration assertions; " + count + " authenticated AB modules.");
        }
    }
}
