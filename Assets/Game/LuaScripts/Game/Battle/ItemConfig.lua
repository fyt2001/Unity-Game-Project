--[[
=============================================================================
ItemConfig.lua - 道具配置表
=============================================================================
Module:     Game/Battle/ItemConfig
Version:    1.0.0

Description:
	道具（与武器、材料区分）的基础定义。
	当前掉落系统已支持 item 类掉落（DropSystem:SpawnItemDrop），
	与 weapon（青色小剑模型）/ material（彩色球模型）在场景中用不同 3D 模型区分。
	具体哪个来源投放道具，由掉落来源决定（如后续 Boss / 事件接入）。
=============================================================================
]]

local ItemConfig = {}

ItemConfig.Items = {
	i_potion = {
		id = "i_potion",
		name = "治疗药水",
		kind = "consumable",
		desc = "立即回复 30% 最大生命。",
	},
	i_bomb = {
		id = "i_bomb",
		name = "爆破雷",
		kind = "throwable",
		desc = "对范围内敌人造成大量伤害。",
	},
}

function ItemConfig.Get(id)
	return ItemConfig.Items[id]
end

return ItemConfig
