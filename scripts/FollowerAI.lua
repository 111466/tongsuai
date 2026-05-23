local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")
local TS = require("TalentSystem")
local SkillSystem = require("SkillSystem")

local dist = Utils.dist
local normalize = Utils.normalize
local clamp = Utils.clamp

local FollowerAI = {}

-- 资源占用表：resourceId -> followerId，防止多个平民采集同一资源
local resourceClaims = {}

--- 标记资源被某个平民占用
local function claimResource(resId, followerId)
    resourceClaims[resId] = followerId
end

--- 释放资源占用
local function releaseResource(resId)
    resourceClaims[resId] = nil
end

--- 检查资源是否已被占用
local function isResourceClaimed(resId)
    return resourceClaims[resId] ~= nil
end

--- 清理无效的占用（持有者死亡或不再采集该资源）
local function cleanupClaims()
    for resId, fId in pairs(resourceClaims) do
        local valid = false
        for _, f in ipairs(GS.followers) do
            if f.id == fId and f.alive and f.state == "working" and f.targetId == resId then
                valid = true
                break
            end
        end
        if not valid then
            resourceClaims[resId] = nil
        end
    end
end

--- 领主级别的资源分配：扫描光环内资源，随机分配给空闲平民
--- 每帧由 updateAll 对每个领主调用一次
local function assignResourcesForLord(lord)
    local peasantSearchRadius = CONFIG.AuraRadius
    if GS.fogActive then peasantSearchRadius = peasantSearchRadius * 0.7 end

    -- 收集光环内未被占用的资源
    local availableResources = {}
    for _, r in ipairs(GS.resources) do
        if r.alive and not isResourceClaimed(r.id) then
            local d = dist(lord.x, lord.y, r.x, r.y)
            if d < peasantSearchRadius then
                table.insert(availableResources, r)
            end
        end
    end

    if #availableResources == 0 then return end

    -- 收集该领主的空闲平民（following 状态的 peasant）
    local idlePeasants = {}
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == "peasant" and f.state == "following" then
            table.insert(idlePeasants, f)
        end
    end

    if #idlePeasants == 0 then return end

    -- 打乱空闲平民顺序（随机分配）
    for i = #idlePeasants, 2, -1 do
        local j = math.random(1, i)
        idlePeasants[i], idlePeasants[j] = idlePeasants[j], idlePeasants[i]
    end

    -- 逐个分配：每个资源只分配一个平民
    local peasantIdx = 1
    for _, r in ipairs(availableResources) do
        if peasantIdx > #idlePeasants then break end
        local f = idlePeasants[peasantIdx]
        f.state = "working"
        f.targetId = r.id
        f.targetX = r.x
        f.targetY = r.y
        f.workTimer = 0
        claimResource(r.id, f.id)
        peasantIdx = peasantIdx + 1
    end
end

local function getGlobalSpeedMul()
    for _, buff in ipairs(GS.globalBuffs) do
        if buff.type == "speed" and buff.remaining > 0 then
            return buff.value
        end
    end
    return 1.0
end

function FollowerAI.updateFollowerAI(f, dt)
    local lord = Entities.findLordById(f.lordId)
    if not lord then
        f.alive = false
        return
    end

    local globalSpd = getGlobalSpeedMul()
    local dToLord = dist(f.x, f.y, lord.x, lord.y)

    -- ===== 光环约束：超出领主光环半径时强制跟随 =====
    if dToLord > CONFIG.AuraRadius
        and f.state ~= "following"
        and f.state ~= "lured" then
        -- 如果在采集，释放资源锁定
        if f.state == "working" then
            releaseResource(f.targetId)
            f.targetId = nil
        end
        f.state = "following"
    end

    -- ===== 悬赏金箱诱惑：敌方平民/士兵被金箱吸引 =====
    if f.state ~= "lured" and (f.fType == "peasant" or f.fType == "soldier") then
        local chest, chestDist = SkillSystem.getNearestBountyChest(f.x, f.y, f.factionId)
        if chest then
            f.state = "lured"
            f.lureChestId = chest.id
            f.lureStunTimer = 0
        end
    end

    if f.state == "lured" then
        -- 找到金箱
        local foundChest = nil
        for _, c in ipairs(GS.bountyChests) do
            if c.id == f.lureChestId and c.alive then foundChest = c break end
        end
        if not foundChest then
            -- 金箱消失，恢复跟随
            f.state = "following"
            f.lureChestId = nil
            f.lureStunTimer = nil
        else
            local dToChest = dist(f.x, f.y, foundChest.x, foundChest.y)
            if dToChest > 15 then
                -- 走向金箱
                local dx, dy = normalize(foundChest.x - f.x, foundChest.y - f.y)
                f.x = f.x + dx * CONFIG.FollowerSpeed * 0.8 * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * 0.8 * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            else
                -- 到达金箱，呆站（被定住2s）
                f.lureStunTimer = (f.lureStunTimer or 0) + dt
                if f.lureStunTimer >= foundChest.stunDur then
                    f.state = "following"
                    f.lureChestId = nil
                    f.lureStunTimer = nil
                end
            end
        end
    elseif f.state == "following" then
        -- 环形编队逻辑
        local myIndex = 0
        local totalFollowing = 0
        for _, of in ipairs(GS.followers) do
            if of.alive and of.lordId == lord.id and of.state == "following" then
                totalFollowing = totalFollowing + 1
                if of.id == f.id then myIndex = totalFollowing end
            end
        end
        local formationRadius = CONFIG.LordRadiusMax + CONFIG.SoldierRadius + math.min(totalFollowing, 12) * 5
        local angleStep = (math.pi * 2) / math.max(totalFollowing, 1)
        local formAngle = angleStep * (myIndex - 1)
        local goalX = lord.x + math.cos(formAngle) * formationRadius
        local goalY = lord.y + math.sin(formAngle) * formationRadius

        -- 随从之间互斥力，避免重叠
        local sepX, sepY = 0, 0
        local separationRadius = CONFIG.SoldierRadius * 2
        for _, of in ipairs(GS.followers) do
            if of.id ~= f.id and of.alive and of.lordId == f.lordId then
                local sd = dist(f.x, f.y, of.x, of.y)
                if sd < separationRadius and sd > 0.1 then
                    local pushStr = (separationRadius - sd) / separationRadius * 120
                    local px, py = normalize(f.x - of.x, f.y - of.y)
                    sepX = sepX + px * pushStr
                    sepY = sepY + py * pushStr
                end
            end
        end

        -- 朝编队目标点移动
        local dashSpeedMul = 1.0
        if lord.isPlayer then
            dashSpeedMul = SkillSystem.getDashSpeedMul()
        end
        local gDist = dist(f.x, f.y, goalX, goalY)
        if gDist > 3 or dToLord > formationRadius + 60 then
            local dx, dy = normalize(goalX - f.x + sepX, goalY - f.y + sepY)
            local speed = CONFIG.FollowerSpeed * dashSpeedMul * globalSpd
            if dToLord > 200 then speed = speed * 1.8 end -- 掉队加速追赶
            if gDist < 20 then speed = speed * (gDist / 20) end -- 接近目标减速
            f.x = f.x + dx * speed * dt
            f.y = f.y + dy * speed * dt
            f.angle = math.atan2(dy, dx)
        else
            -- 已到位，只施加分离力
            if math.abs(sepX) > 0.1 or math.abs(sepY) > 0.1 then
                local sx, sy = normalize(sepX, sepY)
                f.x = f.x + sx * 60 * dt
                f.y = f.y + sy * 60 * dt
            end
        end

        -- 平民资源分配已由 assignResourcesForLord 统一处理，此处不再单独检测

        -- 如果是战斗单位（士兵/骑士/弓箭手），检测光环内的敌人
        if CONFIG.IsCombatUnit[f.fType] then
            -- === 集火号角：玩家随从优先攻击集火目标 ===
            local focusTarget, focusType = nil, nil
            if lord.isPlayer then
                focusTarget, focusType = SkillSystem.getFocusFireTarget()
            end

            if focusTarget then
                -- 集火目标有效，直接切换到攻击集火目标
                f.state = "attacking"
                f.targetId = focusTarget.id
                f.targetX = focusTarget.x
                f.targetY = focusTarget.y
            else
                -- 常规目标搜索
                local searchRadius = CONFIG.AuraRadius
                if GS.fogActive then searchRadius = searchRadius * 0.7 end
                local bestTarget = nil
                local bestTargetDist = searchRadius

                -- 检测敌方随从
                for _, ef in ipairs(GS.followers) do
                    if ef.alive and ef.factionId ~= f.factionId then
                        local dToEnemy = dist(lord.x, lord.y, ef.x, ef.y)
                        if dToEnemy < searchRadius then
                            local df = dist(f.x, f.y, ef.x, ef.y)
                            if df < bestTargetDist then
                                bestTargetDist = df
                                bestTarget = {type = "follower", id = ef.id, x = ef.x, y = ef.y}
                            end
                        end
                    end
                end

                -- 检测敌方领主
                for _, el in ipairs(GS.lords) do
                    if el.alive and el.faction ~= lord.faction then
                        local dToEnemy = dist(lord.x, lord.y, el.x, el.y)
                        if dToEnemy < searchRadius then
                            local df = dist(f.x, f.y, el.x, el.y)
                            if df < bestTargetDist then
                                bestTargetDist = df
                                bestTarget = {type = "lord", id = el.id, x = el.x, y = el.y}
                            end
                        end
                    end
                end

                -- 检测Boss
                for _, b in ipairs(GS.bosses) do
                    if b.alive then
                        local dToBoss = dist(lord.x, lord.y, b.x, b.y)
                        if dToBoss < searchRadius then
                            local df = dist(f.x, f.y, b.x, b.y)
                            if df < bestTargetDist then
                                bestTargetDist = df
                                bestTarget = {type = "boss", id = b.id, x = b.x, y = b.y}
                            end
                        end
                    end
                end

                if bestTarget then
                    f.state = "attacking"
                    f.targetId = bestTarget.id
                    f.targetX = bestTarget.x
                    f.targetY = bestTarget.y
                end
            end
        end

    elseif f.state == "working" then
        -- 平民：移动到资源并采集
        local res = Entities.findResourceById(f.targetId)
        if not res then
            releaseResource(f.targetId)
            f.state = "following"
            f.targetId = nil
            return
        end

        local dToRes = dist(f.x, f.y, res.x, res.y)
        if dToRes > 15 then
            local dx, dy = normalize(res.x - f.x, res.y - f.y)
            f.x = f.x + dx * CONFIG.FollowerSpeed * globalSpd * dt
            f.y = f.y + dy * CONFIG.FollowerSpeed * globalSpd * dt
            f.angle = math.atan2(dy, dx)
        else
            -- 到达资源，开始采集
            local gatherTime = CONFIG.PeasantGatherTime
            f.workTimer = f.workTimer + dt
            if f.workTimer >= gatherTime then
                -- 采集完成
                if res.rType == "tree" then
                    lord.wood = lord.wood + res.amount
                    Entities.spawnParticle(res.x, res.y, 100, 180, 60, 4)

                else
                    lord.stone = lord.stone + res.amount
                    Entities.spawnParticle(res.x, res.y, 160, 160, 180, 4)
                end
                Entities.spawnDamageNumber(res.x, res.y, "+" .. res.amount, 100, 255, 100)
                res.alive = false
                releaseResource(res.id)
                f.state = "following"
                f.targetId = nil
            end
        end

    elseif f.state == "attacking" then
        if SkillSystem.isShieldWallStunned(f) and f.fType == "soldier" then
            return
        end
        -- 战斗单位：冲向目标（骑士加速，弓箭手远程）
        -- 更新目标位置
        local targetAlive = false
        local tx, ty = f.targetX, f.targetY

        -- 查找各类目标
        for _, ef in ipairs(GS.followers) do
            if ef.id == f.targetId and ef.alive then
                tx, ty = ef.x, ef.y
                targetAlive = true
                break
            end
        end
        if not targetAlive then
            for _, el in ipairs(GS.lords) do
                if el.id == f.targetId and el.alive then
                    tx, ty = el.x, el.y
                    targetAlive = true
                    break
                end
            end
        end
        if not targetAlive then
            for _, b in ipairs(GS.bosses) do
                if b.id == f.targetId and b.alive then
                    tx, ty = b.x, b.y
                    targetAlive = true
                    break
                end
            end
        end

        if not targetAlive then
            f.state = "following"
            f.targetId = nil
            return
        end

        f.targetX = tx
        f.targetY = ty

        local dToTarget = dist(f.x, f.y, tx, ty)

        if CONFIG.IsRangedUnit[f.fType] then
            -- 弓箭手：保持距离射击
            local unitRange = CONFIG.ArcherRange
            local unitFleeDistance = CONFIG.ArcherFleeDistance
            local unitFireInterval = CONFIG.ArcherFireInterval

            if dToTarget < unitFleeDistance then
                -- 被贴近，逃跑
                local dx, dy = normalize(f.x - tx, f.y - ty)
                f.x = f.x + dx * CONFIG.FollowerSpeed * 1.1 * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * 1.1 * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            elseif dToTarget > unitRange then
                -- 太远，靠近
                local dx, dy = normalize(tx - f.x, ty - f.y)
                f.x = f.x + dx * CONFIG.FollowerSpeed * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            else
                -- 在射程内，射击
                f.angle = math.atan2(ty - f.y, tx - f.x)
                f.fireTimer = (f.fireTimer or 0) + dt
                if f.fireTimer >= unitFireInterval then
                    f.fireTimer = 0
                    table.insert(GS.projectiles, {
                        x = f.x, y = f.y,
                        tx = tx, ty = ty,
                        speed = 350,
                        factionId = f.factionId,
                        fromArcherId = f.id,
                        alive = true,
                        attackerType = f.fType,
                    })
                end
            end
        else
            -- 近战单位：冲到碰撞距离内，然后停下互砍
            local contactDist = 20
            if dToTarget > contactDist then
                local dx, dy = normalize(tx - f.x, ty - f.y)
                local chargeMul = 1.2
                f.x = f.x + dx * CONFIG.FollowerSpeed * chargeMul * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * chargeMul * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            else
                -- 已进入碰撞距离，停下来（Combat.processCombat 处理伤害）
                f.angle = math.atan2(ty - f.y, tx - f.x)
            end
        end
    end

    -- ===== 治愈师：主动治疗受伤友军 =====
    if f.fType == "healer" and f.alive then
        f.healTimer = (f.healTimer or 0) + dt
        if f.healTimer >= CONFIG.HealerInterval then
            f.healTimer = 0
            -- 在治疗范围内寻找血量最低的友军
            local bestTarget = nil
            local bestHpRatio = 1.0  -- 只治疗血量不满的单位
            local healRange = CONFIG.HealerRange
            -- 检查友军随从
            for _, target in ipairs(GS.followers) do
                if target.alive and target.id ~= f.id
                   and target.factionId == f.factionId
                   and target.hp and target.maxHp
                   and target.hp < target.maxHp then
                    local d = dist(f.x, f.y, target.x, target.y)
                    if d <= healRange then
                        local ratio = target.hp / target.maxHp
                        if ratio < bestHpRatio then
                            bestHpRatio = ratio
                            bestTarget = target
                        end
                    end
                end
            end
            -- 也检查领主
            if lord and lord.alive and lord.hp and lord.maxHp and lord.hp < lord.maxHp then
                local d = dist(f.x, f.y, lord.x, lord.y)
                if d <= healRange then
                    local ratio = lord.hp / lord.maxHp
                    if ratio < bestHpRatio then
                        bestHpRatio = ratio
                        bestTarget = lord
                    end
                end
            end
            -- 执行治疗
            if bestTarget then
                local healAmt = CONFIG.HealerHealAmount
                bestTarget.hp = math.min(bestTarget.maxHp, bestTarget.hp + healAmt)
                -- 在目标位置触发治疗特效（存入全局事件列表）
                if not GS.healEffects then GS.healEffects = {} end
                table.insert(GS.healEffects, {
                    x = bestTarget.x, y = bestTarget.y,
                    frame = 0, timer = 0, targetId = bestTarget.id,
                    factionId = f.factionId  -- 用于 Renderer 选取对应阵营特效
                })
                f.state = "healing"  -- 切换到施法动画状态
                f.healCastTimer = 0.5  -- 施法动画持续时长
            end
        end
        -- 施法状态计时结束后恢复 following
        if f.state == "healing" then
            f.healCastTimer = (f.healCastTimer or 0) - dt
            if f.healCastTimer <= 0 then
                f.state = "following"
            end
        end
    end

    -- 边界限制
    f.x = clamp(f.x, 10, CONFIG.MapWidth - 10)
    f.y = clamp(f.y, 10, CONFIG.MapHeight - 10)
end

--- 每帧调用一次：先清理无效占用，再为每个领主统一分配资源给空闲平民
function FollowerAI.updateAll()
    cleanupClaims()
    for _, lord in ipairs(GS.lords) do
        if lord.alive then
            assignResourcesForLord(lord)
        end
    end
end

return FollowerAI
