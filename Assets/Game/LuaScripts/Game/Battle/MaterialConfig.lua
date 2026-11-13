--[[
=============================================================================
MaterialConfig.lua - 材料配置表
=============================================================================
Module:     Game/Battle/MaterialConfig
Version:    1.0.0

Description:
	怪物（slime/bat）死亡掉落的材料的 id → 名称/颜色/描述。
	color 为 RGB（0~1），供 C# 掉落模型染色使用。
=============================================================================
]]

local MaterialConfig = {}

MaterialConfig.Materials = {
	m_gel = {
		id = "m_gel",
		name = "史莱姆凝胶",
		color = { 0.30, 0.90, 0.40 },
		desc = "史莱姆掉落的粘稠凝胶，是炼金与附魔的基础素材。",
	},
	m_wing = {
		id = "m_wing",
		name = "蝙蝠之翼",
		color = { 0.60, 0.40, 0.90 },
		desc = "蝙蝠掉落的轻薄翼膜，轻盈而坚韧，适合制作轻甲。",
	},
}

function MaterialConfig.Get(id)
	return MaterialConfig.Materials[id]
end

return MaterialConfig
