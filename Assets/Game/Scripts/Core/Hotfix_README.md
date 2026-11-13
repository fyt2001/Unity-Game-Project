# 热更系统说明（Hotfix README）

> 对齐来源：`ShaoNvClient_H02`（WebDownLoadManager / UpdateMgr）
> 适用项目：`My project`（Lua 战斗 + AB 资源 + xLua）
> 最后整理：2026-09-28

---

## 一、整体架构：两段式热更

| 阶段 | 类 | 触发时机 | 职责 |
|---|---|---|---|
| **前台 / 启动期** | `UpdateMgr` | `GameLaunch` 启动序列（`InitFileSystem` 之后） | 拉远端 `versions.csv` → 与本地 diff → 逐个下载到 persistent → 合并清单落盘 |
| **后台 / 运行期** | `WebDownLoadManager` | Lua `GameMain.Init` 调 `Resume()` | 取清单里 `isload == 2` 的项，静默后台补下载（不打断游戏） |

两者共享同一份本地清单 `GameLaunch.localVersion`（`VersionFile`）：`UpdateMgr` 写、`WebDownLoadManager` 读，是**同一个对象引用**（启动序列里 `WebDownLoadManager.Get().LocalVersion = localVersion`）。

---

## 二、数据流

```
启动
 │
 ├─ 读本地 versions.csv ──────────────► GameLaunch.localVersion (VersionFile)
 │                                        │
 ├─ UpdateMgr.Initializer()               │
 │    ├─ [可选] LatestVersionUrl 闸门      │
 │    ├─ 下载 远端 versions.csv ──────────┘
 │    ├─ MakeUpdateInfo(远端) → 差集（缺失 / 版本不符 / 未落地）
 │    ├─ 逐文件 UnityWebRequest 下载 → SafeWriteAllBytes 落 persistent
 │    └─ Renew(差集, 远端版本号) → 回写 localVersion + 落盘 versions.csv
 │                                        │
 └─ Lua GameMain.Init → WebDownLoadManager:Init / SetLuaCall / Resume
      └─ SetUnLoadedList() 取 isload==2 项 → 后台静默下载（Update 轮询状态机）
```

`isload` 约定（沿用旧项目）：

- `0` 未处理
- `1` 已落地
- `2` 延迟下载项（交给 `WebDownLoadManager` 后台补）

---

## 三、各文件职责

| 文件 | 目录 | 职责 |
|---|---|---|
| `VersionFile.cs` | `Common/` | CSV 版本清单。`FromString` / `FromFile` / `Write`、`SetUnLoadedList` / `GetUnLoadedFile` / `GetFileInfo` / `RemoveLoadedList`、`MakeUpdateInfo`（差集）、`Renew`（合并）。`Size` 用 `long`，无第三方 CSV 库。 |
| `FileUtils.cs` | `Utils/` | 路径助手：`RemoteAssetUrl` / `ToRemoteAssetUrl` / `ToPersistentPathSys` / `PersistentPathSys` / `CreateDirectoryForFile` / `SafeWriteAllBytes`。 |
| `HotfixSettings.cs` | `Core/` | 热更配置：`RemoteAssetUrl`(CDN 根)、`VersionCsvName`、`LatestVersionUrl`(可选闸门)、`AutoUpdateEnabled`。 |
| `UpdateMgr.cs` | `Core/` | 前台 diff 更新，单协程，进度经 `GameLaunch.UpdateProgressUI` 反馈。 |
| `WebDownLoadManager.cs` | `Core/` | 后台静默下载状态机（UnityWebRequest + `Update` 轮询），每文件独立重试、超时重发、销毁中断、C# 事件 + Lua 回调。 |
| `GameLaunch.cs` | `Core/` | 启动序列里加载本地清单 →（配置就绪时）跑 `UpdateMgr` → 注入 `WebDownLoadManager.LocalVersion`。 |
| `GameMain.lua` | `LuaScripts/Game/` | `Init` 里 `pcall` 容错调 `WebDownLoadManager` 三回调：`WebFileDownLoaded` / `WebFileDownLoadOne` / `WebFileDownLoadSave`。 |

---

## 四、启动序列位置（`GameLaunch.LaunchSequence`）

```csharp
// 1. InitFileSystem 阶段：加载本地清单 + 注入 WebDownLoadManager
var vfPath = FileUtils.ToPersistentPathSys("versions.csv");
localVersion = VersionFile.FromFile(vfPath) ?? new VersionFile();
WebDownLoadManager.Ensure();
WebDownLoadManager.Get().LocalVersion = localVersion;

// 2. 配置就绪才跑前台热更（CDN 未配置或开关关闭则跳过，开发期不阻断启动）
if (HotfixSettings.AutoUpdateEnabled && !string.IsNullOrEmpty(HotfixSettings.RemoteAssetUrl))
{
    SetPhase(LaunchPhase.InitFileSystem, 0.15f, "检查热更...");
    UpdateMgr.Ensure();
    yield return StartCoroutine(UpdateMgr.Get().Initializer());
}
```

---

## 五、相对旧项目的优化

1. **去掉 `FirstDownLoadManager`（31KB 首包拷贝）**：新项目初始资源走 AB / StreamingAssets（`AssetBundleManager`），`UpdateMgr` 只做远端 diff，不重复造拷贝层。
2. **去掉 `Versions` 版本比较类**：改为 `VersionFile` 文件级 diff（`MakeUpdateInfo`），自包含。
3. **去掉后台 `Thread` 写文件**（`UpdateThreadSaveTask` 还跨线程访问 `localVersion`，不安全）→ 单协程「下载即落盘」，无竞态、无 `Thread.Abort`。
4. **去掉 `WaitForSeconds(10000000)` 死等**与 `isNetworkError/isHttpError` → `UnityWebRequest.Result`；更新失败仅告警并继续启动（不卡死）。
5. **`WebDownLoadManager` 重试死循环修复**：旧 `downloaderrorcount > 3` 只 reset 不处理 → 卡死；改为每文件 `retryCount` 超限真正放弃并继续下一项。

---

## 六、待接入的占位点（上线前补齐）

- **`HotfixSettings.RemoteAssetUrl`** = 真实 CDN 根（如 `https://cdn.xxx.com/hotfix/`）。
  *留空则启动自动跳过热更，开发期不阻断。*
- **`HotfixSettings.LatestVersionUrl`**：可选强制更新闸门（game.json）。
- **一份真实的 `versions.csv`**（首行版本号，后续 `Path,Version,Size,isload,isInPersistentPath,cdnDir`），放 CDN 根。
- **XLua → Generate Code**：`WebDownLoadManager` 已加 `[LuaCallCSharp]`，否则 Lua 侧 `CS.WebDownLoadManager` 为 nil（已用 `pcall` 兜底，不影响启动）。

---

## 七、版本清单（versions.csv）格式

```
<版本号，如 1.0.3>
Path,Version,Size,isload,isInPersistentPath,cdnDir
ui/atlas/a.png,1,12345,1,0,
lua/game/battle.lua,2,678,2,0,        # isload==2 → 后台静默下载
config/c.json,1,99,1,0,
```

- 首行：整体版本号（`VersionFile.Version`）。
- 后续每行一个文件；`UpdateMgr` 用 `Path+Version` 与本地比对出差集。
- `isload==2` 的项由 `WebDownLoadManager` 在游戏运行时后台补下载。
