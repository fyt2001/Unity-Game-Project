--[[
=============================================================================
ChainLightningView.lua - 闪电链连线（程序化 LineRenderer，不依赖美术资源）
=============================================================================
Module:     Game/Battle/View/ChainLightningView

Description:
	由 WeaponSystem:_attackChain 调用，把「起点 → 每个被链中的敌人」画成
	一条带锯齿的闪电连线，短暂存在后淡出销毁。

	为什么用程序化 LineRenderer 而非预制体：
	  - 本套 Casual RPG VFX 只有飞行弹体，没有「连线 / 电火花」素材（见 VFXConfig 注释）；
	  - LineRenderer 用引擎默认材质即可显示纯色发光线，无需额外资源，
	    保证在美术接入前也能看到明显的「链」视觉（之前完全看不到连线）；
	  - 颜色 / 宽度 / 存活时长 / 抖动幅度全部由 VFXConfig 透传，符合「表现参数数据化」规范。

	生命周期：自建 GameObject + LineRenderer，向 UpdateManager 注册淡出计时，
	到点后 RemoveUpdate + Destroy，不依赖逻辑层喂 dt（与 EntityViewBase 同理）。
]]
local UnityEngine = CS.UnityEngine
local UpdateManager = require "Framework.Core.UpdateManager"

local ChainLightningView = {}
local lineMaterial

---@param points table 逻辑坐标点序列（含起点与每个跳跃落点）{{x=,y=}, ...}
---@param params table { height, lifetime, jitter, width, color={r,g,b} }
function ChainLightningView.Spawn(points, params)
	if not points or #points < 2 then return end
	params = params or {}
	local height   = params.height or 0.6
	local lifetime = params.lifetime or 0.18
	local jitter   = params.jitter or 0.35
	local width    = params.width or 0.12
	local col      = params.color or { 0.6, 0.85, 1.0 }

	local go
	local ok = pcall(function()
		go = UnityEngine.GameObject(params.name or "ChainLightning")
	end)
	if not ok or not go then return end

	local lr
	ok = pcall(function()
		lr = go:AddComponent(typeof(UnityEngine.LineRenderer))
	end)
	if not ok or not lr then
		pcall(function() UnityEngine.Object.Destroy(go) end)
		return
	end

	-- Explicit Resources material keeps the shader available in built players as well.
	if not lineMaterial then
		lineMaterial = UnityEngine.Resources.Load("VFX/Combat/BeamLine", typeof(UnityEngine.Material))
	end
	lr.sharedMaterial = lineMaterial
	lr.useWorldSpace = true
	pcall(function() lr.alignment = UnityEngine.LineAlignment.View end)
	lr.startWidth = width
	lr.endWidth = width * 0.5

	-- 逐段细分 + 垂直方向随机抖动，形成锯齿状闪电
	local worldPts = {}
	local steps = 6
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local dx, dy = b.x - a.x, b.y - a.y
		local len = math.sqrt(dx * dx + dy * dy)
		local nx, ny = 0, 0
		if len > 0.0001 then nx, ny = -dy / len, dx / len end
		for s = 0, steps do
			local t = s / steps
			local px = a.x + dx * t
			local py = a.y + dy * t
			if s ~= 0 and s ~= steps then
				local j = (math.random() * 2 - 1) * jitter * (0.25 + len * 0.12)
				px = px + nx * j
				py = py + ny * j
			end
			worldPts[#worldPts + 1] = UnityEngine.Vector3(px, height, py)
		end
	end

	lr.positionCount = #worldPts
	for i = 1, #worldPts do
		lr:SetPosition(i - 1, worldPts[i])
	end

	local baseColor = UnityEngine.Color(col[1], col[2], col[3], 1)
	lr.startColor = baseColor
	lr.endColor = baseColor

	-- 存活期内淡出后销毁：记录 updateId 以便精准注销，避免回调持续堆积
	local elapsed = 0
	local tickId
	tickId = UpdateManager:GetInstance():AddUpdate(function(dt)
		elapsed = elapsed + dt
		local k = 1 - elapsed / lifetime
		if k <= 0 then
			pcall(function() UpdateManager:GetInstance():RemoveUpdate(tickId) end)
			pcall(function() UnityEngine.Object.Destroy(go) end)
			return
		end
		local a = math.max(0, k)
		local c = UnityEngine.Color(col[1], col[2], col[3], a)
		lr.startColor = c
		lr.endColor = c
	end, ChainLightningView)
end

return ChainLightningView
