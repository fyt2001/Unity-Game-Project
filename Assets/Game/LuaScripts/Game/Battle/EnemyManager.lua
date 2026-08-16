--[[
=============================================================================
EnemyManager.lua V1.1.2
=============================================================================
Description:
    敌人管理器。统一管理敌人数据、移动、空间索引、伤害与死亡。

V1.1.2 修复：
    - enemyMap O(1) ID 查找
    - Grid 仅跨 Cell 时更新
    - 死亡后立即从 enemyMap / Grid 移除，数组仍延迟清理
    - 最近目标查询使用 Grid 候选 + 保守提前退出条件
    - Top-N 查询避免全量 table.sort
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
end

function EnemyManager:Init()
    self.enemies = {}
    self._enemyMap = {}
    self._idCounter = 0
    self._pendingRemove = {}
    self._grid = {}
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

    self.enemies[#self.enemies + 1] = enemy
    self._enemyMap[enemy.id] = enemy
    self:_addToGrid(enemy)
    return enemy
end

function EnemyManager:Update(dt, targetX, targetY)
    self:_flushRemoved()
    targetX = targetX or 0
    targetY = targetY or 0

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
        enemy.attackCooldown = math.max(0, enemy.attackCooldown - dt)
    end
end

function EnemyManager:TakeDamage(enemyId, damage, isCrit)
    local enemy = self._enemyMap[enemyId]
    if not enemy or enemy.isDead then return false end

    enemy.hp = enemy.hp - math.max(0, damage or 0)
    if enemy.hp <= 0 then
        enemy.hp = 0
        enemy.isDead = true
        self._enemyMap[enemyId] = nil
        self:_removeFromGrid(enemy, enemy.gridX, enemy.gridY)
        self._pendingRemove[#self._pendingRemove + 1] = enemyId
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
            local cell = self._grid[gx .. "_" .. gy]
            if cell then
                for _, enemy in ipairs(cell) do
                    if not enemy.isDead then
                        local dx = enemy.x - x
                        local dy = enemy.y - y
                        if dx * dx + dy * dy <= rangeSq then
                            result[#result + 1] = enemy
                            if maxCount and #result >= maxCount then return result end
                        end
                    end
                end
            end
        end
    end
    return result
end

function EnemyManager:GetNearestEnemy(x, y, exclude)
    local excludeSet = {}
    if exclude then
        for _, enemy in ipairs(exclude) do excludeSet[enemy.id] = true end
    end

    local centerGX = math.floor(x / GRID_SIZE)
    local centerGY = math.floor(y / GRID_SIZE)
    local nearest = nil
    local minDistSq = math.huge
    local maxRadius = 10

    for radius = 0, maxRadius do
        for dgx = -radius, radius do
            for dgy = -radius, radius do
                if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
                    local cell = self._grid[(centerGX + dgx) .. "_" .. (centerGY + dgy)]
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

        -- 保守下界：尚未搜索的下一圈不可能比 radius * GRID_SIZE 更近。
        -- 使用严格小于，避免边界 Cell 导致错误提前返回。
        if nearest and radius > 0 and minDistSq < (radius * GRID_SIZE) ^ 2 then
            return nearest
        end
    end

    -- 超出预设半径时，全量 fallback 保证结果仍是全局最近。
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
    return nearest
end

function EnemyManager:GetNearestEnemies(x, y, count)
    if not count or count <= 0 then return {} end

    local centerGX = math.floor(x / GRID_SIZE)
    local centerGY = math.floor(y / GRID_SIZE)
    local topN = {}
    local topNCount = 0

    local function insertTopN(enemy, distSq)
        if topNCount < count then
            topNCount = topNCount + 1
            topN[topNCount] = { enemy = enemy, distSq = distSq }
        elseif distSq >= topN[topNCount].distSq then
            return
        else
            topN[topNCount] = { enemy = enemy, distSq = distSq }
        end

        local i = topNCount
        while i > 1 and topN[i].distSq < topN[i - 1].distSq do
            topN[i], topN[i - 1] = topN[i - 1], topN[i]
            i = i - 1
        end
    end

    local maxRadius = 15
    for radius = 0, maxRadius do
        for dgx = -radius, radius do
            for dgy = -radius, radius do
                if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
                    local cell = self._grid[(centerGX + dgx) .. "_" .. (centerGY + dgy)]
                    if cell then
                        for _, enemy in ipairs(cell) do
                            if not enemy.isDead then
                                local dx = enemy.x - x
                                local dy = enemy.y - y
                                insertTopN(enemy, dx * dx + dy * dy)
                            end
                        end
                    end
                end
            end
        end

        -- topN 中第 N 近目标已经小于下一圈可能出现的保守距离时即可停止。
        if topNCount >= count and radius > 0 and topN[topNCount].distSq < (radius * GRID_SIZE) ^ 2 then
            break
        end
    end

    -- 如果没有足够候选，或搜索到最大半径仍不能证明正确性，则 fallback。
    -- fallback 仍使用 Top-N，不再创建全量 distances + table.sort。
    if topNCount < count or topNCount == count and maxRadius > 0 and topN[topNCount].distSq >= (maxRadius * GRID_SIZE) ^ 2 then
        for _, enemy in ipairs(self.enemies) do
            if not enemy.isDead then
                local dx = enemy.x - x
                local dy = enemy.y - y
                insertTopN(enemy, dx * dx + dy * dy)
            end
        end
    end

    local result = {}
    for i = 1, topNCount do result[i] = topN[i].enemy end
    return result
end

function EnemyManager:GetAliveCount()
    local count = 0
    for _, enemy in ipairs(self.enemies) do
        if not enemy.isDead then count = count + 1 end
    end
    return count
end

function EnemyManager:GetAllAlive()
    local result = {}
    for _, enemy in ipairs(self.enemies) do
        if not enemy.isDead then result[#result + 1] = enemy end
    end
    return result
end

function EnemyManager:_addToGrid(enemy, gx, gy)
    gx = gx or math.floor(enemy.x / GRID_SIZE)
    gy = gy or math.floor(enemy.y / GRID_SIZE)
    local key = gx .. "_" .. gy
    enemy.gridX = gx
    enemy.gridY = gy
    enemy.gridKey = key

    local cell = self._grid[key]
    if not cell then
        cell = {}
        self._grid[key] = cell
    end
    cell[#cell + 1] = enemy
end

function EnemyManager:_removeFromGrid(enemy, gx, gy)
    gx = gx or enemy.gridX
    gy = gy or enemy.gridY
    if gx == nil or gy == nil then return end

    local key = gx .. "_" .. gy
    local cell = self._grid[key]
    if cell then
        for i = #cell, 1, -1 do
            if cell[i] == enemy then
                table.remove(cell, i)
                break
            end
        end
        if #cell == 0 then self._grid[key] = nil end
    end

    enemy.gridX = nil
    enemy.gridY = nil
    enemy.gridKey = nil
end

function EnemyManager:_flushRemoved()
    if #self._pendingRemove == 0 then return end

    local removeSet = {}
    for _, id in ipairs(self._pendingRemove) do removeSet[id] = true end

    local alive = {}
    for _, enemy in ipairs(self.enemies) do
        if not removeSet[enemy.id] then alive[#alive + 1] = enemy end
    end

    self.enemies = alive
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
    self._idCounter = 0
end

return EnemyManager
