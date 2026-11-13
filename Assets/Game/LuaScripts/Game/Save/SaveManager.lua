--[[
=============================================================================
SaveManager.lua - 存档落盘 / 读取 / 迁移
=============================================================================
Module:     Game/Save/SaveManager
Version:    1.0.0

Description:
	把 SaveData 持久化到磁盘。

	【为什么不用 JSON】
	  本工程内【没有】JSON 库（搜遍 LuaScripts 无 json/cjson 模块），
	  设计稿附录 E/N 的 JSON 方案无法直接落地。
	  因此改为零依赖方案：Lua 表 ⇄ Lua 字面量。
	    - 序列化：递归输出 {...} 字面量
	    - 反序列化：load("return " .. s)()
	  本地存档非不可信输入，且全程 pcall 包裹；日后若接入 cjson，
	  只需替换本文件内部的 _serialize / _deserialize，对外接口不变。

	【文件 IO】
	  通过 Storage 写入并校验 .tmp，替换前保留有效 .bak。
	  替换中断时读取备份；失败不回落到直接覆盖写入。
=============================================================================
]]

local Logger = require "Framework.UI.Utils.Logger"
local SaveData = require "Game.Save.SaveData"

local SaveManager = {}

local FILE_NAME = "saveData.lua"
local TMP_SUFFIX = ".tmp"
local BACKUP_SUFFIX = ".bak"

-- =============================================================================
-- 路径
-- =============================================================================

function SaveManager.GetPath()
	local ok, dir = pcall(function()
		return CS.UnityEngine.Application.persistentDataPath
	end)
	if ok and type(dir) == "string" and dir ~= "" then
		return dir .. "/save"
	end
	return "./save"
end

function SaveManager.GetFilePath()
	return SaveManager.GetPath() .. "/" .. FILE_NAME
end

-- =============================================================================
-- 序列化（Lua 表 ⇄ Lua 字面量）
-- =============================================================================

local RESERVED = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true,
}

local function isValidKey(k)
	return type(k) == "string" and k:match("^[%a_][%w_]*$") and not RESERVED[k]
end

---递归序列化为 Lua 字面量
function SaveManager._serialize(value, indent)
	indent = indent or 0
	local pad = string.rep("  ", indent)
	local pad2 = string.rep("  ", indent + 1)
	local t = type(value)

	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" then
		assert(value == value and value ~= math.huge and value ~= -math.huge, "Non-finite save number")
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t ~= "table" then
		return "nil"
	end

	-- 数组段
	local parts = {}
	local maxIndex = 0
	for i, v in ipairs(value) do
		maxIndex = i
		parts[#parts + 1] = pad2 .. SaveManager._serialize(v, indent + 1)
	end

	-- 哈希段（排除已输出的连续数组下标）
	local keys = {}
	for k in pairs(value) do
		local isArrayIndex = (type(k) == "number")
			and k == math.floor(k)
			and k >= 1
			and k <= maxIndex
		if not isArrayIndex then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

	for _, k in ipairs(keys) do
		local keyStr = isValidKey(k) and k or ("[" .. SaveManager._serialize(k) .. "]")
		parts[#parts + 1] = pad2 .. keyStr .. " = " .. SaveManager._serialize(value[k], indent + 1)
	end

	if #parts == 0 then return "{}" end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
end

local function validValues(value, seen)
	local kind = type(value)
	if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
	if kind == "string" or kind == "boolean" then return true end
	if kind ~= "table" or seen[value] then return false end
	seen[value] = true
	for key, item in pairs(value) do
		local keyType = type(key)
		if (keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean")
			or not validValues(key, seen) or not validValues(item, seen) then return false end
	end
	seen[value] = nil
	return true
end

local function matchesSchema(data, defaults)
	for key, expected in pairs(defaults) do
		local value = data[key]
		-- Missing fields remain migratable; present fields must keep their type.
		if value ~= nil then
			if type(value) ~= type(expected) then return false end
			if type(expected) == "table" and not matchesSchema(value, expected) then return false end
		end
	end
	return true
end

function SaveManager._isValid(data)
	return type(data) == "table" and validValues(data, {}) and matchesSchema(data, SaveData.Default())
end

function SaveManager._deserialize(content)
	if type(content) ~= "string" then return nil end
	-- Disk saves are return-prefixed; internal round trips may pass a bare table.
	local source = content:match("^%s*return%f[%W]") and content or ("return " .. content)
	local chunk = load(source, "SaveData", "t", {})
	if not chunk then return nil end

	local ok, result = pcall(chunk)
	if not ok then return nil end
	if not SaveManager._isValid(result) then return nil end
	return result
end

-- =============================================================================
-- Recoverable replacement; platform storage must throw on failed operations.
-- =============================================================================

function SaveManager._writeFile(path, content)
	local ok, err = pcall(function()
		-- 走 Storage 抽象：默认 FileStorage(System.IO)，PC/Android/iOS 行为不变；
		-- 微信小游戏注入 WX SDK 实现后本函数无需改动。
		-- Path.GetDirectoryName 是纯字符串运算，全平台可用。
		local storage = CS.Storage.Current
		local dir = CS.System.IO.Path.GetDirectoryName(path)
		if dir and not storage:DirectoryExists(dir) then
			storage:CreateDirectory(dir)
		end

		local tmp = path .. TMP_SUFFIX
		storage:WriteAllText(tmp, content)
		assert(storage:ReadAllText(tmp) == content, "Temporary save verification failed")
		if storage:FileExists(path) then
			local previous = storage:ReadAllText(path)
			if SaveManager._deserialize(previous) then
				local backup = path .. BACKUP_SUFFIX
				storage:WriteAllText(backup, previous)
				assert(storage:ReadAllText(backup) == previous, "Save backup verification failed")
			end
			storage:DeleteFile(path)
		end
		storage:MoveFile(tmp, path)
		assert(storage:ReadAllText(path) == content, "Committed save verification failed")
	end)

	if ok then return true end

	return false, err
end

function SaveManager._readFile(path)
	for _, candidate in ipairs({ path, path .. BACKUP_SUFFIX }) do
		local ok, content = pcall(function()
			local storage = CS.Storage.Current
			if not storage:FileExists(candidate) then return nil end
			return storage:ReadAllText(candidate)
		end)
		if ok and SaveManager._deserialize(content) then
			if candidate ~= path then Logger.Warn("SaveManager", "Recovered previous save backup") end
			return content
		end
	end
	return nil
end

-- =============================================================================
-- 对外接口
-- =============================================================================

---保存
function SaveManager.Save(data)
	if SaveData.IsOnline() then return false, "online_authority" end
	data = data or SaveData.Get()
	if not SaveManager._isValid(data) then
		Logger.Error("SaveManager", "Save rejected: invalid field type, number or cyclic data")
		return false
	end
	data.version = SaveData.VERSION

	local ok, err = SaveManager._writeFile(SaveManager.GetFilePath(), "return " .. SaveManager._serialize(data))
	if not ok then
		Logger.Error("SaveManager", "Save failed: %s", tostring(err))
		return false
	end
	Logger.Debug("SaveManager", "Saved to %s", SaveManager.GetFilePath())
	return true
end

---读取（失败/损坏返回 nil）
function SaveManager.Load()
	if SaveData.IsOnline() then return nil, "online_authority" end
	local content = SaveManager._readFile(SaveManager.GetFilePath())
	if not content or content == "" then return nil end

	local data = SaveManager._deserialize(content)
	if not data then
		Logger.Warn("SaveManager", "Save file corrupted, falling back to new save")
		return nil
	end
	return SaveManager.EnsureSchema(data)
end

---schema 补全：新增字段后旧档仍能正常读取（前向兼容）
function SaveManager.EnsureSchema(data)
	local def = SaveData.Default()
	if type(data) ~= "table" then return def end
	data.version = SaveData.VERSION
	return SaveManager._mergeDefaults(data, def)
end

function SaveManager._mergeDefaults(data, def)
	for k, dv in pairs(def) do
		if data[k] == nil then
			data[k] = dv
		elseif type(dv) == "table" and type(data[k]) == "table" then
			SaveManager._mergeDefaults(data[k], dv)
		end
	end
	return data
end

return SaveManager
