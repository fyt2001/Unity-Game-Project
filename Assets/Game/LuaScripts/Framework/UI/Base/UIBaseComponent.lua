--[[
-- UIBaseComponent.lua - 所有 UI 组件的基类（从 ShaoNvClient_H02 移植，裁剪为 My project 自包含版本）
-- 说明：
--   1、基于组件的设计：容器（UIView / UIButton）负责管理和调度子组件，类似 Unity 挂载脚本
--   2、构造器 __init(holder, var_arg)；创建时调用 OnCreate 解析 transform/gameObject；销毁时 __delete 调 OnDestroy
--   3、组件对应 Unity 原生 Component/Script，容器对应 Unity 原生 GameObject
--
-- 与 H02 的差异（已裁剪，避免引入 H02 私有依赖）：
--   - 移除红点系统（RP / _bindRedpoint / _clearRedPointBind）
--   - UILayer view 链已简化为 holder 链（见 OnCreate），不依赖 H02 UILayer
--   - Updatable 更新系统 → 基于 My project 自带 UpdateManager 的 EnableUpdate（见下），不依赖 H02 Updatable
--   - TimerManager.Relayout → 基于 My project 自带 TimerManager 的 Relayout（见下），不依赖 H02 TimerManager
--   - BindGoldenLuaUICompCS / logUIComp：H02 的 C# LuaUIComponent 绑定工作流，My project 已有中立版
--     UIComponentBinder.cs，已通过 UIBaseContainer:BindLuaUIComp 对接（见上），prefab 直接持有引用零 Find
--   - view 解析简化为：holder == self 时 view = self；否则沿 holder.view 向上查找
--]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIUtil = require "Framework.UI.Utils.UIUtil"
local RedPointManager = require "Framework.UI.Manager.RedPointManager"
local UpdateManager = require "Framework.Core.UpdateManager"
local TimerManager = require "Framework.Core.TimerManager"

local UIBaseComponent = BaseClass("UIBaseComponent")
local base = nil

-- 构造函数：子类不要再写此函数，初始化放 OnCreate
-- holder：持有者（容器）；var_arg：相对路径(string) / 子节点序号(number) / Unity GameObject(userdata)
local function __init(self, holder, var_arg)
	assert(not IsNull(holder), "Err : holder nil!")
	assert(not IsNull(holder.transform), "Err : holder transform nil!")

	self.view = nil
	self.holder = holder
	self.transform = nil
	self.gameObject = nil
	self.rectTransform = nil
	self.__name = nil
	self.__bind_data = nil
	self.__var_arg = var_arg
	self.__uiCompName = nil
	self.__uiComp = nil
	self.activeS_ = nil
	self.activeP_ = false
	self.lastActive_ = false
	self.created_ = false
end

-- 析构函数：子类不要再写此函数，释放放 OnDestroy
local function __delete(self)
	if self.created_ then
		self:OnDestroy()
	end
end

-- 创建：解析 transform / gameObject / rectTransform / view
local function OnCreate(self, uiCSTypeString)
	assert(not IsNull(self.holder), "Err : holder nil!")
	assert(not IsNull(self.holder.transform), "Err : holder transform nil!")
	assert(not IsNull(self.__var_arg), "Err: var_arg nil!")

	-- view 解析（简化版）
	if self.holder == self then
		self.view = self
	else
		local now_holder = self.holder
		while not IsNull(now_holder) do
			if not IsNull(now_holder.view) then
				self.view = now_holder.view
				break
			end
			now_holder = now_holder.holder
		end
		if IsNull(self.view) then
			self.view = self
		end
	end

	local arg_type = type(self.__var_arg)
	if arg_type == "string" then
		self.transform = UIUtil.FindTransDeep(self.holder.transform, self.__var_arg)
		assert(self.transform ~= nil, "****** [" .. tostring(self.holder.transform and self.holder.transform.name) .. "] 下面没有找到 [" .. self.__var_arg .. "]")
		self.gameObject = self.transform.gameObject
	elseif arg_type == "number" then
		self.transform = UIUtil.GetChild(self.holder.transform, self.__var_arg)
		self.gameObject = self.transform.gameObject
	elseif arg_type == "userdata" then
		self.__uiComp = self.__var_arg
		self.gameObject = self.__var_arg.gameObject
		self.transform = self.gameObject.transform
	else
		error("OnCreate : error params list! " .. type(self.__var_arg) .. " " .. tostring(self.__var_arg))
	end
	self.__name = self.gameObject.name

	self.rectTransform = UIUtil.FindComponent(self.transform, typeof(CS.UnityEngine.RectTransform))

	self.__var_arg = nil
	self.created_ = true
	self:EnableUpdate(true)   -- 构造即启用每帧更新（若子类定义了 OnUpdate 等）
end

-- 激活 / 反激活（会向子组件传播）
local function SetActive(self, activeS)
	activeS = activeS or false
	if activeS ~= self.gameObject.activeSelf then
		self.gameObject:SetActive(activeS)
	end
	self.activeS_ = activeS
	local activeH = self.activeP_ and self.activeS_ or false
	self:___TriggerEvent(activeH)
end

local function SetActiveParent(self, parentActive)
	parentActive = parentActive or false
	self.activeP_ = parentActive
	local activeH = self.activeP_ and self.activeS_ or false
	self:___TriggerEvent(activeH)
end

local function ___TriggerEvent(self, active)
	if self.lastActive_ == active then
		return
	end
	self.lastActive_ = active
	local action = active and self.OnEnable or self.OnDisable
	action(self)
end

local function GetActive(self)
	return self.activeS_
end

local function GetActiveHierarchy(self)
	return self.activeS_ and self.activeP_ or false
end

local function OnEnable(self) end
local function OnDisable(self) end

local function GetName(self)
	return self.__name
end

local function SetName(self, name, toUnity)
	self.__name = name
	if toUnity then
		if IsNull(self.gameObject) then
			return
		end
		self.gameObject.name = name
	end
end

local function SetBindData(self, data)
	self.__bind_data = data
end

local function GetBindData(self)
	return self.__bind_data
end

-- transform / 布局辅助
local function SetPos(self, pos)
	self.transform.position = pos
end

local function GetPos(self)
	return self.transform.position
end

local function SetLocalPos(self, pos)
	self.transform.localPosition = pos
end

local function GetLocalPos(self)
	return self.transform.localPosition
end

local function SetRTPos(self, pos, is3d)
	if self.rectTransform then
		if is3d then
			self.rectTransform.anchoredPosition3D = CS.UnityEngine.Vector3(pos.x, pos.y, 0)
		else
			self.rectTransform.anchoredPosition = pos
		end
	end
end

local function GetRTPos(self)
	if self.rectTransform then
		return self.rectTransform.anchoredPosition
	end
end

local function SetScale(self, scale)
	self.rectTransform.localScale = CS.UnityEngine.Vector3(scale, scale, scale)
end

local function SetSize(self, size)
	self.rectTransform.sizeDelta = size
end

local function GetSize(self, isDelta)
	if isDelta then
		return self.rectTransform.sizeDelta
	else
		return self.rectTransform.rect.size
	end
end

local function SetWidth(self, v)
	local size = self:GetSize(true)
	self:SetSize(CS.UnityEngine.Vector2(v, size.y))
end

local function SetHeight(self, v)
	local size = self:GetSize(true)
	self:SetSize(CS.UnityEngine.Vector2(size.x, v))
end

local function SetSiblingIndex(self, index)
	if index then
		self.transform:SetSiblingIndex(index)
	else
		self.transform:SetAsLastSibling()
	end
end

local function SetParent(self, trans, worldPositionStays)
	worldPositionStays = worldPositionStays or false
	self.transform:SetParent(trans, worldPositionStays)
end

-- 销毁：释放引用
local function OnDestroy(self)
	-- 解绑红点，避免 RedPointManager 持有已销毁组件
	if self.__redPoints then
		for name, _ in pairs(self.__redPoints) do
			RedPointManager.UnRegister(name, self)
		end
		self.__redPoints = nil
	end
	self.__redPointGo = nil
	self:EnableUpdate(false)   -- 注销每帧更新
	if self.holder and self.holder.OnComponentDestroy ~= nil then
		self.holder:OnComponentDestroy(self)
	end
	self.holder = nil
	self.transform = nil
	self.gameObject = nil
	self.rectTransform = nil
	self.__name = nil
	self.__bind_data = nil
	self.__uiCompName = nil
	self.__uiComp = nil
end

-- ============ 红点（中立接口，不绑定任何红点库内部结构） ============
-- 订阅某红点名：状态变化自动刷新该组件的红点显示
local function BindRedPoint(self, name)
	if not name then return end
	self.__redPoints = self.__redPoints or {}
	if self.__redPoints[name] then return end
	self.__redPoints[name] = true
	RedPointManager.Register(name, self)
end

-- 取消订阅某红点名
local function UnBindRedPoint(self, name)
	if not name or not self.__redPoints then return end
	if self.__redPoints[name] then
		self.__redPoints[name] = nil
		RedPointManager.UnRegister(name, self)
	end
end

-- 红点状态变化回调（默认实现：显隐当前节点下 "RedPoint" 子物体）
-- 子类可重写以自定义（多红点 / 动画 / 数字角标等）
local function OnRedPointChange(self, name, visible)
	self:SetRedPointVisible(visible)
end

-- 控制红点子物体显隐（懒查找，prefab 上需有名为 "RedPoint" 的子节点）
local function SetRedPointVisible(self, visible)
	if IsNull(self.transform) then return end
	if self.__redPointGo == nil then
		local t = UIUtil.FindTransDeep(self.transform, "RedPoint")
		self.__redPointGo = t and t.gameObject or false
	end
	if self.__redPointGo and self.__redPointGo ~= false then
		if self.__redPointGo.activeSelf ~= visible then
			self.__redPointGo:SetActive(visible)
		end
	end
end

-- ============ 每帧更新（解耦版：基于 My project 自带 UpdateManager，不依赖 H02 Updatable） ============
-- 子类重写 OnUpdate(dt) / OnLateUpdate(dt) / OnFixedUpdate(dt)，调用 EnableUpdate(true) 启用
-- 组件销毁时 OnDestroy 自动 EnableUpdate(false) 注销
local function EnableUpdate(self, enable)
	if self.__updateEnabled == enable then return end
	self.__updateEnabled = enable
	local um = UpdateManager:GetInstance()
	if enable then
		if self.OnUpdate then
			um:AddUpdate(function(dt) self:OnUpdate(dt) end, self)
		end
		if self.OnLateUpdate then
			um:AddLateUpdate(function(dt) self:OnLateUpdate(dt) end, self)
		end
		if self.OnFixedUpdate then
			um:AddFixedUpdate(function(dt) self:OnFixedUpdate(dt) end, self)
		end
	else
		um:RemoveUpdateByTarget(self)   -- 一次性移除本组件所有回调（含 Late/Fixed）
	end
end

-- ============ 布局重建（解耦版：用 My project TimerManager 延迟一帧，不依赖 H02 TimerManager.Relayout） ============
local function Relayout(self)
	if IsNull(self.rectTransform) then return end
	TimerManager:GetInstance():AddDelay(1, function()
		if not IsNull(self.rectTransform) then
			CS.UnityEngine.UI.LayoutRebuilder.ForceRebuildLayoutImmediate(self.rectTransform)
		end
	end)
end

UIBaseComponent.__init = __init
UIBaseComponent.__delete = __delete
UIBaseComponent.OnCreate = OnCreate
UIBaseComponent.OnEnable = OnEnable
UIBaseComponent.OnDisable = OnDisable
UIBaseComponent.GetName = GetName
UIBaseComponent.SetName = SetName
UIBaseComponent.SetBindData = SetBindData
UIBaseComponent.GetBindData = GetBindData
UIBaseComponent.SetActive = SetActive
UIBaseComponent.GetActive = GetActive
UIBaseComponent.GetActiveHierarchy = GetActiveHierarchy
UIBaseComponent.SetActiveParent = SetActiveParent
UIBaseComponent.___TriggerEvent = ___TriggerEvent
UIBaseComponent.OnDestroy = OnDestroy
UIBaseComponent.BindRedPoint = BindRedPoint
UIBaseComponent.UnBindRedPoint = UnBindRedPoint
UIBaseComponent.OnRedPointChange = OnRedPointChange
UIBaseComponent.SetRedPointVisible = SetRedPointVisible
UIBaseComponent.EnableUpdate = EnableUpdate
UIBaseComponent.Relayout = Relayout
UIBaseComponent.SetPos = SetPos
UIBaseComponent.GetPos = GetPos
UIBaseComponent.SetLocalPos = SetLocalPos
UIBaseComponent.GetLocalPos = GetLocalPos
UIBaseComponent.SetRTPos = SetRTPos
UIBaseComponent.GetRTPos = GetRTPos
UIBaseComponent.SetScale = SetScale
UIBaseComponent.SetSize = SetSize
UIBaseComponent.GetSize = GetSize
UIBaseComponent.SetWidth = SetWidth
UIBaseComponent.SetHeight = SetHeight
UIBaseComponent.SetSiblingIndex = SetSiblingIndex
UIBaseComponent.SetParent = SetParent

return UIBaseComponent
