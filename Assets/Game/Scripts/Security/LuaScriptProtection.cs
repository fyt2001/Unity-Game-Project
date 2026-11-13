using System;
using System.Security.Cryptography;

namespace Game.Security
{
    public static class LuaScriptProtection
    {
        public static void ConfigureDeviceEnvironment(XLua.LuaEnv environment)
        {
            // XLua registers preload, builtin, custom, then plaintext/native searchers.
            environment.DoString("local s=package.searchers or package.loaders; for i=#s,4,-1 do s[i]=nil end; package.path=''; package.cpath=''", "ProtectedSearchers");
        }

        public static byte[] Read(byte[] payload, string scriptPath)
        {
            using (var verifier = CreateVerifier())
                return ProtectedLuaPayload.VerifyAndDecrypt(payload, scriptPath, EncryptionKey(), verifier);
        }

        public static byte[] EncryptionKey()
        {
            byte[] key = Convert.FromBase64String(LuaProtectionKeys.EncryptionKeyBase64);
            if (key.Length != 32) throw new CryptographicException("Lua protection is not initialized.");
            return key;
        }

        public static RSA CreateVerifier()
        {
            var rsa = RSA.Create();
            try
            {
                rsa.ImportParameters(new RSAParameters
                {
                    Modulus = Convert.FromBase64String(LuaProtectionKeys.PublicModulusBase64),
                    Exponent = Convert.FromBase64String(LuaProtectionKeys.PublicExponentBase64)
                });
                if (rsa.KeySize != 2048) throw new CryptographicException("Invalid Lua public key.");
                return rsa;
            }
            catch { rsa.Dispose(); throw; }
        }
    }
}
