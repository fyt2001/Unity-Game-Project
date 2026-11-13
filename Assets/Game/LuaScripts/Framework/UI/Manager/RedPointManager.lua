--[[
-- RedPointManager.lua - 轻量红点中枢（My project 自包含，解耦 UI 框架）
-- 职责：只管理「红点名 -> 是否显示」的状态与监听者，不依赖任何业务数据结构。
-- 组件通过 UIBaseComponent:BindRedPoint(name) 订阅；数据层调用 Set 改变状态。
-- 这样 UI 组件不绑定任何红点库的内部结构（对照 H02 的 RP / RDClass / displayNode）。
--]]

local RedPointManager = {}

local data = {}        -- name -> bool（当前是否有红点）
local listeners = {}   -- name -> { [component] = true }

-- 设置某红点状态，通知所有订阅组件
function RedPointManager.Set(name, visible)
	visible = visible or false
	if data[name] == visible then return end
	data[name] = visible
	local ls = listeners[name]
	if ls then
		for comp, _ in pairs(ls) do
			if comp and not IsNull(comp.gameObject) then
				comp:OnRedPointChange(name, visible)
			end
		end
	end
end

-- 读取某红点状态
function RedPointManager.Get(name)
	return data[name] or false
end

-- 订阅：组件注册为某红点的监听者，并立即同步当前状态
function RedPointManager.Register(name, comp)
	listeners[name] = listeners[name] or {}
	listeners[name][comp] = true
	if data[name] then
		comp:OnRedPointChange(name, true)
	end
end

-- 取消订阅
function RedPointManager.UnRegister(name, comp)
	if listeners[name] then
		listeners[name][comp] = nil
	end
end

return RedPointManager
