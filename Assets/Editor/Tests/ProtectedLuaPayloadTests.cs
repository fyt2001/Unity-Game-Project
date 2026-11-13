// Standalone: compile these two sources with Unity's bundled mcs/csc and run with mono.
// Define UNITY_EDITOR for the complete suite; omit it to check the Player API and verifier.
using System;
using System.Security.Cryptography;
using System.Text;
using Game.Security;

public static class ProtectedLuaPayloadTests
{
    private const string Path = "Framework/UI/UIManager.lua";
    private const int HeaderBytes = 60;
    private const int SignatureBytes = 256;
    private const string FailureMessage = "Invalid protected Lua payload.";
    private static int assertions;

    public static int Main()
    {
        try
        {
            TestPaths();
            using (RSA signer = NewRsa(2048))
            using (RSA verifier = PublicOnly(signer))
            using (RSA otherSigner = NewRsa(2048))
            using (RSA otherVerifier = PublicOnly(otherSigner))
            {
                byte[] key = Key(1);
                Assert(verifier.ExportParameters(false).D == null, "Public-only verifier");
                Reject(delegate { verifier.ExportParameters(true); }, "Public key has no private material");
                TestRuntime(signer, verifier, otherSigner, otherVerifier, key);
#if UNITY_EDITOR
                TestEditor(signer, verifier, key);
                Assert(typeof(ProtectedLuaPayload).GetMethod("EncryptAndSign") != null, "Editor signing API");
#else
                Assert(typeof(ProtectedLuaPayload).GetMethod("EncryptAndSign") == null, "Player excludes signing API");
#endif
            }
            Console.WriteLine("PASS: " + assertions + " assertions (" +
#if UNITY_EDITOR
                "UNITY_EDITOR"
#else
                "Player API, no UNITY_EDITOR"
#endif
                + ").");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("FAIL: " + exception);
            return 1;
        }
    }

    private static void TestPaths()
    {
        Equal("framework/ui/uimanager.lua", ProtectedLuaPayload.CanonicalPath(Path), "Canonical suffix retained");
        Equal("framework/ui/uimanager.lua", ProtectedLuaPayload.CanonicalPath("FRAMEWORK\\UI\\UIManager.LUA"), "Slashes and case");
        Equal("framework.ui/uimanager.lua", ProtectedLuaPayload.CanonicalPath("Framework.UI/UIManager.lua"), "Dots remain dots");
        Equal("folder/name.lua.lua", ProtectedLuaPayload.CanonicalPath("Folder/Name.Lua.LUA"), "Only terminal suffix is required");
        Equal("\u6846\u67b6/\u754c\u9762.lua", ProtectedLuaPayload.CanonicalPath("\u6846\u67b6\\\u754c\u9762.LUA"), "Unicode path");
        string[] invalid = {
            null, "", "/a.lua", "\\a.lua", "//server/a.lua", "\\\\server\\a.lua",
            "C:/a.lua", "c:a.lua", "a:b.lua", "../a.lua", "a/../b.lua", "./a.lua",
            "a/./b.lua", "a//b.lua", "a\\\\b.lua", "a.lua/", "a/", "a", "a.lu",
            "a.lua.txt", ".lua", "a/.lua", "a\0.lua", "a\n.lua", "a\t.lua",
            "a\u007f.lua", "a\u0085.lua", "a\ud800.lua", "a\udc00.lua"
        };
        foreach (string path in invalid)
            Reject(delegate { ProtectedLuaPayload.CanonicalPath(path); }, "Invalid canonical path", true);
        string oldCulture = System.Threading.Thread.CurrentThread.CurrentCulture.Name;
        try
        {
            System.Threading.Thread.CurrentThread.CurrentCulture = new System.Globalization.CultureInfo("tr-TR");
            Equal("ui/item.lua", ProtectedLuaPayload.CanonicalPath("UI/ITEM.LUA"), "Invariant lowercase");
        }
        finally
        {
            System.Threading.Thread.CurrentThread.CurrentCulture = new System.Globalization.CultureInfo(oldCulture);
        }
    }

    private static void TestRuntime(RSA signer, RSA verifier, RSA otherSigner, RSA otherVerifier, byte[] key)
    {
        byte[] plain = Encoding.UTF8.GetBytes("return '\u4f60\u597d, \u03bb, \ud83d\ude80'\n");
        byte[] payload = SignedEnvelope(plain, Path, key, signer);
        Bytes(plain, ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, key, verifier), "Independent envelope roundtrip");
        Bytes(plain, ProtectedLuaPayload.VerifyAndDecrypt(payload, "FRAMEWORK\\UI\\UIManager.LUA", key, verifier), "Equivalent file context");
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, "Framework/UI/Other.lua", key, verifier); }, "Context swap", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, "Framework.UI.UIManager.lua", key, verifier); }, "Dots do not alias slashes", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, Key(2), verifier); }, "Wrong AES key", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, key, otherVerifier); }, "Wrong RSA public key", true);
        byte[] forged = SignedEnvelope(plain, Path, key, otherSigner);
        Bytes(plain, ProtectedLuaPayload.VerifyAndDecrypt(forged, Path, key, otherVerifier), "Other signer has valid same-AES envelope");
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(forged, Path, key, verifier); }, "Same AES key cannot forge trusted RSA signature", true);

        // Every byte of the header and first ciphertext block, plus signature boundaries.
        for (int offset = 0; offset < HeaderBytes + 16; offset++)
        {
            byte[] tampered = (byte[])payload.Clone();
            tampered[offset] ^= 1;
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(tampered, Path, key, verifier); }, "Header/ciphertext tamper at " + offset, true);
        }
        int[] extraOffsets = { payload.Length - SignatureBytes - 1, payload.Length - SignatureBytes,
            payload.Length - SignatureBytes + 127, payload.Length - 1 };
        foreach (int offset in extraOffsets)
        {
            byte[] tampered = (byte[])payload.Clone();
            tampered[offset] ^= 0x80;
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(tampered, Path, key, verifier); }, "Ciphertext/signature boundary tamper", true);
        }

        // Exhaust every truncation of this small envelope, including zero bytes.
        for (int length = 0; length < payload.Length; length++)
        {
            byte[] truncated = Slice(payload, length);
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(truncated, Path, key, verifier); }, "Truncated frame", true);
        }
        foreach (int added in new[] { 1, 16, 256 })
        {
            byte[] appended = new byte[payload.Length + added];
            Buffer.BlockCopy(payload, 0, appended, 0, payload.Length);
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(appended, Path, key, verifier); }, "Trailing data", true);
        }
        foreach (uint length in new uint[] { 0, 1, 15, 17, 16, 1048577, 1048593, 0x7fffffff, 0x80000000, 0xfffffff0, 0xffffffff })
        {
            byte[] tampered = (byte[])payload.Clone();
            WriteLength(tampered, length);
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(tampered, Path, key, verifier); }, "Invalid or inconsistent big-endian length", true);
        }
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(plain, Path, key, verifier); }, "Plaintext denied", true);
        byte[] longPlaintext = new byte[512];
        Buffer.BlockCopy(Encoding.ASCII.GetBytes("return 'plain Lua'"), 0, longPlaintext, 0, 18);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(longPlaintext, Path, key, verifier); }, "Long plaintext denied", true);
        byte[] downgrade = (byte[])payload.Clone();
        Buffer.BlockCopy(Encoding.ASCII.GetBytes("ULP00000"), 0, downgrade, 0, 8);
        Resign(downgrade, signer);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(downgrade, Path, key, verifier); }, "Signed downgrade denied", true);

        byte[] maximum = Pattern(ProtectedLuaPayload.MaxPlaintextBytes);
        byte[] maximumPayload = SignedEnvelope(maximum, Path, key, signer);
        Bytes(maximum, ProtectedLuaPayload.VerifyAndDecrypt(maximumPayload, Path, key, verifier), "Maximum output accepted");
        Assert(ReadLength(maximumPayload) == ProtectedLuaPayload.MaxPlaintextBytes + 16, "Maximum padded ciphertext bound");
        foreach (int length in new[] { 0, ProtectedLuaPayload.MaxPlaintextBytes + 1, ProtectedLuaPayload.MaxPlaintextBytes + 15 })
        {
            byte[] oversizedOrEmpty = SignedEnvelope(new byte[length], Path, key, signer);
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(oversizedOrEmpty, Path, key, verifier); }, "Authenticated output outside bound", true);
        }
        byte[] overFrameLimit = new byte[HeaderBytes + ProtectedLuaPayload.MaxPlaintextBytes + 16 + SignatureBytes + 1];
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(overFrameLimit, Path, key, verifier); }, "Total frame bound", true);

        // A one-byte plaintext has 15 padding bytes. This IV mutation makes the last byte zero.
        byte[] badPadding = SignedEnvelope(new byte[] { 42 }, Path, key, signer);
        badPadding[55] ^= 15;
        using (TrackingRsa tracking = new TrackingRsa(verifier))
        {
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(badPadding, Path, key, tracking); }, "Invalid signature precedes invalid padding", true);
            Assert(tracking.VerifyCalls == 1 && !tracking.LastResult, "RSA verification reached before padding handling");
            Resign(badPadding, signer);
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(badPadding, Path, key, tracking); }, "Authenticated bad padding", true);
            Assert(tracking.VerifyCalls == 2 && tracking.LastResult, "Valid signature then padding rejection");
        }
        byte[] mutable = SignedEnvelope(new byte[] { 42 }, Path, key, signer);
        using (TrackingRsa tracking = new TrackingRsa(verifier))
        {
            tracking.AfterVerify = delegate { mutable[55] ^= 15; };
            Bytes(new byte[] { 42 }, ProtectedLuaPayload.VerifyAndDecrypt(mutable, Path, key, tracking), "Decrypts authenticated snapshot despite input mutation");
        }

        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(null, Path, key, verifier); }, "Null payload", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, null, key, verifier); }, "Null runtime path", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, "../bad.lua", key, verifier); }, "Unsafe runtime path", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, null, verifier); }, "Null AES key", true);
        Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, key, null); }, "Null verifier", true);
        foreach (int keyBytes in new[] { 0, 16, 24, 31, 33, 64 })
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, new byte[keyBytes], verifier); }, "AES-256 key required", true);
        foreach (int bits in new[] { 1024, 3072 })
            using (RSA wrongSize = NewRsa(bits))
                Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, key, wrongSize); }, "RSA-2048 verifier required", true);
        using (TrackingRsa throwing = new TrackingRsa(verifier))
        {
            throwing.ThrowOnVerify = true;
            Reject(delegate { ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, key, throwing); }, "Provider errors do not disclose details", true);
        }
    }

#if UNITY_EDITOR
    private static void TestEditor(RSA signer, RSA verifier, byte[] key)
    {
        foreach (int length in new[] { 1, 15, 16, 17, 31, 32, ProtectedLuaPayload.MaxPlaintextBytes - 1, ProtectedLuaPayload.MaxPlaintextBytes })
        {
            byte[] plain = Pattern(length);
            byte[] payload = ProtectedLuaPayload.EncryptAndSign(plain, Path, key, signer);
            Bytes(plain, ProtectedLuaPayload.VerifyAndDecrypt(payload, Path, key, verifier), "Editor block/boundary roundtrip");
            CheckWireFormat(payload, plain, key, verifier);
        }
        byte[] unicode = Encoding.UTF8.GetBytes("return '\u4e16\u754c \ud83d\ude80'\n");
        byte[] unicodeEnvelope = ProtectedLuaPayload.EncryptAndSign(unicode, "\u6846\u67b6\\\u754c\u9762.LUA", key, signer);
        Bytes(unicode, ProtectedLuaPayload.VerifyAndDecrypt(unicodeEnvelope, "\u6846\u67b6/\u754c\u9762.lua", key, verifier), "Unicode content and context");
        byte[] first = ProtectedLuaPayload.EncryptAndSign(unicode, Path, key, signer);
        byte[] second = ProtectedLuaPayload.EncryptAndSign(unicode, Path, key, signer);
        Assert(!Same(first, second), "Randomized envelopes differ");
        Assert(!Same(Range(first, 40, 16), Range(second, 40, 16)), "Randomized IVs differ");
        byte[] source = (byte[])unicode.Clone();
        byte[] keyBefore = (byte[])key.Clone();
        ProtectedLuaPayload.EncryptAndSign(unicode, Path, key, signer);
        Bytes(source, unicode, "Encryption preserves caller plaintext");
        Bytes(keyBefore, key, "Encryption preserves caller key");

        foreach (byte[] invalid in new byte[][] { null, new byte[0], new byte[ProtectedLuaPayload.MaxPlaintextBytes + 1] })
            Reject(delegate { ProtectedLuaPayload.EncryptAndSign(invalid, Path, key, signer); }, "Editor input bound", true);
        Reject(delegate { ProtectedLuaPayload.EncryptAndSign(unicode, "bad.txt", key, signer); }, "Editor invalid path", true);
        Reject(delegate { ProtectedLuaPayload.EncryptAndSign(unicode, Path, null, signer); }, "Editor null AES", true);
        Reject(delegate { ProtectedLuaPayload.EncryptAndSign(unicode, Path, key, null); }, "Editor null signer", true);
        Reject(delegate { ProtectedLuaPayload.EncryptAndSign(unicode, Path, key, verifier); }, "Public-only key cannot sign", true);
        foreach (int length in new[] { 0, 16, 24, 31, 33 })
            Reject(delegate { ProtectedLuaPayload.EncryptAndSign(unicode, Path, new byte[length], signer); }, "Editor AES size", true);
        foreach (int bits in new[] { 1024, 3072 })
            using (RSA wrongSize = NewRsa(bits))
                Reject(delegate { ProtectedLuaPayload.EncryptAndSign(unicode, Path, key, wrongSize); }, "Editor RSA size", true);
    }

    private static void CheckWireFormat(byte[] payload, byte[] plain, byte[] key, RSA verifier)
    {
        Bytes(Encoding.ASCII.GetBytes("ULP00001"), Range(payload, 0, 8), "Wire magic");
        byte[] expectedContext;
        using (SHA256Managed sha = new SHA256Managed())
            expectedContext = sha.ComputeHash(Encoding.UTF8.GetBytes("framework/ui/uimanager.lua"));
        Bytes(expectedContext, Range(payload, 8, 32), "Wire path SHA256");
        int ciphertextLength = ReadLength(payload);
        Assert(ciphertextLength == (plain.Length / 16 + 1) * 16, "Big-endian PKCS7 length");
        Assert(payload.Length == HeaderBytes + ciphertextLength + SignatureBytes, "Exact wire frame");
        byte[] digest;
        using (SHA256Managed sha = new SHA256Managed())
            digest = sha.ComputeHash(payload, 0, payload.Length - SignatureBytes);
        Assert(verifier.VerifyHash(digest, Range(payload, payload.Length - SignatureBytes, SignatureBytes),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1), "Independent RSA verification over entire header/ciphertext");
        using (AesManaged aes = new AesManaged())
        {
            aes.Key = key;
            aes.IV = Range(payload, 40, 16);
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            using (ICryptoTransform decryptor = aes.CreateDecryptor())
                Bytes(plain, decryptor.TransformFinalBlock(payload, HeaderBytes, ciphertextLength), "Independent AES-256-CBC decryption");
        }
    }
#endif

    // Independent fixture construction exercises the runtime parser and authenticated output limits.
    private static byte[] SignedEnvelope(byte[] plain, string path, byte[] key, RSA signer)
    {
        byte[] iv = Pattern(16);
        byte[] ciphertext;
        using (AesManaged aes = new AesManaged())
        {
            aes.Key = key;
            aes.IV = iv;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            using (ICryptoTransform encryptor = aes.CreateEncryptor())
                ciphertext = encryptor.TransformFinalBlock(plain, 0, plain.Length);
        }
        byte[] result = new byte[HeaderBytes + ciphertext.Length + SignatureBytes];
        Buffer.BlockCopy(Encoding.ASCII.GetBytes("ULP00001"), 0, result, 0, 8);
        using (SHA256Managed sha = new SHA256Managed())
        {
            byte[] context = sha.ComputeHash(Encoding.UTF8.GetBytes(path.Replace('\\', '/').ToLowerInvariant()));
            Buffer.BlockCopy(context, 0, result, 8, context.Length);
        }
        Buffer.BlockCopy(iv, 0, result, 40, 16);
        WriteLength(result, (uint)ciphertext.Length);
        Buffer.BlockCopy(ciphertext, 0, result, HeaderBytes, ciphertext.Length);
        Resign(result, signer);
        return result;
    }

    private static void Resign(byte[] payload, RSA signer)
    {
        int signedBytes = payload.Length - SignatureBytes;
        using (SHA256Managed sha = new SHA256Managed())
        {
            byte[] signature = signer.SignHash(sha.ComputeHash(payload, 0, signedBytes),
                HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            Buffer.BlockCopy(signature, 0, payload, signedBytes, SignatureBytes);
        }
    }

    private static RSA NewRsa(int bits)
    {
        // Mono's default RSA provider does not regenerate its key after assigning KeySize.
        RSACryptoServiceProvider rsa = new RSACryptoServiceProvider(bits);
        rsa.PersistKeyInCsp = false;
        RSAParameters generated = rsa.ExportParameters(true);
        Assert(rsa.KeySize == bits && generated.Modulus.Length * 8 == bits, "Generated RSA modulus size");
        return rsa;
    }

    private static RSA PublicOnly(RSA signer)
    {
        RSA rsa = RSA.Create();
        rsa.ImportParameters(signer.ExportParameters(false));
        return rsa;
    }

    private static byte[] Key(byte seed)
    {
        byte[] key = new byte[32];
        for (int i = 0; i < key.Length; i++) key[i] = (byte)(seed + i);
        return key;
    }

    private static byte[] Pattern(int length)
    {
        byte[] result = new byte[length];
        for (int i = 0; i < length; i++) result[i] = (byte)(i * 37 + 11);
        return result;
    }

    private static byte[] Slice(byte[] bytes, int count) { return Range(bytes, 0, count); }

    private static byte[] Range(byte[] bytes, int offset, int count)
    {
        byte[] result = new byte[count];
        Buffer.BlockCopy(bytes, offset, result, 0, count);
        return result;
    }

    private static int ReadLength(byte[] payload)
    {
        return (payload[56] << 24) | (payload[57] << 16) | (payload[58] << 8) | payload[59];
    }

    private static void WriteLength(byte[] payload, uint length)
    {
        payload[56] = (byte)(length >> 24);
        payload[57] = (byte)(length >> 16);
        payload[58] = (byte)(length >> 8);
        payload[59] = (byte)length;
    }

    private static void Reject(Action action, string label, bool generic = false)
    {
        try { action(); }
        catch (CryptographicException exception)
        {
            if (generic)
                Assert(exception.Message == FailureMessage && exception.InnerException == null, label + " generic error");
            assertions++;
            return;
        }
        throw new Exception(label + " was accepted.");
    }

    private static void Equal(string expected, string actual, string label) { Assert(expected == actual, label); }
    private static void Bytes(byte[] expected, byte[] actual, string label) { Assert(Same(expected, actual), label); }

    private static bool Same(byte[] left, byte[] right)
    {
        if (left.Length != right.Length) return false;
        for (int i = 0; i < left.Length; i++) if (left[i] != right[i]) return false;
        return true;
    }

    private static void Assert(bool condition, string label)
    {
        if (!condition) throw new Exception(label);
        assertions++;
    }

    private sealed class TrackingRsa : RSA
    {
        private readonly RSA inner;
        public int VerifyCalls;
        public bool LastResult;
        public bool ThrowOnVerify;
        public Action AfterVerify;

        public TrackingRsa(RSA inner) { this.inner = inner; }
        public override int KeySize { get { return inner.KeySize; } set { throw new NotSupportedException(); } }
        public override RSAParameters ExportParameters(bool includePrivateParameters) { return inner.ExportParameters(includePrivateParameters); }
        public override void ImportParameters(RSAParameters parameters) { throw new NotSupportedException(); }
        public override byte[] EncryptValue(byte[] value) { throw new NotSupportedException(); }
        public override byte[] DecryptValue(byte[] value) { throw new NotSupportedException(); }
        public override bool VerifyHash(byte[] hash, byte[] signature, HashAlgorithmName algorithm, RSASignaturePadding padding)
        {
            VerifyCalls++;
            if (ThrowOnVerify) throw new CryptographicException("Provider detail must never escape.");
            LastResult = inner.VerifyHash(hash, signature, algorithm, padding);
            if (AfterVerify != null) AfterVerify();
            return LastResult;
        }
    }
}
