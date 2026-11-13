// =============================================================================
// FileStorage.cs - 默认存储实现（System.IO）
// =============================================================================
// 适用于 Editor / PC(Steam) / Android / iOS / macOS。
// 行为与改造前直接调用 System.IO 完全一致：
//   ReadAllText  用 1 参重载（UTF8 自动识别 BOM）
//   WriteAllText 用 2 参重载（UTF8 无 BOM）
// =============================================================================

using System.IO;
using XLua;

[LuaCallCSharp]
public class FileStorage : IStorage
{
    public bool FileExists(string path) => File.Exists(path);

    public bool DirectoryExists(string path) => Directory.Exists(path);

    public void CreateDirectory(string path) => Directory.CreateDirectory(path);

    public byte[] ReadAllBytes(string path) => File.ReadAllBytes(path);

    public string ReadAllText(string path) => File.ReadAllText(path);

    public void WriteAllBytes(string path, byte[] data) => File.WriteAllBytes(path, data);

    public void WriteAllText(string path, string text) => File.WriteAllText(path, text);

    public void AppendAllText(string path, string text) => File.AppendAllText(path, text);

    public void DeleteFile(string path) => File.Delete(path);

    public void MoveFile(string srcPath, string dstPath) => File.Move(srcPath, dstPath);

    public void DeleteDirectory(string path, bool recursive) => Directory.Delete(path, recursive);

    public long GetFileSize(string path) => new FileInfo(path).Length;
}
