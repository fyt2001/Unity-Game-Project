--[[
=============================================================================
UIBlockManager.lua
=============================================================================
Module:     Framework/UI/Block/UIBlockManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIBlockManager 管理输入阻塞，在窗口加载/动画/忙碌时防止用户错误操作。
    使用引用计数机制，允许多个窗口同时持有阻塞，直到所有阻塞解除。

    阻塞场景：
        - 窗口加载期间（资源还未就绪）
        - 播放动画期间（入场/出场动画）
        - 网络请求期间（加载数据）
        - 自定义阻塞（特殊业务逻辑）

    特性：
        - 引用计数：多个窗口可同时阻塞输入
        - 阻塞原因追踪：可查询当前阻塞原因
        - 安全：阻止未成年人操作
        - 可替换：支持自定义阻塞 UI 提供者

Dependencies:
    - Class (类系统)

Usage:
    local blockMgr = UIBlockManager.New(blockView)
    blockMgr:Block("Loading", "BagWindow")
    print(blockMgr:IsBlocked()) -- true
    blockMgr:Unblock("Loading", "BagWindow")
    print(blockMgr:IsBlocked()) -- false
=============================================================================
]]

local Class = require "Framework.UI.Utils.Class"

local UIBlockManager = Class.Define("UIBlockManager")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化阻塞管理器
---@param blockView table|nil 阻塞 UI 提供者，需实现 Show/Hide/SetReason
function UIBlockManager:Ctor(blockView)
    self.blockView = blockView
    self.blockCount = 0
    self.blockReasons = {}
end

-- =============================================================================
-- 私有方法：UI 更新
-- =============================================================================

---更新阻塞 UI 的显示状态
function UIBlockManager:UpdateBlockView()
    if self.blockCount > 0 then
        if self.blockView and self.blockView.Show then
            self.blockView:Show()
        end
    else
        if self.blockView and self.blockView.Hide then
            self.blockView:Hide()
        end
    end
end

-- =============================================================================
-- 公共 API：阻塞操作
-- =============================================================================

---添加输入阻塞
---@param reason string 阻塞原因（如 "Loading"、"Animation"、"Network"）
---@param source string 阻塞来源（如窗口名称）
function UIBlockManager:Block(reason, source)
    assert(type(reason) == "string", "block reason must be a string")
    assert(type(source) == "string", "block source must be a string")

    self.blockCount = self.blockCount + 1
    self.blockReasons[#self.blockReasons + 1] = {
        reason = reason,
        source = source,
    }
    self:UpdateBlockView()
end

---移除输入阻塞
---@param reason string 阻塞原因
---@param source string 阻塞来源
function UIBlockManager:Unblock(reason, source)
    if self.blockCount <= 0 then
        return
    end

    -- 从原因列表中移除匹配项
    for index = #self.blockReasons, 1, -1 do
        local entry = self.blockReasons[index]
        if entry.reason == reason and entry.source == source then
            table.remove(self.blockReasons, index)
            self.blockCount = math.max(0, self.blockCount - 1)
            break
        end
    end

    self:UpdateBlockView()
end

-- =============================================================================
-- 公共 API：批量操作
-- =============================================================================

---移除指定来源的所有阻塞
---@param source string 阻塞来源
function UIBlockManager:UnblockAll(source)
    for index = #self.blockReasons, 1, -1 do
        if self.blockReasons[index].source == source then
            table.remove(self.blockReasons, index)
            self.blockCount = math.max(0, self.blockCount - 1)
        end
    end
    self:UpdateBlockView()
end

---强制清除所有阻塞（慎用，可能导致状态不一致）
function UIBlockManager:ForceClear()
    self.blockCount = 0
    self.blockReasons = {}
    self:UpdateBlockView()
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---判断输入是否被阻塞
---@return boolean blocked
function UIBlockManager:IsBlocked()
    return self.blockCount > 0
end

---返回当前阻塞计数
---@return number count
function UIBlockManager:GetBlockCount()
    return self.blockCount
end

---返回当前阻塞原因列表
---@return table reasons 原因数组
function UIBlockManager:GetBlockReasons()
    local result = {}
    for _, entry in ipairs(self.blockReasons) do
        result[#result + 1] = entry.reason
    end
    return result
end

---返回当前阻塞详情列表
---@return table entries 详情数组 [{ reason, source }]
function UIBlockManager:GetBlockDetails()
    local result = {}
    for _, entry in ipairs(self.blockReasons) do
        result[#result + 1] = {
            reason = entry.reason,
            source = entry.source,
        }
    end
    return result
end

return UIBlockManager