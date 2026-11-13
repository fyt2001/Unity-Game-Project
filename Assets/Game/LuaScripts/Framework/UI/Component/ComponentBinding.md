# My project UI 组件自动绑定说明（对齐 ShaoNvClient_H02）

## 1. 设计目标

对齐 H02「零 Find」的设计意图：在 prefab 上挂 `UIComponentBinder`，按命名约定自动收集子节点 UI 组件引用；
运行期由 `UIBaseContainer.AutoBind` 自动 `AddComponent` 出对应 Lua 组件实例并注入根表，**全程不调用 `Transform.Find`**。

每个组件 `OnCreate` 统一采用：

```lua
self.unity_xxx = self.__uiComp or UIUtil.FindXXX(self.transform)
```

- 绑定阶段拿到 userdata → 走 `__uiComp` 分支（**零 Find**）；
- 未绑定（老 prefab） → 走 `UIUtil.FindXXX` 回退分支，兼容不报错。

---

## 2. 命名约定（对应 C# `UIComponentBinder.TypeAbbrMap`）

节点按 `m_xxx_<Abbr>` 命名，`<Abbr>` 由节点上挂载的 Unity 组件类型决定：

| Unity 组件         | 后缀        | Lua 组件类     |
|-------------------|------------|---------------|
| Button            | `_Btn`     | `UIButton`    |
| Text / TextMeshProUGUI| `_Txt`     | `UIText`      |
| Image             | `_Img`     | `UIImage`     |
| RawImage          | `_RawImg`  | `UIRawImage`  |
| Toggle            | `_Tog`     | `UIToggle`    |
| Slider            | `_Sld`     | `UISlider`    |
| ScrollRect        | `_Srt`     | `UIScrollRect`|
| Scrollbar         | `_Slb`     | `UIScrollbar` |
| InputField        | `_Ipt`     | `UIInputField`|
| 无组件纯节点       | `_Transform`| `UINode`     |

> 前缀约定（来自 `UIComponentBinder`）：`m_xxx` 普通组件；`mi_xxx` 图片按钮（同时绑 Button+Image）；
> `c_/ci_` Cell/Item 组件。特殊节点 `SubRoot`/`CurrencyParent`/`CloseBtn`/`ReturnBtn`/`MaskBtn` 有内置绑定。

---

## 3. 自动绑定流程（AutoBind）

1. **编辑器**：prefab 根挂 `UIComponentBinder`，点「执行自动绑定」→ 递归遍历子节点，
   按 `TypeAbbrMap` 生成 `UICompList`（每项 `{ CompName, Comp }`，如 `m_LoginBtn_Btn`）。
2. **运行期**：`UIBaseContainer.OnCreate` → `AutoBind()` 遍历 `UICompList`，按 `CompName` 后缀查
   `_ABBR_TO_CLASS` 映射表，`require` 对应 Lua 类并 `AddComponent(cls, userdata)` 传引用。
3. **零 Find**：`AddComponent` 收到 userdata，解析其 GameObject，经 `_FindComponentByGO` 查重
   （同 GO 同类型复用），`OnCreate(userdata)` → `UIBaseComponent` 把 userdata 设为 `__uiComp`
   → 组件 `self.__uiComp or Find` 直接拿到底层组件，无 Find。
4. **注入根表**：`self[CompName] = inst`，例如 `self.m_LoginBtn_Btn` 即该按钮的 Lua 组件实例。

---

## 4. 业务 View 写法

### 4.1 纯 AutoBind（推荐，对齐 H02 设计意图）

prefab 已绑定后，View 直接读注入字段，零 Find、免写 `AddComponent`：

```lua
function UILoginView:OnCreate()
    base.OnCreate(self)  -- AutoBind 已建好 self.m_LoginBtn_Btn / self.m_SvrText_Txt / self.m_Loading_Transform
    self._loginBtn = self.m_LoginBtn_Btn
    self._svrText  = self.m_SvrText_Txt
    self._loading  = self.m_Loading_Transform
end
```

### 4.2 纯 AutoBind + 路径兜底（兼容未绑定 prefab）

```lua
self._loginBtn = self.m_LoginBtn_Btn or self:AddComponent(UIButton, "ContentRoot/m_LoginBtn")
```

`AddComponent` 内部按 GameObject 查重，即使 AutoBind 已建也不会重复实例化、不 assert。
未绑定字段为 `nil` 时走路径回退，保证不崩。

### 4.3 纯手动 AddComponent（老写法，仍支持）

```lua
self._loginBtn = self:AddComponent(UIButton, "ContentRoot/m_LoginBtn")  -- 回退 Find
```

---

## 5. 组件 API 速查

| 组件类          | 底层组件    | 主要 API |
|----------------|------------|---------|
| `UIButton`     | Button     | `SetOnClick(handler)` / `RemoveClick()` / `SetEnable(bool)` / `SetText(str)` / `GetText()` / `GetUnityButton()` |
| `UIText`       | Text/TMP   | `SetText(str)` / `GetText()` / `GetUnityText()` |
| `UIImage`      | Image      | `SetSprite(sprite)` / `SetColor(r,g,b,a)` / `GetUnityImage()` |
| `UIRawImage`   | RawImage   | `SetTexture(tex)` / `GetTexture()` / `SetNativeSize()` |
| `UIToggle`     | Toggle     | `IsOn()` / `SetCheck(bool, withoutNotify)` / `SetInteractable(bool)` / `SetText(str)` / `SetOnValueChanged(handler)` |
| `UISlider`     | Slider     | `GetValue()` / `SetValue(v)` / `SetMaxValue(v)` / `SetTextComponent(com)` / `SetInteractable(bool)` / `SetOnValueChanged(handler)` |
| `UIScrollRect` | ScrollRect | `GetScrollRect()` / `SetNormalizedPosition(x,y)` / `SetViewScale(fx,fy)` |
| `UIScrollbar`  | Scrollbar  | `GetValue()` / `SetValue(v)` / `SetSize(v)` |
| `UIInputField` | InputField | `GetText()` / `SetText(str, withoutNotify)` / `SetOnChanged(handler)` / `SetCharacterLimit(n)` / `GetCharacterLimit()` |
| `UINode`       | 纯 Transform | `GetGameObject()` / `SetActive(bool)`（继承自 `UIBaseComponent`） |

> 所有组件均继承自 `UIBaseComponent`，拥有 `SetActive(bool)` / `GetGameObject()` / `SetName(str)` 等通用能力，
> 并在 `OnDestroy` 中清理监听、释放 `unity_xxx` 引用，由 `UIBaseContainer` 统一管理生命周期。

---

## 6. 使用前提

- prefab 根节点挂 `UIComponentBinder`，点「执行自动绑定」生成 `UICompList`（节点名按 `m_` 规范 + 类型后缀）。
- View 继承 `UIView`（→ `UIBaseContainer`），其 `OnCreate` 会自动 `AutoBind`。
- 未绑定（无 `UICompList`）时纯 AutoBind 字段为 `nil`，需走「4.2 兜底」或「4.3 手动」写法。

---

## 7. 与 H02 的差异（裁剪 / 对齐说明）

- **AutoBind 默认开启**：My project 在 `UIBaseContainer.OnCreate` 直接 `AutoBind`；H02 当前仓库 `BindCs`
  被注释（默认手动 `AddComponent`）。My project 实现了 H02 设计意图里的「自动 New 组件 + 零 Find」。
- **UIToggle 继承**：H02 的 `UIToggle` 继承 `UIBaseContainer`（当容器），My project 统一用
  `UIBaseComponent`（组件，内部懒找 Text），与 My project 的 `UIButton` 风格一致。
- **裁剪的 C# 依赖**：`UISlider` 去 DOTween 动画；`UIScrollRect` 去 `UnityEngine.UI.Extensions.ScrollRectTweener`；
  `UIRawImage` 去异步纹理加载 / `UIManager` 置灰；`UIInputField` 去 `logUIComp` 告警。均保留核心 API。
- **查重安全**：`AddComponent` 内部 `_FindComponentByGO` 按 GameObject+类型查重，AutoBind（零 Find）
  与手动 `AddComponent`（路径）可安全共存、不重复实例化。

---

## 8. 对象池与虚拟滚动列表（UIListView + PrefabPool）

### 8.1 为什么需要
长列表（聊天、背包、排行榜…）若对每条数据都 `Instantiate` 一个 Item，会造成大量 GC 与卡顿。
大厂做法：列表 Item 经**对象池复用**，且只实例化「可视区 + 缓冲区」的 Item（虚拟滚动）。

> H02 用第三方 C# 插件 `UnitySuperScrollView`（`UISuperScroll` 是其 Lua 包装）。My project 无此插件，
> 故以**纯 Lua** 的 `UIListView` + `PrefabPool` 提供等效能力，不依赖任何第三方 C# 组件。

### 8.2 两层对象池
| 池 | 位置 | 池化对象 | 用途 |
|----|------|---------|------|
| `Core/ObjectPool` | `Framework/Core` | Lua table（数据对象） | 技能/Buff/伤害信息等纯 Lua 数据复用 |
| `UI/Utils/PrefabPool` | `Framework/UI/Utils` | GameObject 实例 | 列表 Item / 飘字 / 图标等 UI 实例复用 |

### 8.3 UIListView 用法
```lua
local UIListView = require "Framework.UI.Component.UIListView"
local list = self:AddComponent(UIListView, "ContentRoot/m_Scroll")  -- m_Scroll 挂原生 ScrollRect

-- 业务自行从 AB/Resources 加载 item prefab（GameObject），交给列表托管
list:SetItemPrefab(itemPrefabGO)
list:SetOnRefresh(function(go, index)
    local txt = UIUtil.FindText(go.transform)
    if txt then txt.text = "第 " .. index end
    -- 业务也可在此给 item 子按钮 AddComponent(UIButton, ...) 绑定点击
end)
list:SetCount(dataCount)   -- 设总数量，触发虚拟滚动
```

### 8.4 约定与限制
- `ScrollRect.content` 的 pivot 需为 **(0.5, 1)**（顶中对齐）；item prefab 的 RectTransform
  anchor = **(0.5, 1)**、pivot = **(0.5, 0.5)**，与 content 一致。
- 当前仅支持**固定 item 高度**的垂直列表；动态高度 / 网格（GridView）为后续扩展点。
- 仅可视区 + 2 个缓冲区的 Item 会被实例化，滚动时自动回收/取出，Item GO 经 `PrefabPool` 复用。
- 列表组件 `OnDestroy` 时自动 `RemoveListener(onValueChanged)` 并 `PrefabPool:Clear()` 销毁所有实例。
