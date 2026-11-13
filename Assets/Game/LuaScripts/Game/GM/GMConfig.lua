--[[
=============================================================================
GMConfig.lua - GM 调试工具的总开关与持久化
=============================================================================
说明：
  - DEBUG_DEFAULT：开发期默认关；正式出包前保持 false（D2）。
	  - 正式包禁止 GM；PlayerPrefs 仅控制编辑器 / Development Build。
  - 切换：Ctrl+Shift+G 持久化翻转（见 GMUI）。
	  - 连点解锁：仅开发环境登录页连点版本号 5 次 ⇒ SetEnabled(true) 复用同一个 GM_Enabled，
    解锁状态本身（_unlockedByTaps）只存在内存里，重启即清零，要重新连点一次。
  - ★ 唯一门控出口是 CanOpenPanel()：GMUI 的热键、UIGMModel 的 devOnly 过滤 etc. 都只调它，
    任何地方都不要再自己写 IsDev() 判断，否则门控一处改动漏掉另一处就会出现「dev 能开 release 也能开」。
=============================================================================
]]

local Unity_PlayerPrefs = CS.UnityEngine.PlayerPrefs
local KEY = "GM_Enabled"
local DEBUG_DEFAULT = false   -- Development builds can enable debugging; release builds cannot.

local GMConfig = {}

-- 连点解锁标记：仅在内存，不落盘。重启后回到 DEBUG_DEFAULT，必须再连点一次。
local _unlockedByTaps = false

-- 读当前 build 是否为开发包：优先 Debug.isDebugBuild，读不到再退 Application.isEditor。
-- 全程 pcall —— 离线/被裁剪的构建里 CS.UnityEngine.Debug 可能取不到 isDebugBuild 静态属性，
-- 读失败不能连带把整个 GMUI.Init() 打挂，所以这里统一降级为 false（保守：不开板子）。
local function _readStatics()
	local ok, v = pcall(function() return CS.UnityEngine.Debug.isDebugBuild end)
	if ok and v then return true end
	local ok2, v2 = pcall(function() return CS.UnityEngine.Application.isEditor end)
	return ok2 and v2 or false
end

---开发包判定：看的是 build 类型（isDebugBuild），与 IsEnabled() 完全无关，
-- 所以 DEBUG_DEFAULT=false 不会把 dev 包的 Ctrl+G 一起掐掉。
function GMConfig.IsDev()
	return _readStatics()
end

function GMConfig.IsEnabled()
	if not GMConfig.IsDev() then return false end
	if Unity_PlayerPrefs.HasKey(KEY) then
		return Unity_PlayerPrefs.GetInt(KEY) == 1
	end
	return DEBUG_DEFAULT
end

function GMConfig.SetEnabled(v)
	if not GMConfig.IsDev() then return false end
	Unity_PlayerPrefs.SetInt(KEY, v and 1 or 0)
	Unity_PlayerPrefs.Save()
	return true
end

function GMConfig.ToggleEnabled()
	GMConfig.SetEnabled(not GMConfig.IsEnabled())
end

---版本号连点是否已解锁（仅内存态，供 CanOpenPanel 与 [GM ON] 回显做守卫）
function GMConfig.IsUnlockedByTaps()
	return GMConfig.IsDev() and _unlockedByTaps
end

---置/清连点解锁标记（仅内存；落盘那一半交给 SetEnabled 走 GM_Enabled）
function GMConfig._SetUnlockedByTaps(v)
	_unlockedByTaps = GMConfig.IsDev() and v and true or false
end

-- ★ 唯一门控出口：任何「能不能开 GM 面板」的判断都只调它。
-- Release ignores persisted and in-memory unlock state.
function GMConfig.CanOpenPanel()
	return GMConfig.IsDev() and GMConfig.IsEnabled()
end

return GMConfig
