-- ============================================================================
-- LordAI.lua  —  AI 领主决策模块
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local dist = Utils.dist
local normalize = Utils.normalize
local randomRange = Utils.randomRange

local LordAI = {}

local function getCombatCount(lordId)
    local count = 0
    for _, f in ipairs(GS.followers) do
        if f.lordId == lordId and f.alive and CONFIG.IsCombatUnit[f.fType] then
            count = count + 1
        end
    end
    return count
end

local function getStrongestLord(excludeFaction)
    local best = nil
    local bestCombat = -1
    for _, l in ipairs(GS.lords) do
        if l.alive and l.faction ~= excludeFaction then
            local c = getCombatCount(l.id)
            if c > bestCombat then
                bestCombat = c
                best = l
            end
        end
    end
    return best, bestCombat
end

function LordAI.updateAILord(lord, dt)
    lord.aiTimer = lord.aiTimer - dt

    local totalCombat = 0
    local typeCounts = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            typeCounts[f.fType] = (typeCounts[f.fType] or 0) + 1
            if CONFIG.IsCombatUnit[f.fType] then
                totalCombat = totalCombat + 1
            end
        end
    end
    local peasantCount = typeCounts["peasant"] or 0

    if peasantCount > 1 and lord.wood >= CONFIG.SoldierCost then
        for _, f in ipairs(GS.followers) do
            if f.lordId == lord.id and f.alive and f.fType == "peasant" and f.state == "following" then
                f.fType = "soldier"
                lord.wood = lord.wood - CONFIG.SoldierCost
                Entities.spawnParticle(f.x, f.y, 255, 200, 50, 3)
                break
            end
        end
    end

    if (typeCounts["soldier"] or 0) >= 2 then
        local nearEnemy = nil
        local nearEnemyDist = 999999
        for _, el in ipairs(GS.lords) do
            if el.alive and el.faction ~= lord.faction then
                local d = dist(lord.x, lord.y, el.x, el.y)
                if d < nearEnemyDist then
                    nearEnemyDist = d
                    nearEnemy = el
                end
            end
        end
        if nearEnemy then
            local enemyCounts = {}
            for _, f in ipairs(GS.followers) do
                if f.lordId == nearEnemy.id and f.alive then
                    enemyCounts[f.fType] = (enemyCounts[f.fType] or 0) + 1
                end
            end

            local enemySoldiers  = enemyCounts["soldier"]  or 0
            local myArchers      = typeCounts["archer"]    or 0
            local myHealers      = typeCounts["healer"]    or 0

            local upgrades = {
                { "archer",   enemySoldiers > myArchers,
                  CONFIG.ArcherCostStone, CONFIG.ArcherCostWood },
                { "healer",   myHealers == 0 and (typeCounts["soldier"] or 0) >= 3,
                  CONFIG.HealerCost.stone, CONFIG.HealerCost.wood },
            }

            for _, upg in ipairs(upgrades) do
                local targetType, shouldUpgrade, stoneCost, woodCost = upg[1], upg[2], upg[3], upg[4]
                if shouldUpgrade and lord.stone >= stoneCost and lord.wood >= woodCost then
                    for _, f in ipairs(GS.followers) do
                        if f.lordId == lord.id and f.alive and f.fType == "soldier" and f.state == "following" then
                            f.fType = targetType
                            f.hp = CONFIG.UnitStats[targetType].hp
                            f.maxHp = CONFIG.UnitStats[targetType].hp
                            lord.stone = lord.stone - stoneCost
                            lord.wood = lord.wood - woodCost
                            Entities.spawnParticle(f.x, f.y, 255, 200, 50, 3)
                            break
                        end
                    end
                    break
                end
            end
        end
    end

    if peasantCount < 2 and lord.wood >= CONFIG.PeasantCost then
        Entities.createFollower(lord, "peasant")
        lord.wood = lord.wood - CONFIG.PeasantCost
    end

    if lord.aiTimer > 0 then return end
    lord.aiTimer = 0.3 + math.random() * 0.5

    local myCombat = totalCombat

    local nearestBoss = nil
    local nearestBossDist = 999999
    for _, b in ipairs(GS.bosses) do
        if b.alive then
            local d = dist(lord.x, lord.y, b.x, b.y)
            if d < nearestBossDist then
                nearestBossDist = d
                nearestBoss = b
            end
        end
    end

    local enemies = {}
    for _, el in ipairs(GS.lords) do
        if el.alive and el.faction ~= lord.faction then
            local d = dist(lord.x, lord.y, el.x, el.y)
            local eCombat = getCombatCount(el.id)
            table.insert(enemies, { lord = el, dist = d, combat = eCombat })
        end
    end
    table.sort(enemies, function(a, b) return a.dist < b.dist end)

    local nearestEnemy = enemies[1]
    local nearestEnemyDist = nearestEnemy and nearestEnemy.dist or 999999
    local enemySoldiers = nearestEnemy and nearestEnemy.combat or 0

    local strongestEnemy, strongestCombat = getStrongestLord(lord.faction)

    local nearestLoot = nil
    local nearestLootDist = 999999
    for _, c in ipairs(GS.chests) do
        if c.alive then
            local d = dist(lord.x, lord.y, c.x, c.y)
            if d < nearestLootDist then
                nearestLootDist = d
                nearestLoot = {x = c.x, y = c.y}
            end
        end
    end
    for _, lb in ipairs(GS.lootBoxes) do
        if lb.alive then
            local d = dist(lord.x, lord.y, lb.x, lb.y)
            if d < nearestLootDist then
                nearestLootDist = d
                nearestLoot = {x = lb.x, y = lb.y}
            end
        end
    end

    if nearestBoss and nearestBossDist < 400 and myCombat < 3 then
        lord.aiState = "flee"
        local dx, dy = normalize(lord.x - nearestBoss.x, lord.y - nearestBoss.y)
        lord.targetX = lord.x + dx * 500
        lord.targetY = lord.y + dy * 500
        return
    end

    if myCombat >= 3 then
        local bestTarget = nil
        local bestScore = -999999

        for _, e in ipairs(enemies) do
            if e.dist > 1000 then break end

            local score = 0
            score = score - e.dist * 0.01
            score = score - e.combat * 5
            score = score - e.lord.hp * 0.3

            if myCombat > e.combat + 1 then
                score = score + 30
            end

            if strongestEnemy and e.lord.id == strongestEnemy.id and myCombat >= 3 then
                local myPower = myCombat + (lord.hp / lord.maxHp) * 3
                if strongestCombat > myPower * 1.5 then
                    score = score - 50
                end
            end

            if e.lord.invincibleTimer > 0 then
                score = score - 100
            end

            if score > bestScore then
                bestScore = score
                bestTarget = e
            end
        end

        if bestTarget and bestScore > -50 then
            lord.aiState = "attack"
            lord.targetX = bestTarget.lord.x
            lord.targetY = bestTarget.lord.y
            lord.aiTargetId = bestTarget.lord.id
            return
        end
    end

    if nearestLoot and nearestLootDist < 600 then
        lord.aiState = "gather"
        lord.targetX = nearestLoot.x
        lord.targetY = nearestLoot.y
        return
    end

    if nearestEnemy and nearestEnemyDist < 350 and myCombat < enemySoldiers then
        lord.aiState = "flee"
        local dx, dy = normalize(lord.x - nearestEnemy.lord.x, lord.y - nearestEnemy.lord.y)
        lord.targetX = lord.x + dx * 400
        lord.targetY = lord.y + dy * 400
        return
    end

    if nearestBoss and myCombat >= 4 then
        lord.aiState = "attack"
        lord.targetX = nearestBoss.x
        lord.targetY = nearestBoss.y
        return
    end

    lord.aiState = "wander"
    local bestResX, bestResY = lord.x, lord.y
    local bestResScore = 0
    for i = 1, 5 do
        local testX = randomRange(100, CONFIG.MapWidth - 100)
        local testY = randomRange(100, CONFIG.MapHeight - 100)
        local resScore = 0
        for _, r in ipairs(GS.resources) do
            if r.alive then
                local d = dist(testX, testY, r.x, r.y)
                if d < 300 then resScore = resScore + 1 end
            end
        end
        if resScore > bestResScore then
            bestResScore = resScore
            bestResX = testX
            bestResY = testY
        end
    end
    lord.targetX = bestResX
    lord.targetY = bestResY

end

return LordAI
