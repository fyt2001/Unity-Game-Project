// =============================================================================
// IStorage.cs - 可写存储抽象（多平台兼容）
// =============================================================================
// 目的：隔离平台差异，让业务代码不感知底层文件系统。
//
//   - Editor / PC / Android / iOS / macOS : FileStorage（System.IO）
//       行为与改造前完全一致，这些平台不受任何影响。
//   - 微信小游戏（WebGL）                  : 官方明确不支持 System.File，
//       届时实现 IStorage 并在启动早期调用 Storage.SetStorage(...) 注入即可，
//       业务代码零改动，也不会出现平台宏污染。
//
// 路径约定：沿用 Application.persistentDataPath 拼接出的绝对路径，与改造前一致。
// =============================================================================

using XLua;

/// <summary>
/// 可写存储抽象。实现类需保证：目录不存在时写入应先创建目录。
/// </summary>
[LuaCallCSharp]
public interface IStorage
{
    bool FileExists(string path);
    bool DirectoryExists(string path);
    void CreateDirectory(string path);
    byte[] ReadAllBytes(string path);
    string ReadAllText(string path);
    void WriteAllBytes(string path, byte[] data);
    void WriteAllText(string path, string text);
    /// <summary>追加文本（日志写入用）。底层不支持追加的平台可用「读-拼-写」实现。</summary>
    void AppendAllText(string path, string text);
    void DeleteFile(string path);
    /// <summary>原子移动/重命名。底层不支持原子 move 的平台可用「读-写-删」实现。</summary>
    void MoveFile(string srcPath, string dstPath);
    void DeleteDirectory(string path, bool recursive);
    long GetFileSize(string path);
}
