local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local BossSystem = {}

function BossSystem.updateBossAI(boss, dt)
    local cfg = CONFIG.BossTypes[boss.bossType] or CONFIG.BossTypes.behemoth

    if boss.bossType == "wolf" then
        -- 幽灵狼：周期性隐身
        boss.stealthTimer = boss.stealthTimer + dt
        if boss.isStealthed then
            if boss.stealthTimer >= cfg.stealthDuration then
                boss.isStealthed = false
                boss.stealthTimer = 0
            end
        else
            if boss.stealthTimer >= cfg.stealthInterval then
                boss.isStealthed = true
                boss.stealthTimer = 0
            end
        end

        -- 幽灵狼优先追击落单单位（离领主最远的农民/弓箭手）
        local bestTarget = nil
        local bestDist = 0
        for _, f in ipairs(GS.followers) do
            if f.alive and (f.fType == "peasant" or f.fType == "archer") then
                local lord = Entities.findLordById(f.lordId)
                if lord then
                    local distFromLord = Utils.dist(f.x, f.y, lord.x, lord.y)
                    if distFromLord > bestDist then
                        bestDist = distFromLord
                        bestTarget = f
                    end
                end
            end
        end

        if bestTarget then
            local dx, dy = Utils.normalize(bestTarget.x - boss.x, bestTarget.y - boss.y)
            boss.x = boss.x + dx * cfg.speed * dt
            boss.y = boss.y + dy * cfg.speed * dt
            boss.angle = math.atan2(dy, dx)

            -- 碰到落单单位造成数值伤害
            local dToTarget = Utils.dist(boss.x, boss.y, bestTarget.x, bestTarget.y)
            if dToTarget < 20 then
                local contactDmg = cfg.contactDamage
                if GS.bloodMoonActive then contactDmg = math.floor(contactDmg * 1.5) end
                bestTarget.hp = bestTarget.hp - contactDmg
                if bestTarget.hp <= 0 then bestTarget.alive = false end
                Entities.spawnParticle(bestTarget.x, bestTarget.y, 150, 100, 220, 6)
                Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, contactDmg, 150, 100, 220)
            end
        else
            -- 没有落单目标，追击最近领主
            local nearestLord = nil
            local nearestDist2 = 999999
            for _, l in ipairs(GS.lords) do
                if l.alive then
                    local d = Utils.dist(boss.x, boss.y, l.x, l.y)
                    if d < nearestDist2 then
                        nearestDist2 = d
                        nearestLord = l
                    end
                end
            end
            if nearestLord then
                boss.targetLordId = nearestLord.id
                local dx, dy = Utils.normalize(nearestLord.x - boss.x, nearestLord.y - boss.y)
                boss.x = boss.x + dx * cfg.speed * dt
                boss.y = boss.y + dy * cfg.speed * dt
                boss.angle = math.atan2(dy, dx)

                if nearestDist2 < 35 and nearestLord.invincibleTimer <= 0 then
                    local contactDmg = cfg.contactDamage
                    if GS.bloodMoonActive then contactDmg = math.floor(contactDmg * 1.5) end
                    nearestLord.hp = nearestLord.hp - contactDmg
                    nearestLord.invincibleTimer = CONFIG.InvincibleTime
                    nearestLord.hitAnimTimer = 0.4  -- 触发受击动画
                    Entities.spawnParticle(nearestLord.x, nearestLord.y, 150, 100, 220, 8)
                    Entities.spawnDamageNumber(nearestLord.x, nearestLord.y, contactDmg, 150, 100, 220)
                end
            end
        end

    else
        -- 巨兽 和 石甲蟹：追击最近领主
        local nearestLord = nil
        local nearestDist = 999999
        for _, l in ipairs(GS.lords) do
            if l.alive then
                local d = Utils.dist(boss.x, boss.y, l.x, l.y)
                if d < nearestDist then
                    nearestDist = d
                    nearestLord = l
                end
            end
        end

        if nearestLord then
            boss.targetLordId = nearestLord.id
            local dx, dy = Utils.normalize(nearestLord.x - boss.x, nearestLord.y - boss.y)
            boss.x = boss.x + dx * cfg.speed * dt
            boss.y = boss.y + dy * cfg.speed * dt
            boss.angle = math.atan2(dy, dx)

            if boss.bossType == "behemoth" then
                -- 巨兽：碰到领主造成伤害
                if nearestDist < 35 and nearestLord.invincibleTimer <= 0 then
                    local contactDmg = cfg.contactDamage
                    if GS.bloodMoonActive then contactDmg = math.floor(contactDmg * 1.5) end
                    nearestLord.hp = nearestLord.hp - contactDmg
                    nearestLord.invincibleTimer = CONFIG.InvincibleTime
                    nearestLord.hitAnimTimer = 0.4  -- 触发受击动画
                    Entities.spawnParticle(nearestLord.x, nearestLord.y, 255, 50, 50, 8)
                    Entities.spawnDamageNumber(nearestLord.x, nearestLord.y, contactDmg, 255, 80, 80)
                end

            elseif boss.bossType == "crab" then
                -- 石甲蟹：周期性AOE伤害
                boss.aoeTimer = boss.aoeTimer + dt
                if boss.aoeTimer >= cfg.aoeInterval then
                    boss.aoeTimer = 0
                    local aoeDmg = cfg.aoeDamage
                    if GS.bloodMoonActive then aoeDmg = math.floor(aoeDmg * 1.5) end
                    -- 对范围内所有单位造成数值伤害
                    for _, f in ipairs(GS.followers) do
                        if f.alive then
                            local d = Utils.dist(boss.x, boss.y, f.x, f.y)
                            if d < cfg.aoeRadius then
                                f.hp = f.hp - aoeDmg
                                if f.hp <= 0 then f.alive = false end
                                Entities.spawnParticle(f.x, f.y, 120, 120, 140, 3)
                                Entities.spawnDamageNumber(f.x, f.y, aoeDmg, 120, 120, 140)
                            end
                        end
                    end
                    -- AOE也对范围内领主造成伤害
                    for _, l in ipairs(GS.lords) do
                        if l.alive and l.invincibleTimer <= 0 then
                            local d = Utils.dist(boss.x, boss.y, l.x, l.y)
                            if d < cfg.aoeRadius then
                                l.hp = l.hp - aoeDmg
                                l.invincibleTimer = CONFIG.InvincibleTime
                                l.hitAnimTimer = 0.4  -- 触发受击动画
                                Entities.spawnParticle(l.x, l.y, 120, 120, 140, 6)
                                Entities.spawnDamageNumber(l.x, l.y, aoeDmg, 120, 120, 140)
                            end
                        end
                    end
                    -- AOE视觉反馈
                    Entities.spawnParticle(boss.x, boss.y, 120, 120, 140, 10)
                end
            end
        end
    end

    boss.x = Utils.clamp(boss.x, 30, CONFIG.MapWidth - 30)
    boss.y = Utils.clamp(boss.y, 30, CONFIG.MapHeight - 30)
end

return BossSystem
