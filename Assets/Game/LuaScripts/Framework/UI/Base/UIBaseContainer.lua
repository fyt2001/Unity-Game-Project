--[[
-- UIBaseContainer.lua - UI 容器基类（从 ShaoNvClient_H02 移植，裁剪为 My project 自包含版本）
-- 说明：
--   1、window.view 是最上层容器
--   2、AddComponent 添加子组件，一般在 OnCreate 中使用；RemoveComponent 相反
--   3、GetComponent 获取组件；GetComponents 获取一类组件
--   4、子组件名字互斥：不同名字对应 Unity 中不同 Transform
--   5、OnDestroy 时遍历并 Delete 所有子组件（触发 __delete -> OnDestroy，自动清理监听）
--   6、AutoBind：遍历 prefab 上 UIComponentBinder 收集的组件引用，按类型缩写自动 New Lua 组件（零 Find），
--      对齐 H02 的 BindGoldenLuaUICompCS（GoldenLuaUIComponent 把组件引用注入 self）+ 业务 AddComponent(cls, userdata) 零 Find 写法，
--      并进一步把「业务手动 AddComponent」自动化，让业务 View 免写 AddComponent
--]]

local BaseClass = require "Framework.UI.Utils.BaseClass"
local UIBaseComponent = require "Framework.UI.Base.UIBaseComponent"
local UIUtil = require "Framework.UI.Utils.UIUtil"
local ClassType = ClassType

local UIBaseContainer = BaseClass("UIBaseContainer", UIBaseComponent)
local base = UIBaseComponent

-- 创建
local function OnCreate(self, ...)
	base.OnCreate(self, ...)
	self.components = {}
	self.length = 0
	self:BindLuaUIComp()   -- 注入 prefab 上 UIComponentBinder 收集的组件引用（对齐 H02 的 BindGoldenLuaUICompCS）
	self:AutoBind()        -- 自动 New 组件（零 Find），对齐 H02 的 BindGoldenLuaUICompCS + 业务 AddComponent(userdata) 零 Find 写法
end

-- 遍历（无序）
local function Walk(self, callback, component_class)
	if self.components ~= nil then
		for _, components in pairs(self.components) do
			for cmp_class, component in pairs(components) do
				if component_class == nil then
					if callback(component) then return end
				elseif cmp_class == component_class then
					if callback(component) then return end
				end
			end
		end
	end
end

-- 如果必要，创建新的记录
local function AddNewRecordIfNeeded(self, name)
	if self.components[name] == nil then
		self.components[name] = {}
	end
end

-- 记录 Component
local function RecordComponent(self, name, component_class, component)
	assert(self.components[name][component_class] == nil, "Already exist component_class : " .. tostring(component_class.__cname) .. ", name:" .. name)
	self.components[name][component_class] = component
end

-- 子组件销毁计数
local function OnComponentDestroy(self, component)
	self.length = self.length - 1
end

-- 解析 AddComponent 的目标 GameObject（用于单一实例查重）
-- 注意：本函数仅用于查重，不负责实际解析 transform（解析在 UIBaseComponent.OnCreate 内完成）
local _ResolveTargetGO
-- 按 GameObject + 类型查重，避免 AutoBind（零 Find 版）与手动 AddComponent（路径版）重复建
local _FindComponentByGO

-- 添加组件（多种重载）：
--   A）inst:AddComponent(ComponentTypeClass, relative_path)
--   B）inst:AddComponent(ComponentTypeClass, child_index)
--   C）inst:AddComponent(ComponentTypeClass, unity_gameObject)
-- 单一实例语义：若已存在指向同一 GameObject 的同类型组件，复用之
--   （AutoBind 用 UIComponentBinder 收集的 userdata 预先建的「零 Find」版，会被手动 AddComponent 复用，不重复实例化）
local function AddComponent(self, component_target, var_arg, ...)
	assert(component_target.__ctype == ClassType.class)
	local targetGO = _ResolveTargetGO(self, var_arg)
	if targetGO and not IsNull(targetGO) then
		local exist = _FindComponentByGO(self, targetGO, component_target)
		if exist then
			return exist
		end
	end
	local component_inst = nil
	local component_class = nil
	if type(var_arg) == "table" and var_arg.__ctype == ClassType.instance then
		component_inst = var_arg
		component_class = var_arg._class_type
	else
		component_inst = component_target.New(self, var_arg)
		component_class = component_target
		component_inst:OnCreate(...)
	end
	local activeS = component_inst.gameObject.activeSelf
	component_inst:SetActive(activeS)
	component_inst:SetActiveParent(self:GetActiveHierarchy())

	local name = component_inst:GetName()
	AddNewRecordIfNeeded(self, name)
	RecordComponent(self, name, component_class, component_inst)
	self.length = self.length + 1
	return component_inst
end

-- 获取组件
local function GetComponent(self, name, component_class)
	local components = self.components[name]
	if components == nil then
		return nil
	end

	if component_class == nil then
		local count = 0
		local result = nil
		for _, component in pairs(components) do
			count = count + 1
			result = component
		end
		assert(count == 1, "Must specify component_class while there are more than one component! count=" .. count)
		return result
	else
		return components[component_class]
	end
end

-- 获取一系列组件
local function GetComponents(self, component_target)
	local components = {}
	if type(component_target) == "table" then
		self:Walk(function(component)
			table.insert(components, component)
		end, component_target)
	elseif type(component_target) == "string" then
		components = self.components[component_target] or {}
	else
		error("GetComponents params err!")
	end
	return components
end

local function GetComponentsCount(self)
	return self.length
end

-- 移除组件
local function RemoveComponent(self, name, component_class)
	local component = self:GetComponent(name, component_class)
	if component ~= nil then
		local cmp_class = component._class_type
		self.components[name][cmp_class] = nil
		component:Delete()
		self.length = self.length - 1
	end
end

-- 移除一系列组件
local function RemoveComponents(self, component_target)
	local components = self:GetComponents(component_target)
	for _, component in pairs(components) do
		local cmp_name = component:GetName()
		local cmp_class = component._class_type
		component:Delete()
		if self.components[cmp_name] then
			self.components[cmp_name][cmp_class] = nil
		end
	end
	self.length = self.length - #components
	return components
end

-- 销毁：遍历并 Delete 所有子组件（由 holder 释放）
local function OnDestroy(self)
	self:Walk(function(component)
		if component.holder == self then
			component:Delete()
		end
	end)
	self.components = nil
	base.OnDestroy(self)
end

UIBaseContainer.OnCreate = OnCreate
UIBaseContainer.Walk = Walk
UIBaseContainer.AddComponent = AddComponent
UIBaseContainer.GetComponent = GetComponent
UIBaseContainer.GetComponents = GetComponents
UIBaseContainer.GetComponentsCount = GetComponentsCount
UIBaseContainer.RemoveComponent = RemoveComponent
UIBaseContainer.RemoveComponents = RemoveComponents
UIBaseContainer.OnDestroy = OnDestroy
UIBaseContainer.OnComponentDestroy = OnComponentDestroy

-- ============ 对接 My project 自带的 UIComponentBinder（中立版 GoldenLuaUIComponent） ============
-- 获取 prefab 根节点的 UIComponentBinder，把它在编辑器收集到的 Unity 组件引用注入本 Lua 视图表
-- 之后即可 self.m_xxx_Btn 直接拿组件，或 AddComponent(UIButton, self.m_LoginBtn_Btn) 实现零 Find
-- 对齐 H02 的 BindGoldenLuaUICompCS（用字符串 GetComponent 以避开 XLua codegen 注册）
local function BindLuaUIComp(self)
	if IsNull(self.gameObject) then return end
	local binder = self.gameObject:GetComponent("UIComponentBinder")
	if binder then
		binder.LuaInstance = self
		binder:LuaBindObject()
	end
end

UIBaseContainer.BindLuaUIComp = BindLuaUIComp

-- ============ 自动绑定（对齐 H02 设计意图中被注释的 BindCs：自动 New 组件，零 Find） ============
-- 类型缩写 → Lua 组件类（对应 UIComponentBinder.cs 的 TypeAbbrMap；仅含 My project 已实现的类）
local _ABBR_TO_CLASS = {
	Btn       = "Framework.UI.Component.UIButton",
	Txt       = "Framework.UI.Component.UIText",
	Img       = "Framework.UI.Component.UIImage",
	RawImg    = "Framework.UI.Component.UIRawImage",
	Tog       = "Framework.UI.Component.UIToggle",
	Sld       = "Framework.UI.Component.UISlider",
	Srt       = "Framework.UI.Component.UIScrollRect",
	Slb       = "Framework.UI.Component.UIScrollbar",
	Ipt       = "Framework.UI.Component.UIInputField",
	Transform = "Framework.UI.Component.UINode",   -- 纯节点（无组件）自动建 UINode，对齐 H02 的 UITransform
}

-- 解析 AddComponent 的目标 GameObject（用于单一实例查重）
function _ResolveTargetGO(self, var_arg)
	if type(var_arg) == "userdata" then
		return var_arg.gameObject
	elseif type(var_arg) == "string" and self.holder and not IsNull(self.holder.transform) then
		local t = UIUtil.FindTransDeep(self.holder.transform, var_arg)
		return t and t.gameObject or nil
	elseif type(var_arg) == "number" and self.holder and not IsNull(self.holder.transform) then
		local t = UIUtil.GetChild(self.holder.transform, var_arg)
		return t and t.gameObject or nil
	end
	return nil
end

-- 按 GameObject + 类型查重，避免 AutoBind（零 Find 版）与手动 AddComponent（路径版）重复建
function _FindComponentByGO(self, go, component_target)
	local hit = nil
	self:Walk(function(c)
		if not IsNull(c.gameObject) and c.gameObject == go and c._class_type == component_target then
			hit = c
			return true
		end
	end)
	return hit
end

-- 自动绑定：遍历 prefab 上 UIComponentBinder 收集的组件引用，按类型缩写 New Lua 组件（零 Find）
-- 对齐 H02 的 BindGoldenLuaUICompCS（GoldenLuaUIComponent 把组件引用注入 self）+ 业务 AddComponent(cls, userdata) 零 Find 写法，
-- 并进一步自动化：业务 View 可直接 self.m_xxx_Btn 访问组件，免写 AddComponent
local function AutoBind(self)
	if IsNull(self.gameObject) then return end
	local binder = self.gameObject:GetComponent("UIComponentBinder")
	if not binder or binder.UICompList == nil then return end
	local list = binder.UICompList
	for i = 0, list.Length - 1 do
		local item = list[i]
		local compName = item.CompName
		local comp = item.Comp
		if comp and compName then
			local abbr = compName:match("_(%w+)$")
			local clsPath = abbr and _ABBR_TO_CLASS[abbr]
			if clsPath then
				local ok, cls = pcall(require, clsPath)
				if ok and cls and type(cls) == "table" then
					-- 传 userdata → 零 Find（AddComponent 内部经 _FindComponentByGO 去重，复用已存在实例）
					local inst = self:AddComponent(cls, comp)
					if inst then
						-- 覆盖注入的 userdata 为组件实例（对齐 H02：self.m_xxx_Btn 即组件）
						self[compName] = inst
					end
				end
			end
		end
	end
end

UIBaseContainer.AutoBind = AutoBind

return UIBaseContainer
