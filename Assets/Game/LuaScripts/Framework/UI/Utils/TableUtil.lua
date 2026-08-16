--[[
=============================================================================
TableUtil.lua
=============================================================================
Module:     Framework/UI/Utils/TableUtil
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    TableUtil 提供通用的表操作工具函数，作为 Lua 标准库的扩展。
    所有函数在 Lua 5.1+ 环境下工作，兼容 XLua。

    提供以下功能：
        - 表复制（浅拷贝）
        - 表合并
        - 值查找
        - 值移除
        - 表遍历
        - 表清空

Dependencies:
    无外部依赖

Usage:
    local TableUtil = require "NewObject.Framework.UI.Utils.TableUtil"
    TableUtil.RemoveValue(t, value)
    TableUtil.Clear(t)
=============================================================================
]]

local TableUtil = {}

-- =============================================================================
-- 复制与合并
-- =============================================================================

---浅拷贝表
---@param source table 源表
---@return table copy 新表
function TableUtil.Copy(source)
    if not source then
        return nil
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

---将 source 表的键值对合并到 target 表中
---同名键会被覆盖
---@param target table 目标表
---@param source table 源表
function TableUtil.Merge(target, source)
    if not target or not source then
        return
    end
    for key, value in pairs(source) do
        target[key] = value
    end
end

-- =============================================================================
-- 查找
-- =============================================================================

---在数组中查找值的索引
---@param list table 数组
---@param value any 要查找的值
---@return number|nil index 索引位置，不存在返回 nil
function TableUtil.IndexOf(list, value)
    if not list then
        return nil
    end
    for index, item in ipairs(list) do
        if item == value then
            return index
        end
    end
    return nil
end

---判断数组中是否包含某个值
---@param list table 数组
---@param value any 要判断的值
---@return boolean contains
function TableUtil.Contains(list, value)
    return TableUtil.IndexOf(list, value) ~= nil
end

-- =============================================================================
-- 移除
-- =============================================================================

---从数组中移除指定值（第一个匹配项）
---@param list table 数组
---@param value any 要移除的值
---@return boolean removed 是否成功移除
function TableUtil.RemoveValue(list, value)
    if not list then
        return false
    end
    for index = #list, 1, -1 do
        if list[index] == value then
            table.remove(list, index)
            return true
        end
    end
    return false
end

---从数组中移除索引位置的元素
---@param list table 数组
---@param index number 要移除的索引
---@return any removed 被移除的元素
function TableUtil.RemoveAt(list, index)
    if not list or index < 1 or index > #list then
        return nil
    end
    return table.remove(list, index)
end

-- =============================================================================
-- 遍历
-- =============================================================================

---遍历表中的所有键值对并执行回调
---@param tbl table 表
---@param callback fun(key:any, value:any) 回调函数
function TableUtil.ForEach(tbl, callback)
    if not tbl or not callback then
        return
    end
    for key, value in pairs(tbl) do
        callback(key, value)
    end
end

---遍历数组中的所有元素并执行回调
---@param list table 数组
---@param callback fun(item:any, index:number) 回调函数
function TableUtil.ForEachArray(list, callback)
    if not list or not callback then
        return
    end
    for index, item in ipairs(list) do
        callback(item, index)
    end
end

---映射数组，返回新数组
---@param list table 数组
---@param callback fun(item:any):any 映射函数
---@return table mapped 新数组
function TableUtil.Map(list, callback)
    if not list or not callback then
        return {}
    end
    local result = {}
    for index, item in ipairs(list) do
        result[index] = callback(item)
    end
    return result
end

---过滤数组，返回满足条件的元素
---@param list table 数组
---@param predicate fun(item:any):boolean 过滤函数
---@return table filtered 过滤后的数组
function TableUtil.Filter(list, predicate)
    if not list or not predicate then
        return {}
    end
    local result = {}
    for _, item in ipairs(list) do
        if predicate(item) then
            result[#result + 1] = item
        end
    end
    return result
end

-- =============================================================================
-- 清空
-- =============================================================================

---清空表中的所有键值对
---@param tbl table 表
function TableUtil.Clear(tbl)
    if not tbl then
        return
    end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

---返回表中的键值对数量
---@param tbl table 表
---@return number count
function TableUtil.Count(tbl)
    if not tbl then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

return TableUtil