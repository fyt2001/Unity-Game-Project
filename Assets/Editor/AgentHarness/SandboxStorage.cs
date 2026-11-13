// Redirects every Storage path under Application.persistentDataPath into a per-run sandbox directory,
// so AgentHarness runs never read or write the user's real save.
using System;
using System.IO;

namespace Game.AgentHarnessEditor
{
    public sealed class SandboxStorage : IStorage
    {
        private readonly FileStorage _inner = new FileStorage();
        private readonly string _realRoot;
        private readonly string _sandboxRoot;
        public int RedirectedCalls { get; private set; }
        public int PassThroughCalls { get; private set; }

        public SandboxStorage(string realRoot, string sandboxRoot)
        {
            _realRoot = Normalize(realRoot).TrimEnd('/');
            _sandboxRoot = Normalize(sandboxRoot).TrimEnd('/');
            Directory.CreateDirectory(_sandboxRoot);
        }

        public string SandboxRoot { get { return _sandboxRoot; } }

        private static string Normalize(string p) { return (p ?? "").Replace('\\', '/'); }

        private string Map(string path)
        {
            string n = Normalize(path);
            if (n.StartsWith(_realRoot + "/", StringComparison.OrdinalIgnoreCase) || string.Equals(n, _realRoot, StringComparison.OrdinalIgnoreCase))
            {
                RedirectedCalls++;
                return _sandboxRoot + n.Substring(_realRoot.Length);
            }
            PassThroughCalls++;
            return path;
        }

        public bool FileExists(string path) { return _inner.FileExists(Map(path)); }
        public bool DirectoryExists(string path) { return _inner.DirectoryExists(Map(path)); }
        public void CreateDirectory(string path) { _inner.CreateDirectory(Map(path)); }
        public byte[] ReadAllBytes(string path) { return _inner.ReadAllBytes(Map(path)); }
        public string ReadAllText(string path) { return _inner.ReadAllText(Map(path)); }
        public void WriteAllBytes(string path, byte[] data) { _inner.WriteAllBytes(Map(path), data); }
        public void WriteAllText(string path, string text) { _inner.WriteAllText(Map(path), text); }
        public void AppendAllText(string path, string text) { _inner.AppendAllText(Map(path), text); }
        public void DeleteFile(string path) { _inner.DeleteFile(Map(path)); }
        public void MoveFile(string srcPath, string dstPath) { _inner.MoveFile(Map(srcPath), Map(dstPath)); }
        public void DeleteDirectory(string path, bool recursive) { _inner.DeleteDirectory(Map(path), recursive); }
        public long GetFileSize(string path) { return _inner.GetFileSize(Map(path)); }
    }
}
