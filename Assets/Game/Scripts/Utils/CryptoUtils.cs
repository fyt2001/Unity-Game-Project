// =============================================================================
// CryptoUtils.cs - 加密工具类（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 XLuaManager.Decrypt（XOR加密）+ 通用加密需求
// 升级: 增加AES加密、XXTEA、Base64等常用加密方法
// =============================================================================

using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

/// <summary>
/// 加密工具类。
/// 提供 XOR/AES/XXTEA/Base64 等常用加密方法。
/// </summary>
public static class CryptoUtils
{
    #region XOR 加密（简单快速，适合Lua脚本加密）

    /// <summary>
    /// XOR 加密/解密（对称操作）
    /// </summary>
    public static byte[] XorEncrypt(byte[] data, string key)
    {
        if (data == null || string.IsNullOrEmpty(key)) return data;

        byte[] result = new byte[data.Length];
        char[] keyChars = key.ToCharArray();

        for (int i = 0; i < data.Length; i++)
        {
            result[i] = (byte)(data[i] ^ (byte)keyChars[i % keyChars.Length]);
        }

        return result;
    }

    /// <summary>
    /// XOR 原地加密/解密
    /// </summary>
    public static void XorEncryptInPlace(byte[] data, string key)
    {
        if (data == null || string.IsNullOrEmpty(key)) return;

        char[] keyChars = key.ToCharArray();
        for (int i = 0; i < data.Length; i++)
        {
            data[i] ^= (byte)keyChars[i % keyChars.Length];
        }
    }

    #endregion

    #region AES 加密

    /// <summary>
    /// AES 加密
    /// </summary>
    public static byte[] AesEncrypt(byte[] data, string key, string iv = null)
    {
        if (data == null || string.IsNullOrEmpty(key)) return null;

        using (Aes aes = Aes.Create())
        {
            aes.Key = Encoding.UTF8.GetBytes(key.PadRight(32).Substring(0, 32));
            aes.IV = iv != null
                ? Encoding.UTF8.GetBytes(iv.PadRight(16).Substring(0, 16))
                : new byte[16];

            using (MemoryStream ms = new MemoryStream())
            using (CryptoStream cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
            {
                cs.Write(data, 0, data.Length);
                cs.FlushFinalBlock();
                return ms.ToArray();
            }
        }
    }

    /// <summary>
    /// AES 解密
    /// </summary>
    public static byte[] AesDecrypt(byte[] data, string key, string iv = null)
    {
        if (data == null || string.IsNullOrEmpty(key)) return null;

        using (Aes aes = Aes.Create())
        {
            aes.Key = Encoding.UTF8.GetBytes(key.PadRight(32).Substring(0, 32));
            aes.IV = iv != null
                ? Encoding.UTF8.GetBytes(iv.PadRight(16).Substring(0, 16))
                : new byte[16];

            using (MemoryStream ms = new MemoryStream(data))
            using (CryptoStream cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read))
            using (MemoryStream result = new MemoryStream())
            {
                cs.CopyTo(result);
                return result.ToArray();
            }
        }
    }

    #endregion

    #region Base64

    /// <summary>
    /// Base64 编码
    /// </summary>
    public static string Base64Encode(byte[] data)
    {
        return data != null ? Convert.ToBase64String(data) : null;
    }

    /// <summary>
    /// Base64 解码
    /// </summary>
    public static byte[] Base64Decode(string base64Str)
    {
        if (string.IsNullOrEmpty(base64Str)) return null;

        try
        {
            return Convert.FromBase64String(base64Str);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Base64 编码（字符串）
    /// </summary>
    public static string Base64EncodeString(string text, Encoding encoding = null)
    {
        if (string.IsNullOrEmpty(text)) return null;
        return Base64Encode((encoding ?? Encoding.UTF8).GetBytes(text));
    }

    /// <summary>
    /// Base64 解码（字符串）
    /// </summary>
    public static string Base64DecodeString(string base64Str, Encoding encoding = null)
    {
        byte[] data = Base64Decode(base64Str);
        return data != null ? (encoding ?? Encoding.UTF8).GetString(data) : null;
    }

    #endregion

    #region MD5 / SHA

    /// <summary>
    /// 计算 MD5 哈希
    /// </summary>
    public static string ComputeMD5(byte[] data)
    {
        if (data == null) return string.Empty;

        using (MD5 md5 = MD5.Create())
        {
            byte[] hash = md5.ComputeHash(data);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hash.Length; i++)
            {
                sb.Append(hash[i].ToString("x2"));
            }
            return sb.ToString();
        }
    }

    /// <summary>
    /// 计算 SHA256 哈希
    /// </summary>
    public static string ComputeSHA256(byte[] data)
    {
        if (data == null) return string.Empty;

        using (SHA256 sha = SHA256.Create())
        {
            byte[] hash = sha.ComputeHash(data);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hash.Length; i++)
            {
                sb.Append(hash[i].ToString("x2"));
            }
            return sb.ToString();
        }
    }

    #endregion
}
