// =============================================================================
// UpdateMgr.cs - 热更版本对比/首包更新管理器（照搬 ShaoNvClient_H02 并优化）
// =============================================================================
// 来源: ShaoNvClient_H02/Assets/Game/Scripts/Core/UpdateMgr.cs
//
// 照搬的旧项目机制:
//   - 启动时加载本地版本清单(GameLaunch.localVersion) -> 拉取远端 versions.csv
//     -> 计算差异(MakeUpdateInfo) -> 逐个下载到 persistent -> 合并清单(Renew)落盘
//   - 进度/文案通过 GameLaunch 进度 UI 反馈
//
// 优化点（相对旧项目）:
//   1. 弃用 FirstDownLoadManager(31KB 首包拷贝) 与 Versions 版本比较类型：
//      新项目初始资源走 AB/StreamingAssets，UpdateMgr 只做「远端 diff 更新」；
//      版本比较改为文件级 diff（VersionFile.MakeUpdateInfo），自包含。
//   2. 弃用后台 Thread 写文件(UpdateThreadSaveTask，且跨线程访问 localVersion 不安全)：
//      改为单协程内「下载即落盘」，逻辑简单且无竞态。
//   3. 弃用 isNetworkError/isHttpError 与 yield return WaitForSeconds(10000000) 死等：
//      改用 UnityWebRequest.Result；更新失败仅告警并继续启动，不卡死启动流程。
//   4. 可选 LatestVersionUrl 闸门(retry 3 次)，对齐旧项目 GetLastVersion 的容错。
// =============================================================================

using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using UnityEngine.Networking;

public class UpdateMgr : MonoBehaviour
{
    private static UpdateMgr s_instance;
    public static UpdateMgr Get()
    {
        if (s_instance == null) Ensure();
        return s_instance;
    }

    /// <summary>若场景中未挂载，自动创建隐藏节点。</summary>
    public static void Ensure()
    {
        if (s_instance != null) return;
        var go = new GameObject("UpdateMgr");
        go.hideFlags = HideFlags.HideInHierarchy;
        DontDestroyOnLoad(go);
        go.AddComponent<UpdateMgr>();
    }

    public Status UpdateStatus { get; private set; } = new Status();

    VersionFile localVersion;

    private void Awake()
    {
        if (s_instance != null && s_instance != this) { Destroy(gameObject); return; }
        s_instance = this;
        UpdateStatus = new Status();
    }

    private void OnDestroy()
    {
        if (s_instance == this) s_instance = null;
    }

    // =========================================================================
    // 主流程
    // =========================================================================

    public IEnumerator Initializer()
    {
        localVersion = (GameLaunch.Instance != null) ? GameLaunch.Instance.localVersion
                                                       : VersionFile.FromFile(FileUtils.ToPersistentPathSys(HotfixSettings.VersionCsvName));
        if (localVersion == null) localVersion = new VersionFile();

        // 0) 总开关 / CDN 未配置 -> 跳过热更（不阻断启动）
        if (!HotfixSettings.AutoUpdateEnabled || string.IsNullOrEmpty(HotfixSettings.RemoteAssetUrl))
        {
            DebugLogger.Info("[UpdateMgr] disabled or CDN not configured, skip. (AutoUpdate={0}, Url={1})",
                HotfixSettings.AutoUpdateEnabled, HotfixSettings.RemoteAssetUrl);
            UpdateStatus.Phase = Phase.Done;
            UpdateStatus.Progress = 1f;
            enabled = false;
            yield break;
        }

        // 1) 可选：最新版本闸门(game.json)，retry 3 次
        if (!string.IsNullOrEmpty(HotfixSettings.LatestVersionUrl))
        {
            bool ok = false;
            for (int retry = 0; retry < 3 && !ok; retry++)
            {
                using (var req = UnityWebRequest.Get(HotfixSettings.LatestVersionUrl))
                {
                    yield return req.SendWebRequest();
                    if (req.result == UnityWebRequest.Result.Success) { ok = true; VesionText = req.downloadHandler.text; }
                    else { DebugLogger.Warn("[UpdateMgr] fetch latest-version failed ({0}): {1}", retry, req.error); yield return new WaitForSeconds(1f); }
                }
            }
            if (!ok)
            {
                UpdateStatus.Phase = Phase.Error;
                SetDesc("版本获取失败，请检查网络");
                // 优化：不卡死启动，继续以本地清单运行
                UpdateStatus.Phase = Phase.Done;
                UpdateStatus.Progress = 1f;
                enabled = false;
                yield break;
            }
            // TODO: 解析 VesionText 决定是否强制更新 / 跳转商店
        }

        // 2) 拉取远端版本清单
        SetDesc("正在检查更新...");
        string remoteUrl = FileUtils.ToRemoteAssetUrl(HotfixSettings.VersionCsvName);
        using (var www = UnityWebRequest.Get(remoteUrl))
        {
            yield return www.SendWebRequest();
            if (www.result != UnityWebRequest.Result.Success)
            {
                DebugLogger.Warn("[UpdateMgr] fetch remote version failed: {0}", www.error);
                UpdateStatus.Phase = Phase.Error;
                SetDesc("更新清单下载失败，使用本地版本");
                UpdateStatus.Phase = Phase.Done;
                UpdateStatus.Progress = 1f;
                enabled = false;
                yield break;
            }

            VersionFile remoteVersion = VersionFile.FromString(www.downloadHandler.text);

            // 3) 计算差异
            var updateInfo = localVersion.MakeUpdateInfo(remoteVersion);
            if (updateInfo.UpdateList.Count > 0)
            {
                UpdateStatus.Phase = Phase.Updating;
                int count = updateInfo.UpdateList.Count;
                long total = updateInfo.TotalSize;
                long processed = 0;

                SetDesc(string.Format("发现 {0} 个更新文件", count));

                for (int i = 0; i < count; i++)
                {
                    var f = updateInfo.UpdateList[i];
                    string url = FileUtils.ToRemoteAssetUrl(f.Path);
                    using (var w = UnityWebRequest.Get(url))
                    {
                        yield return w.SendWebRequest();
                        if (w.result != UnityWebRequest.Result.Success)
                        {
                            DebugLogger.Error("[UpdateMgr] download failed: {0} ({1})", f.Path, w.error);
                            UpdateStatus.Phase = Phase.Error;
                            SetDesc("文件下载失败: " + f.Path);
                            UpdateStatus.Phase = Phase.Done;
                            UpdateStatus.Progress = 1f;
                            enabled = false;
                            yield break;
                        }

                        string des = FileUtils.ToPersistentPathSys(f.Path);
                        FileUtils.SafeWriteAllBytes(des, w.downloadHandler.data);
                        f.isInPersistentPath = 1;
                        f.isload = 1;
                        localVersion.ChangeOne(f);

                        processed += f.Size;
                        SetProgress(total > 0 ? (float)processed / (float)total : 1f);
                        SetDesc(string.Format("更新中 {0}/{1}", i + 1, count));
                    }
                }

                // 4) 合并清单并落盘
                localVersion.Renew(updateInfo, remoteVersion.Version);
                localVersion.Write(FileUtils.ToPersistentPathSys(HotfixSettings.VersionCsvName));
                if (GameLaunch.Instance != null) GameLaunch.Instance.localVersion = localVersion;
                DebugLogger.Info("[UpdateMgr] updated {0} files, local version = {1}", count, localVersion.Version);
            }
            else
            {
                DebugLogger.Info("[UpdateMgr] already up-to-date (local version = {0})", localVersion.Version);
            }
        }

        UpdateStatus.Phase = Phase.Done;
        UpdateStatus.Progress = 1f;
        enabled = false;
        yield break;
    }

    // =========================================================================
    // 进度反馈（对齐旧项目 GameLaunch.SetDesc / SetProgress，映射到新项目 UpdateProgressUI）
    // =========================================================================

    void SetDesc(string s)
    {
        if (GameLaunch.Instance != null) GameLaunch.Instance.UpdateProgressUI(-1f, s);
        else DebugLogger.Info("[UpdateMgr] " + s);
    }

    void SetProgress(float p)
    {
        if (GameLaunch.Instance != null) GameLaunch.Instance.UpdateProgressUI(p, "");
    }

    // =========================================================================
    // 状态
    // =========================================================================

    public class Status
    {
        public Phase Phase;
        public float Progress;
    }

    public enum Phase
    {
        Invalid = 0,
        FetchingVersionFile = 0xd,
        Updating = 0x15,
        Done = 0x1d,
        Error = 0x2,
    }

    // 最近一次闸门返回文本（LatestVersionUrl），保留以便解析
    public string VesionText { get; private set; }
}
