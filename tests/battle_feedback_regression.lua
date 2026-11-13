local EnemyManager = require "Game.Battle.EnemyManager"
local VFXConfig = require "Game.Battle.VFXConfig"

local function manager(positions, reverse)
    local m = EnemyManager.New()
    for i, p in ipairs(positions) do
        local e = { id = i, x = p[1], y = p[2], speed = p.speed or 0,
            sepMass = p.mass or 1, attackRange = p.range or 100,
            aiState = "chase", attackCooldown = 100, isDead = false }
        m.enemies[#m.enemies + 1] = e
        m._enemyMap[i] = e
        m:_addToGrid(e)
    end
    if reverse then
        for i = 1, math.floor(#m.enemies / 2) do
            local j = #m.enemies - i + 1
            m.enemies[i], m.enemies[j] = m.enemies[j], m.enemies[i]
        end
    end
    return m
end

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

local shallow = manager({{0, 0}, {1.099, 0}})
shallow:Update(1/60, 0, 0)
assert(math.abs(shallow._enemyMap[1].x) < 0.0001, "shallow overlap still creates fixed-speed push")

local overlap = manager({{0, 0}, {0, 0}})
for _ = 1, 300 do overlap:Update(1/60, 0, 0) end
assert(distance(overlap.enemies[1], overlap.enemies[2]) > 1.09, "identical positions never separate")
local before = overlap.enemies[1].x
for _ = 1, 60 do overlap:Update(1/60, 0, 0) end
assert(math.abs(overlap.enemies[1].x - before) < 0.001, "pair does not settle")

local mass = manager({{0, 0}, {.5, 0, mass = 12}})
mass:Update(1/60, 0, 0)
local ratio = math.abs(mass.enemies[1].x) / math.abs(mass.enemies[2].x - .5)
assert(math.abs(ratio - 12) < 0.001, "boss mass weighting reversed")

local positions = {}
for i = 1, 32 do
    positions[i] = { (i % 8) * .07 - .25, math.floor((i - 1) / 8) * .07 - .1 }
end
local a, b = manager(positions), manager(positions, true)
for _ = 1, 300 do a:Update(1/60, 0, 0); b:Update(1/60, 0, 0) end
local orderError = 0
for id = 1, 32 do
    orderError = math.max(orderError, distance(a._enemyMap[id], b._enemyMap[id]))
end
assert(orderError < 0.000001, "frame movement depends on iteration order")
local maxLateMotion = 0
for _ = 1, 120 do
    local previous = {}
    for id = 1, 32 do previous[id] = {x = a._enemyMap[id].x, y = a._enemyMap[id].y} end
    a:Update(1/60, 0, 0)
    for id = 1, 32 do maxLateMotion = math.max(maxLateMotion, distance(previous[id], a._enemyMap[id])) end
end
assert(maxLateMotion < 0.005, "crowd has large late jitter")

local frameDistances = {}
for _, fps in ipairs({30, 60, 120}) do
    local m = manager({{0, 0}, {.2, 0}})
    for _ = 1, 5 * fps do m:Update(1/fps, 0, 0) end
    frameDistances[#frameDistances + 1] = distance(m.enemies[1], m.enemies[2])
end
assert(math.abs(frameDistances[1] - frameDistances[3]) < .001, "frame-rate dependent settling")

local chase = manager({{10, 0, speed = 100, range = 1.3}})
chase:Update(1, 0, 0)
assert(math.abs(chase.enemies[1].x - 1.3) < .000001, "chase overshoots attack stopping range")
local pausedX, pausedY = chase.enemies[1].x, chase.enemies[1].y
chase:Update(0, 0, 0)
assert(chase.enemies[1].x == pausedX and chase.enemies[1].y == pausedY, "zero-dt update changed position")

local blockedBoss = manager({{3, 0, mass = 12, speed = 1, range = 1}, {2.5, 0}})
blockedBoss:Update(1/60, 0, 0)
assert(blockedBoss._enemyMap[1].x < 2.99, "boss completely brakes for a light blocker")
local fleeing = manager({{3, 0, speed = 2, range = 1}, {3.5, 0}})
fleeing._enemyMap[1].aiState = "flee"
fleeing:Update(1/60, 0, 0)
assert(fleeing._enemyMap[1].x > 3.03, "flee speed was swallowed by chase yielding")

local crowdedChase = {}
for i = 1, 32 do crowdedChase[i] = {3 + (i%8)*.03, math.floor((i-1)/8)*.03, speed = 1.5, range = 1.2} end
local cm = manager(crowdedChase)
for _ = 1, 1800 do cm:Update(1/60, 0, 0) end
local lateChaseStep, minimumSpacing = 0, 100
for _ = 1, 120 do
    local previous = {}
    for id = 1, 32 do previous[id] = {x = cm._enemyMap[id].x, y = cm._enemyMap[id].y} end
    cm:Update(1/60, 0, 0)
    for id = 1, 32 do lateChaseStep = math.max(lateChaseStep, distance(previous[id], cm._enemyMap[id])) end
end
for i = 1, 32 do for j = i+1, 32 do minimumSpacing = math.min(minimumSpacing, distance(cm._enemyMap[i], cm._enemyMap[j])) end end
assert(minimumSpacing > .7, "crowded pursuit compresses bodies too tightly")
assert(lateChaseStep < .003, "crowded pursuit fails to settle")

for _, fps in ipairs({30, 120}) do
    local m = manager(crowdedChase)
    for _ = 1, 30*fps do m:Update(1/fps, 0, 0) end
    local maxSpeed, minSpacing = 0, 100
    for _ = 1, 2*fps do
        local previous = {}
        for id = 1, 32 do previous[id] = {x=m._enemyMap[id].x, y=m._enemyMap[id].y} end
        m:Update(1/fps, 0, 0)
        for id = 1, 32 do maxSpeed = math.max(maxSpeed, distance(previous[id], m._enemyMap[id])*fps) end
    end
    for i = 1, 32 do for j = i+1, 32 do minSpacing = math.min(minSpacing, distance(m._enemyMap[i], m._enemyMap[j])) end end
    assert(minSpacing > .7 and maxSpeed < .25, "crowded pursuit failed at " .. fps .. "fps")
end

local oldCenter = 0
for _, e in ipairs(cm.enemies) do oldCenter = oldCenter + e.x/32 end
for _ = 1, 300 do cm:Update(1/60, 6, 0) end
local newCenter = 0
for _, e in ipairs(cm.enemies) do newCenter = newCenter + e.x/32 end
assert(newCenter > oldCenter+.5, "settled crowd fails to follow a moved target")

for _, path in ipairs(VFXConfig.AllPaths()) do
    assert(CS.UnityEngine.Resources.Load(path, typeof(CS.UnityEngine.GameObject)) ~= nil, "missing VFX " .. path)
end

return string.format("PASS: shallow/exact overlap, Boss ratio %.2f, order error %.8f, stopped crowd step %.5f, chasing crowd step %.5f / spacing %.3f, 30/60/120fps, chase stop, Boss blocker, flee, VFX paths", ratio, orderError, maxLateMotion, lateChaseStep, minimumSpacing)
