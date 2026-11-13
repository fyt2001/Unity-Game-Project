--[[
=============================================================================
BattleLayers.lua - 战斗世界分层高度
=============================================================================
Module:     Game/Battle/BattleLayers

Description:
	坐标约定：逻辑坐标 (x, y) → Unity 世界坐标 Vector3(x, height, y)。
	本模块统一定义这里的 height。

	此前这些高度被硬编码在 6 个文件里（0.6 / 0.5 / 0.1 / 0 …），
	同一层要调整就得全局搜一遍，且很容易漏改导致特效浮空或穿地。
	现在改这里一处即可。

层级（由低到高）：
	Ground     0.0   地面平面：敌人、掉落物站立位置
	Footstep   0.1   脚步尘土
	GroundHit  0.5   地面附近的受击 / 死亡特效
	Projectile 0.6   子弹飞行层
	Overhead   1.6   头顶锚点（血条等，与 HomeSceneBootstrapper 保持一致）
=============================================================================
]]

local BattleLayers = {
	Ground     = 0.0,
	Footstep   = 0.1,
	GroundHit  = 0.5,
	Projectile = 0.6,
	Drop       = 0.6,   -- 掉落物悬浮基准（在其上下做 sin 浮动）
	Overhead   = 1.6,
}

return BattleLayers
