#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Collections;
using System.Linq;
using System.Security.Cryptography;
using UnityEngine;
using XLua;

namespace Game.Security
{
    public sealed class LuaProtectionPlayerProbe : MonoBehaviour
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void StartIfRequested()
        {
            if (!Environment.GetCommandLineArgs().Contains("--verify-lua-protection")
                && !Application.absoluteURL.Contains("verifyLuaProtection=1")) return;
            var instance = new GameObject("LuaProtectionPlayerProbe");
            DontDestroyOnLoad(instance);
            instance.AddComponent<LuaProtectionPlayerProbe>();
        }

        private IEnumerator Start()
        {
            yield return LuaBundleLoader.LoadAsync();
            bool succeeded = false;
            try
            {
                if (!LuaBundleLoader.IsReady) throw new Exception("Bundle unavailable.");
                const string path = "game/battle/enemyconfig.lua";
                byte[] plain = LuaBundleLoader.TryGetScript(path);
                var text = Resources.FindObjectsOfTypeAll<TextAsset>().First(x => x.name.ToLowerInvariant() == "enemyconfig.lua");
                byte[] payload = text.bytes;
                if (!LuaScriptProtection.Read(payload, path).SequenceEqual(plain)) throw new Exception("Roundtrip mismatch.");
                Reject(plain, path);
                var tampered = (byte[])payload.Clone();
                tampered[60] ^= 1;
                Reject(tampered, path);
                Reject(payload, "game/battle/other.lua");
                var manager = XLuaManager.Instance;
                manager.LoadMode = LuaLoadMode.Editor;
                if (manager.LoadMode != LuaLoadMode.Device) throw new Exception("Player mode override bypass.");
                using (var env = new LuaEnv())
                {
                    env.AddLoader(manager.CustomLoader);
                    LuaScriptProtection.ConfigureDeviceEnvironment(env);
                    env.DoString("local c=require 'Game.Battle.EnemyConfig'; assert(type(c)=='table'); require 'xlua.util'; assert(not pcall(require,'security_test_missing')); assert(not pcall(require,'cs_coroutine')); assert(#(package.searchers or package.loaders)==3)");
                }
                Debug.Log("[LuaProtectionPlayerProbe] PASS: protected config executed; plaintext/tamper/wrong-path/missing-module/mode-bypass rejected.");
                succeeded = true;
            }
            catch (Exception e) { Debug.LogError("[LuaProtectionPlayerProbe] FAIL: " + e); }
            if (Environment.GetCommandLineArgs().Contains("--quit-after-probe")) Application.Quit(succeeded ? 0 : 1);
            Destroy(gameObject);
        }

        private static void Reject(byte[] bytes, string path)
        {
            try { LuaScriptProtection.Read(bytes, path); }
            catch (CryptographicException) { return; }
            throw new Exception("Invalid Lua was accepted.");
        }
    }
}
#endif
