// =============================================================================
// WebDownLoadManager.cs - 热更静默下载管理器（照搬 ShaoNvClient_H02 并优化）
// =============================================================================
// 来源: ShaoNvClient_H02/Assets/Game/Scripts/Core/WebDownLoadManager.cs
//
// 照搬的旧项目机制:
//   - 消费 GameLaunch.localVersion（VersionFile 版本清单），取 isload==2 的待下载项
//   - 用 FileUtils.ToRemoteAssetUrl / ToPersistentPathSys / CreateDirectoryForFile 拼 URL 与落地
//   - 同一套 Lua 回调: callLua(指定 bundle 完成) / downLoadCall(单文件 / "All") / loadSaveCall(清单落盘)
//
// 优化点（相对旧项目）:
//   1. 旧代码 downloaderrorcount 超过 3 次只 reset 为 0 却什么都不做 -> 卡死；
//      改为「每文件独立 retryCount，超过 MaxRetry 真正放弃并回调 OnError/继续下一项」。
//   2. 弃用已废弃的 isHttpError/isNetworkError，改用 UnityWebRequest.Result 判定。
//   3. 单例带 Ensure() 自动建节点，不必依赖场景手动挂载；Destroy 时中断所有在途请求。
//   4. 额外暴露 C# 事件 OnFileDownloaded / OnAllDownloaded / OnError，供非 Lua 调用方使用。
// =============================================================================

using UnityEngine;
using XLua;
using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine.Networking;

[LuaCallCSharp]
public class WebDownLoadManager : MonoBehaviour
{
    // =========================================================================
    // 单例
    // =========================================================================

    private static WebDownLoadManager s_instance;

    public static WebDownLoadManager Get()
    {
        if (s_instance == null) Ensure();
        return s_instance;
    }

    /// <summary>若场景中未挂载，自动创建一个隐藏节点，避免 Lua 侧 Get() 拿到 nil。</summary>
    public static void Ensure()
    {
        if (s_instance != null) return;
        var go = new GameObject("WebDownLoadManager");
        go.hideFlags = HideFlags.HideInHierarchy;
        DontDestroyOnLoad(go);
        go.AddComponent<WebDownLoadManager>();
    }

    // =========================================================================
    // 版本清单数据源（照搬旧项目: 直接用 VersionFile，由 GameLaunch 注入）
    // =========================================================================

    public VersionFile LocalVersion { get; set; } = new VersionFile();

    // =========================================================================
    // Lua 回调（对齐旧项目 API 面）
    // =========================================================================

    LuaFunction callLua;       // 指定 bundle 下载完成 -> Action<string>(bundleName)
    LuaFunction downLoadCall;  // 单文件 / 全部完成 -> Action<string>(path | "All")
    LuaFunction loadSaveCall;  // 清单进度落盘 -> Call()

    public void SetLuaCall(LuaFunction call1, LuaFunction call2)
    {
        callLua = call1;
        downLoadCall = call2;
    }

    public void SetSaveLuaCall(LuaFunction call1)
    {
        loadSaveCall = call1;
    }

    public void ReleaseLuaCallbacks()
    {
        callLua?.Dispose(); callLua = null;
        downLoadCall?.Dispose(); downLoadCall = null;
        loadSaveCall?.Dispose(); loadSaveCall = null;
    }

    // =========================================================================
    // C# 事件（优化: 非 Lua 调用方也能订阅）
    // =========================================================================

    public event Action<string> OnFileDownloaded;
    public event Action OnAllDownloaded;
    public event Action<string> OnError;

    // =========================================================================
    // 字段（照搬旧项目）
    // =========================================================================

    double _currentDownload = 0;
    double _totalDownload = 0;
    bool isPause;

    public List<string> Loadlist = new List<string>();
    float wversionTime = 0;

    public double CurrentDownload => _currentDownload;
    public double TotalDownload => _totalDownload;
    public bool IsPause => isPause;

    const float DownloadTimeout = 30f;   // 单文件下载超时（秒）
    const int MaxRetry = 3;              // 单文件最大重试次数

    List<DownloadItem> wlist = new List<DownloadItem>();
    bool dowloadIsSpecific;
    string currentBundle;
    VersionFile.FileInfo loadedInfo;

    // =========================================================================
    // 生命周期
    // =========================================================================

    private void Awake()
    {
        if (s_instance != null && s_instance != this)
        {
            Destroy(gameObject);
            return;
        }
        s_instance = this;
        Loadlist = new List<string>();
        DebugLogger.Info("[WebDownLoadManager] Awake, instance ready");
    }

    private void OnDestroy()
    {
        if (s_instance == this) s_instance = null;
        AbortAll();
        ReleaseLuaCallbacks();
    }

    void AbortAll()
    {
        foreach (var d in wlist)
        {
            try { d.www?.Dispose(); } catch { }
        }
        wlist.Clear();
    }

    // =========================================================================
    // 进度 / 初始化（照搬旧项目）
    // =========================================================================

    public double GetTotalDownLoad()
    {
        var list = LocalVersion.GetUnLoadedList();
        if (list.Count == 0) return -1;
        double total = 0;
        for (int i = 0; i < list.Count; i++) total += list[i].Size;
        return total;
    }

    public void Init()
    {
        isPause = true; // 旧项目默认暂停，由调用方 Resume 触发
        LocalVersion.SetUnLoadedList();
        _totalDownload = GetTotalDownLoad();
        DebugLogger.Info("[WebDownLoadManager] Init, totalDownload={0}", _totalDownload);
    }

    public void Pause() => isPause = true;

    public void Resume()
    {
        isPause = false;
        if (Loadlist.Count > 0) DownLoadByName(Loadlist[0]);
        else DownLoadOne();
    }

    // =========================================================================
    // 下载驱动（照搬旧项目状态机）
    // =========================================================================

    public void DownLoadOne()
    {
        if (isPause) return;

        if (loadedInfo == null)
        {
            var info = LocalVersion.GetUnLoadedFile();
            if (info != null)
            {
                AddDownloadItem(info);
            }
            else
            {
                LocalVersion.Write(FileUtils.ToPersistentPathSys("versions.csv"));
                _currentDownload = _totalDownload;
                downLoadCall?.Action<string>("All");
                OnAllDownloaded?.Invoke();
                DebugLogger.Info("[WebDownLoadManager] All download finished");
            }
        }
    }

    public void DownLoadList(string bundle)
    {
        if (isPause) return;
        currentBundle = bundle;
        dowloadIsSpecific = true;
        if (Loadlist.Count > 0) DownLoadByName(Loadlist[0]);
    }

    public void DownLoadByName(string name)
    {
        var info = LocalVersion.GetFileInfo(name);
        if (info == loadedInfo)
        {
            if (Loadlist.Count > 0) Loadlist.RemoveAt(0);
            return;
        }

        if (loadedInfo == null)
        {
            // isload==2: 该项需要下载（沿用旧项目约定）
            if (info != null && info.isload == 2) AddDownloadItem(info);
        }
    }

    void AddDownloadItem(VersionFile.FileInfo fileInfo)
    {
        loadedInfo = fileInfo;
        string remoteUrl = FileUtils.ToRemoteAssetUrl(fileInfo.cdnDir + "/" + fileInfo.Path);
        var www = UnityWebRequest.Get(remoteUrl);
        wlist.Add(new DownloadItem
        {
            www = www,
            FileInfo = fileInfo,
            createTime = Time.time
        });
        www.SendWebRequest();
        DebugLogger.Debug("[WebDownLoadManager] Start download: {0}", remoteUrl);
    }

    // =========================================================================
    // 帧轮询（优化: 超时/出错按文件独立重试，超限真正放弃并继续）
    // =========================================================================

    void Update()
    {
        if (wlist.Count == 0) return;

        for (int i = wlist.Count - 1; i >= 0; i--)
        {
            var d = wlist[i];

            // 超时重发
            if (d.resend || (Time.time - d.createTime > DownloadTimeout))
            {
                d.resend = false;
                if (++d.retryCount > MaxRetry) { FailItem(d, i, "timeout"); continue; }
                Redownload(d);
                continue;
            }

            var www = d.www;
            bool inProgress = www.result == UnityWebRequest.Result.InProgress;

            if (!inProgress && www.result != UnityWebRequest.Result.Success)
            {
                if (++d.retryCount > MaxRetry) { FailItem(d, i, www.error); continue; }
                DebugLogger.Warn("[WebDownLoadManager] Download error, retry({0}): {1}",
                    d.retryCount, www.error);
                Redownload(d);
                continue;
            }

            if (www.isDone && www.result == UnityWebRequest.Result.Success)
            {
                SaveFile(d.FileInfo, www.downloadHandler.data);
                wlist.RemoveAt(i);
                www.Dispose();
            }
        }
    }

    void Redownload(DownloadItem d)
    {
        try { d.www?.Dispose(); } catch { }
        string remoteUrl = FileUtils.ToRemoteAssetUrl(d.FileInfo.cdnDir + "/" + d.FileInfo.Path);
        var www = UnityWebRequest.Get(remoteUrl);
        d.www = www;
        d.createTime = Time.time;
        www.SendWebRequest();
    }

    void FailItem(DownloadItem d, int index, string reason)
    {
        DebugLogger.Error("[WebDownLoadManager] Give up after retries: {0} ({1})", d.FileInfo.Path, reason);
        try { d.www?.Dispose(); } catch { }
        wlist.RemoveAt(index);
        Loadlist.Remove(d.FileInfo.Path);
        if (loadedInfo == d.FileInfo) loadedInfo = null;
        OnError?.Invoke(d.FileInfo.Path);
        if (!isPause) DownLoadOne(); // 失败也继续下一项，不卡死
    }

    void SaveFile(VersionFile.FileInfo fileInfo, byte[] bytes)
    {
        string des = FileUtils.ToPersistentPathSys(fileInfo.Path);
        FileUtils.SafeWriteAllBytes(des, bytes);
        fileInfo.isInPersistentPath = 1;
        fileInfo.isload = 1;

        // 定期持久化清单进度（旧项目每 15s 写一次）
        if (Time.time - wversionTime > 15)
        {
            wversionTime = Time.time;
            LocalVersion.Write(FileUtils.ToPersistentPathSys("versions.csv"));
            loadSaveCall?.Call();
        }

        LocalVersion.RemoveLoadedList(fileInfo);
        _currentDownload += fileInfo.Size;
        downLoadCall?.Action<string>(fileInfo.Path);
        OnFileDownloaded?.Invoke(fileInfo.Path);

        Loadlist.Remove(fileInfo.Path);
        loadedInfo = null;

        if (Loadlist.Count == 0)
        {
            if (dowloadIsSpecific)
            {
                dowloadIsSpecific = false;
                callLua?.Action<string>(currentBundle);
            }
            if (!isPause) DownLoadOne();
        }
        else if (!isPause)
        {
            DownLoadByName(Loadlist[0]);
        }
    }

    // =========================================================================
    // 下载项
    // =========================================================================

    class DownloadItem
    {
        public VersionFile.FileInfo FileInfo;
        public UnityWebRequest www;
        public float createTime;
        public int retryCount;
        public bool resend = false;
    }
}
