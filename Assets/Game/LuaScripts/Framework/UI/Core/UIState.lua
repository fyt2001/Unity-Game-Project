--[[
=============================================================================
UIState.lua
=============================================================================
Module:     Framework/UI/Core/UIState
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIState 是整个 UI Framework 的单一生生命周期状态机（Finite State Machine）。
    它负责统一管理所有 Window 的生命周期状态，并定义合法的状态流转规则。

    整个 Framework 中，UIManager、UIWindow、UIWindowFactory、UIAnimationManager、
    UIResourceManager 全部依赖 UIState。

    任何模块不得自行维护生命周期状态。

Design Principles:
    - UIState 不仅仅是一个 Enum，它同时负责状态定义、流转规则、合法性检查和调试输出
    - 业务代码禁止直接比较状态数值，必须通过 UIState 提供的接口完成状态判断
    - 状态流转只能单向，禁止跳跃，禁止回退
    - 所有状态转换必须通过 AssertTransition 验证合法性

Lifecycle:
    None -> Loading -> Loaded -> Creating -> Created -> Opening -> Opened
    -> Focused -> Hidden -> Closing -> Closed -> Destroying -> Destroyed

Dependencies:
    - 无外部依赖（纯 Lua 模块）

Usage:
    local UIState = require "Framework.UI.Core.UIState"
    if UIState.IsOpened(window:GetState()) then ... end
    UIState.AssertTransition(from, to, windowName)
=============================================================================
]]

-- =============================================================================
-- 状态常量定义
-- 所有状态值均为整数，用于高效比较和序列化
-- =============================================================================

local UIState = {
    -- 初始状态：Window 尚未创建
    None = 0,

    -- 异步加载阶段：正在从磁盘/网络加载 Prefab 资源
    Loading = 1,

    -- 资源加载完成：Prefab Asset 已加载到内存，尚未实例化
    Loaded = 2,

    -- 创建阶段：正在实例化 GameObject 并绑定 MVC 组件
    Creating = 3,

    -- 创建完成：Window 实例化完毕，MVC 已绑定，尚未打开
    Created = 4,

    -- 打开动画阶段：正在播放打开动画（如淡入、缩放、滑入）
    Opening = 5,

    -- 已打开：Window 完全可见，但未获得输入焦点
    Opened = 6,

    -- 已聚焦：Window 获得输入焦点，可接收用户交互
    Focused = 7,

    -- 已隐藏：Window 被其他窗口遮挡，不可见但保持存活
    Hidden = 8,

    -- 关闭动画阶段：正在播放关闭动画
    Closing = 9,

    -- 已关闭：Window 不可见，根据缓存策略决定是否销毁
    Closed = 10,

    -- 销毁阶段：正在释放 GameObject 和 MVC 引用
    Destroying = 11,

    -- 已销毁：Window 完全释放，所有引用已置空
    Destroyed = 12,
}

-- =============================================================================
-- 状态名称映射表
-- 用于日志输出和调试面板显示
-- =============================================================================

local names = {
    [UIState.None] = "None",
    [UIState.Loading] = "Loading",
    [UIState.Loaded] = "Loaded",
    [UIState.Creating] = "Creating",
    [UIState.Created] = "Created",
    [UIState.Opening] = "Opening",
    [UIState.Opened] = "Opened",
    [UIState.Focused] = "Focused",
    [UIState.Hidden] = "Hidden",
    [UIState.Closing] = "Closing",
    [UIState.Closed] = "Closed",
    [UIState.Destroying] = "Destroying",
    [UIState.Destroyed] = "Destroyed",
}

-- =============================================================================
-- 状态转换规则表
-- transitions[from][to] = true 表示该转换合法
-- 未列出的转换均视为非法，将被 AssertTransition 拒绝
-- =============================================================================

local transitions = {
    -- None 只能进入 Loading（开始创建）或 Destroyed（直接销毁）
    [UIState.None] = {
        [UIState.Loading] = true,
        [UIState.Destroyed] = true,
    },

    -- Loading 可以进入 Loaded（加载成功）或 Closed（加载被取消）
    [UIState.Loading] = {
        [UIState.Loaded] = true,
        [UIState.Closed] = true,
    },

    -- Loaded 可以进入 Creating（开始实例化）或 Destroying（加载后直接销毁）
    [UIState.Loaded] = {
        [UIState.Creating] = true,
        [UIState.Destroying] = true,
    },

    -- Creating 可以进入 Created（实例化完成）或 Destroying（创建过程中销毁）
    [UIState.Creating] = {
        [UIState.Created] = true,
        [UIState.Destroying] = true,
    },

    -- Created 可以进入 Opening（开始打开）或 Destroying（创建后直接销毁）
    [UIState.Created] = {
        [UIState.Opening] = true,
        [UIState.Destroying] = true,
    },

    -- Opening 可以进入 Opened（打开动画完成）或 Closing（打开过程中关闭）
    [UIState.Opening] = {
        [UIState.Opened] = true,
        [UIState.Closing] = true,
    },

    -- Opened 可以进入 Focused（获得焦点）、Hidden（被遮挡）或 Closing（关闭）
    [UIState.Opened] = {
        [UIState.Focused] = true,
        [UIState.Hidden] = true,
        [UIState.Closing] = true,
    },

    -- Focused 可以进入 Hidden（失去焦点）或 Closing（关闭）
    [UIState.Focused] = {
        [UIState.Hidden] = true,
        [UIState.Closing] = true,
    },

    -- Hidden 可以进入 Opening（重新显示）或 Closing（关闭）
    [UIState.Hidden] = {
        [UIState.Opening] = true,
        [UIState.Closing] = true,
    },

    -- Closing 只能进入 Closed（关闭动画完成）
    [UIState.Closing] = {
        [UIState.Closed] = true,
    },

    -- Closed 可以进入 Opening（重新打开）或 Destroying（销毁）
    [UIState.Closed] = {
        [UIState.Opening] = true,
        [UIState.Destroying] = true,
    },

    -- Destroying 只能进入 Destroyed（销毁完成）
    [UIState.Destroying] = {
        [UIState.Destroyed] = true,
    },

    -- Destroyed 是终态，不可再转换
    [UIState.Destroyed] = {},
}

-- =============================================================================
-- 状态分类（用于快速判断状态组）
-- =============================================================================

-- 活跃状态集合：Window 已创建且可交互
local activeStates = {
    [UIState.Created] = true,
    [UIState.Opening] = true,
    [UIState.Opened] = true,
    [UIState.Focused] = true,
    [UIState.Hidden] = true,
}

-- 过渡状态集合：处于异步操作或动画中，不可直接操作
local transitionStates = {
    [UIState.Loading] = true,
    [UIState.Creating] = true,
    [UIState.Opening] = true,
    [UIState.Closing] = true,
    [UIState.Destroying] = true,
}

-- 可见状态集合：Window 可在屏幕上显示
local visibleStates = {
    [UIState.Opening] = true,
    [UIState.Opened] = true,
    [UIState.Focused] = true,
}

-- 关闭状态集合：Window 不可见且不可交互
local closedStates = {
    [UIState.Closed] = true,
    [UIState.Destroying] = true,
    [UIState.Destroyed] = true,
}

-- =============================================================================
-- 公共 API：状态名称
-- =============================================================================

---返回状态的可读名称，用于日志和调试面板
---@param state number UIState 枚举值
---@return string name 状态名称，未知状态返回 "Unknown(N)"
function UIState.GetName(state)
    return names[state] or ("Unknown(" .. tostring(state) .. ")")
end

-- =============================================================================
-- 公共 API：状态转换
-- =============================================================================

---判断从 from 状态转换到 to 状态是否合法
---相同状态的转换（幂等）始终返回 true
---@param from number 当前状态
---@param to number 目标状态
---@return boolean valid 转换是否合法
function UIState.CanTransition(from, to)
    if from == to then
        return true
    end
    return transitions[from] and transitions[from][to] == true or false
end

---断言状态转换合法，非法时抛出错误并附带窗口名称
---错误信息包含窗口名、当前状态和目标状态，便于定位问题
---@param from number 当前状态
---@param to number 目标状态
---@param windowName string|nil 可选的窗口名称，用于错误信息
function UIState.AssertTransition(from, to, windowName)
    if UIState.CanTransition(from, to) then
        return
    end
    error(string.format(
        "Illegal UI state transition: %s %s -> %s",
        tostring(windowName or "<unknown>"),
        UIState.GetName(from),
        UIState.GetName(to)
    ), 2)
end

---返回 from 状态所有合法的目标状态列表
---@param from number 当前状态
---@return table toStates 目标状态数组
function UIState.GetValidTransitions(from)
    local result = {}
    local map = transitions[from]
    if map then
        for to, _ in pairs(map) do
            result[#result + 1] = to
        end
    end
    return result
end

-- =============================================================================
-- 公共 API：状态判断（单个状态）
-- 所有状态判断必须通过这些接口完成，禁止直接比较状态数值
-- =============================================================================

---判断是否为 Loading 状态（异步加载资源中）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsLoading(state)
    return state == UIState.Loading
end

---判断是否为 Loaded 状态（Prefab 已加载，尚未实例化）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsLoaded(state)
    return state == UIState.Loaded
end

---判断是否为 Creating 状态（正在实例化 GameObject）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsCreating(state)
    return state == UIState.Creating
end

---判断是否为 Created 状态（Window 实例化完毕，尚未打开）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsCreated(state)
    return state == UIState.Created
end

---判断是否为 Opening 状态（正在播放打开动画）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsOpening(state)
    return state == UIState.Opening
end

---判断是否为 Opened 或 Focused 状态（可见且可交互）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsOpened(state)
    return state == UIState.Opened or state == UIState.Focused
end

---判断是否为 Focused 状态（获得输入焦点）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsFocused(state)
    return state == UIState.Focused
end

---判断是否为 Hidden 状态（被遮挡但保持存活）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsHidden(state)
    return state == UIState.Hidden
end

---判断是否为 Closing 状态（正在播放关闭动画）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsClosing(state)
    return state == UIState.Closing
end

---判断是否为 Closed 或 Destroyed 状态（不可见且不可交互）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsClosed(state)
    return state == UIState.Closed or state == UIState.Destroyed
end

---判断是否为 Destroying 状态（正在释放资源）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsDestroying(state)
    return state == UIState.Destroying
end

---判断是否为 Destroyed 状态（完全销毁）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsDestroyed(state)
    return state == UIState.Destroyed
end

-- =============================================================================
-- 公共 API：状态判断（分类）
-- =============================================================================

---判断是否为活跃状态（Window 已创建且可交互）
---活跃状态包括：Created, Opening, Opened, Focused, Hidden
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsActive(state)
    return activeStates[state] == true
end

---判断是否为过渡状态（处于异步操作或动画中）
---过渡状态包括：Loading, Creating, Opening, Closing, Destroying
---处于过渡状态的 Window 不可直接操作
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsTransitioning(state)
    return transitionStates[state] == true
end

---判断是否为可见状态（Window 可在屏幕上显示）
---可见状态包括：Opening, Opened, Focused
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsVisible(state)
    return visibleStates[state] == true
end

---判断是否为终态（Window 生命周期结束）
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsTerminal(state)
    return state == UIState.Destroyed
end

---判断是否为可重入状态（Window 可重新打开）
---可重入状态包括：Closed, None, Destroyed
---@param state number UIState 枚举值
---@return boolean result
function UIState.IsReusable(state)
    return state == UIState.None
        or state == UIState.Closed
        or state == UIState.Destroyed
end

-- =============================================================================
-- 公共 API：调试
-- =============================================================================

---返回所有状态值及其名称的映射表，用于调试面板
---@return table map { [state] = "name" }
function UIState.GetAllStates()
    return names
end

---返回状态总数
---@return number count
function UIState.GetStateCount()
    local count = 0
    for _ in pairs(UIState) do
        if type(UIState[_]) == "number" then
            count = count + 1
        end
    end
    return count
end

return UIState