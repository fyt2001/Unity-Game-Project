--[[
=============================================================================
Logger.lua
=============================================================================
Module:     Framework/UI/Utils/Logger
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    Logger 是 UI 框架的日志外观类，提供统一的日志接口。
    支持日志级别过滤、自定义输出目标（Sink）和格式化输出。

    日志级别（从高到低）：
        - Error: 严重错误，框架无法继续运行
        - Warn: 警告，非预期但可恢复
        - Info: 一般信息（状态变更、生命周期事件）
        - Debug: 调试信息，仅开发环境输出

    特性：
        - 可替换日志实现（Unity Debug、XLua 日志、自定义）
        - 日志级别过滤
        - 自定义输出目标（Sink）
        - 格式化输出支持

Dependencies:
    无外部依赖

Usage:
    local Logger = require "Framework.UI.Utils.Logger"
    Logger.Info("Bag", "Window opened successfully")
    Logger.Error("Bag", "Failed to load resource: %s", path)
=============================================================================
]]

local Logger = {}

-- =============================================================================
-- 日志级别常量
-- =============================================================================

Logger.Level = {
    Debug = 0,
    Info = 1,
    Warn = 2,
    Error = 3,
    None = 4,
}

-- =============================================================================
-- 配置
-- =============================================================================

Logger.currentLevel = Logger.Level.Debug
Logger.sinks = {}
Logger.tagPrefix = "[UI]"

-- =============================================================================
-- 公共 API：日志输出
-- =============================================================================

---输出 Debug 级别日志
---@param tag string 日志标签（如窗口名、模块名）
---@param format string 格式化字符串
---@param ... 格式化参数
function Logger.Debug(tag, format, ...)
    Logger.Log(Logger.Level.Debug, "DEBUG", tag, format, ...)
end

---输出 Info 级别日志
---@param tag string 日志标签
---@param format string 格式化字符串
---@param ... 格式化参数
function Logger.Info(tag, format, ...)
    Logger.Log(Logger.Level.Info, "INFO", tag, format, ...)
end

---输出 Warn 级别日志
---@param tag string 日志标签
---@param format string 格式化字符串
---@param ... 格式化参数
function Logger.Warn(tag, format, ...)
    Logger.Log(Logger.Level.Warn, "WARN", tag, format, ...)
end

---输出 Error 级别日志
---@param tag string 日志标签
---@param format string 格式化字符串
---@param ... 格式化参数
function Logger.Error(tag, format, ...)
    Logger.Log(Logger.Level.Error, "ERROR", tag, format, ...)
end

-- =============================================================================
-- 私有方法
-- =============================================================================

---格式化日志消息
---@param format string 格式化字符串
---@param args table 参数表
---@return string message 格式化后的消息
function Logger.FormatMessage(format, args)
    if not format then
        return ""
    end
    if #args == 0 then
        return format
    end
    -- 使用 %. 替换格式字符串中的 %s 等占位符
    local result = string.gsub(format, "%%(%w)", function(spec)
        local arg = args[1]
        table.remove(args, 1)
        if spec == "s" then
            return tostring(arg)
        elseif spec == "d" then
            return tostring(math.floor(tonumber(arg) or 0))
        elseif spec == "f" then
            return string.format("%.2f", tonumber(arg) or 0)
        else
            return "%%" .. spec
        end
    end)
    return result
end

---核心日志输出方法
---@param level number 日志级别
---@param levelName string 级别名称
---@param tag string 日志标签
---@param format string 格式化字符串
---@param ... 格式化参数
function Logger.Log(level, levelName, tag, format, ...)
    -- 级别过滤
    if level < Logger.currentLevel then
        return
    end

    local args = table.pack(...)
    local message = Logger.FormatMessage(format, args)

    -- 输出到所有 Sink
    for _, sink in ipairs(Logger.sinks) do
        if sink[levelName:lower()] then
            sink[levelName:lower()](sink, tag, message)
        end
    end

    -- 默认输出：使用 print 或 Unity Debug
    local fullMessage = string.format(
        "%s[%s][%s] %s",
        Logger.tagPrefix,
        levelName,
        tostring(tag),
        message
    )

    -- 尝试使用 Unity 的 Debug.Log
    if unityLog then
        if level == Logger.Level.Error then
            unityLog.LogError(fullMessage)
        elseif level == Logger.Level.Warn then
            unityLog.LogWarning(fullMessage)
        else
            unityLog.Log(fullMessage)
        end
    else
        print(fullMessage)
    end
end

-- =============================================================================
-- 公共 API：配置
-- =============================================================================

---设置日志级别
---@param level number Logger.Level 枚举值
function Logger.SetLevel(level)
    Logger.currentLevel = level
end

---设置日志标签前缀
---@param prefix string 前缀字符串
function Logger.SetTagPrefix(prefix)
    Logger.tagPrefix = prefix
end

---添加日志输出目标
---@param sink table 需实现 debug/info/warn/error 方法
function Logger.AddSink(sink)
    Logger.sinks[#Logger.sinks + 1] = sink
end

---清空所有日志输出目标
function Logger.ClearSinks()
    Logger.sinks = {}
end

return Logger