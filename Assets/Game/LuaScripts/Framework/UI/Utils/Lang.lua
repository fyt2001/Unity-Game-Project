--[[
-- Lang.lua - 轻量多语言文案表（最小骨架，对齐大厂 i18n 规范）
-- 用法：
--     local Lang = require "Framework.UI.Utils.Lang"
--     label:SetText(Lang.Get("app_ver") .. version)
-- 设计：当前仅中文。结构保留「key → 文本」映射，后续可平滑替换为完整 i18n
--      （按 key 查多语言表 / 远程配置 / 语种切换），对外接口 Lang.Get(key) 保持稳定。
-- 约束：UI 展示文本一律经此入口，禁止在业务文件硬编码文案（见 lua-coding-standards 规则第 7 节）。
--]]
local Lang = {}

-- 文案表（key → 当前语种文本）
local _texts = {
	app_ver = "App Ver: ",
	res_ver = "Res Ver: ",
	loading_init = "正在初始化...",
	loading_done = "加载完成",
}

-- 取文案；缺 key 时回退返回 key 本身，便于发现漏配
function Lang.Get(key)
	return _texts[key] or key
end

return Lang
