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
    local deathCost = 100
    if GS.bloodMoonActive then deathCost = 150 end
    lord.strongholdHP = lord.strongholdHP - deathCost

    if lord.strongholdHP <= 0 then
        lord.strongholdHP = 0
        lord.alive = false
        -- 惩罚：损失50%资源 & 掉落战利品
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
        return false  -- 永久淘汰
    end

    -- 据点HP > 0，进入复活流程
    lord.alive = false
    -- 惩罚
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
    -- 在死亡位置复活（不是据点位置）
    foundLord.x = foundLord.deathX or foundLord.x
    foundLord.y = foundLord.deathY or foundLord.y
    foundLord.invincibleTimer = 3.0
    foundLord.lordMode = "charge"  -- 复活后默认进攻模式
    -- 初始随从：2农民 + 1士兵
    Entities.createFollower(foundLord, "peasant")
    Entities.createFollower(foundLord, "peasant")
    Entities.createFollower(foundLord, "soldier")
    Entities.spawnParticle(foundLord.x, foundLord.y, 100, 200, 255, 15)
    print("[RESPAWN] Faction " .. foundLord.faction .. " lord respawned at death position!")
end

function Stronghold.updateStrongholds(dt)
    -- 遍历所有活着的领主，更新防御塔和领域伤害
    for _, lord in ipairs(GS.lords) do
        if not lord.alive then goto continueLord end

        -- 更新模式切换提示文字
        if lord.modeSwitchText then
            lord.modeSwitchText.timer = lord.modeSwitchText.timer - dt
            if lord.modeSwitchText.timer <= 0 then
                lord.modeSwitchText = nil
            end
        end

        -- ===== 防御塔攻击逻辑（跟随领主，不再崩溃） =====
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
