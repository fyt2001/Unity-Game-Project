// =============================================================================
// VersionFile.cs - 热更版本清单（对齐 ShaoNvClient_H02 VersionFile）
// =============================================================================
// 来源: ShaoNvClient_H02/Assets/Game/Scripts/Common/VersionFile.cs
//
// 优化点:
//   旧项目依赖第三方 CSV 库 ElencySolutions.CsvHelper；这里改为内置轻量 CSV
//   解析/写入，去掉外部依赖，且对缺字段/脏数据做容错（TryParse），不再抛异常中断。
//   旧项目的 Versions 类型与 RuntimeSettings/平台强耦合，这里把版本号简化为 string
//   （WebDownLoadManager 仅消费文件清单，不关心版本比较；版本对比留给 UpdateMgr）。
//   文件尺寸用 long（避免 uint 溢出），接口与 WebDownLoadManager 的调用面保持一致。
// =============================================================================

using System.Collections.Generic;
using System.IO;
using System.Text;

public class VersionFile
{
    public string Version { get; set; }

    private readonly Dictionary<string, FileInfo> _fileInfoMap = new Dictionary<string, FileInfo>();
    private List<FileInfo> unloadedList = new List<FileInfo>();

    public VersionFile() { }
    public VersionFile(string version, List<FileInfo> files)
    {
        Version = version;
        if (files != null)
            foreach (var f in files)
                if (!_fileInfoMap.ContainsKey(f.Path)) _fileInfoMap[f.Path] = f;
    }

    // =========================================================================
    // 解析（内置 CSV，优化：容错 + 无第三方依赖）
    // =========================================================================

    public static VersionFile FromString(string content)
    {
        var vf = new VersionFile();
        if (string.IsNullOrEmpty(content)) return vf;

        var lines = content.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i].Trim('\r', ' ');
            if (line.Length == 0) continue;

            if (i == 0) { vf.Version = line; continue; }

            var f = ParseRow(line);
            if (f != null && !vf._fileInfoMap.ContainsKey(f.Path)) vf._fileInfoMap[f.Path] = f;
        }
        return vf;
    }

    public static VersionFile FromFile(string filePath)
    {
        if (!Storage.Current.FileExists(filePath)) return null;
        try { return FromString(Storage.Current.ReadAllText(filePath)); }
        catch (System.Exception e)
        {
            DebugLogger.Error("[VersionFile] parse failed: {0}", e.Message);
            return null;
        }
    }

    static FileInfo ParseRow(string line)
    {
        var p = line.Split(',');
        if (p.Length < 3) return null; // 至少需要 Path,Version,Size

        var f = new FileInfo { Path = p[0] };
        if (p.Length > 1) f.Version = p[1];
        if (p.Length > 2) long.TryParse(p[2], out f.Size);
        if (p.Length > 3) int.TryParse(p[3], out f.isload);
        if (p.Length > 4) int.TryParse(p[4], out f.isInPersistentPath);
        if (p.Length > 5) f.cdnDir = p[5];
        return f;
    }

    // =========================================================================
    // 写入（对齐旧项目 CSV 格式: 首行版本号, 后续 Path,Version,Size,isload,isInPersistentPath,cdnDir）
    // =========================================================================

    public void Write(string path)
    {
        FileUtils.CreateDirectoryForFile(path);
        var sb = new StringBuilder();
        sb.AppendLine(Version ?? "1.0.0");
        foreach (var f in _fileInfoMap.Values)
            sb.AppendLine($"{f.Path},{f.Version},{f.Size},{f.isload},{f.isInPersistentPath},{f.cdnDir}");

        try { Storage.Current.WriteAllText(path, sb.ToString()); }
        catch (System.Exception e) { DebugLogger.Error("[VersionFile] write failed: {0}", e.Message); }
    }

    // =========================================================================
    // 待下载清单（WebDownLoadManager 消费面，对齐旧项目）
    // =========================================================================

    /// <summary>isload==2 视为待下载（延迟/静默下载项）。</summary>
    public void SetUnLoadedList()
    {
        unloadedList.Clear();
        foreach (var kv in _fileInfoMap)
            if (kv.Value.isload == 2) unloadedList.Add(kv.Value);
    }

    public List<FileInfo> GetUnLoadedList() => unloadedList;
    public FileInfo GetUnLoadedFile() => unloadedList.Count > 0 ? unloadedList[0] : null;
    public FileInfo GetFileInfo(string name) => _fileInfoMap.TryGetValue(name, out var v) ? v : null;
    public void RemoveLoadedList(FileInfo info) => unloadedList.Remove(info);

    // =========================================================================
    // 查询 / 更新（供 UpdateMgr 等后续模块使用）
    // =========================================================================

    public bool IsLoaded(string name) => _fileInfoMap.TryGetValue(name, out var v) && v.isload == 1;
    public bool IsInPersistentPath(string name) => _fileInfoMap.TryGetValue(name, out var v) && v.isInPersistentPath > 0;
    public void ChangeOne(FileInfo info) { if (info != null) _fileInfoMap[info.Path] = info; }
    public Dictionary<string, FileInfo> GetFileInfoMap() => _fileInfoMap;

    // =========================================================================
    // 差异计算 / 合并（对齐旧项目 VersionFile.MakeUpdateInfo / Renew，供 UpdateMgr 使用）
    // 优化: 旧项目依赖 Versions 类型做版本号比较；这里改为文件级 diff
    //       （本地缺失 / 未落地 / 版本号不一致 即视为需更新），自包含无第三方依赖。
    // =========================================================================

    /// <summary>本地相对远端的待更新列表（对齐旧项目 MakeUpdateInfo）。</summary>
    public UpdateInfo MakeUpdateInfo(VersionFile remote)
    {
        var info = new UpdateInfo { Version = remote };
        if (remote == null) return info;

        foreach (var rf in remote.GetFileInfoMap().Values)
        {
            var lf = GetFileInfo(rf.Path);
            bool need = (lf == null) || (lf.isload != 1) || (lf.Version != rf.Version);
            if (need) info.UpdateList.Add(rf);
        }
        return info;
    }

    /// <summary>把一次更新结果合并回本地清单（对齐旧项目 Renew）。
    /// 远端清单为权威源；本次实际下载的项标记 isload=1/isInPersistentPath=1，
    /// 远端标记为 isload==2 的延迟项会保留，交由 WebDownLoadManager 后台补下载。</summary>
    public void Renew(UpdateInfo info, string newVersion)
    {
        Version = newVersion;
        if (info?.Version == null) return;

        foreach (var rf in info.Version.GetFileInfoMap().Values)
            _fileInfoMap[rf.Path] = rf; // 保留远端原始 isload（含延迟项 2）

        foreach (var f in info.UpdateList)
        {
            f.isload = 1;
            f.isInPersistentPath = 1;
            _fileInfoMap[f.Path] = f;
        }
    }

    // =========================================================================
    // 单文件信息（对齐旧项目 VersionFile.FileInfo）
    // =========================================================================

    /// <summary>一次热更的差异结果（对齐旧项目 VersionFile.UpdateInfo）。</summary>
    public class UpdateInfo
    {
        public VersionFile Version;
        public List<FileInfo> UpdateList = new List<FileInfo>();
        public long TotalSize
        {
            get { long s = 0; foreach (var f in UpdateList) s += f.Size; return s; }
        }
    }



    public class FileInfo
    {
        public string Path;
        public string Version;
        public long Size;
        public int isload;            // 0 未加载(首启) 1 已落地 2 延迟/待下载
        public int isInPersistentPath; // 0 不在可读写目录 1 在
        public string cdnDir;

        public string GetParentPath() => Path.Length > 0 ? System.IO.Path.GetDirectoryName(Path) + "/" : "";
        public string GetName() => System.IO.Path.GetFileName(Path);
        public override string ToString() => $"path:{Path},version:{Version},size:{Size}";
    }
}
