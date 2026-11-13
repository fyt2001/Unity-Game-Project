--[[
=============================================================================
PrefabPool.lua - GameObject 级对象池（对齐大厂 UI 列表复用规范）
=============================================================================
Module:     Framework/UI/Utils/PrefabPool
Target:     Unity + XLua（My project 的 BaseClass 体系）

描述：
	复用频繁创建/销毁的 UI Item 实例（GameObject），避免大量 Instantiate/Destroy
	造成的卡顿与 GC 压力。与 Framework/Core/ObjectPool（仅池化 Lua table）互补：
		- Core/ObjectPool  : 池化纯 Lua 数据对象（技能/Buff/伤害信息…）
		- UI/Utils/PrefabPool: 池化 GameObject 实例（列表 Item / 飘字 / 图标…）

用法：
	local PrefabPool = require "Framework.UI.Utils.PrefabPool"
	local pool = PrefabPool.New(itemPrefabGO, contentTransform)
	local go = pool:Get()        -- 取出（池空则 Instantiate 并挂到 parent）
	pool:Release(go)             -- 回收（仅 SetActive(false)，不销毁）
	pool:Preload(10)             -- 预创建 10 个
	pool:Clear()                 -- 真正销毁所有实例（View 关闭时调用）
]]
local PrefabPool = {}

---@param prefab UnityEngine.GameObject 模板（不会被销毁，仅克隆）
---@param parent UnityEngine.Transform 实例化后的父节点（通常是 ScrollRect.content）
function PrefabPool.New(prefab, parent)
	local t = {
		_prefab = prefab,
		_parent = parent,
		_free = {},   -- 空闲可复用实例
		_all = {},    -- 全部已创建实例（用于 Clear 销毁）
	}
	setmetatable(t, { __index = PrefabPool })
	return t
end

---取出一个实例（池空则克隆）
---@return UnityEngine.GameObject
function PrefabPool:Get()
	local go
	if #self._free > 0 then
		go = table.remove(self._free)
	else
		go = CS.UnityEngine.GameObject.Instantiate(self._prefab)
		go.transform:SetParent(self._parent, false)
		table.insert(self._all, go)
	end
	if not IsNull(go) then go:SetActive(true) end
	return go
end

---回收实例（不销毁，仅隐藏等待复用）
function PrefabPool:Release(go)
	if IsNull(go) then return end
	go:SetActive(false)
	table.insert(self._free, go)
end

---预创建 count 个空闲实例
function PrefabPool:Preload(count)
	for i = 1, (count or 0) do
		local go = CS.UnityEngine.GameObject.Instantiate(self._prefab)
		go.transform:SetParent(self._parent, false)
		go:SetActive(false)
		table.insert(self._free, go)
		table.insert(self._all, go)
	end
end

---销毁全部实例（View 关闭 / prefab 切换时调用）
function PrefabPool:Clear()
	for _, go in ipairs(self._all) do
		if not IsNull(go) then CS.UnityEngine.GameObject.Destroy(go) end
	end
	self._free = {}
	self._all = {}
end

return PrefabPool
