-- ============================================================================
-- Combat.lua - 战斗结算 + 弹射物 + 拾取 + 死亡处理
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")
local TS = require("TalentSystem")
local SkillSystem = require("SkillSystem")
local ShopSystem = require("ShopSystem")
local CampaignState = require("CampaignState")
local CodexState = require("CodexState")

local Combat = {}

-- 计算单位对单位的伤害
local function calcUnitDamage(attackerType, defenderType, attackerLordId)
    local stats = CONFIG.UnitStats[attackerType]
    if not stats then return 0 end
    local dmg = stats.atk
    if GS.bloodMoonActive then dmg = dmg * 1.5 end

    -- 天赋攻击加成
    local talentEffects = TS.getActiveEffects()
    dmg = dmg * talentEffects.atkMul

    -- 暴击判定
    if talentEffects.critChance > 0 and math.random() < talentEffects.critChance then
        dmg = dmg * talentEffects.critDamageMul
    end

    -- 无尽模式攻击 buff
    if GS.gameMode == "endless" then
        dmg = dmg * ShopSystem.getEndlessAtkMul()
    end

    return math.floor(dmg)
end

-- 护甲减伤
local function applyArmor(dmg, defenderUnit)
    -- 无尽模式护甲 buff
    if GS.gameMode == "endless" then
        dmg = math.floor(dmg * ShopSystem.getEndlessArmorMul())
    end
    return dmg
end

-- 获取单位半径
local function getUnitRadius(fType)
    return CONFIG.UnitRadius[fType] or CONFIG.SoldierRadius
end

function Combat.processCombat(dt)
    -- 战斗单位 vs 战斗单位（近战碰撞 → 周期性伤害）
    for i = 1, #GS.followers do
        local fa = GS.followers[i]
        if fa.alive and fa.fType ~= "archer" and fa.state == "attacking" then
            for j = 1, #GS.followers do
                if i ~= j then
                    local fb = GS.followers[j]
                    if fb.alive and fb.factionId ~= fa.factionId then
                        local d = Utils.dist(fa.x, fa.y, fb.x, fb.y)
                        local raA = getUnitRadius(fa.fType)
                        local raB = getUnitRadius(fb.fType)
                        local hitDist = (raA + raB) * 0.8
                        if d < hitDist then
                            -- 在碰撞距离内：周期性攻击
                            fa.attackTimer = fa.attackTimer - dt
                            if fa.attackTimer <= 0 then
                                local dmg = calcUnitDamage(fa.fType, fb.fType, fa.lordId)
                                dmg = applyArmor(dmg, fb)
                                fb.hp = fb.hp - dmg
                                fb.hitTimer = 0.2
                                local baseInterval = CONFIG.UnitStats[fa.fType].atkInterval
                                local frenzyMul = SkillSystem.getFrenzyAtkSpeedMul(fa.factionId)
                                fa.attackTimer = baseInterval / frenzyMul
                                Entities.spawnDamageNumber(fb.x, fb.y, dmg, 255, 80, 80)
                                Entities.spawnParticle((fa.x + fb.x)/2, (fa.y + fb.y)/2, 255, 200, 50, 3)
                                local lifesteal = SkillSystem.getLifestealPct(fa.factionId)
                                if lifesteal > 0 then
                                    local healAmt = math.floor(dmg * lifesteal)
                                    if healAmt > 0 then
                                        local stats = CONFIG.UnitStats[fa.fType]
                                        fa.hp = math.min(stats.hp, fa.hp + healAmt)
                                        Entities.spawnDamageNumber(fa.x, fa.y, "+" .. healAmt, 100, 255, 100)
                                    end
                                end
                            end
                            -- 反击：被攻击方也可以攻击回来
                            if fb.fType ~= "archer" and fb.state == "attacking" then
                                fb.attackTimer = fb.attackTimer - dt
                                if fb.attackTimer <= 0 then
                                    local dmgBack = calcUnitDamage(fb.fType, fa.fType, fb.lordId)
                                    dmgBack = applyArmor(dmgBack, fa)
                                    fa.hp = fa.hp - dmgBack
                                    fa.hitTimer = 0.2
                                    local baseIntervalB = CONFIG.UnitStats[fb.fType].atkInterval
                                    local frenzyMulB = SkillSystem.getFrenzyAtkSpeedMul(fb.factionId)
                                    fb.attackTimer = baseIntervalB / frenzyMulB
                                    Entities.spawnDamageNumber(fa.x, fa.y, dmgBack, 255, 80, 80)
                                    local lifestealB = SkillSystem.getLifestealPct(fb.factionId)
                                    if lifestealB > 0 then
                                        local healB = math.floor(dmgBack * lifestealB)
                                        if healB > 0 then
                                            local statsB = CONFIG.UnitStats[fb.fType]
                                            fb.hp = math.min(statsB.hp, fb.hp + healB)
                                            Entities.spawnDamageNumber(fb.x, fb.y, "+" .. healB, 100, 255, 100)
                                        end
                                    end
                                end
                            end
                            -- 检查死亡
                            if fa.hp <= 0 then fa.alive = false end
                            if fb.hp <= 0 then fb.alive = false end
                            -- 存活方重置状态
                            if fa.alive and not fb.alive then
                                fa.state = "following"
                                fa.targetId = nil
                            end
                            if fb.alive and not fa.alive then
                                fb.state = "following"
                                fb.targetId = nil
                            end
                            break  -- fa 本轮只与一个敌人交战
                        end
                    end
                end
            end
        end
    end

    -- 战斗单位 vs 领主（持续输出，不再自杀）
    for i = 1, #GS.followers do
        local f = GS.followers[i]
        if f.alive and CONFIG.IsCombatUnit[f.fType] and not CONFIG.IsRangedUnit[f.fType] and f.state == "attacking" then
            for _, l in ipairs(GS.lords) do
                if l.alive and l.faction ~= f.factionId then
                    local d = Utils.dist(f.x, f.y, l.x, l.y)
                    local fRadius = getUnitRadius(f.fType)
                    if d < (fRadius + CONFIG.LordRadiusMin) * 0.8 then
                        -- 周期性攻击领主
                        f.attackTimer = f.attackTimer - dt
                        if f.attackTimer <= 0 then
                            local dmg = CONFIG.UnitStats[f.fType].atk
                            if GS.bloodMoonActive then dmg = math.floor(dmg * 1.5) end
                            if l.invincibleTimer <= 0 then
                                l.hp = l.hp - dmg
                                l.invincibleTimer = 0.1  -- 短暂无敌防止同帧多次结算
                                l.hitAnimTimer = 0.3     -- 触发受击动画（独立于无敌计时）
                                l.hitTimer = 0.2  -- 受击反馈
                                Entities.spawnDamageNumber(l.x, l.y, dmg, 255, 50, 50)
                                Entities.spawnParticle(l.x, l.y, 255, 80, 80, 3)
                            end
                            f.attackTimer = CONFIG.UnitStats[f.fType].atkInterval
                        end
                        break
                    end
                end
            end
        end

        -- 战斗单位 vs Boss（持续输出，不再自杀）
        if f.alive and CONFIG.IsCombatUnit[f.fType] and not CONFIG.IsRangedUnit[f.fType] and f.state == "attacking" then
            for _, b in ipairs(GS.bosses) do
                if b.alive and not b.isStealthed then
                    local d = Utils.dist(f.x, f.y, b.x, b.y)
                    if d < (CONFIG.BossRadius + getUnitRadius(f.fType)) * 0.8 then
                        f.attackTimer = f.attackTimer - dt
                        if f.attackTimer <= 0 then
                            local dmg = CONFIG.UnitStats[f.fType].atk
                            if GS.bloodMoonActive then dmg = math.floor(dmg * 1.5) end
                            b.hp = b.hp - dmg
                            b.hitTimer = 0.3  -- Boss受击反馈（更长恢复时间）
                            f.attackTimer = CONFIG.UnitStats[f.fType].atkInterval
                            Entities.spawnDamageNumber(b.x, b.y, dmg, 255, 200, 50)
                            Entities.spawnParticle(b.x, b.y, 255, 150, 50, 3)
                        end
                        break
                    end
                end
            end
        end
    end

    -- === 近战单位 vs 拒马（可被攻击摧毁） ===
    for _, f in ipairs(GS.followers) do
        if f.alive and f.fType ~= "archer" and f.state == "attacking" then
            for _, b in ipairs(GS.barricades) do
                if b.alive and b.ownerFaction ~= f.factionId then
                    local d = Utils.dist(f.x, f.y, b.x, b.y)
                    if d < b.radius + getUnitRadius(f.fType) then
                        f.attackTimer = f.attackTimer - dt
                        if f.attackTimer <= 0 then
                            local dmg = CONFIG.UnitStats[f.fType].atk
                            b.hp = b.hp - dmg
                            f.attackTimer = CONFIG.UnitStats[f.fType].atkInterval
                            Entities.spawnDamageNumber(b.x, b.y, dmg, 139, 90, 43)
                            Entities.spawnParticle(b.x, b.y, 139, 90, 43, 2)
                            if b.hp <= 0 then
                                b.alive = false
                                Entities.spawnParticle(b.x, b.y, 139, 90, 43, 10)
                            end
                        end
                        break  -- 每帧只攻击一个拒马
                    end
                end
            end
        end
    end
end

-- 箭矢飞行与命中处理
function Combat.processProjectiles(dt)
    for i = #GS.projectiles, 1, -1 do
        local p = GS.projectiles[i]
        if p.alive then
            -- 计算飞行方向
            local dx = p.tx - p.x
            local dy = p.ty - p.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < 8 then
                -- 到达目标点，检测命中
                p.alive = false

                -- AOE 弹射物：对范围内所有敌方造成伤害
                if p.isAOE and p.aoeRadius then
                    for _, f in ipairs(GS.followers) do
                        if f.alive and f.factionId ~= p.factionId then
                            local aoeDist = Utils.dist(p.x, p.y, f.x, f.y)
                            if aoeDist < p.aoeRadius then
                                local aoeDmg = calcUnitDamage(p.attackerType or "archer", f.fType, nil)
                                aoeDmg = math.floor(aoeDmg * 0.6)
                                aoeDmg = applyArmor(aoeDmg, f)
                                f.hp = f.hp - aoeDmg
                                f.hitTimer = 0.2
                                Entities.spawnDamageNumber(f.x, f.y, aoeDmg, 160, 50, 220)
                                if f.hp <= 0 then
                                    f.alive = false
                                    Entities.spawnParticle(f.x, f.y, 160, 50, 220, 4)
                                end
                            end
                        end
                    end
                    Entities.spawnParticle(p.x, p.y, 160, 50, 220, 10)  -- AOE 爆炸特效
                else
                    -- 单体命中逻辑
                    for _, f in ipairs(GS.followers) do
                        if f.alive and f.factionId ~= p.factionId then
                            local hitDist = Utils.dist(p.x, p.y, f.x, f.y)
                            if hitDist < 12 then
                                local dmg = calcUnitDamage(p.attackerType or "archer", f.fType, nil)
                                dmg = applyArmor(dmg, f)
                                f.hp = f.hp - dmg
                                f.hitTimer = 0.2  -- 受击反馈
                                Entities.spawnDamageNumber(f.x, f.y, dmg, 255, 150, 50)
                                if f.hp <= 0 then
                                    f.alive = false
                                    Entities.spawnParticle(f.x, f.y, 255, 150, 50, 4)
                                end
                                break
                            end
                        end
                    end
                end
                -- 箭矢命中领主
                for _, l in ipairs(GS.lords) do
                    if l.alive and l.faction ~= p.factionId and l.invincibleTimer <= 0 then
                        local hitDist = Utils.dist(p.x, p.y, l.x, l.y)
                        if hitDist < 20 then
                            local lordDmg = CONFIG.UnitStats.archer.atk  -- 20点，不乘克制
                            if GS.bloodMoonActive then lordDmg = math.floor(lordDmg * 1.5) end
                            l.hp = l.hp - lordDmg
                            l.invincibleTimer = 0.3
                            l.hitAnimTimer = 0.4     -- 触发受击动画
                            l.hitTimer = 0.2  -- 受击反馈
                            Entities.spawnParticle(l.x, l.y, 255, 80, 80, 4)
                            Entities.spawnDamageNumber(l.x, l.y, lordDmg, 255, 50, 50)
                            break
                        end
                    end
                end
                -- 箭矢命中Boss（幽灵狼隐身时免疫）
                for _, b in ipairs(GS.bosses) do
                    if b.alive and not b.isStealthed then
                        local hitDist = Utils.dist(p.x, p.y, b.x, b.y)
                        if hitDist < CONFIG.BossRadius then
                            local bossDmg = CONFIG.UnitStats.archer.atk  -- 20点
                            if GS.bloodMoonActive then bossDmg = math.floor(bossDmg * 1.5) end
                            b.hp = b.hp - bossDmg
                            b.hitTimer = 0.3  -- Boss受击反馈（更长恢复时间）
                            Entities.spawnParticle(b.x, b.y, 255, 150, 50, 4)
                            Entities.spawnDamageNumber(b.x, b.y, bossDmg, 255, 200, 50)
                            break
                        end
                    end
                end
            else
                -- 飞行中
                local nx, ny = dx / d, dy / d
                p.x = p.x + nx * p.speed * dt
                p.y = p.y + ny * p.speed * dt
            end
        end
    end

    -- 清除已消亡的箭矢
    for i = #GS.projectiles, 1, -1 do
        if not GS.projectiles[i].alive then
            table.remove(GS.projectiles, i)
        end
    end

end

-- ============================================================================
-- 拾取系统
-- ============================================================================

function Combat.processPickups()
    for _, l in ipairs(GS.lords) do
        if not l.alive then goto continueLord end

        -- 拾取宝箱
        for _, c in ipairs(GS.chests) do
            if c.alive and Utils.dist(l.x, l.y, c.x, c.y) < 40 then
                c.alive = false
                l.wood = l.wood + c.wood
                l.hp = math.min(l.maxHp, l.hp + c.heal)
                Entities.spawnParticle(c.x, c.y, 255, 255, 100, 10)
                Entities.spawnDamageNumber(c.x, c.y, "+" .. c.wood .. " 木材", 100, 255, 100)
                if c.heal > 0 then
                    Entities.spawnDamageNumber(c.x, c.y - 20, "+" .. c.heal .. " 生命", 100, 255, 200)
                end
            end
        end

        -- 拾取遗产包
        for _, lb in ipairs(GS.lootBoxes) do
            if lb.alive and Utils.dist(l.x, l.y, lb.x, lb.y) < 40 then
                lb.alive = false
                l.wood = l.wood + lb.wood
                l.stone = l.stone + lb.stone
                Entities.spawnParticle(lb.x, lb.y, 255, 200, 50, 12)
                local totalLoot = lb.wood + lb.stone
                Entities.spawnDamageNumber(lb.x, lb.y, "+" .. totalLoot .. " 战利品!", 255, 220, 50)
            end
        end

        ::continueLord::
    end
end

-- ============================================================================
-- 死亡处理
-- ============================================================================

function Combat.processDeaths()
    -- Boss死亡 => 根据类型掉落不同战利品
    for _, b in ipairs(GS.bosses) do
        if b.alive and b.hp <= 0 then
            b.alive = false
            local cfg = CONFIG.BossTypes[b.bossType] or CONFIG.BossTypes.behemoth
            local loot = cfg.loot

            -- 掉落宝箱（木材+治疗）
            if (loot.wood or 0) > 0 or (loot.heal or 0) > 0 then
                Entities.createChest(b.x, b.y, loot.wood or 0, loot.heal or 0)
            end

            -- 掉落战利品箱（木材+石头，仅当石头>0时额外掉一个）
            if (loot.stone or 0) > 0 then
                Entities.createLootBox(b.x, b.y, 0, loot.stone)
            end

            -- 幽灵狼特殊掉落：全局移速buff
            if loot.speedBuff and loot.speedBuff > 0 then
                table.insert(GS.globalBuffs, {
                    type = "speed",
                    remaining = loot.speedBuff,
                    value = 1.3,  -- 30%移速提升
                })
                print("[BUFF] 幽灵狼击败！全体移速+30%，持续" .. loot.speedBuff .. "秒")
            end

            Entities.spawnParticle(b.x, b.y, 255, 100, 50, 15)
            CodexState.recordEnemyEncounter(b.bossType)
            print("[BOSS] " .. cfg.name .. " defeated!")
        end
    end

    -- 领主死亡 => 据点复活 或 真正淘汰
    for _, l in ipairs(GS.lords) do
        if l.alive and l.hp <= 0 then
            local Stronghold = require("Stronghold")
            local willRespawn = Stronghold.onLordDeath(l)
            if not willRespawn then
                -- 据点HP耗尽，真正淘汰
                print("[LORD] Faction " .. l.faction .. " eliminated (strongholdHP=0)!")
                if l.isPlayer then
                    GS.gameState = "gameover"
                    GS.settledGlory = TS.settleGame(false, GS.gameTime)
                end
            end
        end
    end

    -- 清理死亡实体
    for i = #GS.followers, 1, -1 do
        if not GS.followers[i].alive then table.remove(GS.followers, i) end
    end
    for i = #GS.resources, 1, -1 do
        if not GS.resources[i].alive then table.remove(GS.resources, i) end
    end
    for i = #GS.bosses, 1, -1 do
        if not GS.bosses[i].alive then table.remove(GS.bosses, i) end
    end
    for i = #GS.chests, 1, -1 do
        if not GS.chests[i].alive then table.remove(GS.chests, i) end
    end
    for i = #GS.lootBoxes, 1, -1 do
        if not GS.lootBoxes[i].alive then table.remove(GS.lootBoxes, i) end
    end

    -- 胜利检测：所有敌方领主的据点HP归零 + 领主本体也死亡
    if GS.gameState == "playing" then
        local allEnemiesEliminated = true
        for _, l in ipairs(GS.lords) do
            if l.faction ~= 1 then
                -- 敌方领主还活着，或据点HP还有（能复活）
                if l.alive or l.strongholdHP > 0 then
                    allEnemiesEliminated = false
                    break
                end
            end
        end
        -- 也检查是否有正在复活中的敌方领主
        if allEnemiesEliminated then
            for lordId, info in pairs(GS.respawning) do
                if info.lordRef and info.lordRef.faction ~= 1 then
                    allEnemiesEliminated = false
                    break
                end
            end
        end
        if allEnemiesEliminated then
            GS.gameState = "victory"
            GS.settledGlory = TS.settleGame(true, GS.gameTime)

            -- 战役模式：记录通关进度
            if GS.gameMode == "campaign" and GS.selectedLevelId then
                -- 计算玩家损失的随从数
                local casualties = 0
                for _, f in ipairs(GS.followers) do
                    if f.factionId == 1 and not f.alive then
                        casualties = casualties + 1
                    end
                end
                local reward = CampaignState.clearLevel(GS.selectedLevelId, casualties)
                if reward then
                    GS.campaignReward = reward
                    print("[CAMPAIGN] Level " .. GS.selectedLevelId .. " cleared! Reward: " .. reward.type .. "=" .. reward.id)
                else
                    print("[CAMPAIGN] Level " .. GS.selectedLevelId .. " cleared (no new reward)")
                end
            end
        end
    end
end

return Combat
