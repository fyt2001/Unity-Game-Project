--[[
=============================================================================
EnemyManager.lua V1.1
=============================================================================
Module:     Game/Battle/EnemyManager
Version:    1.1.1

Description:
    敌人管理器。管理所有敌人的创建、移动、伤害、死亡。

    性能设计（应对数百敌人同屏）：
        - 统一 Update 循环，不使用每个敌人的独立 Update
        - 敌人数据用纯 Lua table，不绑定 MonoBehaviour
        - 死亡敌人标记后延迟移除（避免遍历中修改列表）
        - 空间查询优化：使用网格分桶 + O(1) ID 查找
        - Grid 增量更新：只有跨 Cell 时才重新索引
        - 最近目标查询使用 Grid 环形搜索 + 精确 Cell 距离下界

Changelog V1.1.1:
    - 修复 Grid 最近目标提前退出条件不严谨导致可能漏掉真正最近目标的问题
    - 增加 OnEnemyKilled 回调，统一死亡事件出口
    - Init 重置 ID 计数，保证同一个 Manager 重复开战时状态干净

Usage:
    local em = EnemyManager.New()
    em:Init()
    em:SpawnEnemy(config)
    em:Update(dt, playerX, playerY)
=============================================================================
]]

local Class = require "Framework.Core.Class"

local EnemyManager = Class.Define("EnemyManager")

local GRID_SIZE = 5

function EnemyManager:Ctor()
    self.enemies = {}
    self._enemyMap = {}
    self._idCounter = 0
    self._pendingRemove = {}

    self._grid = {}
    self.onEnemyKilled = nil
end

function EnemyManager:Init()
    self.enemies = {}
    self._enemyMap = {}
    self._idCounter = 0
    self._pendingRemove = {}
    self._grid = {}
    self.onEnemyKilled = nil
end

---设置敌人死亡回调
---@param callback function|nil function(enemyId, enemy)
function EnemyManager:SetOnEnemyKilled(callback)
    self.onEnemyKilled = callback
end

function EnemyManager:SpawnEnemy(config)
    config = config or {}

    self._idCounter = self._idCounter + 1
    local enemy = {
        id = self._idCounter,
        x = config.x or 0,
        y = config.y or 0,
        maxHp = config.hp or 50,
        hp = config.hp or 50,
        speed = config.speed or 2.0,
        damage = config.damage or 5,
        exp = config.exp or 10,
        enemyType = config.enemyType or "normal",
        isDead = false,
        aiState = "chase",
        attackCooldown = 0,
        attackInterval = config.attackInterval or 1.0,
        gridX = nil,
        gridY = nil,
        gridKey = nil,
    }

    table.insert(self.enemies, enemy)
    self._enemyMap[enemy.id] = enemy
    self:_addToGrid(enemy)
    return enemy
end

function EnemyManager:Update(dt, targetX, targetY)
    self:_flushRemoved()

    for _, enemy in ipairs(self.enemies) do
        if not enemy.isDead then
            self:_updateEnemy(enemy, dt, targetX, targetY)
        end
    end
end

function EnemyManager:_updateEnemy(enemy, dt, targetX, targetY)
    local dx = targetX - enemy.x
    local dy = targetY - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > 0 then
        dx = dx / dist
        dy = dy / dist
    end

    local moveSpeed = enemy.speed
    if enemy.aiState == "flee" then
        moveSpeed = enemy.speed * 1.5
        dx = -dx
        dy = -dy
    end

    local oldGridX = enemy.gridX
    local oldGridY = enemy.gridY

    enemy.x = enemy.x + dx * moveSpeed * dt
    enemy.y = enemy.y + dy * moveSpeed * dt

    local newGridX = math.floor(enemy.x / GRID_SIZE)
    local newGridY = math.floor(enemy.y / GRID_SIZE)

    if oldGridX ~= newGridX or oldGridY ~= newGridY then
        self:_removeFromGrid(enemy, oldGridX, oldGridY)
        self:_addToGrid(enemy, newGridX, newGridY)
    end

    if enemy.attackCooldown > 0 then
        enemy.attackCooldown = enemy.attackCooldown - dt
        if enemy.attackCooldown < 0 then
            enemy.attackCooldown = 0
        end
    end
end

function EnemyManager:TakeDamage(enemyId, damage, isCrit)
    local enemy = self._enemyMap[enemyId]
    if not enemy or enemy.isDead then
        return false
    end

    enemy.hp = enemy.hp - damage

    if enemy.hp <= 0 then
        enemy.hp = 0
        enemy.isDead = true
        table.insert(self._pendingRemove, enemyId)
        self:_removeFromGrid(enemy, enemy.gridX, enemy.gridY)

        if self.onEnemyKilled then
            self.onEnemyKilled(enemy.id, enemy)
        end

        return true
    end

    return false
end

function EnemyManager:GetEnemiesInRange(x, y, range, maxCount)
    local result = {}
    local rangeSq = range * range

    local minGX = math.floor((x - range) / GRID_SIZE)
    local maxGX = math.floor((x + range) / GRID_SIZE)
    local minGY = math.floor((y - range) / GRID_SIZE)
    local maxGY = math.floor((y + range) / GRID_SIZE)

    for gx = minGX, maxGX do
        for gy = minGY, maxGY do
            local key = gx .. "_" .. gy
            local cell = self._grid[key]
            if cell then
                for _, enemy in ipairs(cell) do
                    if not enemy.isDead then
                        local dx = enemy.x - x
                        local dy = enemy.y - y
                        if dx * dx + dy * dy <= rangeSq then
                            result[#result + 1] = enemy
                            if maxCount and #result >= maxCount then
                                return result
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

---计算一个 Grid Cell 内任意点到查询点的最小距离平方
function EnemyManager:_getCellMinDistSq(x, y, gx, gy)
    local minX = gx * GRID_SIZE
    local maxX = minX + GRID_SIZE
    local minY = gy * GRID_SIZE
    local maxY = minY + GRID_SIZE

    local dx = 0
    local dy = 0

    if x < minX then
        dx = minX - x
    elseif x > maxX then
        dx = x - maxX
    end

    if y < minY then
        dy = minY - y
    elseif y > maxY then
        dy = y - maxY
    end

    return dx * dx + dy * dy
end

---计算下一圈未搜索 Cell 的最小可能距离平方
function EnemyManager:_getNextRingMinDistSq(x, y, centerGX, centerGY, radius)
    local nextRadius = radius + 1
    local minDistSq = math.huge

    for dgx = -nextRadius, nextRadius do
        for dgy = -nextRadius, nextRadius do
            if math.abs(dgx) == nextRadius or math.abs(dgy) == nextRadius then
                local distSq = self:_getCellMinDistSq(
                    x,
                    y,
                    centerGX + dgx,
                    centerGY + dgy
                )
                if distSq < minDistSq then
                    minDistSq = distSq
                end
            end
        end
    end

    return minDistSq
end

function EnemyManager:GetNearestEnemy(x, y, exclude)
    local excludeSet = {}
    if exclude then
        for _, e in ipairs(exclude) do
            excludeSet[e.id] = true
        end
    end

    local centerGX = math.floor(x / GRID_SIZE)
    local centerGY = math.floor(y / GRID_SIZE)

    local nearest = nil
    local minDistSq = math.huge

    -- 先搜索局部 Grid。若候选已经不可能被下一圈击败，则可以安全提前结束。
    local maxRadius = 10
    for radius = 0, maxRadius do
        for dgx = -radius, radius do
            for dgy = -radius, radius do
                if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
                    local key = (centerGX + dgx) .. "_" .. (centerGY + dgy)
                    local cell = self._grid[key]
                    if cell then
                        for _, enemy in ipairs(cell) do
                            if not enemy.isDead and not excludeSet[enemy.id] then
                                local dx = enemy.x - x
                                local dy = enemy.y - y
                                local distSq = dx * dx + dy * dy
                                if distSq < minDistSq then
                                    minDistSq = distSq
                                    nearest = enemy
                                end
                            end
                        end
                    end
                end
            end
        end

        if nearest then
            local nextRingMinDistSq = self:_getNextRingMinDistSq(
                x,
                y,
                centerGX,
                centerGY,
                radius
            )
            if minDistSq <= nextRingMinDistSq then
                return nearest
            end
        end
    end

    -- 地图超出局部搜索范围时，使用全局 fallback 保证结果正确。
    if not nearest then
        for _, enemy in ipairs(self.enemies) do
            if not enemy.isDead and not excludeSet[enemy.id] then
                local dx = enemy.x - x
                local dy = enemy.y - y
                local distSq = dx * dx + dy * dy
                if distSq < minDistSq then
                    minDistSq = distSq
                    nearest = enemy
                end
            end
        end
    end

    return nearest
end

function EnemyManager:GetNearestEnemies(x, y, count)
    if count <= 0 then
        return {}
    end

    local centerGX = math.floor(x / GRID_SIZE)
    local centerGY = math.floor(y / GRID_SIZE)

    local topN = {}
    local topNCount = 0

    local function insertTopN(enemy, distSq)
        if topNCount < count then
            topNCount = topNCount + 1
            topN[topNCount] = { enemy = enemy, distSq = distSq }
            local i = topNCount
            while i > 1 and topN[i].distSq < topN[i - 1].distSq do
                topN[i], topN[i - 1] = topN[i - 1], topN[i]
                i = i - 1
            end
        elseif distSq < topN[topNCount].distSq then
            topN[topNCount] = { enemy = enemy, distSq = distSq }
            local i = topNCount
            while i > 1 and topN[i].distSq < topN[i - 1].distSq do
                topN[i], topN[i - 1] = topN[i - 1], topN[i]
                i = i - 1
            end
        end
    end

    local maxRadius = 15
    for radius = 0, maxRadius do
        for dgx = -radius, radius do
            for dgy = -radius, radius do
                if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
                    local key = (centerGX + dgx) .. "_" .. (centerGY + dgy)
                    local cell = self._grid[key]
                    if cell then
                        for _, enemy in ipairs(cell) do
                            if not enemy.isDead then
                                local dx = enemy.x - x
                                local dy = enemy.y - y
                                local distSq = dx * dx + dy * dy
                                insertTopN(enemy, distSq)
                            end
                        end
                    end
                end
            end
        end

        if topNCount >= count then
            local nextRingMinDistSq = self:_getNextRingMinDistSq(
                x,
                y,
                centerGX,
                centerGY,
                radius
            )
            if topN[topNCount].distSq <= nextRingMinDistSq then
                break
            end
        end
    end

    -- 如果局部 Grid 没覆盖足够候选，或仍可能存在更近的远端目标，
    -- 全局遍历只维护 Top-N，不再创建全量 distances + table.sort。
    local localBestDistSq = topNCount >= count and topN[topNCount].distSq or math.huge
    for _, enemy in ipairs(self.enemies) do
        if not enemy.isDead then
            local dx = enemy.x - x
            local dy = enemy.y - y
            local distSq = dx * dx + dy * dy

            if topNCount < count or distSq < localBestDistSq then
                insertTopN(enemy, distSq)
                if topNCount >= count then
                    localBestDistSq = topN[topNCount].distSq
                end
            end
        end
    end

    local result = {}
    for i = 1, topNCount do
        result[#result + 1] = topN[i].enemy
    end
    return result
end

function EnemyManager:GetAliveCount()
    local count = 0
    for _, enemy in ipairs(self.enemies) do
        if not enemy.isDead then
            count = count + 1
        end
    end
    return count
end

function EnemyManager:GetAllAlive()
    local result = {}
    for _, enemy in ipairs(self.enemies) do
        if not enemy.isDead then
            result[#result + 1] = enemy
        end
    end
    return result
end

function EnemyManager:_addToGrid(enemy, gx, gy)
    gx = gx or math.floor(enemy.x / GRID_SIZE)
    gy = gy or math.floor(enemy.y / GRID_SIZE)

    local key = gx .. "_" .. gy

    -- 防御性检查：同一个 Enemy 不允许重复挂在同一个 Cell。
    if enemy.gridKey == key then
        return
    end

    enemy.gridX = gx
    enemy.gridY = gy
    enemy.gridKey = key

    if not self._grid[key] then
        self._grid[key] = {}
    end

    table.insert(self._grid[key], enemy)
end

function EnemyManager:_removeFromGrid(enemy, gx, gy)
    local key

    if gx ~= nil and gy ~= nil then
        key = gx .. "_" .. gy
    else
        key = enemy.gridKey
    end

    if not key then
        return
    end

    local cell = self._grid[key]
    if cell then
        for i = #cell, 1, -1 do
            if cell[i].id == enemy.id then
                table.remove(cell, i)
                break
            end
        end

        if #cell == 0 then
            self._grid[key] = nil
        end
    end

    enemy.gridX = nil
    enemy.gridY = nil
    enemy.gridKey = nil
end

function EnemyManager:_flushRemoved()
    if #self._pendingRemove == 0 then
        return
    end

    local removeSet = {}
    for _, id in ipairs(self._pendingRemove) do
        removeSet[id] = true
    end

    local alive = {}
    for _, enemy in ipairs(self.enemies) do
        if not removeSet[enemy.id] then
            alive[#alive + 1] = enemy
        end
    end
    self.enemies = alive

    for _, id in ipairs(self._pendingRemove) do
        self._enemyMap[id] = nil
    end

    self._pendingRemove = {}
end

function EnemyManager:Cleanup()
    self:_flushRemoved()
end

function EnemyManager:Destroy()
    self.enemies = {}
    self._enemyMap = {}
    self._pendingRemove = {}
    self._grid = {}
    self.onEnemyKilled = nil
end

return EnemyManager
