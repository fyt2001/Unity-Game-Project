--[[
=============================================================================
CJKFont.lua - 中文 SDF 字体统一入口
=============================================================================
Module:     Framework/UI/Utils/CJKFont

Description:
	UI 的中文一律用 AlibabaPuHuiTiSDF（阿里普惠体 3.0 Regular 静态预烘焙）。

	【为什么需要它】
	工程原有字体都不够用：
	  - "LiberationSans SDF"（TMP 自带拉丁字体）：0 个汉字
	  - "CJK SDF"（Assets/Game/Fonts）：只有 131 个汉字，UI 文案实际要 1138 个
	所以不换字体就会有大量 □。

	【字体与烘焙策略】
	  源字体：AlibabaPuHuiTi-3-55-Regular.ttf（阿里普惠体 3.0，永久免费商用）
	  烘焙集：工程实扫 UI 字符 1138 + ASCII 95 + GB2312 一级 3755 + 标点 ≈ 4005 字
	  AtlasPopulationMode = Static（运行时零动态扩容、零掉帧）
	  Static 下 TMP 会自动清空 m_SourceFontFile ⇒ 源 .ttf 不随包，仅编辑器侧保留
	  生成工具：Assets/Game/Editor/FontTools/TMPFontBaker.cs（菜单 Tools/字体/）

	【历史坑：属性名不是 fontAsset】
	原先七个面板各写一份 loadTmpFont()，执行 `tmp.fontAsset = font`。
	但 TMP_Text 上的属性叫 **font**（类型 TMP_FontAsset），**没有 fontAsset**；
	xLua 找不到成员会抛错，而调用点外面包了 pcall —— 于是这些"覆盖"
	从头到尾都是静默空操作，一次都没生效过。本模块统一用 `.font`。

	【两条生效路径，互为补充】
	1) InstallGlobalFallback()：把本字体加进 TMP 全局 fallback 列表。
	   主字体缺字形时 TMP 自动回落取字 —— 全工程所有 TMP 一次性生效，
	   包含运行时动态创建的 TMP，且无需改任何 prefab。**首选**。
	2) Apply / ApplyAll：直接把 TMP 的 font 换成本字体（显式、彻底）。
	   给需要完全统一字形的面板用。

	【拿不到字体怎么办】
	返回 nil，调用方什么都不做 —— 保留 prefab 预置字体。
	**绝不退化成 LiberationSans**（那是把中文变 □ 的行为）。
=============================================================================
]]

local CJKFont = {}

---Resources 下的中文 SDF 字体（Assets/Game/Resources/Fonts/AlibabaPuHuiTiSDF.asset）
local FONT_PATH = "Fonts/AlibabaPuHuiTiSDF"

local cached = nil
local tried = false
local fallbackInstalled = false

---取中文 SDF 字体；拿不到返回 nil（调用方必须保留 prefab 预置字体）
---@return userdata|nil TMP_FontAsset
function CJKFont.Get()
	if tried then return cached end
	tried = true
	cached = false

	local ok, font = pcall(function()
		return CS.UnityEngine.Resources.Load(FONT_PATH, typeof(CS.TMPro.TMP_FontAsset))
	end)

	if ok and font then
		cached = font
	else
		print("[CJKFont] 加载 " .. FONT_PATH .. " 失败，沿用 prefab 预置字体")
	end

	if cached then return cached end
	return nil
end

---把单个 TMP 的字体换成中文 SDF；拿不到字体或 tmp 为空就什么都不做
---@param tmp userdata|nil TextMeshProUGUI / TMP_Text 组件
function CJKFont.Apply(tmp)
	if not tmp then return end
	local font = CJKFont.Get()
	if not font then return end
	pcall(function() tmp.font = font end)
end

---把 root 下所有 TMP 的字体换成中文 SDF（不含 root 自身）
---@param root userdata|nil Transform
---@return number 实际替换的 TMP 个数
function CJKFont.ApplyAll(root)
	local font = CJKFont.Get()
	if not root or not font then return 0 end

	local count = 0
	local stack = { root }
	while #stack > 0 do
		local tr = stack[#stack]
		stack[#stack] = nil
		local c = tr.childCount
		for i = 0, c - 1 do
			local ch = tr:GetChild(i)
			if ch then
				stack[#stack + 1] = ch
				local ok, t = pcall(function()
					return ch:GetComponent(typeof(CS.TMPro.TextMeshProUGUI))
				end)
				if ok and t then
					pcall(function() t.font = font end)
					count = count + 1
				end
			end
		end
	end
	return count
end

---把本字体注册为 TMP 全局 fallback（幂等）
---注册后：任何 TMP（含动态创建）缺中文字形时都会自动回落到本字体
---@return boolean 是否注册成功
function CJKFont.InstallGlobalFallback()
	if fallbackInstalled then return true end

	local font = CJKFont.Get()
	if not font then return false end

	local ok, err = pcall(function()
		local list = CS.TMPro.TMP_Settings.fallbackFontAssets
		if list == nil then error("TMP_Settings.fallbackFontAssets is nil") end
		for i = 0, list.Count - 1 do
			if list[i] == font then
				fallbackInstalled = true
				return
			end
		end
		list:Add(font)
		fallbackInstalled = true
	end)

	if not ok then
		print("[CJKFont] 注册全局 fallback 失败：" .. tostring(err))
	end
	return fallbackInstalled
end

return CJKFont
