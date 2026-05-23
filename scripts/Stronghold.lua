-- ============================================================================
-- Stronghold.lua - 领主附属据点系统（防御塔、复活、领域伤害）
-- 据点不再是独立实体，而是领主身上的属性
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local Stronghold = {}

--- 领主死亡时调用，返回 true 表示会复活，false 表示真正淘汰
function Stronghold.onLordDeath(lord)
    -- 记录死亡位置
    lord.deathX = lord.x
    lord.deathY = lord.y

    -- 扣据点HP
    local deathCost = 70
    if GS.bloodMoonActive then deathCost = 105 end
    lord.strongholdHP = lord.strongholdHP - deathCost

    if lord.strongholdHP <= 0 then
        lord.strongholdHP = 0
        lord.alive = false
        local lootWood = math.floor(lord.wood * 0.5)
        local lootStone = math.floor(lord.stone * 0.5)
        lord.wood = lord.wood - lootWood
        lord.stone = lord.stone - lootStone
        for _, f in ipairs(GS.followers) do
            if f.lordId == lord.id and f.alive then
                f.alive = false
                Entities.spawnParticle(f.x, f.y, 150, 150, 150, 2)
            end
        end
        if lootWood > 0 or lootStone > 0 then
            Entities.createLootBox(lord.x, lord.y, lootWood, lootStone)
        end
        Entities.spawnParticle(lord.x, lord.y, 255, 50, 50, 20)
        return false
    end

    lord.alive = false
    local lootWood = math.floor(lord.wood * 0.3)
    local lootStone = math.floor(lord.stone * 0.3)
    lord.wood = lord.wood - lootWood
    lord.stone = lord.stone - lootStone
    local followers = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            table.insert(followers, f)
        end
    end
    for i, f in ipairs(followers) do
        if i % 2 == 0 then
            f.alive = false
            Entities.spawnParticle(f.x, f.y, 150, 150, 150, 2)
        end
    end
    if lootWood > 0 or lootStone > 0 then
        Entities.createLootBox(lord.x, lord.y, lootWood, lootStone)
    end
    Entities.spawnParticle(lord.x, lord.y, 255, 50, 50, 20)
    GS.respawning[lord.id] = { timer = CONFIG.RespawnTime, lordRef = lord }
    print("[LORD] Faction " .. lord.faction .. " lord killed, strongholdHP=" .. lord.strongholdHP .. ", respawning in " .. CONFIG.RespawnTime .. "s...")
    return true
end

function Stronghold.respawnLord(lordId)
    local foundLord = nil
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then foundLord = l break end
    end
    if not foundLord then return end
    if foundLord.strongholdHP <= 0 then return end  -- 据点HP耗尽不复活

    foundLord.alive = true
    foundLord.hp = math.floor(foundLord.maxHp * CONFIG.RespawnHpRatio)
    foundLord.x = math.random(200, CONFIG.MapWidth - 200)
    foundLord.y = math.random(200, CONFIG.MapHeight - 200)
    foundLord.invincibleTimer = 2.0
    local hasFollowers = false
    for _, f in ipairs(GS.followers) do
        if f.lordId == foundLord.id and f.alive then
            hasFollowers = true
            f.x = foundLord.x + math.random(-40, 40)
            f.y = foundLord.y + math.random(-40, 40)
            f.state = "following"
        end
    end
    if not hasFollowers then
        Entities.createFollower(foundLord, "peasant")
        Entities.createFollower(foundLord, "soldier")
    end
    Entities.spawnParticle(foundLord.x, foundLord.y, 100, 200, 255, 15)
    print("[RESPAWN] Faction " .. foundLord.faction .. " lord respawned at random position!")
end

function Stronghold.updateStrongholds(dt)
    -- 遍历所有活着的领主，更新防御塔和领域伤害
    for _, lord in ipairs(GS.lords) do
        if not lord.alive then goto continueLord end

        if lord.towerActive then
            lord.towerTimer = lord.towerTimer + dt
            if lord.towerTimer >= CONFIG.StrongholdTowerInterval then
                lord.towerTimer = 0
                local bestTarget = nil
                local bestDist = CONFIG.StrongholdTowerRange
                -- 寻找射程内最近的敌方单位
                for _, f in ipairs(GS.followers) do
                    if f.alive and f.factionId ~= lord.faction then
                        local d = Utils.dist(lord.x, lord.y, f.x, f.y)
                        if d < bestDist then
                            bestDist = d
                            bestTarget = f
                        end
                    end
                end
                -- 也检测敌方领主
                for _, l in ipairs(GS.lords) do
                    if l.alive and l.faction ~= lord.faction and l.invincibleTimer <= 0 then
                        local d = Utils.dist(lord.x, lord.y, l.x, l.y)
                        if d < bestDist then
                            bestDist = d
                            bestTarget = l
                        end
                    end
                end
                if bestTarget then
                    local towerDmg = CONFIG.StrongholdTowerDamage  -- 15点
                    if GS.bloodMoonActive then towerDmg = math.floor(towerDmg * 1.5) end
                    if bestTarget.fType then
                        -- 是随从：数值伤害（不再一击杀）
                        bestTarget.hp = bestTarget.hp - towerDmg
                        Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, towerDmg, 255, 200, 50)
                        if bestTarget.hp <= 0 then
                            bestTarget.alive = false
                        end
                    else
                        -- 是领主
                        bestTarget.hp = bestTarget.hp - towerDmg
                        bestTarget.invincibleTimer = 0.1
                        bestTarget.hitAnimTimer = 0.3  -- 触发受击动画
                        Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, towerDmg, 255, 200, 50)
                    end
                    Entities.spawnParticle(bestTarget.x, bestTarget.y, 255, 200, 50, 4)
                end
            end
        end

        -- （已移除：旧版防守模式AOE伤害）

        ::continueLord::
    end

    -- 处理复活倒计时
    local toRemove = {}
    for lordId, info in pairs(GS.respawning) do
        info.timer = info.timer - dt
        if info.timer <= 0 then
            Stronghold.respawnLord(lordId)
            table.insert(toRemove, lordId)
        end
    end
    for _, lordId in ipairs(toRemove) do
        GS.respawning[lordId] = nil
    end
end

return Stronghold
