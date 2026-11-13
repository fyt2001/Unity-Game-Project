--[[
=============================================================================
BaseScene.lua - 场景脚本基类（My project 自包含）
=============================================================================
Module:     Game/Scene/BaseScene

Description:
	所有场景脚本（LoginScene / HomeScene / BattleScene …）的公共基类。

	场景脚本是「模块级单例」：SceneLoader 直接 require 模块表，并把它当作
	实例调用（result:OnCreate / result:OnComplete / result:OnLeave）。
	因此本基类通过 metatable 继承，子类用下面两行即可复用基类方法：

		local SubScene = {}
		setmetatable(SubScene, { __index = BaseScene })

	职责（本类只管事件订阅/注销，生命周期由各场景自行编排）：
		- RegisterEvent(eventManager, event, handler)
		    封装「以 self 为 target 的全局事件订阅」，子类无需再手写闭包与 target。
		- UnregisterAllEvents(eventManager)
		    按 self 批量注销（EventManager:RemoveListenerByTarget(self)），
		    子类 OnLeave 调一次即可，无需维护 _eventHandles 数组。

	这样「基类统一处理 RemoveListener」对场景类同样成立，与 UIController 的
	做法一致：订阅时带 target=self，销毁/离开时由基类按对象一次性清掉。
=============================================================================
]]

local BaseScene = {}
BaseScene.__index = BaseScene

---订阅全局事件（自动以 self 作为 target，便于统一注销）
---@param eventManager table EventManager 实例
---@param event string 事件名
---@param handler function 处理函数（签名为 function(self, ...)）
function BaseScene:RegisterEvent(eventManager, event, handler)
	if not eventManager or not event or not handler then return end
	eventManager:AddListener(event, function(...)
		handler(self, ...)
	end, self)
end

---按 self 批量注销全局事件（对应 RegisterEvent 的 target）
---@param eventManager table EventManager 实例
function BaseScene:UnregisterAllEvents(eventManager)
	if not eventManager then return end
	eventManager:RemoveListenerByTarget(self)
end

return BaseScene
