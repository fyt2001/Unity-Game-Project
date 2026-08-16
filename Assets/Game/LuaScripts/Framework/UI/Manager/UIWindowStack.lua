--[[
=============================================================================
UIWindowStack.lua
=============================================================================
Module:     Framework/UI/Manager/UIWindowStack
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIWindowStack 维护窗口中逻辑打开顺序的栈结构。
    它不关心层级、Zone、资源或缓存策略，只管理窗口的 Push/Pop/Peek 顺序。

    栈顶窗口代表最后打开的窗口，用于 Back 操作和焦点判断的备用逻辑。

Dependencies:
    - Class (类系统)
    - TableUtil (表工具)

Usage:
    local stack = UIWindowStack.New()
    stack:Push(window)
    local top = stack:Peek()
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local TableUtil = require "NewObject.Framework.UI.Utils.TableUtil"

local UIWindowStack = Class.Define("UIWindowStack")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化空栈
function UIWindowStack:Ctor()
    self.items = {}
end

-- =============================================================================
-- 公共 API：栈操作
-- =============================================================================

---将窗口推入栈顶
---如果窗口已在栈中，先移除旧位置再推入栈顶
---@param window table UIWindow 实例
function UIWindowStack:Push(window)
    assert(window ~= nil, "cannot push nil window to stack")
    TableUtil.RemoveValue(self.items, window)
    self.items[#self.items + 1] = window
end

---弹出栈顶窗口
---@return table|nil window 栈顶窗口，空栈返回 nil
function UIWindowStack:Pop()
    return table.remove(self.items)
end

---查看栈顶窗口（不移除）
---@return table|nil window 栈顶窗口，空栈返回 nil
function UIWindowStack:Peek()
    return self.items[#self.items]
end

---查看栈底窗口（不移除）
---@return table|nil window 栈底窗口
function UIWindowStack:Bottom()
    return self.items[1]
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---从栈中移除指定窗口
---@param window table UIWindow 实例
---@return boolean removed 是否成功移除
function UIWindowStack:Remove(window)
    return TableUtil.RemoveValue(self.items, window)
end

---判断窗口是否在栈中
---@param window table UIWindow 实例
---@return boolean exists
function UIWindowStack:Contains(window)
    return TableUtil.IndexOf(self.items, window) ~= nil
end

---返回栈中窗口数量
---@return number count
function UIWindowStack:Count()
    return #self.items
end

---返回栈中所有窗口的数组（从底到顶）
---@return table windows
function UIWindowStack:GetAll()
    local result = {}
    for _, window in ipairs(self.items) do
        result[#result + 1] = window
    end
    return result
end

---返回窗口在栈中的索引位置
---@param window table UIWindow 实例
---@return number|nil index 索引位置，不存在返回 nil
function UIWindowStack:IndexOf(window)
    return TableUtil.IndexOf(self.items, window)
end

-- =============================================================================
-- 公共 API：批量操作
-- =============================================================================

---清空栈（不关闭窗口，仅清除顺序记录）
function UIWindowStack:Clear()
    TableUtil.Clear(self.items)
end

---移除所有匹配条件的窗口
---@param predicate fun(window:table):boolean 过滤函数
---@return number count 移除的窗口数量
function UIWindowStack:RemoveWhere(predicate)
    local count = 0
    for index = #self.items, 1, -1 do
        if predicate(self.items[index]) then
            table.remove(self.items, index)
            count = count + 1
        end
    end
    return count
end

return UIWindowStack