--[[
=============================================================================
SampleBagModel.lua
=============================================================================
Module:     Framework/UI/Sample/SampleBagModel
Version:    3.0.0
Author:     Framework Team
Status:     Sample (示例代码)
Target:     Unity + XLua

Description:
    SampleBagModel 是背包窗口的数据模型示例，演示如何将展示数据与
    视图层分离。模型负责存储和管理背包物品数据，不包含任何 UI 逻辑。

    生命周期回调：
        - OnCreate: 窗口创建时初始化数据
        - OnOpen: 窗口打开时接收参数
        - OnRefresh: 窗口刷新时更新数据
        - OnDestroy: 窗口销毁时清理数据

Dependencies:
    - Class (类系统)
    - UIModel (模型基类)

Usage:
    由 UIManager 通过 UIWindowFactory 自动创建，无需手动实例化。
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"
local UIModel = require "NewObject.Framework.UI.Core.UIModel"

local SampleBagModel = Class.Define("SampleBagModel")
Class.Extend(SampleBagModel, UIModel)

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化模型字段
---@param windowName string 所属窗口名称
function SampleBagModel:Ctor(windowName)
    UIModel.Ctor(self, windowName)
    self.items = {}
    self.bagId = 0
    self.selectedItemId = nil
end

-- =============================================================================
-- 生命周期回调
-- =============================================================================

---窗口创建时初始化数据
---重置物品列表为空
function SampleBagModel:OnCreate()
    self.items = {}
    self.bagId = 0
    self.selectedItemId = nil
end

---窗口打开时接收参数并准备展示数据
---@param bagId number|nil 背包 ID
function SampleBagModel:OnOpen(bagId)
    self.bagId = bagId or 0
end

---窗口刷新时更新模型数据
---@param items table|nil 新的物品列表
function SampleBagModel:OnRefresh(items)
    self.items = items or self.items
end

---窗口销毁时清理数据
function SampleBagModel:OnDestroy()
    self.items = nil
    self.bagId = 0
    self.selectedItemId = nil
end

-- =============================================================================
-- 公共 API：数据操作
-- =============================================================================

---向背包添加物品
---@param item table 物品数据
function SampleBagModel:AddItem(item)
    self.items[#self.items + 1] = item
end

---从背包移除物品
---@param itemId number 物品 ID
---@return boolean removed 是否成功移除
function SampleBagModel:RemoveItem(itemId)
    for index = #self.items, 1, -1 do
        if self.items[index].id == itemId then
            table.remove(self.items, index)
            if self.selectedItemId == itemId then
                self.selectedItemId = nil
            end
            return true
        end
    end
    return false
end

---设置选中物品
---@param itemId number 物品 ID
function SampleBagModel:SetSelectedItem(itemId)
    self.selectedItemId = itemId
end

---获取选中物品
---@return table|nil item 选中的物品
function SampleBagModel:GetSelectedItem()
    if not self.selectedItemId then
        return nil
    end
    for _, item in ipairs(self.items) do
        if item.id == self.selectedItemId then
            return item
        end
    end
    return nil
end

---获取物品数量
---@return number count
function SampleBagModel:GetItemCount()
    return #self.items
end

return SampleBagModel