// =============================================================================
// HotfixSettings.cs - 热更配置（取代 ShaoNvClient_H02 RuntimeSettings）
// =============================================================================
// 旧项目 RuntimeSettings 携带 Versions / Platform / 平台首包路径等游戏特定配置；
// 新项目只保留热更真正需要的几项，集中于此，便于运维/构建脚本注入。

public static class HotfixSettings
{
    /// <summary>热更 CDN 根地址（http(s)://...）。留空则跳过热更（开发期不阻断启动）。</summary>
    public static string RemoteAssetUrl
    {
        get => FileUtils.RemoteAssetUrl;
        set => FileUtils.RemoteAssetUrl = value;
    }

    /// <summary>远端版本清单文件名（对齐旧项目 _versionCsvFilePath）。</summary>
    public const string VersionCsvName = "versions.csv";

    /// <summary>可选「最新版本闸门」URL（如 game.json）。留空则跳过该步。</summary>
    public static string LatestVersionUrl = string.Empty;

    /// <summary>是否启用启动期热更。关闭则完全跳过 UpdateMgr。</summary>
    public static bool AutoUpdateEnabled = true;
}
