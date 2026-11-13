# My project — UI 框架规范化进度总结

> 目标：对齐 `ShaoNvClient_H02` 的「零 Find + 组件化」UI 框架设计意图，在 My project 的 `BaseClass`（XLua）体系上重建一套可维护、低耦合、可扩展的 UI 框架，并裁剪 H02 的业务依赖。
> 最后更新：2026-09-23（P1 全部落地）

---

## 1. 已落地成果

### 1.1 组件体系（零 Find + 组件化）
| 组件类 | 底层 Unity 组件 | 后缀约定 | 状态 |
|---|---|---|---|
| `UIButton` | Button | `_Btn` | ✅ |
| `UIText` | Text / TMP | `_Txt` | ✅ |
| `UIImage` | Image | `_Img` | ✅ |
| `UIRawImage` | RawImage | `_RawImg` | ✅ |
| `UIToggle` | Toggle | `_Tog` | ✅ |
| `UISlider` | Slider | `_Sld` | ✅ |
| `UIScrollRect` | ScrollRect | `_Srt` | ✅ |
| `UIScrollbar` | Scrollbar | `_Slb` | ✅ |
| `UIInputField` | InputField | `_Ipt` | ✅ |
| `UINode` | 纯 Transform | `_Transform` | ✅ |

未实现（AutoBind 遇之安全跳过）：`UIDropdown`(`_Dpd`) / `UIAnimation`(`_Ani`) / `UIAnimator`(`_Anr`)。

### 1.2 基础设施
- `UIUtil`：`FindXxx` 系列（走 `_searchComponent(transform, typeof(...))`），统一底层组件查找入口。
- `UIBaseContainer`：`AutoBind()` + `_ABBR_TO_CLASS`（含易错项 `Slb`/`Ipt`）+ `AddComponent` 按 GameObject 查重 + `BindLuaUIComp`。
- `UIBaseComponent`：组件基类；`OnCreate` 统一 `self.__uiComp or UIUtil.FindXxx(self.transform)`，`OnDestroy` 清理监听、释放 `unity_xxx`。
- `BaseClass`：My project 的 Lua 类系统（XLua，非 H02 的 `Class` 旧体系）。

### 1.3 防御性空判断（统一 `IsNull`）
所有组件访问底层 userdata 前统一 `IsNull` 判空。
`UIButton` / `UIImage` / `UIToggle` 由裸 `nil` 判空整改为 `IsNull`（修复底层组件 `Destroy` 后 userdata 非空但失效的误调用）；其余组件本就用 `IsNull`。已写入强制规范。

### 1.4 多语言 i18n（全项目落地）
- `Framework/UI/Utils/Lang.lua`：文案表入口，`Lang.Get(key)` 缺 key 返回 key。
- 接入：`LoginView` / `LoadingView` / `LoadingModel` / `LoadingManager`。
- `Game/UI` 下运行期已无硬编码中文残留（仅注释内的示例文案）。

### 1.5 对象池与虚拟滚动列表
- `Core/ObjectPool`：Lua table 对象池（技能 / Buff / 伤害信息等纯 Lua 数据复用）。
- `UI/Utils/PrefabPool`：GameObject 级对象池（列表 Item / 飘字 / 图标等 UI 实例复用，避免频繁 `Instantiate/Destroy`）。
- `UI/Component/UIListView`：垂直虚拟滚动列表，仅实例化「可视区 + 2 缓冲区」的 Item，滚动时自动回收 / 取出，Item GO 经 `PrefabPool` 复用。

> 对齐说明：H02 的 `UISuperScroll` 依赖第三方 C# 插件 `UnitySuperScrollView`（`SuperScrollView_LoopListView2`）。My project 无此插件，故以**纯 Lua** 的 `UIListView` + `PrefabPool` 提供等效能力，未移植其 C# 包装层。组件化 Item（`UISuperItemBase`）与网格（GridView）列为后续扩展点。

### 1.6 业务接入
- `LoginView`：纯 AutoBind + 路径兜底写法。
- `Loading` 模块：经 `Lang` 取文案。

### 1.7 规范文档
- `Framework/UI/Component/ComponentBinding.md`：给业务开发者的组件绑定与使用说明（含 `UIListView` / `PrefabPool` 第 8 节）。
- `ui-framework-conventions`（规则）：AI 自用强制规范（零 Find、组件化、`__uiComp` 回退、`m_` 命名、监听自清理、依赖裁剪、复用 / 封装 / 可读性纪律、P0–P2 Roadmap）。
- `lua-coding-standards`（规则）：语言级 Lua 规范（强制 `local`、命名风格、缩进 / 行宽、`require` 顺序、文件头注释、禁用 `module()` / 随意 `_G` / 魔法数字）。

---

## 2. 对齐 H02 的差异清单（裁剪 / 对齐说明）

| 维度 | H02 | My project | 说明 |
|---|---|---|---|
| AutoBind | 默认手动 `AddComponent`（`BindCs` 被注释） | `UIBaseContainer.OnCreate` 直接 `AutoBind` | My project 实现了 H02 设计意图里的「自动 New 组件 + 零 Find」 |
| `UIToggle` 继承 | `UIBaseContainer`（当容器） | `UIBaseComponent`（组件，内部懒找 Text） | 与 `UIButton` 风格一致 |
| 依赖裁剪 | 含 DOTween / ScrollRectTweener / 异步纹理 / 置灰 / `logUIComp` | 全部裁剪，仅保留核心 API | 去 `UISlider` 动画、`UIScrollRect` Tweener、`UIRawImage` 异步纹理、`UIInputField` 告警等 |
| 类系统 | 旧 `Class` 体系 | `BaseClass`（XLua） | 禁止引入 H02 `Class` 旧体系 |
| 列表 / 虚拟滚动 | 第三方插件 `UnitySuperScrollView`（`UISuperScroll` 包装） | 纯 Lua `UIListView` + `PrefabPool` | My project 无插件，纯 Lua 等效 |
| 查重安全 | — | `AddComponent` 内部 `_FindComponentByGO` 按 GO+类型查重 | AutoBind（零 Find）与手动 `AddComponent`（路径）可安全共存、不重复实例化 |

---

## 3. Roadmap（对标腾讯级大厂规范）

### P0 — 语言 / 质量基础设施
| 项 | 状态 |
|---|---|
| 语言级 Lua 规范 | ✅ 已单列为 `lua-coding-standards` 规则 |
| 静态检查门禁（luacheck + 全局白名单 `.luacheckrc` + pre-commit / CI） | ⬜ 未做（当前仅 EmmyLua 编辑器提示，无强制门禁） |
| 统一日志规范（分级 DEBUG/INFO/WARN/ERROR + 模块 tag） | ✅ 基础设施已落地（`Framework/UI/Utils/Logger.lua` 分级 + 模块 tag + 多 Sink；`UIWindow`/`UIManager` 已用 `Logger.Debug/Info/Warn/Error`）；约定新增日志统一走 `Logger.Xxx(tag, fmt)`，禁止 `print`/`LogRed` 等无分级写法，业务层既有 `print` 散用列为后续清理 |

### P1 — 线上稳定性与扩展成本
| 项 | 状态 |
|---|---|
| 防御性 `IsNull` 统一 | ✅ |
| 多语言 i18n（全项目） | ✅ |
| UI 列表对象池 / 虚拟滚动 | ✅ |

### P2 — 团队规模化后显价值
| 项 | 状态 |
|---|---|
| 可观测性（UI 打开耗时打点 + Dump 快照） | ✅ 最小钩子已落地（`UIManager:Open`→`WindowOpened` 全链路耗时经 `Logger.Info` 输出；崩溃 / 性能监控 SDK、内存打点为后续） |
| 测试体系（框架组件可测性契约 + 引入单测框架） | 🔶 方案已定：组件可测性契约已具备，待 CI 环境引入 busted / luaunit 跑纯逻辑组件单测 |
| 协作文档（ADR、CHANGELOG、模块 owner） | ✅ 起步已沉淀（`UI_FRAMEWORK_STATUS.md` / `RULE.mdc` / `lua-coding-standards`） |

---

## 4. 已具备基线（不重复造，仅记录）
零 Find + 组件化 + AutoBind；统一 `m_` 命名约定；监听生命周期自清理；复用 / 封装 / 可读性纪律（第 10 节）；依赖裁剪解耦。

---

## 5. 后续待办（按优先级）
1. **P0 静态检查门禁**：引入 `luacheck` + 声明 `CS` / `typeof` / `IsNull` / `Unity_*` 全局白名单的 `.luacheckrc`，配置 pre-commit hook 与 CI 跑 lint（把当前 EmmyLua 误报转成可自动化检查的真实门禁）。
2. **P0 统一日志规范**：日志分级 + 模块 tag + 结构化；替换散用无分级写法。
3. **P2 测试体系**：框架组件可测性 + 单元测试；UI 冒烟 / 自动化。
4. **P2 可观测性**：崩溃 / 性能监控接入；UI 打开耗时、内存打点。
5. **P2 协作文档**：ADR、CHANGELOG、模块 owner、Breaking change 声明。
6. **扩展**：`UIListView` 动态高度 / 网格（GridView）；组件化 Item（`UISuperItemBase` 模式）。
