// Generated client decryption material and PUBLIC verification key only.
// Committed in the UNINITIALIZED state on purpose: the real values are a local, uncommitted change.
// Fill them with Tools/Security/Initialize Lua protection keys (reads the signing secret kept outside the workspace,
// see LuaProtectionBuild.SecretPath), then recompile. Never commit the filled-in file.
namespace Game.Security
{
    public static class LuaProtectionKeys
    {
        public const string EncryptionKeyBase64 = "";
        public const string PublicModulusBase64 = "";
        public const string PublicExponentBase64 = "AQAB";
    }
}
