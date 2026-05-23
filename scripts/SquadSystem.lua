-- ============================================================================
-- SquadSystem.lua — 副将小队管理（分兵、归队、突击出击、劝降、独立 AI）
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local SQ = {}

-- =========================================================================
-- 分兵：将指定随从分配给副将，组成小队
-- =========================================================================

--- 创建副将小队
--- @param lordId number 所属领主 ID
--- @param viceGeneralId number 副将随从 ID
--- @param memberIds number[] 分配给小队的随从 ID 列表
--- @param formation string|nil 小队阵型（可选，默认跟随主队）
function SQ.createSquad(lordId, viceGeneralId, memberIds, formation)
    if not GS.squads then GS.squads = {} end

    -- 设计规范：同一时间最多 1 个副将小队生效
    if GS.squads[lordId] and #GS.squads[lordId] >= 1 then
        print("[SQUAD] Lord " .. lordId .. " already has an active squad — disband first")
        return false
    end

    -- 验证副将存在
    local vg = nil
    for _, f in ipairs(GS.followers) do
        if f.id == viceGeneralId and f.alive and f.fType == "vice_general" then
            vg = f
            break
        end
    end
    if not vg then
        print("[SQUAD] Vice general not found: " .. tostring(viceGeneralId))
        return false
    end

    -- 验证成员存在且属于同一领主
    local validMembers = {}
    for _, mid in ipairs(memberIds) do
        for _, f in ipairs(GS.followers) do
            if f.id == mid and f.alive and f.lordId == lordId and f.id ~= viceGeneralId then
                table.insert(validMembers, mid)
                break
            end
        end
    end

    local squad = {
        squadLeaderId = viceGeneralId,
        lordId = lordId,
        memberIds = validMembers,
        formation = formation or "circle",
        state = "active",     -- active, returning, charging, fleeing, scattered
        targetX = vg.x,
        targetY = vg.y,
        aiTimer = 0,
        -- 突击出击相关
        chargeTimer = 0,            -- 突击已持续时间
        defectionTimer = 0,         -- 劝降检测计时
        -- 逃窜/分散相关
        fleeTimer = 0,              -- 逃窜剩余时间
        scatterTimer = 0,           -- 分散剩余时间
        scatterTargets = {},        -- 分散目标坐标 { [followerId] = {x, y} }
    }

    GS.squads[lordId] = GS.squads[lordId] or {}
    table.insert(GS.squads[lordId], squad)

    -- 标记成员归属小队
    vg.squadRole = "leader"
    vg.squadIdx = #GS.squads[lordId]
    for _, mid in ipairs(validMembers) do
        for _, f in ipairs(GS.followers) do
            if f.id == mid then
                f.squadRole = "member"
                f.squadLeaderId = viceGeneralId
                break
            end
        end
    end

    print("[SQUAD] Created squad with " .. #validMembers .. " members under vice general " .. viceGeneralId)
    return true
end

-- =========================================================================
-- 归队：解散小队，成员回到主队
-- =========================================================================

function SQ.disbandSquad(lordId, squadIndex)
    if not GS.squads or not GS.squads[lordId] then return end
    local squad = GS.squads[lordId][squadIndex]
    if not squad then return end

    -- 清除成员标记
    for _, f in ipairs(GS.followers) do
        if f.squadLeaderId == squad.squadLeaderId then
            f.squadRole = nil
            f.squadLeaderId = nil
            f.squadStateCache = nil
        end
        if f.id == squad.squadLeaderId then
            f.squadRole = nil
            f.squadIdx = nil
            f.squadStateCache = nil
        end
    end

    table.remove(GS.squads[lordId], squadIndex)
    print("[SQUAD] Disbanded squad " .. squadIndex .. " for lord " .. lordId)
end

--- 解散领主的所有小队
function SQ.disbandAll(lordId)
    if not GS.squads or not GS.squads[lordId] then return end
    while #GS.squads[lordId] > 0 do
        SQ.disbandSquad(lordId, #GS.squads[lordId])
    end
end

-- =========================================================================
-- 突击出击
-- =========================================================================

--- 发起突击：小队脱离领主，获得高移速进攻
--- @param lordId number
--- @param squadIndex number
--- @return boolean success
function SQ.startCharge(lordId, squadIndex)
    if not GS.squads or not GS.squads[lordId] then return false end
    local squad = GS.squads[lordId][squadIndex]
    if not squad then return false end
    if squad.state ~= "active" then return false end

    -- 检查是否有可进攻阵型
    local formationId = GS.getActiveFormationId(lordId)
    if not formationId or not CONFIG.OffensiveFormations[formationId] then
        print("[SQUAD] Cannot charge: no offensive formation active")
        return false
    end

    squad.state = "charging"
    squad.chargeTimer = 0
    squad.defectionTimer = 0

    -- 缓存状态到随从上，供 FollowerAI 和 Renderer 使用
    SQ._cacheSquadState(squad)

    -- 通知
    GS.eventNotification = { text = "小队突击出击！", timer = 2.0 }
    print("[SQUAD] Squad " .. squadIndex .. " charging!")
    return true
end

--- 召回突击中的小队
--- @param lordId number
--- @param squadIndex number
function SQ.recallSquad(lordId, squadIndex)
    if not GS.squads or not GS.squads[lordId] then return end
    local squad = GS.squads[lordId][squadIndex]
    if not squad then return end
    if squad.state ~= "charging" then return end

    squad.state = "active"
    squad.chargeTimer = 0
    squad.defectionTimer = 0

    SQ._cacheSquadState(squad)

    GS.eventNotification = { text = "小队已召回", timer = 1.5 }
    print("[SQUAD] Squad " .. squadIndex .. " recalled")
end

--- 触发劝降：小队叛变，成员转变阵营
--- @param squad table
local function triggerDefection(squad)
    -- 找到最近的敌方领主作为新阵营归属
    local leader = nil
    for _, f in ipairs(GS.followers) do
        if f.id == squad.squadLeaderId and f.alive then
            leader = f
            break
        end
    end
    if not leader then return end

    local nearestEnemyLord = nil
    local nearestDist = 999999
    for _, l in ipairs(GS.lords) do
        if l.alive and l.faction ~= leader.factionId then
            local d = Utils.dist(leader.x, leader.y, l.x, l.y)
            if d < nearestDist then
                nearestDist = d
                nearestEnemyLord = l
            end
        end
    end

    if not nearestEnemyLord then return end

    -- 转变阵营：副将和所有成员
    local allIds = { squad.squadLeaderId }
    for _, mid in ipairs(squad.memberIds) do
        table.insert(allIds, mid)
    end

    for _, fid in ipairs(allIds) do
        for _, f in ipairs(GS.followers) do
            if f.id == fid and f.alive then
                f.factionId = nearestEnemyLord.faction
                f.lordId = nearestEnemyLord.id
                f.squadRole = nil
                f.squadLeaderId = nil
                f.squadStateCache = "fleeing"
                -- 设置逃窜方向（远离原领主）
                local fleeAngle = math.random() * math.pi * 2
                f.fleeTargetX = f.x + math.cos(fleeAngle) * CONFIG.ScatterMinDist
                f.fleeTargetY = f.y + math.sin(fleeAngle) * CONFIG.ScatterMinDist
                f.fleeTimer = CONFIG.DefectionFleeDuration
                break
            end
        end
    end

    -- 从小队列表中移除（不走 disbandSquad 因为成员已转阵营）
    for lordId, squads in pairs(GS.squads) do
        for i, s in ipairs(squads) do
            if s == squad then
                table.remove(squads, i)
                break
            end
        end
    end

    GS.eventNotification = { text = "小队被劝降叛变！", timer = 3.0 }
    Entities.spawnDamageNumber(leader.x, leader.y, "叛变!", 255, 255, 255)
    print("[SQUAD] Squad defected to faction " .. nearestEnemyLord.faction)
end

-- =========================================================================
-- 巨兽分散：外部调用触发队伍分散
-- =========================================================================

--- 触发小队分散（被巨兽攻击时调用）
--- @param lordId number
--- @param beastX number 巨兽位置
--- @param beastY number
function SQ.triggerScatter(lordId, beastX, beastY)
    if not GS.squads or not GS.squads[lordId] then return end

    for _, squad in ipairs(GS.squads[lordId]) do
        if squad.state == "active" or squad.state == "charging" then
            squad.state = "scattered"
            squad.scatterTimer = CONFIG.ScatterDuration
            squad.scatterTargets = {}

            -- 为每个成员生成分散目标点（远离巨兽的随机方向）
            local allIds = { squad.squadLeaderId }
            for _, mid in ipairs(squad.memberIds) do
                table.insert(allIds, mid)
            end

            for _, fid in ipairs(allIds) do
                for _, f in ipairs(GS.followers) do
                    if f.id == fid and f.alive then
                        -- 远离巨兽方向 + 随机偏移
                        local dx, dy = Utils.normalize(f.x - beastX, f.y - beastY)
                        local randAngle = (math.random() - 0.5) * math.pi * 0.8
                        local cos_a, sin_a = math.cos(randAngle), math.sin(randAngle)
                        local ndx = dx * cos_a - dy * sin_a
                        local ndy = dx * sin_a + dy * cos_a
                        local scatterDist = Utils.randomRange(CONFIG.ScatterMinDist, CONFIG.ScatterMaxDist)
                        local tx = Utils.clamp(f.x + ndx * scatterDist, 50, CONFIG.MapWidth - 50)
                        local ty = Utils.clamp(f.y + ndy * scatterDist, 50, CONFIG.MapHeight - 50)
                        squad.scatterTargets[fid] = { x = tx, y = ty }
                        break
                    end
                end
            end

            SQ._cacheSquadState(squad)
            print("[SQUAD] Squad scattered from beast at " .. math.floor(beastX) .. "," .. math.floor(beastY))
        end
    end
end

-- =========================================================================
-- 小队 AI（每帧调用）
-- =========================================================================

function SQ.update(dt)
    if not GS.squads then return end
    for lordId, squads in pairs(GS.squads) do
        for i = #squads, 1, -1 do
            local squad = squads[i]

            if squad.state == "charging" then
                SQ._updateChargingAI(squad, dt)
            elseif squad.state == "scattered" then
                SQ._updateScatteredAI(squad, dt)
            else
                SQ.updateSquadAI(squad, dt)
            end

            -- 如果副将死亡，自动解散
            local leaderAlive = false
            for _, f in ipairs(GS.followers) do
                if f.id == squad.squadLeaderId and f.alive then
                    leaderAlive = true
                    break
                end
            end
            if not leaderAlive then
                SQ.disbandSquad(lordId, i)
            end
        end
    end

    -- 更新逃窜中的散兵（已叛变但在逃窜的单位）
    for _, f in ipairs(GS.followers) do
        if f.alive and f.squadStateCache == "fleeing" and f.fleeTimer then
            f.fleeTimer = f.fleeTimer - dt
            if f.fleeTimer <= 0 then
                f.squadStateCache = nil
                f.fleeTargetX = nil
                f.fleeTargetY = nil
                f.fleeTimer = nil
                f.state = "following"
            end
        end
    end
end

--- 突击状态 AI
function SQ._updateChargingAI(squad, dt)
    squad.chargeTimer = squad.chargeTimer + dt

    -- 超时自动召回
    if squad.chargeTimer >= CONFIG.ChargeMaxDuration then
        squad.state = "active"
        squad.chargeTimer = 0
        SQ._cacheSquadState(squad)
        GS.eventNotification = { text = "突击超时，小队回归", timer = 2.0 }
        print("[SQUAD] Charge timeout, returning to active")
        return
    end

    -- 劝降检测
    squad.defectionTimer = squad.defectionTimer + dt
    if squad.defectionTimer >= CONFIG.DefectionCheckInterval then
        squad.defectionTimer = 0
        SQ._checkDefection(squad)
        -- 如果已叛变，squad 已从列表移除，直接返回
        if squad.state ~= "charging" then return end
    end

    -- 找到副将
    local leader = nil
    for _, f in ipairs(GS.followers) do
        if f.id == squad.squadLeaderId and f.alive then
            leader = f
            break
        end
    end
    if not leader then return end

    -- 突击 AI：寻找最近敌人（搜索范围扩大到 500px）
    squad.aiTimer = (squad.aiTimer or 0) - dt
    if squad.aiTimer > 0 then return end
    squad.aiTimer = 0.5 + math.random() * 0.3

    local nearestEnemy = nil
    local nearestDist = 999999

    -- 搜索敌方随从
    for _, f in ipairs(GS.followers) do
        if f.alive and f.factionId ~= leader.factionId then
            local d = Utils.dist(leader.x, leader.y, f.x, f.y)
            if d < 500 and d < nearestDist then
                nearestDist = d
                nearestEnemy = f
            end
        end
    end

    -- 搜索敌方领主
    for _, l in ipairs(GS.lords) do
        if l.alive and l.faction ~= leader.factionId then
            local d = Utils.dist(leader.x, leader.y, l.x, l.y)
            if d < 500 and d < nearestDist then
                nearestDist = d
                nearestEnemy = l
            end
        end
    end

    if nearestEnemy then
        squad.targetX = nearestEnemy.x
        squad.targetY = nearestEnemy.y
    else
        -- 无敌人时随机巡逻
        squad.targetX = Utils.clamp(leader.x + Utils.randomRange(-200, 200), 50, CONFIG.MapWidth - 50)
        squad.targetY = Utils.clamp(leader.y + Utils.randomRange(-200, 200), 50, CONFIG.MapHeight - 50)
    end
end

--- 劝降检测
function SQ._checkDefection(squad)
    local leader = nil
    for _, f in ipairs(GS.followers) do
        if f.id == squad.squadLeaderId and f.alive then
            leader = f
            break
        end
    end
    if not leader then return end

    local chance = CONFIG.DefectionBaseChance

    -- 靠近敌方领主时概率翻倍
    for _, l in ipairs(GS.lords) do
        if l.alive and l.faction ~= leader.factionId then
            local d = Utils.dist(leader.x, leader.y, l.x, l.y)
            if d < CONFIG.DefectionNearEnemyDist then
                chance = chance * CONFIG.DefectionNearEnemyMul
                break
            end
        end
    end

    if math.random() < chance then
        triggerDefection(squad)
    end
end

--- 分散状态 AI
function SQ._updateScatteredAI(squad, dt)
    squad.scatterTimer = squad.scatterTimer - dt
    if squad.scatterTimer <= 0 then
        -- 分散结束，回归正常
        squad.state = "active"
        squad.scatterTargets = {}
        SQ._cacheSquadState(squad)
        GS.eventNotification = { text = "小队重新集结", timer = 1.5 }
        print("[SQUAD] Squad regrouped after scatter")
        return
    end

    -- 每个成员朝自己的分散目标移动（由 FollowerAI 处理实际移动）
    -- 这里只需要保持 scatterTargets 有效
end

--- 缓存小队状态到成员身上（供 FollowerAI 和 Renderer 读取）
function SQ._cacheSquadState(squad)
    local allIds = { squad.squadLeaderId }
    for _, mid in ipairs(squad.memberIds) do
        table.insert(allIds, mid)
    end
    for _, fid in ipairs(allIds) do
        for _, f in ipairs(GS.followers) do
            if f.id == fid and f.alive then
                f.squadStateCache = squad.state
                break
            end
        end
    end
end

--- 单个小队的常规 AI 决策（active/returning 状态）
function SQ.updateSquadAI(squad, dt)
    squad.aiTimer = squad.aiTimer - dt
    if squad.aiTimer > 0 then return end
    squad.aiTimer = 0.8 + math.random() * 0.5

    -- 找到副将
    local leader = nil
    for _, f in ipairs(GS.followers) do
        if f.id == squad.squadLeaderId and f.alive then
            leader = f
            break
        end
    end
    if not leader then return end

    -- 找到所属领主
    local lord = nil
    for _, l in ipairs(GS.lords) do
        if l.id == squad.lordId and l.alive then
            lord = l
            break
        end
    end
    if not lord then return end

    -- 小队独立 AI：在领主附近一定范围内自主行动
    -- 策略：向最近敌人移动，或在领主后方巡逻
    local nearestEnemy = nil
    local nearestDist = 999999
    for _, f in ipairs(GS.followers) do
        if f.alive and f.factionId ~= leader.factionId then
            local d = Utils.dist(leader.x, leader.y, f.x, f.y)
            if d < 300 and d < nearestDist then
                nearestDist = d
                nearestEnemy = f
            end
        end
    end

    if nearestEnemy then
        -- 有敌人时追击
        squad.targetX = nearestEnemy.x
        squad.targetY = nearestEnemy.y
    else
        -- 无敌人时在领主侧后方巡逻
        local offsetAngle = lord.angle + math.pi + (math.random() - 0.5) * 1.0
        local patrolDist = 100 + math.random() * 80
        squad.targetX = lord.x + math.cos(offsetAngle) * patrolDist
        squad.targetY = lord.y + math.sin(offsetAngle) * patrolDist
    end

    -- 保持在地图内
    squad.targetX = Utils.clamp(squad.targetX, 50, CONFIG.MapWidth - 50)
    squad.targetY = Utils.clamp(squad.targetY, 50, CONFIG.MapHeight - 50)
end

-- =========================================================================
-- 查询
-- =========================================================================

--- 判断随从是否属于某个小队
function SQ.isInSquad(followerId)
    for _, f in ipairs(GS.followers) do
        if f.id == followerId then
            return f.squadRole ~= nil
        end
    end
    return false
end

--- 获取随从所在小队的目标位置（FollowerAI 调用）
function SQ.getSquadTarget(followerId)
    if not GS.squads then return nil, nil end
    for _, f in ipairs(GS.followers) do
        if f.id == followerId and f.squadLeaderId then
            -- 找到所属小队
            for _, squads in pairs(GS.squads) do
                for _, squad in ipairs(squads) do
                    if squad.squadLeaderId == f.squadLeaderId then
                        -- 分散状态下返回个体目标
                        if squad.state == "scattered" and squad.scatterTargets[followerId] then
                            return squad.scatterTargets[followerId].x, squad.scatterTargets[followerId].y
                        end
                        return squad.targetX, squad.targetY
                    end
                end
            end
        end
    end
    return nil, nil
end

--- 获取随从所在小队的状态
function SQ.getSquadState(followerId)
    if not GS.squads then return nil end
    for _, f in ipairs(GS.followers) do
        if f.id == followerId then
            -- 检查缓存
            if f.squadStateCache then return f.squadStateCache end
            if f.squadLeaderId then
                for _, squads in pairs(GS.squads) do
                    for _, squad in ipairs(squads) do
                        if squad.squadLeaderId == f.squadLeaderId then
                            return squad.state
                        end
                    end
                end
            end
            return nil
        end
    end
    return nil
end

--- 获取领主的小队列表（UI 用）
function SQ.getSquads(lordId)
    if not GS.squads or not GS.squads[lordId] then return {} end
    local result = {}
    for i, squad in ipairs(GS.squads[lordId]) do
        local memberCount = 0
        for _, mid in ipairs(squad.memberIds) do
            for _, f in ipairs(GS.followers) do
                if f.id == mid and f.alive then
                    memberCount = memberCount + 1
                    break
                end
            end
        end
        result[i] = {
            index = i,
            leaderId = squad.squadLeaderId,
            memberCount = memberCount,
            formation = squad.formation,
            state = squad.state,
            chargeTimer = squad.chargeTimer,
        }
    end
    return result
end

--- 检查领主是否有小队可以突击
function SQ.canCharge(lordId)
    if not GS.squads or not GS.squads[lordId] then return false end
    local formationId = GS.getActiveFormationId(lordId)
    if not formationId or not CONFIG.OffensiveFormations[formationId] then return false end
    for _, squad in ipairs(GS.squads[lordId]) do
        if squad.state == "active" then return true end
    end
    return false
end

--- 检查领主是否有正在突击的小队
function SQ.hasChargingSquad(lordId)
    if not GS.squads or not GS.squads[lordId] then return false end
    for _, squad in ipairs(GS.squads[lordId]) do
        if squad.state == "charging" then return true end
    end
    return false
end

return SQ
