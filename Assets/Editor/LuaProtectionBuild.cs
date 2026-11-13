using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Game.Security;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace MyProject.Editor
{
    public static class LuaProtectionBuild
    {
        private const string KeySource = "Assets/Game/Scripts/Security/LuaProtectionKeys.cs";
        private const string SourceRoot = "Assets/Game/LuaScripts/";
        private const string LibraryRoot = "Assets/XLua/Resources/";
        private const string StageRoot = "assets/game/luabundlesrc/";

        [Serializable]
        private sealed class BuildSecret
        {
            public string aes;
            public string rsaPrivateXml;
        }

        public static string SecretPath
        {
            get
            {
                string configured = Environment.GetEnvironmentVariable("UNITY_LUA_SIGNING_KEY_PATH");
                string path = string.IsNullOrEmpty(configured)
                    ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                        ".codex", "build-secrets", "my-project-lua-v1", "signing-key.json") : configured;
                if (!Path.IsPathRooted(path)) throw new BuildFailedException("Signing key path must be absolute.");
                path = Path.GetFullPath(path);
                string workspace = Path.GetFullPath("..").TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (path.StartsWith(workspace, StringComparison.OrdinalIgnoreCase))
                    throw new BuildFailedException("Signing secrets must be outside the Unity workspace.");
                return path;
            }
        }

        [MenuItem("Tools/Security/Initialize Lua protection keys")]
        public static void Initialize()
        {
            string path = SecretPath;
            if (!string.IsNullOrEmpty(LuaProtectionKeys.PublicModulusBase64))
            {
                using (OpenSigner()) { }
                Debug.Log("[LuaProtection] Existing keys verified; no rotation performed.");
                return;
            }
            BuildSecret secret;
            if (File.Exists(path)) secret = JsonUtility.FromJson<BuildSecret>(File.ReadAllText(path));
            else
            {
                byte[] aes = new byte[32];
                using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(aes);
                using (var rsa = new RSACryptoServiceProvider(2048))
                {
                    rsa.PersistKeyInCsp = false;
                    secret = new BuildSecret { aes = Convert.ToBase64String(aes), rsaPrivateXml = rsa.ToXmlString(true) };
                }
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (var writer = new StreamWriter(stream)) writer.Write(JsonUtility.ToJson(secret));
            }
            using (var rsa = RSA.Create())
            {
                rsa.FromXmlString(secret.rsaPrivateXml);
                if (rsa.KeySize != 2048 || Convert.FromBase64String(secret.aes).Length != 32)
                    throw new BuildFailedException("Invalid external signing material.");
                var pub = rsa.ExportParameters(false);
                string source = "// Generated client decryption material and PUBLIC verification key only.\n" +
                    "namespace Game.Security\n{\n    public static class LuaProtectionKeys\n    {\n" +
                    "        public const string EncryptionKeyBase64 = \"" + secret.aes + "\";\n" +
                    "        public const string PublicModulusBase64 = \"" + Convert.ToBase64String(pub.Modulus) + "\";\n" +
                    "        public const string PublicExponentBase64 = \"" + Convert.ToBase64String(pub.Exponent) + "\";\n    }\n}\n";
                File.WriteAllText(KeySource, source, new UTF8Encoding(false));
            }
            AssetDatabase.Refresh();
            Debug.Log("[LuaProtection] Keys initialized. Signing private key is outside the workspace; wait for recompilation before building.");
        }

        public static RSA OpenSigner()
        {
            if (!File.Exists(SecretPath)) throw new BuildFailedException("Restore the external Lua signing key; never silently rotate it.");
            var secret = JsonUtility.FromJson<BuildSecret>(File.ReadAllText(SecretPath));
            var rsa = RSA.Create();
            try
            {
                rsa.FromXmlString(secret.rsaPrivateXml);
                var pub = rsa.ExportParameters(false);
                if (rsa.KeySize != 2048 || Convert.ToBase64String(pub.Modulus) != LuaProtectionKeys.PublicModulusBase64
                    || Convert.ToBase64String(pub.Exponent) != LuaProtectionKeys.PublicExponentBase64
                    || secret.aes != LuaProtectionKeys.EncryptionKeyBase64)
                    throw new BuildFailedException("Lua signing material does not match the compiled client keys. Initialize and recompile first.");
                LuaScriptProtection.EncryptionKey();
                return rsa;
            }
            catch { rsa.Dispose(); throw; }
        }

        public static SortedDictionary<string, string> Sources()
        {
            var sources = new SortedDictionary<string, string>(StringComparer.Ordinal);
            foreach (var file in Directory.GetFiles(SourceRoot, "*.lua", SearchOption.AllDirectories))
                sources.Add(ProtectedLuaPayload.CanonicalPath(file.Substring(SourceRoot.Length)), file);
            // Vendor modules needed by require must also take the authenticated path.
            foreach (var file in Directory.GetFiles(LibraryRoot, "*.lua.txt", SearchOption.AllDirectories))
                sources.Add(ProtectedLuaPayload.CanonicalPath(file.Substring(LibraryRoot.Length, file.Length - LibraryRoot.Length - 4)), file);
            if (sources.Count == 0) throw new BuildFailedException("No Lua sources found.");
            return sources;
        }

        public static int ValidateBundle(string path)
        {
            var bundle = AssetBundle.LoadFromFile(path);
            if (bundle == null) throw new BuildFailedException("Lua bundle cannot be loaded for protection verification.");
            try
            {
                var names = bundle.GetAllAssetNames();
                var sources = Sources();
                if (names.Length != sources.Count) throw new BuildFailedException("Lua bundle source count mismatch; rebuild it.");
                foreach (var pair in sources)
                {
                    string name = StageRoot + pair.Key + ".txt";
                    if (!names.Contains(name)) throw new BuildFailedException("Lua bundle module missing: " + pair.Key);
                    var asset = bundle.LoadAsset<TextAsset>(name);
                    var plain = LuaScriptProtection.Read(asset.bytes, pair.Key);
                    if (!plain.SequenceEqual(File.ReadAllBytes(pair.Value)))
                        throw new BuildFailedException("Lua bundle is stale: " + pair.Key);
                }
                return names.Length;
            }
            finally { bundle.Unload(true); }
        }

        public static void RejectPlaintextCopies()
        {
            var applicationHashes = new HashSet<string>(StringComparer.Ordinal);
            using (var sha = SHA256.Create())
            {
                foreach (var file in Directory.GetFiles(SourceRoot, "*.lua", SearchOption.AllDirectories))
                    applicationHashes.Add(Convert.ToBase64String(sha.ComputeHash(File.ReadAllBytes(file))));
                foreach (var file in Directory.GetFiles("Assets", "*", SearchOption.AllDirectories))
                {
                    string normalized = file.Replace('\\', '/');
                    if (!normalized.Contains("/Resources/") && !normalized.StartsWith("Assets/StreamingAssets/", StringComparison.Ordinal)) continue;
                    if (file.EndsWith(".meta", StringComparison.OrdinalIgnoreCase)) continue;
                    // Upstream XLua examples are public vendor source, not private game code.
                    if ((!normalized.StartsWith("Assets/XLua/", StringComparison.Ordinal)
                            && (normalized.EndsWith(".lua", StringComparison.OrdinalIgnoreCase) || normalized.EndsWith(".lua.txt", StringComparison.OrdinalIgnoreCase)))
                        || (new FileInfo(file).Length <= ProtectedLuaPayload.MaxPlaintextBytes
                            && applicationHashes.Contains(Convert.ToBase64String(sha.ComputeHash(File.ReadAllBytes(file))))))
                        throw new BuildFailedException("Plaintext Lua in player resources; preserve/move it before publishing: " + normalized);
                }
            }
        }
    }

    public sealed class LuaProtectionPreflight : IPreprocessBuildWithReport
    {
        public int callbackOrder { get { return -1000; } }
        public void OnPreprocessBuild(BuildReport report)
        {
            using (LuaProtectionBuild.OpenSigner()) { }
            LuaProtectionBuild.RejectPlaintextCopies();
            string path = Path.Combine(Application.streamingAssetsPath, "AssetBundles", MyAssetBundles.Utility.GetPlatformName(), "lua/scripts.asset");
            int count = LuaProtectionBuild.ValidateBundle(path);
            Debug.Log("[LuaProtection] Publish preflight verified " + count + " authenticated modules.");
        }
    }
}
