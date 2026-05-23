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

function LordAI.updateAILord(lord, dt)
    lord.aiTimer = lord.aiTimer - dt

    -- 通用计数：使用 CONFIG 分类表
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

    -- 优先转化士兵(有平民且有钱时)
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

    -- AI 兵种升级决策（泛化版 — 根据可用兵种和敌方构成决策）
    if (typeCounts["soldier"] or 0) >= 2 then
        -- 寻找最近敌方领主
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
            -- 统计敌方兵种
            local enemyCounts = {}
            for _, f in ipairs(GS.followers) do
                if f.lordId == nearEnemy.id and f.alive then
                    enemyCounts[f.fType] = (enemyCounts[f.fType] or 0) + 1
                end
            end

            -- 升级优先级：根据敌方构成决策
            -- { targetType, condition, stoneCost, woodCost }
            local enemySoldiers  = enemyCounts["soldier"]  or 0
            local enemyArchers   = enemyCounts["archer"]   or 0
            local myArchers      = typeCounts["archer"]    or 0
            local myHealers      = typeCounts["healer"]    or 0

            local upgrades = {
                -- 敌方近战多 → 补弓手
                { "archer",   enemySoldiers > myArchers,
                  CONFIG.ArcherCostStone, CONFIG.ArcherCostWood },
                -- 无治愈师且兵力足够 → 补一个
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
                    break  -- 每次决策只升级一个
                end
            end
        end
    end

    -- 买平民
    if peasantCount < 2 and lord.wood >= CONFIG.PeasantCost then
        Entities.createFollower(lord, "peasant")
        lord.wood = lord.wood - CONFIG.PeasantCost
    end

    if lord.aiTimer > 0 then return end
    lord.aiTimer = 0.5 + math.random() * 1.0

    -- 决策树（使用 totalCombat 替代硬编码的三兵种求和）
    local myCombat = totalCombat
    -- 1. 检测附近的Boss
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

    -- 2. 检测附近的敌方领主
    local nearestEnemy = nil
    local nearestEnemyDist = 999999
    local enemySoldiers = 0
    for _, el in ipairs(GS.lords) do
        if el.alive and el.faction ~= lord.faction then
            local d = dist(lord.x, lord.y, el.x, el.y)
            if d < nearestEnemyDist then
                nearestEnemyDist = d
                nearestEnemy = el
                local eCombat = Entities.countCombatFollowers(el.id)
                enemySoldiers = eCombat
            end
        end
    end

    -- 3. 检测附近宝箱/遗产
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

    -- 决策

    -- 兵力充足时追击敌方领主
    if myCombat >= 4 then
        local weakestEnemy = nil
        local weakestEnemyHP = 999999
        for _, el in ipairs(GS.lords) do
            if el.alive and el.faction ~= lord.faction then
                local d = dist(lord.x, lord.y, el.x, el.y)
                if d < 800 and el.hp < weakestEnemyHP then
                    weakestEnemyHP = el.hp
                    weakestEnemy = el
                end
            end
        end
        if weakestEnemy and myCombat >= 5 then
            lord.aiState = "attack"
            lord.targetX = weakestEnemy.x
            lord.targetY = weakestEnemy.y
            lord.aiTargetId = weakestEnemy.id
            return
        end
    end

    -- 条件1: Boss太近，且兵力不足 => 逃跑
    if nearestBoss and nearestBossDist < 400 and myCombat < 5 then
        lord.aiState = "flee"
        local dx, dy = normalize(lord.x - nearestBoss.x, lord.y - nearestBoss.y)
        lord.targetX = lord.x + dx * 500
        lord.targetY = lord.y + dy * 500
        return
    end

    -- 有宝箱就捡
    if nearestLoot and nearestLootDist < 500 then
        lord.aiState = "gather"
        lord.targetX = nearestLoot.x
        lord.targetY = nearestLoot.y
        return
    end

    -- 条件2: 恃强凌弱（总战斗单位比较）
    if nearestEnemy and nearestEnemyDist < 600 and myCombat > enemySoldiers + 2 then
        lord.aiState = "attack"
        lord.targetX = nearestEnemy.x
        lord.targetY = nearestEnemy.y
        lord.aiTargetId = nearestEnemy.id
        return
    end

    -- 条件3: 弱于敌方，逃跑
    if nearestEnemy and nearestEnemyDist < 400 and myCombat < enemySoldiers then
        lord.aiState = "flee"
        local dx, dy = normalize(lord.x - nearestEnemy.x, lord.y - nearestEnemy.y)
        lord.targetX = lord.x + dx * 400
        lord.targetY = lord.y + dy * 400
        return
    end

    -- Boss可打且兵力充足
    if nearestBoss and myCombat >= 5 then
        lord.aiState = "attack"
        lord.targetX = nearestBoss.x
        lord.targetY = nearestBoss.y
        return
    end

    -- 默认: 四处游荡寻找资源
    lord.aiState = "wander"
    -- 寻找资源密集区
    local bestResX, bestResY = lord.x, lord.y
    local bestResScore = 0
    -- 随机取几个点评估
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
