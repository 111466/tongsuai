-- ============================================================================
-- SkillSystem.lua - 领主主动技能系统
-- 4个技能: dash, bounty, arrowRain, shieldWall
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local SkillSystem = {}

local SKILL_ORDER = { "dash", "bounty", "arrowRain", "shieldWall" }

local SKILL_NAMES = {
    dash = "领主冲锋",
    bounty = "重金悬赏",
    arrowRain = "箭雨",
    shieldWall = "盾墙",
}

-- ============================================================================
-- 初始化
-- ============================================================================

function SkillSystem.init()
    GS.skillCooldowns = {}
    GS.skillStates = {}
    GS.bountyChests = {}
    for _, name in ipairs(SKILL_ORDER) do
        GS.skillCooldowns[name] = 0
        GS.skillStates[name] = nil
    end
    print("[SKILL] Skill system initialized")
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function SkillSystem.getSkillOrder()
    return SKILL_ORDER
end

function SkillSystem.getSkillName(skillId)
    return SKILL_NAMES[skillId] or skillId
end

function SkillSystem.getCooldown(skillId)
    return GS.skillCooldowns[skillId] or 0
end

function SkillSystem.getMaxCooldown(skillId)
    local cfg = CONFIG.Skills[skillId]
    return cfg and cfg.cd or 0
end

function SkillSystem.isActive(skillId)
    return GS.skillStates[skillId] ~= nil
end

local function getPlayerLord()
    local l = GS.lords[1]
    if l and l.alive and l.isPlayer then return l end
    return nil
end

local function getPlayerFollowers(lord)
    local result = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            table.insert(result, f)
        end
    end
    return result
end

local function countFollowerType(lord, fType)
    local count = 0
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive and f.fType == fType then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- 能否释放判断
-- ============================================================================

function SkillSystem.canActivate(skillId)
    local lord = getPlayerLord()
    if not lord then return false, "领主不存在" end

    if (GS.skillCooldowns[skillId] or 0) > 0 then
        return false, "冷却中"
    end

    local cfg = CONFIG.Skills[skillId]
    if not cfg then return false, "技能不存在" end

    if skillId == "bounty" then
        local totalRes = lord.wood + lord.stone
        if totalRes < cfg.resourceCost then
            return false, "资源不足(" .. cfg.resourceCost .. ")"
        end
    end

    if skillId == "arrowRain" then
        local archerCount = countFollowerType(lord, "archer")
        if archerCount < cfg.requireArchers then
            return false, "弓箭手不足(" .. cfg.requireArchers .. ")"
        end
    end

    if skillId == "shieldWall" then
        local soldierCount = countFollowerType(lord, "soldier")
        if soldierCount < cfg.requireSoldiers then
            return false, "士兵不足(" .. cfg.requireSoldiers .. ")"
        end
    end

    return true
end

-- ============================================================================
-- 技能释放
-- ============================================================================

function SkillSystem.activate(skillId, ...)
    local ok, reason = SkillSystem.canActivate(skillId)
    if not ok then
        print("[SKILL] Cannot activate " .. skillId .. ": " .. reason)
        return false
    end

    local cfg = CONFIG.Skills[skillId]
    GS.skillCooldowns[skillId] = cfg.cd

    if skillId == "dash" then
        SkillSystem._activateDash(cfg, ...)
    elseif skillId == "bounty" then
        SkillSystem._activateBounty(cfg)
    elseif skillId == "arrowRain" then
        SkillSystem._activateArrowRain(cfg)
    elseif skillId == "shieldWall" then
        SkillSystem._activateShieldWall(cfg)
    end

    print("[SKILL] Activated: " .. SKILL_NAMES[skillId])
    return true
end

-- ============================================================================
-- 技能1: 领主冲锋 (dash)
-- 快速位移200px，到达点击溃敌人，随从加速2s
-- ============================================================================

function SkillSystem._activateDash(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    local dirX, dirY
    if math.abs(GS.joystickX) > 0.1 or math.abs(GS.joystickY) > 0.1 then
        dirX, dirY = Utils.normalize(GS.joystickX, GS.joystickY)
    else
        dirX = math.cos(lord.angle)
        dirY = math.sin(lord.angle)
    end

    local startX, startY = lord.x, lord.y
    local endX = Utils.clamp(lord.x + dirX * cfg.dist, 20, CONFIG.MapWidth - 20)
    local endY = Utils.clamp(lord.y + dirY * cfg.dist, 20, CONFIG.MapHeight - 20)

    GS.skillStates.dash = {
        startX = startX, startY = startY,
        endX = endX, endY = endY,
        timer = 0,
        duration = cfg.duration,
        knockbackDone = false,
        followerSpeedTimer = cfg.followerSpeedDur,
    }

    Entities.spawnParticle(lord.x, lord.y, 80, 160, 255, 8)
end

local function _updateDash(dt)
    local state = GS.skillStates.dash
    if not state then return end
    local lord = getPlayerLord()
    if not lord then GS.skillStates.dash = nil return end

    local cfg = CONFIG.Skills.dash
    state.timer = state.timer + dt

    if state.timer < state.duration then
        local t = state.timer / state.duration
        lord.x = Utils.lerp(state.startX, state.endX, t)
        lord.y = Utils.lerp(state.startY, state.endY, t)
        lord.invincibleTimer = 0.1
        Entities.spawnParticle(lord.x, lord.y, 80, 160, 255, 2)
    else
        lord.x = state.endX
        lord.y = state.endY

        if not state.knockbackDone then
            state.knockbackDone = true
            for _, f in ipairs(GS.followers) do
                if f.alive and f.factionId ~= lord.faction then
                    local d = Utils.dist(lord.x, lord.y, f.x, f.y)
                    if d < cfg.interruptRadius then
                        local dx, dy = Utils.normalize(f.x - lord.x, f.y - lord.y)
                        f.x = f.x + dx * cfg.knockback
                        f.y = f.y + dy * cfg.knockback
                        f.x = Utils.clamp(f.x, 10, CONFIG.MapWidth - 10)
                        f.y = Utils.clamp(f.y, 10, CONFIG.MapHeight - 10)
                        f.state = "following"
                        f.targetId = nil
                    end
                end
            end
            Entities.spawnParticle(lord.x, lord.y, 255, 255, 100, 15)
        end
    end

    state.followerSpeedTimer = state.followerSpeedTimer - dt
    if state.timer >= state.duration and state.followerSpeedTimer <= 0 then
        GS.skillStates.dash = nil
    end
end

-- ============================================================================
-- 技能2: 重金悬赏 (bounty)
-- 消耗50资源，放出金箱诱惑敌方平民/士兵
-- ============================================================================

function SkillSystem._activateBounty(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    local cost = cfg.resourceCost
    local woodUse = math.min(lord.wood, cost)
    lord.wood = lord.wood - woodUse
    local remaining = cost - woodUse
    if remaining > 0 then
        lord.stone = lord.stone - remaining
    end

    local frontX = lord.x + math.cos(lord.angle) * 120
    local frontY = lord.y + math.sin(lord.angle) * 120
    frontX = Utils.clamp(frontX, 20, CONFIG.MapWidth - 20)
    frontY = Utils.clamp(frontY, 20, CONFIG.MapHeight - 20)

    local chest = {
        id = GS.newId(),
        x = frontX, y = frontY,
        lifetime = cfg.lifetime,
        lureRadius = cfg.lureRadius,
        stunDur = cfg.stunDur,
        ownerFaction = lord.faction,
        alive = true,
    }
    table.insert(GS.bountyChests, chest)

    Entities.spawnParticle(frontX, frontY, 255, 215, 0, 12)
    print("[SKILL] Bounty chest placed at " .. math.floor(frontX) .. "," .. math.floor(frontY))
end

local function _updateBountyChests(dt)
    for i = #GS.bountyChests, 1, -1 do
        local c = GS.bountyChests[i]
        if c.alive then
            c.lifetime = c.lifetime - dt
            if c.lifetime <= 0 then
                c.alive = false
                Entities.spawnParticle(c.x, c.y, 255, 215, 0, 8)
            end
        end
        if not c.alive then
            table.remove(GS.bountyChests, i)
        end
    end
end

-- ============================================================================
-- 技能3: 箭雨 (arrowRain)
-- 解锁条件：3个弓箭手
-- 在领主前方200px处降下箭雨，范围半径80px，3波AOE伤害
-- ============================================================================

function SkillSystem._activateArrowRain(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    local targetX = lord.x + math.cos(lord.angle) * cfg.range
    local targetY = lord.y + math.sin(lord.angle) * cfg.range
    targetX = Utils.clamp(targetX, 20, CONFIG.MapWidth - 20)
    targetY = Utils.clamp(targetY, 20, CONFIG.MapHeight - 20)

    GS.skillStates.arrowRain = {
        x = targetX,
        y = targetY,
        radius = cfg.radius,
        waves = cfg.waves,
        waveInterval = cfg.waveInterval,
        timer = 0,
        wavesDone = 0,
        damage = cfg.damage,
        ownerFaction = lord.faction,
    }

    Entities.spawnParticle(targetX, targetY, 240, 200, 50, 10)
    print("[SKILL] Arrow Rain at " .. math.floor(targetX) .. "," .. math.floor(targetY))
end

local function _updateArrowRain(dt)
    local state = GS.skillStates.arrowRain
    if not state then return end

    state.timer = state.timer + dt

    while state.wavesDone < state.waves and state.timer >= (state.wavesDone + 1) * state.waveInterval do
        state.wavesDone = state.wavesDone + 1

        for _, f in ipairs(GS.followers) do
            if f.alive and f.factionId ~= state.ownerFaction then
                local d = Utils.dist(state.x, state.y, f.x, f.y)
                if d < state.radius then
                    f.hp = f.hp - state.damage
                    f.hitTimer = 0.2
                    if f.hp <= 0 then
                        f.alive = false
                        Entities.spawnParticle(f.x, f.y, 240, 200, 50, 4)
                    end
                    Entities.spawnDamageNumber(f.x, f.y, state.damage, 240, 200, 50)
                end
            end
        end

        for _, l in ipairs(GS.lords) do
            if l.alive and l.faction ~= state.ownerFaction then
                local d = Utils.dist(state.x, state.y, l.x, l.y)
                if d < state.radius then
                    l.hp = l.hp - state.damage
                    l.hitTimer = 0.2
                    Entities.spawnDamageNumber(l.x, l.y, state.damage, 240, 200, 50)
                end
            end
        end

        Entities.spawnParticle(state.x, state.y, 240, 200, 50, 8)
        print("[SKILL] Arrow Rain wave " .. state.wavesDone .. "/" .. state.waves)
    end

    if state.wavesDone >= state.waves then
        GS.skillStates.arrowRain = nil
    end
end

-- ============================================================================
-- 技能4: 盾墙 (shieldWall)
-- 解锁条件：3个士兵
-- 所有士兵举盾3秒，受到伤害-50%，无法移动
-- ============================================================================

function SkillSystem._activateShieldWall(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    GS.skillStates.shieldWall = {
        timer = cfg.duration,
        factionId = lord.faction,
    }

    Entities.spawnParticle(lord.x, lord.y, 220, 80, 80, 12)
    print("[SKILL] Shield Wall activated")
end

local function _updateShieldWall(dt)
    local state = GS.skillStates.shieldWall
    if not state then return end

    state.timer = state.timer - dt
    if state.timer <= 0 then
        GS.skillStates.shieldWall = nil
        print("[SKILL] Shield Wall ended")
    end
end

-- ============================================================================
-- 每帧更新（由 main.lua 调用）
-- ============================================================================

function SkillSystem.update(dt)
    if GS.gameState ~= "playing" then return end

    for _, name in ipairs(SKILL_ORDER) do
        if GS.skillCooldowns[name] and GS.skillCooldowns[name] > 0 then
            GS.skillCooldowns[name] = GS.skillCooldowns[name] - dt
            if GS.skillCooldowns[name] < 0 then
                GS.skillCooldowns[name] = 0
            end
        end
    end

    _updateDash(dt)
    _updateBountyChests(dt)
    _updateArrowRain(dt)
    _updateShieldWall(dt)
end

-- ============================================================================
-- 查询接口（供其他模块使用）
-- ============================================================================

function SkillSystem.getDashSpeedMul()
    local state = GS.skillStates.dash
    if state and state.followerSpeedTimer > 0 then
        return CONFIG.Skills.dash.followerSpeedMul
    end
    return 1.0
end

function SkillSystem.getNearestBountyChest(x, y, factionId)
    local nearest = nil
    local minDist = math.huge
    for _, c in ipairs(GS.bountyChests) do
        if c.alive and c.ownerFaction ~= factionId then
            local d = Utils.dist(x, y, c.x, c.y)
            if d < c.lureRadius and d < minDist then
                minDist = d
                nearest = c
            end
        end
    end
    return nearest, minDist
end

function SkillSystem.getArrowRainState()
    return GS.skillStates.arrowRain
end

function SkillSystem.isShieldWallActive(factionId)
    local state = GS.skillStates.shieldWall
    if state and state.factionId == factionId then
        return true
    end
    return false
end

function SkillSystem.isShieldWallStunned(follower)
    if not SkillSystem.isShieldWallActive(follower.factionId) then
        return false
    end
    return follower.fType == "soldier"
end

function SkillSystem.getUnlockStatus()
    local lord = getPlayerLord()
    local result = {}
    for _, name in ipairs(SKILL_ORDER) do
        local cfg = CONFIG.Skills[name]
        if not cfg then
            result[name] = false
        elseif name == "arrowRain" then
            result[name] = lord and countFollowerType(lord, "archer") >= cfg.requireArchers
        elseif name == "shieldWall" then
            result[name] = lord and countFollowerType(lord, "soldier") >= cfg.requireSoldiers
        else
            result[name] = true
        end
    end
    return result
end

return SkillSystem
