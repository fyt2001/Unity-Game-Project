# 新项目 C# 框架层 - 腾讯级生产标准

> 从 `ShaoNvClient_H02`（幻域神姬）提炼精华，移植到新项目。

## 目录结构

共 **13 个子目录**；`.cs` 文件数量以磁盘为准，本文不再维护硬编码计数（历史上曾写 48，已过期）。下表是历史清单，可能与磁盘不完全一致。P1-0 已删除 `Battle/BattleView.cs` 与 `Debug/DebugBattlePanel.cs`、`Debug/TestInputSimulator.cs`（三者全工程 0 挂载、Lua 侧 0 引用）。

> 历史校验脚本路径 `C:/Unity_1/tools/verify_readme_tree.py` 在目录迁移后已失效，且该脚本当前不存在。在重新提供校验脚本之前，不要把本树当作基线。工程主路径现为 `C:/ProjectsRoot/Unity_1/My project`。

```
Assets/Game/Scripts/
├── Core/                        # 核心框架
│   ├── GameLaunch.cs            # 启动流程编排器（7 段 LaunchPhase 协程链，DDOL 单入口）
│   ├── XLuaManager.cs           # XLua管理器（CustomLoader/SafeDoString/Macro/热重载）
│   ├── Tick.cs                  # 全局Tick驱动系统（Update/LateUpdate/FixedUpdate统一管理）
│   ├── MonoSingleton.cs         # MonoBehaviour 单例基类（线程安全双重检查锁）
│   ├── Singleton.cs             # 纯C#类单例基类
│   ├── UpdateMgr.cs             # 热更版本对比 / 首包更新（照搬 H02 并优化）
│   ├── WebDownLoadManager.cs    # 热更静默下载管理
│   ├── WebRequestLua.cs         # Lua 侧 HTTP 请求桥
│   ├── AssetBundleManager.cs    # AssetBundle 管理器
│   ├── AssetBundleLoadOperation.cs # AB 异步加载操作封装
│   ├── AssetBundleUtility.cs    # AB 平台工具类（平台名/路径规则）
│   ├── LuaBundleLoader.cs       # Lua 脚本 AB 加载器（多平台）
│   ├── AtlasBinder.cs           # 把 AB 中的 SpriteAtlas 绑定到运行时 sprite
│   ├── HotfixSettings.cs        # 热更配置（取代 H02 RuntimeSettings）
│   ├── UIAssetBundleHelper.cs   # Lua 访问 AB 的非泛型桥（XLua 调不了未登记泛型，需登记 [LuaCallCSharp]）
│   └── Storage/                 # 可写存储抽象（多平台兼容）
│       ├── IStorage.cs          # 存储接口
│       ├── Storage.cs           # 存储门面（静态入口，支持运行时注入）
│       └── FileStorage.cs       # 默认实现（System.IO）
│
├── Common/                      # 通用
│   └── VersionFile.cs           # 热更版本清单（对齐 H02 VersionFile）
│
├── GameLaunch/                  # 启动 / 场景引导层
│   ├── HomeSceneBootstrapper.cs # 正式表现层：摇杆输入桥接 + 俯视相机跟随 + Transform 同步
│   ├── LuaGameBootstrap.cs      # legacy 战斗入口（正式链路中主动让路，见「入口约定」文档）
│   ├── LuaViewBehaviour.cs      # 挂在实体 GameObject 上的通用 Lua 组件（Bind→New→OnCreate）
│   └── LuaPathConfig.cs         # Lua 路径配置（ScriptableObject）
│
├── Character/                   # 角色视图（Spine 2D / 3D 双实现）
│   ├── ICharacterView.cs        # 角色视图统一接口（上层只依赖此接口）
│   ├── CharacterView.cs         # 状态词表 CharacterState（对齐 .playable 命名约定）
│   ├── Model3DCharacterView.cs  # 3D 角色视图实现
│   ├── SpineCharacterView.cs    # Spine（2D 骨骼）角色视图实现
│   └── PlaceholderCharacter.cs  # 兼容层（逻辑已上移到 Model3DCharacterView）
│
├── Camera/                      # 相机
│   └── TopDownCameraFollow.cs   # 俯视角跟随 + 滚轮缩放（正交/透视双模式）
│
├── Input/                       # 输入
│   └── VirtualJoystick.cs       # 虚拟摇杆（JoystickMoveEvent / 中性复位）
│
├── Interaction/                 # 场景交互
│   ├── Interactable.cs          # 可交互对象（射线命中 / 一次性触发 / MeshCollider 辅助）
│   └── InteractionController.cs # 交互控制器（最近命中 + UI 遮挡检查 + 悬停查询）
│
├── UI/                          # UI组件
│   ├── UIComponentBinder.cs     # Lua UI组件自动绑定系统（命名约定驱动）
│   ├── EnhancedButton.cs        # 增强版Button（修复Bug/两阶段动画/Pointer事件）
│   ├── ButtonPressScale.cs      # 按钮点击缩放反馈
│   ├── UpdateUICanvasScaler.cs  # UI 分辨率自适应
│   └── Login/LoginCharClicker.cs # 登录面板 3D 角色点击交互（纯 C#，不依赖 XLua）
│
├── VFX/                         # 特效
│   ├── MoveClickIndicator.cs    # 移动点击指示器（扩散波 + 水平圆环）
│   └── CasualRPGVFX_UVScroller.cs # 第三方 VFX 包「丢失脚本」的重建版
│
├── Extension/                   # 扩展方法库
│   ├── UnityExtension.cs        # Unity扩展（GameObject/Transform/RectTransform/UI便捷API）
│   ├── StringExtension.cs       # 字符串扩展（正则/格式化/截取/转换）
│   └── CollectionExtension.cs   # 集合扩展（遍历/安全获取/Implode拼接）
│
├── Debug/                       # 调试工具
│   ├── DebugLogger.cs           # 企业级日志系统（时间戳/分级/文件持久化）
│   └── TimeProfiler.cs          # 轻量级性能计时器（纳秒精度/统计/Dump）
│
├── Utils/                       # 工具类
│   ├── JsonUtils.cs             # JSON工具（序列化/反序列化/文件读写）
│   ├── FileUtils.cs             # 文件工具（安全读写/MD5/路径管理）
│   ├── CryptoUtils.cs           # 加密工具（XOR/AES/Base64/哈希；⚠ 全库零调用，见 P1-1 审计）
│   └── MissingGlyphWatcher.cs   # 运行时缺字监视器（TMP 原生警告捕获，仅 EDITOR/DEVELOPMENT_BUILD）
│
└── Resource/                    # 资源管理（目录保留，原 3 个文件已随 P0-4 删除，现为空）
```

编辑器工具**不在** Scripts 下，而在其兄弟目录 `Assets/Editor/`：

```
Assets/Editor/                   # 编辑器工具
├── UIComponentBinderEditor.cs   # UI绑定可视化编辑器（自动绑定+代码生成）
├── MVCGenerator.cs              # Lua MVC代码生成器（一键创建Model/View/Ctrl）
└── BuildTools.cs                # 构建工具集（打包/版本管理/Jenkins CI）
```

## 核心设计思想

### 1. 命名约定驱动 (Convention over Configuration)
- `UIComponentBinder` 通过 `m_`/`mi_`/`c_`/`ci_` 前缀自动发现并绑定UI组件
- 编辑器工具将此约定同步到 Lua 代码

### 2. 启动链编排 (Launch Pipeline)
- `GameLaunch` 提供 7 段 `LaunchPhase` 协程启动链：InitLogger → InitFileSystem → InitResources → InitLua → InitModules → StartGame → Complete
- 进度回调 + 错误处理 + 可扩展的启动任务注册

### 3. 全局 Tick 驱动 (Centralized Update)
- `Tick` 类统一管理 Update/LateUpdate/FixedUpdate 回调
- 支持优先级排序 + 动态注册/注销

### 4. 线程安全单例 (Thread-Safe Singleton)
- `MonoSingleton` / `Singleton` 两种单例模式
- 双重检查锁保证线程安全

### 5. 流畅扩展方法 (Fluent API)
- Unity/字符串/集合三大扩展方法库
- 安全空检查 + 异常捕获 + 链式调用

## 使用方式

### 场景配置
```
GameObject "Boot"
  └── GameLaunch (脚本挂载)
       ├── LuaLoadMode: Editor (编辑器) / Device (真机)
       ├── AutoInitResources: false (默认Resources模式)
       └── ShowProgress: false
```

### 启动流程
1. `GameLaunch.Start()` → 协程启动链
2. 每个阶段通过 `SetPhase()` 更新进度
3. Lua 初始化 → Framework 加载 → GameMain 加载
4. `Tick.OnUpdate()` 驱动整个游戏循环

### 编辑器工具
- `Tools/MVC/生成 UI 模块` → 一键创建 Model/View/Ctrl
- `Tools/Build/构建 Android APK` → 一键打包
- `Tools/Build/复制 Lua 脚本到 Resources` → 同步Lua代码
- `UIComponentBinder` Inspector → 自动绑定 + 生成Lua代码

## 与旧项目 (ShaoNvClient_H02) 的关系

| 新项目模块 | 旧项目来源 | 升级点 |
|-----------|-----------|--------|
| MonoSingleton | MonoSingleton | 增加线程安全双重检查锁 |
| DebugLogger | GoldenLogger | 增加日志级别、文件轮转 |
| Tick | GameLaunch.Tick | 增加优先级排序、动态注册 |
| XLuaManager | XLuaManager | 统一CustomLoader、SafeDoString兼容 |
| GameLaunch | GameLaunch | 阶段枚举、进度回调、可扩展 |
| UIComponentBinder | GoldenLuaUIComponent | 去除TMPro/Spine依赖、提取核心 |
| EnhancedButton | GoldenButton+GoldenButtonAnim2S | 合并两个组件 |
| MVCGenerator | MVCTools+GoldenLuaUIComponentManager | 独立代码生成器 |
| BuildTools | BuildToolWindow+ProjectBuildTools | 独立构建工具集 |

## 版本历史

- v1.1.1 (2026-10-03): 基线纠正 —— **46 → 48 个 .cs**，补登漏记的 `Core/UIAssetBundleHelper.cs`（Lua 侧 AB 非泛型桥）与 `Utils/MissingGlyphWatcher.cs`（运行时缺字监视器）；`CryptoUtils` 补注「全库零调用」；新增基线校验工具 `C:/Unity_1/tools/verify_readme_tree.py`，此后「与真实结构逐一双向对照通过」这句必须以该脚本退出码 0 为前提。**本版未改动任何 C# 代码。**
- v1.1.0 (2026-10-01): P0 技术定锚（Class 收敛 / 入口转正 / C# 死代码清理 / luacheck 门禁）+ P1-0（删 3 个 Debug 件）；目录树补全为**完整版**（当时写 13 目录 / 46 文件，**计数有误，见 v1.1.1**）
- v1.0.0 (2026-08-04): 初始版本，从 ShaoNvClient_H02 提炼精华移植
