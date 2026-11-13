--[[
-- UIUtil.lua - UI 组件查找辅助（从 ShaoNvClient_H02 移植，裁剪为 My project 自包含版本）
-- 提供：IsNull（全局）、FindTransDeep、GetChild、FindComponent、FindButton、FindText、FindImage
--]]

local CS = CS
local UnityEngineUI = CS.UnityEngine.UI

-- 全局 IsNull：XLua 下判断 UnityEngine.Object 是否为空（含已 Destroy 的对象）
IsNull = IsNull or function(o)
	if o == nil then return true end
	if type(o) ~= "userdata" then return false end
	local ok, res = pcall(function() return CS.UnityEngine.Object.ReferenceEquals(o, nil) end)
	if ok then return res end
	return false
end

-- 在 transform 上直接取组件
local function FindComponent(transform, type)
	return transform:GetComponent(type)
end

-- 取第 index 个子节点（0-based）
local function GetChild(transform, index)
	return transform:GetChild(index)
end

-- 按 "A/B/C" 相对路径深度查找（对齐 H02 FindTransDeep）
local function FindTransDeep(transform, path)
	if not transform or not path or path == "" then return transform end
	local cur = transform
	for seg in string.gmatch(path, "[^/]+") do
		if not cur then return nil end
		cur = cur:Find(seg)
	end
	return cur
end

-- 在 self 及所有子孙中查找指定类型的组件（深度优先）
local function _searchComponent(transform, compType, depth)
	depth = depth or 0
	if depth > 30 then return nil end
	local c = transform:GetComponent(compType)
	if not IsNull(c) then return c end
	local count = transform.childCount
	for i = 0, count - 1 do
		local r = _searchComponent(transform:GetChild(i), compType, depth + 1)
		if not IsNull(r) then return r end
	end
	return nil
end

local function FindButton(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.Button))
end

local function FindImage(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.Image))
end

local function FindText(transform)
	local t = _searchComponent(transform, typeof(UnityEngineUI.Text))
	if not IsNull(t) then return t end
	local TMPType = CS.TMPro and CS.TMPro.TextMeshProUGUI
	if TMPType then
		return _searchComponent(transform, typeof(TMPType))
	end
	return nil
end

local function FindToggle(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.Toggle))
end

local function FindSlider(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.Slider))
end

local function FindScrollRect(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.ScrollRect))
end

local function FindScrollbar(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.Scrollbar))
end

local function FindInputField(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.InputField))
end

local function FindRawImage(transform)
	return _searchComponent(transform, typeof(UnityEngineUI.RawImage))
end

return {
	FindComponent = FindComponent,
	GetChild = GetChild,
	FindTransDeep = FindTransDeep,
	FindButton = FindButton,
	FindImage = FindImage,
	FindText = FindText,
	FindToggle = FindToggle,
	FindSlider = FindSlider,
	FindScrollRect = FindScrollRect,
	FindScrollbar = FindScrollbar,
	FindInputField = FindInputField,
	FindRawImage = FindRawImage,
}
