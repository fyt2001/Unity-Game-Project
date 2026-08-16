# 新项目 C# 框架层 - 腾讯级生产标准

> 从 `ShaoNvClient_H02`（幻域神姬）提炼精华，移植到新项目。

## 目录结构

```
Assets/Resources/Scripts/CSharp/
├── Core/                        # 核心框架
│   ├── MonoSingleton.cs         # MonoBehaviour 单例基类（线程安全双重检查锁）
│   ├── Singleton.cs             # 纯C#类单例基类
│   ├── SingletonBehaviour.cs    # 轻量MonoBehaviour单例
│   ├── Tick.cs                  # 全局Tick驱动系统（Update/LateUpdate/FixedUpdate统一管理）
│   ├── XLuaManager.cs           # XLua管理器（CustomLoader/SafeDoString/Macro/热重载）
│   ├── GameLaunch.cs            # 游戏启动流程编排器（6阶段协程启动链）
│   └── LuaBootstrap.cs          # 简化版启动引导器
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
├── Resource/                    # 资源管理
│   ├── GameObjectPool.cs        # GameObject对象池（预热/容量限制/PoolManager全局管理）
│   └── ResourceLoadType.cs      # 统一资源类型枚举
│
├── UI/                          # UI组件
│   ├── UIComponentBinder.cs     # Lua UI组件自动绑定系统（命名约定驱动）
│   └── EnhancedButton.cs        # 增强版Button（修复Bug/两阶段动画/Pointer事件）
│
├── Utils/                       # 工具类
│   ├── JsonUtils.cs             # JSON工具（序列化/反序列化/文件读写）
│   ├── FileUtils.cs             # 文件工具（安全读写/MD5/路径管理）
│   └── CryptoUtils.cs           # 加密工具（XOR/AES/Base64/MD5/SHA256）
│
└── Editor/                      # 编辑器工具
    ├── UIComponentBinderEditor.cs # UI绑定可视化编辑器（自动绑定+代码生成）
    ├── MVCGenerator.cs          # Lua MVC代码生成器（一键创建Model/View/Ctrl）
    └── BuildTools.cs            # 构建工具集（打包/版本管理/Jenkins CI）
```

## 核心设计思想

### 1. 命名约定驱动 (Convention over Configuration)
- `UIComponentBinder` 通过 `m_`/`mi_`/`c_`/`ci_` 前缀自动发现并绑定UI组件
- 编辑器工具将此约定同步到 Lua 代码

### 2. 启动链编排 (Launch Pipeline)
- `GameLaunch` 提供 6 阶段协程启动链：Logger → FileSystem → Resources → Lua → Modules → Game
- 进度回调 + 错误处理 + 可扩展的启动任务注册

### 3. 全局 Tick 驱动 (Centralized Update)
- `Tick` 类统一管理 Update/LateUpdate/FixedUpdate 回调
- 支持优先级排序 + 动态注册/注销

### 4. 线程安全单例 (Thread-Safe Singleton)
- `MonoSingleton` / `Singleton` / `SingletonBehaviour` 三种单例模式
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
| GameObjectPool | AssetFactory | 独立通用池、支持容量限制 |
| MVCGenerator | MVCTools+GoldenLuaUIComponentManager | 独立代码生成器 |
| BuildTools | BuildToolWindow+ProjectBuildTools | 独立构建工具集 |

## 版本历史

- v1.0.0 (2026-08-04): 初始版本，从 ShaoNvClient_H02 提炼精华移植
