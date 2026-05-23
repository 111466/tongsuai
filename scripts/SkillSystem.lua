-- ============================================================================
-- SkillSystem.lua - 领主主动技能系统
-- 6个技能: dash, focusFire, barricade, repel, bloodSacrifice, bounty
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local SkillSystem = {}

-- 技能名称列表（按键位 1-10 对应）
local SKILL_ORDER = { "dash", "focusFire", "barricade", "repel", "bloodSacrifice", "bounty",
                       "advisorReveal", "drummerWarDrum", "paladinShield", "assassinStrike" }

-- 技能中文名称
local SKILL_NAMES = {
    dash = "领主冲锋",
    focusFire = "集火号角",
    barricade = "召唤拒马",
    repel = "光环斥力",
    bloodSacrifice = "血祭",
    bounty = "重金悬赏",
    advisorReveal = "洞察全局",
    drummerWarDrum = "战鼓激励",
    paladinShield = "神圣护盾",
    assassinStrike = "暗影突袭",
}

-- ============================================================================
-- 初始化
-- ============================================================================

function SkillSystem.init()
    GS.skillCooldowns = {}
    GS.skillStates = {}
    GS.barricades = {}
    GS.bountyChests = {}
    GS.skillSelectingTarget = false
    -- 特殊兵种技能状态
    GS.advisorRevealState = nil
    GS.drummerBuffState = nil
    GS.paladinShieldState = nil
    GS.assassinStrikeState = nil
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

--- 获取玩家领主引用
local function getPlayerLord()
    local l = GS.lords[1]
    if l and l.alive and l.isPlayer then return l end
    return nil
end

--- 获取玩家领主的随从列表
local function getPlayerFollowers(lord)
    local result = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            table.insert(result, f)
        end
    end
    return result
end

--- 检查领主是否拥有指定类型的存活单位
local function hasUnitType(lord, fType)
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == fType then return true end
    end
    return false
end

-- ============================================================================
-- 能否释放判断
-- ============================================================================

function SkillSystem.canActivate(skillId)
    local lord = getPlayerLord()
    if not lord then return false, "领主不存在" end

    -- CD 检查
    if (GS.skillCooldowns[skillId] or 0) > 0 then
        return false, "冷却中"
    end

    local cfg = CONFIG.Skills[skillId]
    if not cfg then return false, "技能不存在" end

    -- 资源检查
    if skillId == "barricade" then
        if lord.wood < cfg.woodCost then
            return false, "木材不足(" .. cfg.woodCost .. ")"
        end
    elseif skillId == "bounty" then
        local totalRes = lord.wood + lord.stone
        if totalRes < cfg.resourceCost then
            return false, "资源不足(" .. cfg.resourceCost .. ")"
        end
    end

    -- 血祭需要至少 sacrificeCount 个随从
    if skillId == "bloodSacrifice" then
        local followers = getPlayerFollowers(lord)
        if #followers < cfg.sacrificeCount then
            return false, "随从不足(" .. cfg.sacrificeCount .. ")"
        end
    end

    -- 特殊兵种技能需要拥有对应兵种
    if skillId == "advisorReveal" then
        if not hasUnitType(lord, "advisor") then return false, "需要军师" end
    elseif skillId == "drummerWarDrum" then
        if not hasUnitType(lord, "drummer") then return false, "需要鼓手" end
    elseif skillId == "paladinShield" then
        if not hasUnitType(lord, "paladin") then return false, "需要圣骑士" end
    elseif skillId == "assassinStrike" then
        if not hasUnitType(lord, "assassin") then return false, "需要刺客" end
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
    elseif skillId == "focusFire" then
        SkillSystem._activateFocusFire(cfg, ...)
    elseif skillId == "barricade" then
        SkillSystem._activateBarricade(cfg)
    elseif skillId == "repel" then
        SkillSystem._activateRepel(cfg)
    elseif skillId == "bloodSacrifice" then
        SkillSystem._activateBloodSacrifice(cfg)
    elseif skillId == "bounty" then
        SkillSystem._activateBounty(cfg)
    elseif skillId == "advisorReveal" then
        return SkillSystem._activateAdvisorReveal(getPlayerLord())
    elseif skillId == "drummerWarDrum" then
        return SkillSystem._activateDrummerWarDrum(getPlayerLord())
    elseif skillId == "paladinShield" then
        return SkillSystem._activatePaladinShield(getPlayerLord())
    elseif skillId == "assassinStrike" then
        return SkillSystem._activateAssassinStrike(getPlayerLord())
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

    -- 冲锋方向：取当前移动方向，若静止取面朝方向
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

    -- 视觉特效：冲锋拖尾粒子
    Entities.spawnParticle(lord.x, lord.y, 80, 160, 255, 8)
end

local function _updateDash(dt)
    local state = GS.skillStates.dash
    if not state then return end
    local lord = getPlayerLord()
    if not lord then GS.skillStates.dash = nil return end

    local cfg = CONFIG.Skills.dash
    state.timer = state.timer + dt

    -- 位移阶段
    if state.timer < state.duration then
        local t = state.timer / state.duration
        lord.x = Utils.lerp(state.startX, state.endX, t)
        lord.y = Utils.lerp(state.startY, state.endY, t)
        -- 冲锋期间无敌
        lord.invincibleTimer = 0.1
        -- 拖尾粒子
        Entities.spawnParticle(lord.x, lord.y, 80, 160, 255, 2)
    else
        -- 到达终点
        lord.x = state.endX
        lord.y = state.endY

        -- 击溃到达点的敌人（一次性）
        if not state.knockbackDone then
            state.knockbackDone = true
            for _, f in ipairs(GS.followers) do
                if f.alive and f.factionId ~= lord.faction then
                    local d = Utils.dist(lord.x, lord.y, f.x, f.y)
                    if d < cfg.interruptRadius then
                        -- 铁桶阵免疫击退
                        if not GS.tcIsKnockbackImmune(f.lordId) then
                            local dx, dy = Utils.normalize(f.x - lord.x, f.y - lord.y)
                            f.x = f.x + dx * cfg.knockback
                            f.y = f.y + dy * cfg.knockback
                            f.x = Utils.clamp(f.x, 10, CONFIG.MapWidth - 10)
                            f.y = Utils.clamp(f.y, 10, CONFIG.MapHeight - 10)
                            -- 打断攻击状态
                            f.state = "following"
                            f.targetId = nil
                        end
                    end
                end
            end
            -- 冲击波特效
            Entities.spawnParticle(lord.x, lord.y, 255, 255, 100, 15)
        end
    end

    -- 随从加速buff倒计时
    state.followerSpeedTimer = state.followerSpeedTimer - dt
    if state.timer >= state.duration and state.followerSpeedTimer <= 0 then
        GS.skillStates.dash = nil
    end
end

-- ============================================================================
-- 技能2: 集火号角 (focusFire)
-- 点击敌方领主/Boss，弓箭手集火5s，骑士加速接近
-- ============================================================================

--- 进入集火选目标模式
function SkillSystem._activateFocusFire(cfg)
    -- 进入目标选择模式
    GS.skillSelectingTarget = true
    -- 暂不开始CD，等选中目标后才开始
    GS.skillCooldowns.focusFire = 0
    print("[SKILL] Focus Fire: select target (click enemy lord/boss)")
end

--- 选中集火目标后调用
function SkillSystem.confirmFocusFireTarget(targetId, targetType)
    local lord = getPlayerLord()
    if not lord then return end
    local cfg = CONFIG.Skills.focusFire

    GS.skillSelectingTarget = false
    GS.skillCooldowns.focusFire = cfg.cd

    GS.skillStates.focusFire = {
        targetId = targetId,
        targetType = targetType,  -- "lord" or "boss"
        timer = cfg.duration,
    }

    Entities.spawnParticle(lord.x, lord.y, 255, 100, 50, 10)
    print("[SKILL] Focus Fire confirmed on " .. targetType .. " id=" .. targetId)
end

--- 取消集火目标选择
function SkillSystem.cancelFocusFire()
    GS.skillSelectingTarget = false
    GS.skillCooldowns.focusFire = 0
    print("[SKILL] Focus Fire cancelled")
end

local function _updateFocusFire(dt)
    local state = GS.skillStates.focusFire
    if not state then return end

    state.timer = state.timer - dt

    -- 检查目标是否还存在
    local targetAlive = false
    if state.targetType == "lord" then
        local t = Entities.findLordById(state.targetId)
        if t then targetAlive = true end
    elseif state.targetType == "boss" then
        local t = Entities.findBossById(state.targetId)
        if t then targetAlive = true end
    end

    if state.timer <= 0 or not targetAlive then
        GS.skillStates.focusFire = nil
    end
end

-- ============================================================================
-- 技能3: 召唤拒马 (barricade)
-- 消耗15木材，在领主身后放置障碍物
-- ============================================================================

function SkillSystem._activateBarricade(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    -- 扣资源
    lord.wood = lord.wood - cfg.woodCost

    -- 在领主身后放置（面朝方向的反方向，偏移60px）
    local behindX = lord.x - math.cos(lord.angle) * 60
    local behindY = lord.y - math.sin(lord.angle) * 60
    behindX = Utils.clamp(behindX, 20, CONFIG.MapWidth - 20)
    behindY = Utils.clamp(behindY, 20, CONFIG.MapHeight - 20)

    local barricade = {
        id = GS.newId(),
        x = behindX, y = behindY,
        hp = cfg.hp,
        maxHp = cfg.hp,
        radius = cfg.radius,
        lifetime = cfg.lifetime,
        ownerFaction = lord.faction,
        alive = true,
    }
    table.insert(GS.barricades, barricade)

    Entities.spawnParticle(behindX, behindY, 139, 90, 43, 10)
    print("[SKILL] Barricade placed at " .. math.floor(behindX) .. "," .. math.floor(behindY))
end

local function _updateBarricades(dt)
    local cfg = CONFIG.Skills.barricade
    for i = #GS.barricades, 1, -1 do
        local b = GS.barricades[i]
        if b.alive then
            b.lifetime = b.lifetime - dt

            -- 对接触拒马的敌方单位造成DPS
            for _, f in ipairs(GS.followers) do
                if f.alive and f.factionId ~= b.ownerFaction then
                    local d = Utils.dist(f.x, f.y, b.x, b.y)
                    if d < b.radius + 15 then
                        f.hp = f.hp - cfg.dps * dt
                        if f.hp <= 0 then
                            f.alive = false
                            Entities.spawnParticle(f.x, f.y, 139, 90, 43, 4)
                        end
                    end
                end
            end

            -- 超时或HP耗尽则销毁
            if b.lifetime <= 0 or b.hp <= 0 then
                b.alive = false
                Entities.spawnParticle(b.x, b.y, 139, 90, 43, 8)
            end
        end
        if not b.alive then
            table.remove(GS.barricades, i)
        end
    end
end

-- ============================================================================
-- 技能4: 光环斥力 (repel)
-- 瞬间将光环内敌方近战单位推开100px
-- ============================================================================

function SkillSystem._activateRepel(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    local pushCount = 0
    local auraR = CONFIG.AuraRadius

    for _, f in ipairs(GS.followers) do
        if f.alive and f.factionId ~= lord.faction then
            -- 只推近战单位（非弓箭手），铁桶阵免疫
            if f.fType ~= "archer" and not GS.tcIsKnockbackImmune(f.lordId) then
                local d = Utils.dist(lord.x, lord.y, f.x, f.y)
                if d < auraR then
                    local dx, dy = Utils.normalize(f.x - lord.x, f.y - lord.y)
                    -- 距离过近时给个默认方向
                    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
                        local randAngle = math.random() * math.pi * 2
                        dx = math.cos(randAngle)
                        dy = math.sin(randAngle)
                    end
                    f.x = f.x + dx * cfg.pushDist
                    f.y = f.y + dy * cfg.pushDist
                    f.x = Utils.clamp(f.x, 10, CONFIG.MapWidth - 10)
                    f.y = Utils.clamp(f.y, 10, CONFIG.MapHeight - 10)
                    -- 打断攻击
                    f.state = "following"
                    f.targetId = nil
                    pushCount = pushCount + 1
                end
            end
        end
    end

    -- 斥力波纹特效
    GS.skillStates.repel = {
        x = lord.x, y = lord.y,
        timer = 0.5,  -- 视觉效果持续0.5s
        radius = auraR,
    }

    Entities.spawnParticle(lord.x, lord.y, 180, 220, 255, 20)
    print("[SKILL] Repel pushed " .. pushCount .. " enemies")
end

local function _updateRepel(dt)
    local state = GS.skillStates.repel
    if not state then return end
    state.timer = state.timer - dt
    if state.timer <= 0 then
        GS.skillStates.repel = nil
    end
end

-- ============================================================================
-- 技能5: 血祭 (bloodSacrifice)
-- 牺牲2个最低HP随从，领主回30HP，全军狂暴6s
-- ============================================================================

function SkillSystem._activateBloodSacrifice(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    local followers = getPlayerFollowers(lord)

    -- 按HP排序（升序），牺牲最低HP的
    table.sort(followers, function(a, b) return a.hp < b.hp end)

    local sacrificed = 0
    for i = 1, math.min(cfg.sacrificeCount, #followers) do
        local f = followers[i]
        f.alive = false
        -- 牺牲特效（红色血雾）
        Entities.spawnParticle(f.x, f.y, 200, 30, 30, 8)
        Entities.spawnDamageNumber(f.x, f.y, "牺牲", 200, 30, 30)
        sacrificed = sacrificed + 1
    end

    -- 领主回血
    lord.hp = math.min(lord.maxHp, lord.hp + cfg.healLord)
    Entities.spawnDamageNumber(lord.x, lord.y, "+" .. cfg.healLord, 50, 255, 100)

    -- 启动狂暴状态
    GS.skillStates.bloodSacrifice = {
        timer = cfg.frenzyDur,
        lordId = lord.id,
    }

    Entities.spawnParticle(lord.x, lord.y, 200, 30, 30, 15)
    print("[SKILL] Blood Sacrifice: " .. sacrificed .. " followers sacrificed, frenzy active")
end

local function _updateBloodSacrifice(dt)
    local state = GS.skillStates.bloodSacrifice
    if not state then return end
    state.timer = state.timer - dt
    if state.timer <= 0 then
        GS.skillStates.bloodSacrifice = nil
        print("[SKILL] Frenzy ended")
    end
end

-- ============================================================================
-- 技能6: 重金悬赏 (bounty)
-- 消耗50资源，放出金箱诱惑敌方平民/士兵
-- ============================================================================

function SkillSystem._activateBounty(cfg)
    local lord = getPlayerLord()
    if not lord then return end

    -- 扣资源（优先木材，不足补石头）
    local cost = cfg.resourceCost
    local woodUse = math.min(lord.wood, cost)
    lord.wood = lord.wood - woodUse
    local remaining = cost - woodUse
    if remaining > 0 then
        lord.stone = lord.stone - remaining
    end

    -- 在领主前方120px放置金箱
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
-- 军师：洞察全局
-- ============================================================================

function SkillSystem._activateAdvisorReveal(lord)
    local advisor = nil
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == "advisor" then
            advisor = f
            break
        end
    end
    if not advisor then return false end

    local cfg = CONFIG.Skills.advisorReveal
    GS.advisorRevealState = {
        active = true,
        x = advisor.x, y = advisor.y,
        timer = cfg.duration,
        radius = cfg.revealRadius,
    }
    GS.skillCooldowns.advisorReveal = cfg.cd
    print("[SKILL] Advisor Reveal activated")
    return true
end

local function _updateAdvisorReveal(dt)
    local s = GS.advisorRevealState
    if not s or not s.active then return end
    s.timer = s.timer - dt
    if s.timer <= 0 then
        s.active = false
        GS.advisorRevealState = nil
    end
end

--- 查询某位置是否在军师洞察范围内
function SkillSystem.isInRevealRange(x, y)
    local s = GS.advisorRevealState
    if not s or not s.active then return false end
    return Utils.dist(x, y, s.x, s.y) < s.radius
end

-- ============================================================================
-- 鼓手：战鼓激励
-- ============================================================================

function SkillSystem._activateDrummerWarDrum(lord)
    local drummer = nil
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == "drummer" then
            drummer = f
            break
        end
    end
    if not drummer then return false end

    local cfg = CONFIG.Skills.drummerWarDrum
    GS.drummerBuffState = {
        active = true,
        x = drummer.x, y = drummer.y,
        timer = cfg.duration,
        radius = cfg.buffRadius,
        mul = cfg.atkSpeedMul,
    }
    GS.skillCooldowns.drummerWarDrum = cfg.cd
    print("[SKILL] Drummer War Drum activated")
    return true
end

local function _updateDrummerWarDrum(dt)
    local s = GS.drummerBuffState
    if not s or not s.active then return end
    s.timer = s.timer - dt
    if s.timer <= 0 then
        s.active = false
        GS.drummerBuffState = nil
    end
end

--- 查询某单位是否受鼓手激励（返回攻速倍率）
function SkillSystem.getDrummerAtkSpeedMul(x, y, factionId)
    local s = GS.drummerBuffState
    if not s or not s.active then return 1.0 end
    if Utils.dist(x, y, s.x, s.y) < s.radius then
        return s.mul
    end
    return 1.0
end

-- ============================================================================
-- 圣骑士：神圣护盾
-- ============================================================================

function SkillSystem._activatePaladinShield(lord)
    local paladin = nil
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == "paladin" then
            paladin = f
            break
        end
    end
    if not paladin then return false end

    local cfg = CONFIG.Skills.paladinShield
    GS.paladinShieldState = {
        active = true,
        x = paladin.x, y = paladin.y,
        timer = cfg.duration,
        radius = cfg.shieldRadius,
        followUnit = paladin,
    }
    GS.skillCooldowns.paladinShield = cfg.cd
    print("[SKILL] Paladin Shield activated")
    return true
end

local function _updatePaladinShield(dt)
    local s = GS.paladinShieldState
    if not s or not s.active then return end
    s.timer = s.timer - dt
    -- 跟随圣骑士位置
    if s.followUnit and s.followUnit.alive then
        s.x = s.followUnit.x
        s.y = s.followUnit.y
    end
    if s.timer <= 0 then
        s.active = false
        GS.paladinShieldState = nil
    end
end

--- 查询某单位是否在护盾范围内（免疫伤害）
function SkillSystem.isShielded(x, y, factionId)
    local s = GS.paladinShieldState
    if not s or not s.active then return false end
    return Utils.dist(x, y, s.x, s.y) < s.radius
end

-- ============================================================================
-- 刺客：暗影突袭
-- ============================================================================

function SkillSystem._activateAssassinStrike(lord)
    local assassin = nil
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == "assassin" then
            assassin = f
            break
        end
    end
    if not assassin then return false end

    -- 找到最近的敌方单位作为目标
    local cfg = CONFIG.Skills.assassinStrike
    local target = nil
    local minDist = cfg.targetSearchRadius
    for _, f in ipairs(GS.followers) do
        if f.alive and f.factionId ~= assassin.factionId then
            local d = Utils.dist(assassin.x, assassin.y, f.x, f.y)
            if d < minDist then
                minDist = d
                target = f
            end
        end
    end
    if not target then return false end

    GS.assassinStrikeState = {
        active = true,
        unitId = assassin.id,
        targetId = target.id,
        timer = cfg.stealthDuration,
        phase = "stealth",
        damageMul = cfg.damageMul,
    }
    assassin.stealthed = true
    GS.skillCooldowns.assassinStrike = cfg.cd
    print("[SKILL] Assassin Strike activated, target: " .. target.fType)
    return true
end

local function _updateAssassinStrike(dt)
    local s = GS.assassinStrikeState
    if not s or not s.active then return end

    local assassin = nil
    local target = nil
    for _, f in ipairs(GS.followers) do
        if f.id == s.unitId then assassin = f end
        if f.id == s.targetId then target = f end
    end

    if not assassin or not assassin.alive or not target or not target.alive then
        if assassin then assassin.stealthed = false end
        s.active = false
        GS.assassinStrikeState = nil
        return
    end

    if s.phase == "stealth" then
        s.timer = s.timer - dt
        -- 隐身期间快速移向目标
        local dx, dy = Utils.normalize(target.x - assassin.x, target.y - assassin.y)
        assassin.x = assassin.x + dx * CONFIG.FollowerSpeed * 3.0 * dt
        assassin.y = assassin.y + dy * CONFIG.FollowerSpeed * 3.0 * dt

        local dist = Utils.dist(assassin.x, assassin.y, target.x, target.y)
        if dist < 15 or s.timer <= 0 then
            -- 执行致命一击
            s.phase = "strike"
            assassin.stealthed = false
            local baseDmg = CONFIG.UnitStats.assassin.atk
            local finalDmg = math.floor(baseDmg * s.damageMul)
            target.hp = target.hp - finalDmg
            Entities.spawnDamageNumber(target.x, target.y, finalDmg, 255, 50, 50)
            if target.hp <= 0 then
                target.alive = false
                Entities.spawnParticle(target.x, target.y, 100, 0, 100, 8)
            end
            s.active = false
            GS.assassinStrikeState = nil
        end
    end
end

-- ============================================================================
-- 每帧更新（由 main.lua 调用）
-- ============================================================================

function SkillSystem.update(dt)
    if GS.gameState ~= "playing" then return end

    -- 冷却倒计时
    for _, name in ipairs(SKILL_ORDER) do
        if GS.skillCooldowns[name] and GS.skillCooldowns[name] > 0 then
            GS.skillCooldowns[name] = GS.skillCooldowns[name] - dt
            if GS.skillCooldowns[name] < 0 then
                GS.skillCooldowns[name] = 0
            end
        end
    end

    -- 各技能持续效果更新
    _updateDash(dt)
    _updateFocusFire(dt)
    _updateBarricades(dt)
    _updateRepel(dt)
    _updateBloodSacrifice(dt)
    _updateBountyChests(dt)
    -- 特殊兵种技能
    _updateAdvisorReveal(dt)
    _updateDrummerWarDrum(dt)
    _updatePaladinShield(dt)
    _updateAssassinStrike(dt)
end

-- ============================================================================
-- 查询接口（供其他模块使用）
-- ============================================================================

--- 获取冲锋随从加速倍率（FollowerAI 用）
function SkillSystem.getDashSpeedMul()
    local state = GS.skillStates.dash
    if state and state.followerSpeedTimer > 0 then
        return CONFIG.Skills.dash.followerSpeedMul
    end
    return 1.0
end

--- 获取集火目标（FollowerAI 用）
--- 返回 targetEntity, targetType 或 nil
function SkillSystem.getFocusFireTarget()
    local state = GS.skillStates.focusFire
    if not state then return nil, nil end
    if state.targetType == "lord" then
        return Entities.findLordById(state.targetId), "lord"
    elseif state.targetType == "boss" then
        return Entities.findBossById(state.targetId), "boss"
    end
    return nil, nil
end

--- 集火骑士加速倍率
function SkillSystem.getFocusFireKnightSpeedBonus()
    local state = GS.skillStates.focusFire
    if state then
        return CONFIG.Skills.focusFire.knightSpeedBonus
    end
    return 0
end

--- 获取狂暴攻速倍率（Combat 用）
function SkillSystem.getFrenzyAtkSpeedMul(factionId)
    local state = GS.skillStates.bloodSacrifice
    if state then
        local lord = getPlayerLord()
        if lord and lord.faction == factionId then
            return CONFIG.Skills.bloodSacrifice.atkSpeedMul
        end
    end
    return 1.0
end

--- 获取吸血比例（Combat 用）
function SkillSystem.getLifestealPct(factionId)
    local state = GS.skillStates.bloodSacrifice
    if state then
        local lord = getPlayerLord()
        if lord and lord.faction == factionId then
            return CONFIG.Skills.bloodSacrifice.lifestealPct
        end
    end
    return 0
end

--- 拒马减速查询（FollowerAI 用）
--- 返回减速因子（0.5 = 50%减速），若不在拒马范围内返回 1.0
function SkillSystem.getBarricadeSlowFactor(x, y, factionId)
    local cfgB = CONFIG.Skills.barricade
    for _, b in ipairs(GS.barricades) do
        if b.alive and b.ownerFaction ~= factionId then
            local d = Utils.dist(x, y, b.x, b.y)
            if d < b.radius + 15 then
                return cfgB.slowFactor
            end
        end
    end
    return 1.0
end

--- 悬赏金箱吸引查询（FollowerAI 用）
--- 返回最近的敌方金箱或 nil
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

--- 拒马碰撞阻挡（FollowerAI 用）
--- 敌方单位试图穿过拒马时被推回
function SkillSystem.applyBarricadeCollision(f, dt)
    for _, b in ipairs(GS.barricades) do
        if b.alive and b.ownerFaction ~= f.factionId then
            local d = Utils.dist(f.x, f.y, b.x, b.y)
            if d < b.radius then
                -- 推出拒马
                local dx, dy = Utils.normalize(f.x - b.x, f.y - b.y)
                f.x = b.x + dx * (b.radius + 1)
                f.y = b.y + dy * (b.radius + 1)
            end
        end
    end
end

return SkillSystem
