# UI Framework

This directory contains a production-style Lua UI framework skeleton for Unity + XLua projects.

## Goals

- Single public entry: `UIManager`
- Strict lifecycle state machine: `UIState`
- MVC per window: `UIView`, `UIController`, `UIModel`
- Replaceable subsystems: resource, animation, layer, zone, cache, event
- No business logic inside framework managers
- Every method includes comments for responsibility, parameters, and returns

## Directory

```text
Framework/UI
├── Animation
├── Base
├── Block
├── Cache
├── Component
├── Config
├── Core
├── Event
├── Layer
├── Manager
├── Resource
├── Sample        (仅供写法参考；无对应 prefab，不可运行)
├── Utils
├── Zone
├── UI编码规范.md
├── UIFramework.lua   (框架统一入口)
└── README.md
```

## Basic Usage

```lua
local UI = require "Framework.UI.UIFramework"
local manager = UI.Create()

-- 窗口注册：每个窗口一个 RegisterXxx(uiManager) 脚本，由 GameMain 统一调用。
-- 活模板（可直接照抄）：
--   Game/UI/Dungeon/RegisterFloorEventPopup.lua
--   Game/UI/Dungeon/RegisterRunResultPanel.lua
local RegisterFloorEventPopup = require "Game.UI.Dungeon.RegisterFloorEventPopup"
RegisterFloorEventPopup(manager)

manager:Open("FloorEventPopup", "标题", "正文")
manager:Refresh("FloorEventPopup")
manager:Close("FloorEventPopup")
```

> 注意：`Framework/UI/Sample/` 下的 SampleBag 四件套是**纸质模板**——
> 类写法正确（`Class.Define` + `Class.Extend`），但工程内没有
> `Resources/UI/SampleBag.prefab`，注册后也无法 `Open`。新窗口请照抄上面两个
> 活模板，不要再照抄 SampleBag。

## Public API

- `Open(name, ...)`
- `Close(name, reason)`
- `Back(reason)`
- `CloseAll(reason)`
- `Destroy(nameOrWindow)`
- `GetWindow(name)`
- `IsOpen(name)`
- `IsLoading(name)`
- `Refresh(name, ...)`
- `Preload(name, callback)`
- `AddListener(eventName, callback, owner)`
- `RemoveListener(handle)`
- `BlockInput(key, reason)`
- `UnblockInput(key)`
- `Dump()`
- `LogDump()`

## Core Rule

Business code depends on `UIFramework` and `UIManager` only.

Do not access internal managers directly from game logic.
