using System;
using System.Security.Cryptography;
using System.Text;

namespace Game.Security
{
    /// <summary>Bounded, path-bound Lua envelopes. Shipped AES keys can be extracted.</summary>
    public static class ProtectedLuaPayload
    {
        public const int MaxPlaintextBytes = 1048576;

        private const int ContextOffset = 8;
        private const int IvOffset = 40;
        private const int LengthOffset = 56;
        private const int HeaderBytes = 60;
        private const int SignatureBytes = 256;
        private const int BlockBytes = 16;
        private const int MaxCiphertextBytes = MaxPlaintextBytes + BlockBytes;
        private const string FailureMessage = "Invalid protected Lua payload.";
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("ULP00001");
        private static readonly Encoding PathEncoding = new UTF8Encoding(false, true);

        /// <summary>Returns a relative, slash-normalized lowercase path retaining its .lua suffix.</summary>
        public static string CanonicalPath(string path)
        {
            if (string.IsNullOrEmpty(path)) throw Failure();
            for (int i = 0; i < path.Length; i++)
            {
                if (path[i] == ':' || char.IsControl(path[i])) throw Failure();
            }

            string canonical = path.Replace('\\', '/').ToLowerInvariant();
            string[] segments = canonical.Split('/');
            foreach (string segment in segments)
            {
                if (segment.Length == 0 || segment == "." || segment == "..") throw Failure();
            }
            string filename = segments[segments.Length - 1];
            if (filename.Length <= 4 || !filename.EndsWith(".lua", StringComparison.Ordinal))
                throw Failure();

            try
            {
                PathEncoding.GetByteCount(canonical);
            }
            catch (ArgumentException)
            {
                throw Failure();
            }
            return canonical;
        }

#if UNITY_EDITOR
        public static byte[] EncryptAndSign(byte[] plain, string scriptPath, byte[] aesKey, RSA signer)
        {
            try
            {
                ValidateKeys(aesKey, signer);
                if (plain == null || plain.Length < 1 || plain.Length > MaxPlaintextBytes)
                    throw Failure();

                byte[] context = ContextHash(scriptPath);
                byte[] iv = new byte[BlockBytes];
                using (RandomNumberGenerator random = RandomNumberGenerator.Create())
                    random.GetBytes(iv);

                byte[] ciphertext;
                using (AesManaged aes = CreateAes(aesKey, iv))
                using (ICryptoTransform encryptor = aes.CreateEncryptor())
                    ciphertext = encryptor.TransformFinalBlock(plain, 0, plain.Length);

                int signedBytes = HeaderBytes + ciphertext.Length;
                byte[] payload = new byte[signedBytes + SignatureBytes];
                Buffer.BlockCopy(Magic, 0, payload, 0, Magic.Length);
                Buffer.BlockCopy(context, 0, payload, ContextOffset, context.Length);
                Buffer.BlockCopy(iv, 0, payload, IvOffset, iv.Length);
                WriteLength(payload, ciphertext.Length);
                Buffer.BlockCopy(ciphertext, 0, payload, HeaderBytes, ciphertext.Length);

                byte[] signature = signer.SignHash(Hash(payload, signedBytes),
                    HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
                if (signature == null || signature.Length != SignatureBytes) throw Failure();
                Buffer.BlockCopy(signature, 0, payload, signedBytes, SignatureBytes);
                return payload;
            }
            catch (CryptographicException) { throw Failure(); }
            catch (ArgumentException) { throw Failure(); }
            catch (InvalidOperationException) { throw Failure(); }
            catch (NotSupportedException) { throw Failure(); }
        }

        private static void WriteLength(byte[] payload, int length)
        {
            payload[LengthOffset] = (byte)(length >> 24);
            payload[LengthOffset + 1] = (byte)(length >> 16);
            payload[LengthOffset + 2] = (byte)(length >> 8);
            payload[LengthOffset + 3] = (byte)length;
        }
#endif

        public static byte[] VerifyAndDecrypt(byte[] payload, string scriptPath, byte[] aesKey, RSA verifier)
        {
            try
            {
                ValidateKeys(aesKey, verifier);
                if (payload == null || payload.Length < HeaderBytes + BlockBytes + SignatureBytes ||
                    payload.Length > HeaderBytes + MaxCiphertextBytes + SignatureBytes)
                    throw Failure();

                // Verify and decrypt the same bounded snapshot, even if a caller mutates its input.
                byte[] envelope = (byte[])payload.Clone();
                if (!FixedTimeEquals(envelope, 0, Magic)) throw Failure();
                uint length = ((uint)envelope[LengthOffset] << 24) |
                    ((uint)envelope[LengthOffset + 1] << 16) |
                    ((uint)envelope[LengthOffset + 2] << 8) |
                    envelope[LengthOffset + 3];
                if (length < BlockBytes || length > MaxCiphertextBytes || length % BlockBytes != 0)
                    throw Failure();

                // Conversion and addition are safe only after the unsigned bound check above.
                int ciphertextBytes = (int)length;
                int signedBytes = HeaderBytes + ciphertextBytes;
                if (envelope.Length != signedBytes + SignatureBytes) throw Failure();
                if (!FixedTimeEquals(envelope, ContextOffset, ContextHash(scriptPath))) throw Failure();

                byte[] signature = new byte[SignatureBytes];
                Buffer.BlockCopy(envelope, signedBytes, signature, 0, SignatureBytes);
                if (!verifier.VerifyHash(Hash(envelope, signedBytes), signature,
                    HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) throw Failure();

                // No AES instance or decryptor exists until the whole envelope is authenticated.
                byte[] iv = new byte[BlockBytes];
                Buffer.BlockCopy(envelope, IvOffset, iv, 0, iv.Length);
                byte[] plain;
                using (AesManaged aes = CreateAes(aesKey, iv))
                using (ICryptoTransform decryptor = aes.CreateDecryptor())
                    plain = decryptor.TransformFinalBlock(envelope, HeaderBytes, ciphertextBytes);
                if (plain.Length < 1 || plain.Length > MaxPlaintextBytes)
                {
                    Array.Clear(plain, 0, plain.Length);
                    throw Failure();
                }
                return plain;
            }
            catch (CryptographicException) { throw Failure(); }
            catch (ArgumentException) { throw Failure(); }
            catch (InvalidOperationException) { throw Failure(); }
            catch (NotSupportedException) { throw Failure(); }
        }

        private static void ValidateKeys(byte[] aesKey, RSA rsa)
        {
            if (aesKey == null || aesKey.Length != 32 || rsa == null || rsa.KeySize != 2048)
                throw Failure();
        }

        private static AesManaged CreateAes(byte[] key, byte[] iv)
        {
            AesManaged aes = new AesManaged();
            try
            {
                aes.KeySize = 256;
                aes.BlockSize = 128;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = key;
                aes.IV = iv;
                return aes;
            }
            catch
            {
                aes.Dispose();
                throw;
            }
        }

        private static byte[] ContextHash(string scriptPath)
        {
            byte[] bytes = PathEncoding.GetBytes(CanonicalPath(scriptPath));
            return Hash(bytes, bytes.Length);
        }

        private static byte[] Hash(byte[] bytes, int count)
        {
            using (SHA256Managed sha = new SHA256Managed())
                return sha.ComputeHash(bytes, 0, count);
        }

        private static bool FixedTimeEquals(byte[] bytes, int offset, byte[] expected)
        {
            int difference = 0;
            for (int i = 0; i < expected.Length; i++)
                difference |= bytes[offset + i] ^ expected[i];
            return difference == 0;
        }

        private static CryptographicException Failure()
        {
            return new CryptographicException(FailureMessage);
        }
    }
}
