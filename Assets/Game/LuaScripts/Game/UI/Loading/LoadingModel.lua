--[[
=============================================================================
LoadingModel.lua - 加载界面数据模型
=============================================================================
Module:     Game/UI/Loading/LoadingModel
Version:    1.0.0
Description:
    Loading 窗口的数据模型。
    管理加载进度、提示文本、加载阶段等数据。

    数据字段：
        - progress: 当前进度 (0.0 ~ 1.0)
        - text: 当前提示文本
        - phase: 当前加载阶段名称
        - isComplete: 是否加载完成
=============================================================================
]]

local LoadingModel = {}

function LoadingModel:Init()
    self.data = {
        progress = 0,
        text = "正在初始化...",
        phase = "None",
        isComplete = false,
        startTime = os.clock(),
    }
end

---设置进度
---@param progress number 0.0 ~ 1.0
---@param text string|nil 提示文本
function LoadingModel:SetProgress(progress, text)
    self.data.progress = math.min(math.max(progress, 0), 1)
    if text then
        self.data.text = text
    end
end

---设置加载阶段
---@param phase string 阶段名称
---@param text string|nil 提示文本
function LoadingModel:SetPhase(phase, text)
    self.data.phase = phase
    if text then
        self.data.text = text
    end
end

---标记加载完成
function LoadingModel:SetComplete()
    self.data.progress = 1
    self.data.isComplete = true
    self.data.text = "加载完成"
end

---获取当前数据
---@return table
function LoadingModel:GetData()
    return self.data
end

---获取已用时间（秒）
---@return number
function LoadingModel:GetElapsedTime()
    return os.clock() - self.data.startTime
end

function LoadingModel:Clear()
    self.data = {
        progress = 0,
        text = "",
        phase = "None",
        isComplete = false,
        startTime = os.clock(),
    }
end

return LoadingModel
