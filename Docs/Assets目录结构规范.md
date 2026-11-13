# Assets 目录结构规范（推荐）

> 适用范围：`My project`（Unity 2021.3 + XLua + 自研 MVC UI 框架）
> 目的：收敛当前「根级 `Assets/Scripts` / `Assets/Resources` 与 `Game/` 下平行目录混用、空占位文件夹散落」的混乱。
> 本文只给规范，不移动文件。确认后再按最后一节执行。

## 一、总原则

1. **游戏自有代码/资源统一收敛到 `Assets/Game/`**，不在 `Assets/` 根级另开一套 `Scripts` / `Resources` 平行目录。
2. **第三方包保留在 `Assets/` 根，不纳入 `Game/`**：`XLua`、`ThirdParty`（Spine 等，含自身 asmdef）、`TextMesh Pro`、`Plugins`。
3. **只有需要 `Resources.Load` 加载的资源才放 `Resources/`**；其余放 `Prefabs/` 或 `AssetsPackage/`。UI 窗口 prefab 必须放 `Resources/UI/<窗口名>/`，因为框架按 `UIWindowConfig.prefab = "UI/<窗口名>"` 从 `Game/Resources` 加载。
4. **编辑器脚本放 `Editor/` 目录**（Unity 自动排除出运行时程序集），不要散在普通脚本目录。
5. **移动 `.cs` 必须连同 `.meta` 一起移动**：GUID 不变，prefab / 材质 / 其他脚本对它的引用不丢。
6. 本项目的游戏 C# **没有 asmdef**（全在默认 `Assembly-CSharp`），所以跨目录移动不改变程序集归属，安全。

## 二、推荐结构

```
Assets/
├─ Game/                       # 游戏自有（核心整理目标）
│  ├─ LuaScripts/              # 全部 Lua（框架 + 游戏）
│  │  ├─ Framework/            # 框架：UI/Core/Manager/Base/Config/...
│  │  └─ Game/
│  │     ├─ UI/                # 各窗口 MVC：Home / Login / Dungeon / GM / Loading
│  │     ├─ Dungeon/           # 副本 / 战斗逻辑（DungeonManager 等）
│  │     ├─ GM/                # GM 作弊（GMUI / GMCommands / GMConfig）
│  │     └─ ...
│  ├─ Scripts/                 # 全部游戏 C#（不再分根级 Assets/Scripts）
│  │  ├─ Character/            # 角色视图：CharacterView / Model3DCharacterView / SpineCharacterView / ICharacterView
│  │  ├─ UI/                   # UI 辅助：EnhancedButton / UIComponentBinder / ButtonPressScale / UpdateUICanvasScaler
│  │  ├─ Debug/                # 调试：DebugLogger / TimeProfiler
│  │  ├─ Core/                 # 核心桥接（框架与 C# 的粘合层）
│  │  ├─ Common/ Utils/ Extension/ Interaction/ Resource/ VFX/
│  │  └─ LuaGameBootstrap.cs / LuaUpdateDriver.cs / LuaViewBehaviour.cs / LuaPathConfig.cs  # 启动文件
│  ├─ Resources/               # 仅放 Resources.Load 资源
│  │  ├─ UI/                   # UI prefab：Home / Login / Dungeon / GM / Loading
│  │  ├─ Shaders/              # 运行时 shader：GridShader / MoveIndicator
│  │  └─ ...
│  ├─ Prefabs/                 # 非 Resources 的普通 prefab（PlaceholderCharacter / QuaterniusHero / BattleViews）
│  ├─ Fonts/                   # 字体
│  ├─ AssetsPackage/           # Addressables / 打包资源
│  └─ Editor/                  # 编辑器脚本（ViewPrefabBuilder 等）
├─ Editor/                     # 仅放“与具体游戏无关”的通用编辑器工具；游戏相关请并入 Game/Editor
├─ Plugins/                    # 原生插件（不动）
├─ ThirdParty/                 # 第三方（Spine 等，含自身 asmdef，不动）
├─ XLua/                       # XLua 运行时（不动）
├─ TextMesh Pro/              # TMP（不动）
├─ Scenes/                     # 场景（LaunchScene 等）
└─ Screenshots/               # 运行时截图落盘：建议加 .gitignore 或定期清理，不要提交进版本库
```

> 说明：`Game/Prefabs/` 与 `Game/Resources/` 里都有 prefab 是**合理的**——能 `Resources.Load` 的（UI 窗口等）必须在 `Resources/` 下；普通 prefab 放 `Prefabs/`。这不是混乱点，保留即可。

## 三、当前需要收敛的问题（对应本次审查）

| # | 现状（混乱点） | 规范去向 |
|---|----------------|----------|
| 1 | ✅ **已完成** — `Assets/Scripts/Character/*` 已并入 `Assets/Game/Scripts/Character/`（CharacterView / ICharacterView / Model3DCharacterView / SpineCharacterView + PlaceholderCharacter，共 5 个 .cs） | 根级 `Assets/Scripts/` 已整体删除，`.cs`+`.meta` 成对移动，编译 **0 error** |
| 2 | ✅ **已完成** — `LoginCharClicker.cs` 已迁入 `Assets/Game/Scripts/UI/Login/` | 同上 |
| 3 | ✅ **已完成**（已并入第 1 项） | — |
| 4 | ✅ **已完成** — `Assets/Scripts/Debug/` 空目录已删除 | 连同 `.meta` |
| 5 | ✅ **已完成** — `Assets/Resources/UI/`、`Assets/Resources/Scripts/` 空目录已删除 | 连同 `.meta` |
| 6 | 根级 `Assets/Resources/` 仅 2 个 shader（GridShader / MoveIndicator） | **建议保留**：参考项目 H02 的根级 `Resources/` 同样只放全局 shader / 设置（4 shader + `DOTweenSettings.asset` + 1 txt）。迁移到 `Game/Resources/Shaders/` 属可选优化，非必须 |
| 7 | `Assets/Editor/`（9 个 cs）与 `Assets/Game/Editor/` 并存 | 游戏相关并入 `Game/Editor/`；通用工具保留并注明 |
| 8 | 统一后 `Assets/Scripts/`、`Assets/Resources/` 空壳 | 确认无运行时引用后删除 |

## 四、移动 / 清理安全守则

1. **成对移动**：`.cs` 与同名 `.meta` 必须一起移动（用 Unity 内拖拽，或脚本 `Move-Item` 同时搬两个文件）。
2. **先确认引用**：移动前在代码/资源里搜一下目标脚本类名、shader 名是否被广泛引用（GUID 移动后不变，本应无影响，但确认更稳）。
3. **shader / material**：靠 GUID 引用，移动 `.shader` + `.meta` 即保引用。
4. **asmdef**：当前游戏脚本无 asmdef；Spine 的 asmdef 仅约束 `ThirdParty/Spine`，与本次整理无关。
5. **执行后验证**：让 Unity 刷新 → 看 Console 无编译错误 → 跑一次 Enter Play → 验证 UI 窗口（Home/Login/GM）能正常打开、角色能显示。
6. **删除空壳前**：确认 `Assets/Resources` 的 2 个 shader 已迁走、且没有任何代码用 `Resources.Load("GridShader")` 之类从根级 Resources 取资源；否则保留或同步改加载路径。

## 五、建议落地顺序（确认后）

1. 低风险：删空占位（#4、#5）。
2. 迁 shader（#6）→ 验证战斗网格/移动指示正常。
3. 迁 C# 脚本（#1、#2、#3）→ 编译验证。
4. 处理 `Assets/Editor`（#7）。
5. 删空壳（#8）→ 最终 Enter Play 全量验证。

## 六、对照参考项目（ShaoNvClient_H02）的进阶优化建议

参考项目规模远大于我们（6073 lua / 3624 prefab / 229 cs），但其**分层思路**可直接复用。以下按优先级列出我们还能优化的点。

### 参考项目值得学的做法

1. **Lua 按"职责"分层，而非只按 Framework/Game 二分**
   参考：`Common / Config(1486) / Core / DataCenter(343) / Framework(98) / GameLogic / Global(24) / Net(134+144pb) / UI(3849) / Sdk / Spine / XLua`，另有 `GameTest(7) / UnitTest(12)` 独立测试目录。
   我们：仅 `Common(空) / Framework(60) / Game(76)`，**缺 `Config`、`DataCenter`、`Net`、`Global` 与测试目录**。

2. **UI 窗口统一 `UI` 前缀，一个窗口一个目录**
   参考：`UIBag / UIHero / UILogin / UIGM / UIDungeon ...`（全部窗口目录一律 `UIXxx` 命名）。
   我们：`Game/UI/Home / Login / Dungeon / GM`（无前缀），且 `Dungeon/` 下同时存在副本逻辑与窗口，**UI 与业务逻辑未分离**。

3. **C# 按能力建子目录，不在 Scripts 根散文件**
   参考：`GameLaunch / UICore(37) / Lua(8) / Framework(13) / Core(11) / Common(70) / Utils(16) / Channel / Extensions / XLua / Spine / Effect / RenderTexture / InitUI`。
   我们：`Game/Scripts` 根散放 10 个 .cs（LuaGameBootstrap、LuaUpdateDriver、LuaViewBehaviour、LuaPathConfig、HomeSceneBootstrapper、BattleView、DebugBattlePanel、TestInputSimulator、TopDownCameraFollow、VirtualJoystick）。

4. **AssetsPackage 按"资源类型 + 用途"分大类**
   参考：`Effect / Models / Shaders / Sound(5834 Wwise) / SpinePfb / UI_New(24744) / UI(旧) / ProtoPB / Scene / Video`。
   我们：`Characters / Models / SpinePfb / UI_New / UI / Effect(空)`——方向一致，但缺 `Shaders`、`Sound`，且 `Effect/` 为**空占位**。

5. **约定文档随代码走**
   参考：`LuaScripts/代码规范.txt`、`TODO.txt`、`Macro说明.txt`；调试脚本（`LuaDebug / LuaPanda / mobdebug / json`）放 `LuaScripts` 根。
   我们：规范写在 `My project/Docs/`，建议挪到 `Assets/Game/` 下并补一份 Lua 代码规范。

### 本项目优化清单（按优先级）

| 优先级 | 优化项 | 当前状态 | 建议 |
|---|---|---|---|
| P0 | C# 根散文件归类 ✅ **已完成** | `Game/Scripts` 根散放 10 个 .cs | 已建 `GameLaunch/`(5)、`Battle/`(1)、`Camera/`(1)、`Input/`(1)；`DebugBattlePanel` / `TestInputSimulator` 并入已有 `Debug/`。`.cs` + `.meta` 成对移动，Unity 编译 **0 error** |
| P0 | UI 与业务逻辑分离 ✅ 复核后**无需改动** | 原判断有误 | 实为**本就分离**：`Game/UI/Dungeon/` 只有 MVC（View / Model / Controller + Register），`Game/Dungeon/` 只有逻辑（DungeonManager / FloorEventSystem / FloorGenerator / ItemSystem 等） |
| P0 | 清 Lua/C# 空占位 ❌ 判断有误，**不删** | `LuaScripts/Common`、`Game/Build`、`Game/Mod`、`Game/Save` | 复核后**均非空**：分别含 `Define.lua`、`BuildSystem`、`ModSystem`、`SaveManager` 等真实模块，必须保留 |
| P1 | 删真空遗留目录 ✅ **已完成** | `Assets/Scripts/Debug`、`Assets/Resources/UI`、`Assets/Resources/Scripts`、`Assets/Game/Scripts/Character` 已复核 `count=0` | 4 个空目录及其 `.meta` 已删除，Unity 编译 **0 error** |
| P1 | UI 窗口统一 `UI` 前缀 | `Home / Login / Dungeon / GM` | 改名 `UIHome / UILogin / UIDungeon / UIGM`，`Game/Resources/UI/` 下 prefab 目录同步改名 |
| P1 | 补 Lua 分层目录 | 仅 Common/Framework/Game | 预留 `Config / DataCenter / Net / Global / UnitTest`（可先空目录 + README 说明用途，渐进填充） |
| P2 | AssetsPackage 补齐 | 缺 Shaders/Sound；`Effect/` 空占位 | `Shaders/` **非必须**（参考项目把全局 shader 留在根 `Resources/`）；保留根 `Resources` 的 GridShader / MoveIndicator 即可；`Effect/` 空占位可删或填充；预留 `Sound/` |
| P2 | 文档随代码 | 规范在 `My project/Docs/` | 挪到 `Assets/Game/` 下；补 `LuaScripts/代码规范.txt`（Lua 命名 / 分层 / require 约定） |
| P3 | 测试隔离 | 无独立 Lua 测试目录 | 建 `Game/Scripts/Debug`（已有）；Lua 侧建 `UnitTest/`，调试脚本放 `LuaScripts` 根 |

### 不建议照搬的部分

- 参考项目 `ImprotFightEffect/`、`_MainGame/`、`TestFight*.unity` 属其历史遗留 / 临时目录，我们不学。（其根级 `Assets/Resources` **不是**遗留，而是全局 shader / 设置的正规位置，与我们一致。）
- 参考项目**没有 `Game/Resources/`**：其 UI prefab 全在 `Game/AssetsPackage/UI_New/`(1066 prefab) 与 `Game/AssetsPackage/UI/`(1126 prefab)，走自有资源 / AB 体系，**并非 `Resources.Load`**。我们框架依赖 `Game/Resources/UI/` + `ResourcesProvider` 的 `Resources.Load("UI/...")`，**必须保留 `Game/Resources/`**，不能因参考项目没有就删掉。
- 参考 `UI/` 与 `UI_New/` 新旧并存是历史包袱；我们目前以 `UI_New` 为主即可，但应明确 `UI/`（旧）只做兼容、不再新增内容。
- 参考因 6000+ lua / 200+ 窗口导致目录极深；我们规模小，**不要为对齐而过度分层**，P1/P2 按需渐进即可。
