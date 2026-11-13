local Class = require "Framework.Core.Class"
local ObjectPool = require "Framework.Core.ObjectPool"
local EntityViewFactory = require "Game.Battle.View.EntityViewFactory"
local VFXConfig = require "Game.Battle.VFXConfig"
local VFXManager = require "Game.Battle.VFXManager"
local BattleLayers = require "Game.Battle.BattleLayers"

local BulletManager = Class.Define("BulletManager")

function BulletManager:Ctor()
	self.bullets = {}
	self._pendingRemove = {}
	self._pool = nil
	self._viewPool = { player = {}, enemy = {} }
	self.enemyManager = nil
end

function BulletManager:Init()
	-- 销毁上一局残留的子弹视图（活跃 + 池中），避免场景残留/泄漏
	local function destroyList(list)
		if not list then return end
		for _, v in ipairs(list) do pcall(function() v:Destroy() end) end
	end
	if self.bullets then
		for _, b in ipairs(self.bullets) do
			if b.view then pcall(function() b.view:Destroy() end) end
		end
	end
	-- 池 key 是 "faction|bulletType" 复合键：必须遍历全部，
	-- 不能只写死 player / enemy，否则元素弹体视图会泄漏。
	if self._viewPool then
		for _, list in pairs(self._viewPool) do destroyList(list) end
	end
	self.bullets = {}
	self._pendingRemove = {}
	self._viewPool = {}

	self._pool = ObjectPool.New(
		function()
			return {
				x = 0,
				y = 0,
				dirX = 0,
				dirY = 0,
				speed = 0,
				damage = 0,
				isCrit = false,
				range = 0,
				traveled = 0,
				pierce = false,
				bulletType = "normal",
				faction = "player",
				hitIds = {},
				_remove = false,
			}
		end,
		function(b)
			b.x = 0
			b.y = 0
			b.dirX = 0
			b.dirY = 0
			b.speed = 0
			b.damage = 0
			b.isCrit = false
			b.range = 0
			b.traveled = 0
			b.visualSpawnHeight = nil
			b.visualAge = 0
			b.pierce = false
			b.bulletType = "normal"
			b.faction = "player"
			b._remove = false

			for k in pairs(b.hitIds) do
				b.hitIds[k] = nil
			end
		end,
		32,
		256
	)
end

function BulletManager:Inject(enemyManager)
	self.enemyManager = enemyManager
end

function BulletManager:SpawnBullet(config)
	config = config or {}
	local bullet = self._pool:Get()

	bullet.x = config.x or 0
	bullet.y = config.y or 0
	bullet.dirX = config.dirX or 0
	bullet.dirY = config.dirY or 0
	bullet.speed = config.speed or 10
	bullet.damage = config.damage or 10
	bullet.isCrit = config.isCrit or false
	bullet.range = config.range or 10
	bullet.traveled = 0
	bullet.visualSpawnHeight = config.visualSpawnHeight
	bullet.visualAge = 0
	bullet.pierce = config.pierce or false
	bullet.bulletType = config.bulletType or "normal"
	bullet.faction = config.faction or "player"
	bullet._remove = false

	table.insert(self.bullets, bullet)
	-- 表现层：从对象池取一个子弹视图（按 阵营 + 元素 取，元素决定弹体模型）
	bullet.view = self:_acquireView(bullet.faction, bullet.bulletType, bullet.x, bullet.y, bullet.visualSpawnHeight)
	return bullet
end

--- 从视图池取一个子弹视图（缺失则新建）。
-- 池 key 必须带上 bulletType：不同元素的弹体模型不同，
-- 只按 faction 复用会把 frost 的模型发给 fire 子弹。
function BulletManager:_acquireView(faction, bulletType, x, y, height)
	faction = faction or "player"
	bulletType = bulletType or "normal"
	local key = faction .. "|" .. bulletType
	local pool = self._viewPool[key]
	local v = (pool and #pool > 0) and table.remove(pool)
		or EntityViewFactory.CreateBulletView(faction, bulletType)
	if v then
		v.bulletType = bulletType
		v:SetActive(true)
		v:SetFaction(faction)
		-- 三步顺序不能乱：
		-- ① 整体重置：清残留拖尾 + 清掉转向基准（_lastX）
		if v.ResetVisual then v:ResetVisual() end
		-- ② 归位到本次出生点。此时 _lastX 已清，
		--    不会按「旧死亡位置 → 新出生点」算出一个错误朝向
		if v.SetPosition then v:SetPosition(x or 0, y or 0, height) end
		-- ③ 再清一次拖尾：② 那次瞬移会被 TrailRenderer 记成一条长尾
		--    （表现正是「残留上一次的轨迹」），必须在归位之后抹掉
		if v.ClearTrails then v:ClearTrails() end
	end
	return v
end

--- 回收子弹视图（隐藏并放回池）
function BulletManager:_releaseView(view)
	if not view then return end
	pcall(function() view:SetActive(false) end)
	-- key 与 _acquireView 保持一致（含 bulletType）
	local key = (view.faction or "player") .. "|" .. (view.bulletType or "normal")
	self._viewPool[key] = self._viewPool[key] or {}
	table.insert(self._viewPool[key], view)
end

function BulletManager:Update(dt)
	for _, bullet in ipairs(self.bullets) do
		if not bullet._remove then
			bullet.visualAge = bullet.visualAge + dt
			local moveDist = bullet.speed * dt
			bullet.x = bullet.x + bullet.dirX * moveDist
			bullet.y = bullet.y + bullet.dirY * moveDist
			bullet.traveled = bullet.traveled + moveDist

			if bullet.traveled >= bullet.range then
				self:Remove(bullet)
			end
		end
	end

	-- 表现层：同步存活子弹视图坐标
	for _, bullet in ipairs(self.bullets) do
		if not bullet._remove and bullet.view then
			local height = BattleLayers.Projectile
			if bullet.visualSpawnHeight then
				local t = math.min(1, bullet.visualAge / 0.08)
				height = bullet.visualSpawnHeight + (height - bullet.visualSpawnHeight) * t
			end
			bullet.view:SetPosition(bullet.x, bullet.y, height)
		end
	end
end

---移除子弹
---@param byHit boolean|nil true=被命中而消失 → 播 impact；nil/false=射程耗尽自然消散
function BulletManager:Remove(bullet, byHit)
	if not bullet or bullet._remove then
		return
	end

	bullet._remove = true
	self._pendingRemove[#self._pendingRemove + 1] = bullet

	-- 只有「被命中」才播冲击特效：射程耗尽属于消散，再播一次 impact
	-- 会在地图边缘凭空冒一堆爆炸，还会和 DamageSystem 的受击特效重复叠加。
	if not byHit then return end

	pcall(function()
		local t = bullet.bulletType or "normal"
		local cfg = VFXConfig.ProjectileType[t]
		if cfg and cfg.impact then
			VFXManager.Spawn(cfg.impact, bullet.x, bullet.y, BattleLayers.Projectile)
		end
	end)
end

function BulletManager:Cleanup()
	if #self._pendingRemove == 0 then
		return
	end

	for _, bullet in ipairs(self._pendingRemove) do
		for i = #self.bullets, 1, -1 do
			if self.bullets[i] == bullet then
				if bullet.view then self:_releaseView(bullet.view); bullet.view = nil end
				table.remove(self.bullets, i)
				break
			end
		end
		self._pool:Release(bullet)
	end

	self._pendingRemove = {}
end

function BulletManager:GetActiveBullets()
	return self.bullets
end

function BulletManager:GetActiveCount()
	return #self.bullets
end

function BulletManager:Destroy()
	-- 表现层：销毁所有子弹视图（活跃 + 池中）
	if self.bullets then
		for _, b in ipairs(self.bullets) do
			if b.view then pcall(function() b.view:Destroy() end) end
		end
	end
	if self._viewPool then
		for _, list in pairs(self._viewPool) do
			for _, v in ipairs(list) do pcall(function() v:Destroy() end) end
		end
	end

	self.bullets = {}
	self._pendingRemove = {}

	if self._pool then
		self._pool:Clear()
	end

	self._pool = nil
	self._viewPool = nil
	self.enemyManager = nil
end

return BulletManager
