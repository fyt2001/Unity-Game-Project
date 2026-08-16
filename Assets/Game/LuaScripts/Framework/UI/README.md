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
├── Cache
├── Config
├── Core
├── Event
├── Layer
├── Manager
├── Resource
├── Sample
├── Utils
└── Zone
```

## Basic Usage

```lua
local UIFramework = require "NewObject.Framework.UI.UIFramework"
local manager = UIFramework.Create()

local RegisterSample = require "NewObject.Framework.UI.Sample.RegisterSample"
RegisterSample(UIFramework.UIWindowConfig)

manager:Open("SampleBag", 1)
manager:Refresh("SampleBag", { 1001, 1002 })
manager:Close("SampleBag")
```

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
