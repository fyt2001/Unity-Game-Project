--[[
=============================================================================
EnemyManager.lua V1.1
=============================================================================
Module:     Game/Battle/EnemyManager
Version:    1.1.0

Description:
    敌人管理器。管理所有敌人的创建、移动、伤害、死亡。
    
    性能设计（应对数百敌人同屏）：
        - 统一 Update 循环，不使用每个敌人的独立 Update
        - 敌人数据用纯 Lua table，不绑定 MonoBehaviour
        - 死亡敌人标记后延迟移除（避免遍历中修改列表）
        - 空间查询优化：使用网格分桶 + O(1) ID 查找
        - Grid 增量更新：只有跨 Cell 时才重新索引

Changelog V1.1:
    - 新增 _enemyMap 实现 O(1) ID 查找
    - Grid 增量更新：保存 enemy.gridX/gridY/gridKey 避免每帧无条件 remove/add
    - GetNearestEnemy 优先使用 Grid 空间搜索
    - GetNearestEnemies 使用 Top-N 小数组插入排序，避免全量 table.sort
    - 死亡流程统一：从 Grid、enemyMap、enemies 三处清理

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
end

function EnemyManager:Init()
    self.enemies = {}
    self._enemyMap = {}
    self._pendingRemove = {}
    self._grid = {}
end

function EnemyManager:SpawnEnemy(config)
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
    end
end

function EnemyManager:TakeDamage(enemyId, damage, isCrit)
    local enemy = self._enemyMap[enemyId]
    if not enemy or enemy.isDead then return false end

    enemy.hp = enemy.hp - damage

    if enemy.hp <= 0 then
        enemy.hp = 0
        enemy.isDead = true
        table.insert(self._pendingRemove, enemyId)
        self:_removeFromGrid(enemy, enemy.gridX, enemy.gridY)
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
            local nextRingMinDist = radius * GRID_SIZE
            if minDistSq < nextRingMinDist * nextRingMinDist then
                return nearest
            end
        end
    end

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
    if count <= 0 then return {} end

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
    local visitedCells = {}

    for radius = 0, maxRadius do
        for dgx = -radius, radius do
            for dgy = -radius, radius do
                if radius == 0 or math.abs(dgx) == radius or math.abs(dgy) == radius then
                    local key = (centerGX + dgx) .. "_" .. (centerGY + dgy)
                    if not visitedCells[key] then
                        visitedCells[key] = true
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
        end

        if topNCount >= count then
            local nextRingMinDist = radius * GRID_SIZE
            if topN[topNCount].distSq < nextRingMinDist * nextRingMinDist then
                break
            end
        end
    end

    if topNCount < count then
        for _, enemy in ipairs(self.enemies) do
            if not enemy.isDead then
                local dx = enemy.x - x
                local dy = enemy.y - y
                local distSq = dx * dx + dy * dy
                local alreadyIn = false
                for i = 1, topNCount do
                    if topN[i].enemy.id == enemy.id then
                        alreadyIn = true
                        break
                    end
                end
                if not alreadyIn then
                    insertTopN(enemy, distSq)
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
        if not enemy.isDead then count = count + 1 end
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
    enemy.gridX = gx
    enemy.gridY = gy
    enemy.gridKey = key
    if not self._grid[key] then
        self._grid[key] = {}
    end
    table.insert(self._grid[key], enemy)
end

function EnemyManager:_removeFromGrid(enemy, gx, gy)
    gx = gx or enemy.gridX
    gy = gy or enemy.gridY
    local key = gx and gy and (gx .. "_" .. gy) or enemy.gridKey
    if not key then return end
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
    if #self._pendingRemove == 0 then return end

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
end

return EnemyManager