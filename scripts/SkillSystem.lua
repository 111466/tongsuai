-- ============================================================================
-- SkillSystem.lua - 领主主动技能系统（拖拽施法）
-- 4个技能: dash, bounty, arrowRain, shieldWall
-- 所有技能采用"按住拖动选择方向/位置，松开释放"模式
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

local MAX_RANGE = CONFIG.AuraRadius * 2

-- ============================================================================
-- 初始化
-- ============================================================================

function SkillSystem.init()
    GS.skillCooldowns = {}
    GS.skillStates = {}
    GS.bountyChests = {}
    GS.skillAiming = nil
    for _, name in ipairs(SKILL_ORDER) do
        GS.skillCooldowns[name] = 0
        GS.skillStates[name] = nil
    end
    print("[SKILL] Skill system initialized (drag-cast)")
end

-- ============================================================================
-- 内部工具
-- ============================================================================

local function getPlayerLord()
    local l = GS.lords[1]
    if l and l.alive and l.isPlayer then return l end
    return nil
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

local function clampToWorld(x, y)
    return Utils.clamp(x, 20, CONFIG.MapWidth - 20),
           Utils.clamp(y, 20, CONFIG.MapHeight - 20)
end

local function clampToLordRange(wx, wy, lordX, lordY)
    local dx = wx - lordX
    local dy = wy - lordY
    local d = Utils.dist(lordX, lordY, wx, wy)
    if d > MAX_RANGE then
        local nx, ny = Utils.normalize(dx, dy)
        wx = lordX + nx * MAX_RANGE
        wy = lordY + ny * MAX_RANGE
    end
    return clampToWorld(wx, wy)
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

-- ============================================================================
-- 能否释放判断（简化为 true/false）
-- ============================================================================

function SkillSystem.canActivate(skillId)
    local lord = getPlayerLord()
    if not lord then return false end

    if (GS.skillCooldowns[skillId] or 0) > 0 then
        return false
    end

    if skillId == "bounty" then
        local cfg = CONFIG.Skills.bounty
        local totalRes = lord.wood + lord.stone
        if totalRes < cfg.resourceCost then
            return false, "资源不足"
        end
    end

    if skillId == "arrowRain" then
        local archerCount = countFollowerType(lord, "archer")
        if archerCount < 1 then
            return false, "弓箭手不足"
        end
    end

    if skillId == "shieldWall" then
        local soldierCount = countFollowerType(lord, "soldier")
        if soldierCount < 1 then
            return false, "士兵不足"
        end
    end

    return true
end

-- ============================================================================
-- 拖拽施法状态管理
-- ============================================================================

function SkillSystem.startAiming(skillId, screenX, screenY, fingerId)
    if not SkillSystem.canActivate(skillId) then
        return false
    end

    GS.skillAiming = {
        skillId = skillId,
        startX = screenX,
        startY = screenY,
        currentX = screenX,
        currentY = screenY,
        aimStartTime = os.clock(),
        fingerId = fingerId,  -- 触摸手指ID，nil表示鼠标
    }
    return true
end

function SkillSystem.updateAiming(screenX, screenY)
    if not GS.skillAiming then return end
    GS.skillAiming.currentX = screenX
    GS.skillAiming.currentY = screenY
end

function SkillSystem.cancelAiming()
    GS.skillAiming = nil
end

function SkillSystem.confirmAiming()
    if not GS.skillAiming then return false end

    local aiming = GS.skillAiming
    local skillId = aiming.skillId

    if not SkillSystem.canActivate(skillId) then
        GS.skillAiming = nil
        return false
    end

    local lord = getPlayerLord()
    if not lord then
        GS.skillAiming = nil
        return false
    end

    local cfg = CONFIG.Skills[skillId]
    GS.skillCooldowns[skillId] = cfg.cd

    -- 计算拖拽向量（当前位置 - 按钮中心起点）
    local dragX = aiming.currentX - aiming.startX
    local dragY = aiming.currentY - aiming.startY
    local dragDist = math.sqrt(dragX * dragX + dragY * dragY)
    local DEADZONE = 15  -- 小于15px的拖拽视为无方向
    local QUICK_TAP_THRESHOLD_MS = 200  -- 200ms内的点击视为快速点击
    local MAX_DRAG_DIST_PX = 100  -- 屏幕上最大拖动距离，超过此距离为最大释放距离

    local dirX, dirY  -- 屏幕空间方向（已归一化）
    local targetWX, targetWY  -- 世界空间目标位置

    local aimTimeElapsed = (os.clock() - aiming.aimStartTime) * 1000  -- 毫秒

    -- 判断是快速点击还是有拖动
    if aimTimeElapsed < QUICK_TAP_THRESHOLD_MS and dragDist < DEADZONE * 2 then
        -- 快速点击：朝角色朝向释放
        dirX = math.cos(lord.angle)
        dirY = math.sin(lord.angle)
        targetWX = lord.x + dirX * MAX_RANGE
        targetWY = lord.y + dirY * MAX_RANGE
    else
        -- 有拖动：根据拖动距离和方向释放
        if dragDist >= DEADZONE then
            dirX = dragX / dragDist
            dirY = dragY / dragDist
            -- 拖动距离映射到世界距离：0 到 MAX_RANGE
            local releaseDist = math.min(dragDist / MAX_DRAG_DIST_PX, 1.0) * MAX_RANGE
            targetWX = lord.x + dirX * releaseDist
            targetWY = lord.y + dirY * releaseDist
        else
            -- 有长按但拖动不够：朝角色朝向释放
            dirX = math.cos(lord.angle)
            dirY = math.sin(lord.angle)
            targetWX = lord.x + dirX * MAX_RANGE
            targetWY = lord.y + dirY * MAX_RANGE
        end
    end

    if skillId == "dash" then
        SkillSystem._activateDash(cfg, dirX, dirY)
    elseif skillId == "bounty" then
        SkillSystem._activateBounty(cfg, targetWX, targetWY)
    elseif skillId == "arrowRain" then
        SkillSystem._activateArrowRain(cfg, targetWX, targetWY)
    elseif skillId == "shieldWall" then
        local aimAngle = math.atan2(dirY, dirX)
        SkillSystem._activateShieldWall(cfg, aimAngle)
    end

    print("[SKILL] Activated: " .. SKILL_NAMES[skillId])
    GS.skillAiming = nil
    return true
end

function SkillSystem.getAimingState()
    return GS.skillAiming
end

function SkillSystem.getAimingTargetPosition()
    local aiming = GS.skillAiming
    if not aiming then return nil end

    local lord = getPlayerLord()
    if not lord then return nil end

    local dragX = aiming.currentX - aiming.startX
    local dragY = aiming.currentY - aiming.startY
    local dragDist = math.sqrt(dragX * dragX + dragY * dragY)
    local DEADZONE = 15
    local MAX_DRAG_DIST_PX = 100

    local dirX, dirY
    if dragDist >= DEADZONE then
        dirX = dragX / dragDist
        dirY = dragY / dragDist
        local releaseDist = math.min(dragDist / MAX_DRAG_DIST_PX, 1.0) * MAX_RANGE
        return lord.x + dirX * releaseDist, lord.y + dirY * releaseDist, dirX, dirY
    else
        dirX = math.cos(lord.angle)
        dirY = math.sin(lord.angle)
        return lord.x + dirX * MAX_RANGE, lord.y + dirY * MAX_RANGE, dirX, dirY
    end
end

function SkillSystem.activateWithTarget(skillId, targetWX, targetWY)
    if not SkillSystem.canActivate(skillId) then
        return false
    end

    local lord = getPlayerLord()
    if not lord then return false end

    local cfg = CONFIG.Skills[skillId]
    local tx, ty = clampToLordRange(targetWX, targetWY, lord.x, lord.y)

    GS.skillCooldowns[skillId] = cfg.cd

    if skillId == "dash" then
        local dx, dy = Utils.normalize(tx - lord.x, ty - lord.y)
        if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then
            dx = math.cos(lord.angle)
            dy = math.sin(lord.angle)
        end
        SkillSystem._activateDash(cfg, dx, dy)
    elseif skillId == "bounty" then
        SkillSystem._activateBounty(cfg, tx, ty)
    elseif skillId == "arrowRain" then
        SkillSystem._activateArrowRain(cfg, tx, ty)
    elseif skillId == "shieldWall" then
        local aimAngle = math.atan2(ty - lord.y, tx - lord.x)
        SkillSystem._activateShieldWall(cfg, aimAngle)
    end

    print("[SKILL] Activated: " .. SKILL_NAMES[skillId] .. " at " .. math.floor(tx) .. "," .. math.floor(ty))
    return true
end

-- ============================================================================
-- 技能1: 冲锋 (dash)
-- 拖拽方向 = 位移方向，距离 440px
-- ============================================================================

function SkillSystem._activateDash(cfg, dirX, dirY)
    local lord = getPlayerLord()
    if not lord then return end

    local startX, startY = lord.x, lord.y
    local endX = Utils.clamp(lord.x + dirX * cfg.dist, 20, CONFIG.MapWidth - 20)
    local endY = Utils.clamp(lord.y + dirY * cfg.dist, 20, CONFIG.MapHeight - 20)

    GS.skillStates.dash = {
        startX = startX, startY = startY,
        endX = endX, endY = endY,
        timer = 0,
        duration = cfg.duration,
        knockbackDone = false,
        knockbackDist = cfg.knockback,
        interruptRadius = cfg.interruptRadius,
        followerSpeedTimer = cfg.followerSpeedDur,
        followerSpeedMul = cfg.followerSpeedMul,
    }

    Entities.spawnParticle(lord.x, lord.y, 80, 160, 255, 8)
end

local function _updateDash(dt)
    local state = GS.skillStates.dash
    if not state then return end
    local lord = getPlayerLord()
    if not lord then GS.skillStates.dash = nil return end

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
                    if d < state.interruptRadius then
                        local dx, dy = Utils.normalize(f.x - lord.x, f.y - lord.y)
                        f.x = f.x + dx * state.knockbackDist
                        f.y = f.y + dy * state.knockbackDist
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
-- 技能2: 悬赏 (bounty)
-- 拖拽到目标位置放置金箱
-- ============================================================================

function SkillSystem._activateBounty(cfg, targetX, targetY)
    local lord = getPlayerLord()
    if not lord then return end

    local cost = cfg.resourceCost
    local woodUse = math.min(lord.wood, cost)
    lord.wood = lord.wood - woodUse
    local remaining = cost - woodUse
    if remaining > 0 then
        lord.stone = lord.stone - remaining
    end

    local chest = {
        id = GS.newId(),
        x = targetX, y = targetY,
        lifetime = cfg.lifetime,
        lureRadius = cfg.lureRadius,
        stunDur = cfg.stunDur,
        ownerFaction = lord.faction,
        alive = true,
    }
    table.insert(GS.bountyChests, chest)

    Entities.spawnParticle(targetX, targetY, 255, 215, 0, 12)
    print("[SKILL] Bounty chest placed at " .. math.floor(targetX) .. "," .. math.floor(targetY))
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
-- 拖拽到目标位置降下箭雨
-- ============================================================================

function SkillSystem._activateArrowRain(cfg, targetX, targetY)
    local lord = getPlayerLord()
    if not lord then return end

    local archerCount = countFollowerType(lord, "archer")
    local level = math.max(1, archerCount)
    local radius = cfg.baseRadius + (level - 1) * cfg.radiusPerLevel
    local waves = cfg.baseWaves + (level - 1) * cfg.wavesPerLevel
    local damage = cfg.baseDamage + archerCount * cfg.damagePerArcher

    if not targetX or not targetY then
        targetX = lord.x + math.cos(lord.angle) * 200
        targetY = lord.y + math.sin(lord.angle) * 200
    end
    targetX = Utils.clamp(targetX, 20, CONFIG.MapWidth - 20)
    targetY = Utils.clamp(targetY, 20, CONFIG.MapHeight - 20)

    GS.skillStates.arrowRain = {
        x = targetX,
        y = targetY,
        radius = radius,
        waves = waves,
        waveInterval = cfg.waveInterval,
        timer = 0,
        wavesDone = 0,
        damage = damage,
        ownerFaction = lord.faction,
    }

    Entities.spawnParticle(targetX, targetY, 240, 200, 50, 10)
    print("[SKILL] Arrow Rain at " .. math.floor(targetX) .. "," .. math.floor(targetY)
        .. " radius=" .. radius .. " waves=" .. waves .. " dmg=" .. damage)
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
-- 拖拽到目标位置，士兵列阵
-- ============================================================================

function SkillSystem._activateShieldWall(cfg, aimAngle)
    local lord = getPlayerLord()
    if not lord then return end

    local soldiers = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive and f.fType == "soldier" then
            table.insert(soldiers, f)
        end
    end

    local soldierCount = #soldiers
    local duration = cfg.baseDuration + (soldierCount - 1) * cfg.durationPerLevel

    local angle = aimAngle or lord.angle
    local perpAngle = angle + math.pi / 2
    local rowSize = cfg.rowSize
    local spacing = cfg.spacing

    local centerX = lord.x + math.cos(angle) * 40
    local centerY = lord.y + math.sin(angle) * 40

    for i, f in ipairs(soldiers) do
        local rowIdx = (i - 1) % rowSize
        local rowCount = math.min(rowSize, soldierCount - ((i - 1) // rowSize) * rowSize)
        local offset = (rowIdx - (rowCount - 1) / 2) * spacing
        local rowOffset = ((i - 1) // rowSize) * spacing

        f.shieldWallTargetX = centerX + math.cos(perpAngle) * offset + math.cos(angle) * (-rowOffset)
        f.shieldWallTargetY = centerY + math.sin(perpAngle) * offset + math.sin(angle) * (-rowOffset)
        f.shieldWallTargetX = Utils.clamp(f.shieldWallTargetX, 10, CONFIG.MapWidth - 10)
        f.shieldWallTargetY = Utils.clamp(f.shieldWallTargetY, 10, CONFIG.MapHeight - 10)
    end

    GS.skillStates.shieldWall = {
        timer = duration,
        factionId = lord.faction,
    }

    Entities.spawnParticle(lord.x, lord.y, 220, 80, 80, 12)
    print("[SKILL] Shield Wall activated duration=" .. duration .. " soldiers=" .. soldierCount)
end

local function _updateShieldWall(dt)
    local state = GS.skillStates.shieldWall
    if not state then return end

    state.timer = state.timer - dt
    if state.timer <= 0 then
        for _, f in ipairs(GS.followers) do
            if f.alive and f.fType == "soldier" and f.factionId == state.factionId then
                f.shieldWallTargetX = nil
                f.shieldWallTargetY = nil
            end
        end
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
        return state.followerSpeedMul
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
    return follower.shieldWallTargetX ~= nil
end

function SkillSystem.getUnlockStatus()
    local lord = getPlayerLord()
    local result = {}
    for _, name in ipairs(SKILL_ORDER) do
        local cfg = CONFIG.Skills[name]
        if not cfg then
            result[name] = false
        elseif name == "arrowRain" then
            result[name] = lord and countFollowerType(lord, "archer") >= 1
        elseif name == "shieldWall" then
            result[name] = lord and countFollowerType(lord, "soldier") >= 1
        else
            result[name] = true
        end
    end
    return result
end

-- 集火目标查询（当前未实现集火标记系统，始终返回 nil）
function SkillSystem.getFocusFireTarget()
    return nil, nil
end

return SkillSystem
