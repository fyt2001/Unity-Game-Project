--[[
=============================================================================
UIAnimationManager.lua
=============================================================================
Module:     Framework/UI/Animation/UIAnimationManager
Version:    3.0.0
Author:     Framework Team
Status:     Frozen (Public API)
Target:     Unity + XLua

Description:
    UIAnimationManager 负责窗口的打开/关闭动画（入场/出场）。
    默认实现为 Instant 动画（无动画），外部可注入 DOTween 或自定义动画提供者。

    动画协议：
        - OpenAnimation(gameObject, onComplete): 播放入场动画，完成后调用 onComplete
        - CloseAnimation(gameObject, onComplete): 播放出场动画，完成后调用 onComplete

    特性：
        - 可替换动画提供者
        - 支持动画取消
        - 回调安全（保证 onComplete 仅被调用一次）

Dependencies:
    - Class (类系统)

Usage:
    local animMgr = UIAnimationManager.New(provider)
    animMgr:PlayOpenAnimation(gameObject, function() print("open done") end)
    animMgr:PlayCloseAnimation(gameObject, function() print("close done") end)
=============================================================================
]]

local Class = require "NewObject.Framework.UI.Utils.Class"

local UIAnimationManager = Class.Define("UIAnimationManager")

-- =============================================================================
-- 构造函数
-- =============================================================================

---初始化动画管理器
---@param provider table|nil 动画提供者，需实现 OpenAnimation/CloseAnimation/StopAnimation
function UIAnimationManager:Ctor(provider)
    self.provider = provider
    self.activeAnimations = {}
    self.nextId = 0
end

-- =============================================================================
-- 私有方法：动画追踪
-- =============================================================================

---注册轨迹动画，返回动画 ID
---@param gameObject any 目标 GameObject
---@return number animId
function UIAnimationManager:TrackAnimation(gameObject)
    self.nextId = self.nextId + 1
    self.activeAnimations[self.nextId] = gameObject
    return self.nextId
end

---移除动画轨迹
---@param animId number 动画 ID
function UIAnimationManager:UntrackAnimation(animId)
    self.activeAnimations[animId] = nil
end

---创建一次性回调包装器，确保 onComplete 仅被调用一次
---@param onComplete fun() 原始回调
---@param animId number 动画 ID
---@return fun() wrapped 包装后的回调
function UIAnimationManager:WrapCallback(onComplete, animId)
    local called = false
    return function()
        if called then
            return
        end
        called = true
        self:UntrackAnimation(animId)
        if onComplete then
            onComplete()
        end
    end
end

-- =============================================================================
-- 公共 API：开场动画
-- =============================================================================

---播放窗口入场动画
---@param gameObject any Unity GameObject 或适配器
---@param onComplete fun()|nil 动画完成回调
---@return number animId 动画 ID，可用于取消
function UIAnimationManager:PlayOpenAnimation(gameObject, onComplete)
    if not gameObject then
        if onComplete then
            onComplete()
        end
        return
    end

    local animId = self:TrackAnimation(gameObject)
    local wrapped = self:WrapCallback(onComplete, animId)

    -- 使用 Provider 播放动画
    if self.provider and self.provider.PlayOpenAnimation then
        self.provider:PlayOpenAnimation(gameObject, wrapped)
        return animId
    end

    -- 默认：无动画，直接回调
    wrapped()
    return animId
end

-- =============================================================================
-- 公共 API：退场动画
-- =============================================================================

---播放窗口退场动画
---@param gameObject any Unity GameObject 或适配器
---@param onComplete fun()|nil 动画完成回调
---@return number animId 动画 ID，可用于取消
function UIAnimationManager:PlayCloseAnimation(gameObject, onComplete)
    if not gameObject then
        if onComplete then
            onComplete()
        end
        return
    end

    local animId = self:TrackAnimation(gameObject)
    local wrapped = self:WrapCallback(onComplete, animId)

    -- 使用 Provider 播放动画
    if self.provider and self.provider.PlayCloseAnimation then
        self.provider:PlayCloseAnimation(gameObject, wrapped)
        return animId
    end

    -- 默认：无动画，直接回调
    wrapped()
    return animId
end

-- =============================================================================
-- 公共 API：停止动画
-- =============================================================================

---停止指定 GameObject 上的所有动画
---@param gameObject any Unity GameObject 或适配器
function UIAnimationManager:StopAnimation(gameObject)
    if not gameObject then
        return
    end

    -- 清理轨迹
    for animId, trackedObject in pairs(self.activeAnimations) do
        if trackedObject == gameObject then
            self.activeAnimations[animId] = nil
        end
    end

    if self.provider and self.provider.StopAnimation then
        self.provider:StopAnimation(gameObject)
    end
end

---停止所有进行中的动画
function UIAnimationManager:StopAll()
    self.activeAnimations = {}
    if self.provider and self.provider.StopAll then
        self.provider:StopAll()
    end
end

-- =============================================================================
-- 公共 API：查询
-- =============================================================================

---判断指定 GameObject 上是否有正在播放的动画
---@param gameObject any Unity GameObject 或适配器
---@return boolean playing
function UIAnimationManager:IsPlaying(gameObject)
    for _, trackedObject in pairs(self.activeAnimations) do
        if trackedObject == gameObject then
            return true
        end
    end
    return false
end

---返回当前正在播放的动画数量
---@return number count
function UIAnimationManager:GetActiveAnimationCount()
    local count = 0
    for _ in pairs(self.activeAnimations) do
        count = count + 1
    end
    return count
end

return UIAnimationManager