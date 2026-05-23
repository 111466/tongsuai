-- ============================================================================
-- GiantBeastSystem.lua — 巨兽危险区系统
-- 静态巨兽：小队伍靠近不攻击，大队伍靠近会攻击并使队伍分散
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")
local SquadSystem = require("SquadSystem")
local CodexState = require("CodexState")

local BS = {}

-- =========================================================================
-- 初始化：在地图上放置巨兽
-- =========================================================================

function BS.init()
    GS.giantBeasts = {}

    -- 在地图上随机放置巨兽（远离中心玩家出生点和地图边缘）
    local margin = CONFIG.BeastSpawnMargin
    local centerX = CONFIG.MapWidth / 2
    local centerY = CONFIG.MapHeight / 2
    local minDistFromCenter = 600  -- 不要在玩家出生点附近

    local placed = 0
    local attempts = 0
    while placed < CONFIG.BeastMaxOnMap and attempts < 50 do
        attempts = attempts + 1
        local x = Utils.randomRange(margin, CONFIG.MapWidth - margin)
        local y = Utils.randomRange(margin, CONFIG.MapHeight - margin)

        -- 检查距中心的距离
        local d = Utils.dist(x, y, centerX, centerY)
        if d > minDistFromCenter then
            -- 检查与其他巨兽的距离（不要太近）
            local tooClose = false
            for _, beast in ipairs(GS.giantBeasts) do
                if Utils.dist(x, y, beast.x, beast.y) < 500 then
                    tooClose = true
                    break
                end
            end
            if not tooClose then
                Entities.createGiantBeast(x, y)
                placed = placed + 1
            end
        end
    end

    print("[BEAST] Placed " .. placed .. " giant beasts on map")
end

-- =========================================================================
-- 每帧更新：检测群体靠近并触发攻击/分散
-- =========================================================================

function BS.update(dt)
    if not GS.giantBeasts then return end

    for _, beast in ipairs(GS.giantBeasts) do
        if beast.alive then
            -- 攻击动画计时
            if beast.isAttacking then
                beast.attackAnimTimer = beast.attackAnimTimer - dt
                if beast.attackAnimTimer <= 0 then
                    beast.isAttacking = false
                end
            end

            -- 攻击冷却
            beast.attackTimer = math.max(0, beast.attackTimer - dt)

            -- 检测每个领主附近的群体数量
            for _, lord in ipairs(GS.lords) do
                if lord.alive then
                    local dToLord = Utils.dist(beast.x, beast.y, lord.x, lord.y)
                    if dToLord < CONFIG.BeastAggroRadius then
                        -- 统计这个领主在巨兽范围内的单位数量
                        local groupSize = 1  -- 领主自身算一个
                        local nearbyFollowers = {}
                        for _, f in ipairs(GS.followers) do
                            if f.alive and f.lordId == lord.id then
                                local df = Utils.dist(beast.x, beast.y, f.x, f.y)
                                if df < CONFIG.BeastAggroRadius then
                                    groupSize = groupSize + 1
                                    table.insert(nearbyFollowers, f)
                                end
                            end
                        end

                        -- 群体数量超过阈值，触发攻击
                        if groupSize >= CONFIG.BeastGroupThreshold and beast.attackTimer <= 0 then
                            BS._attack(beast, lord, nearbyFollowers)
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- 巨兽攻击逻辑
-- =========================================================================

function BS._attack(beast, lord, nearbyFollowers)
    beast.attackTimer = CONFIG.BeastAttackInterval
    beast.isAttacking = true
    beast.attackAnimTimer = 0.8  -- 攻击动画持续
    beast.aggroTarget = lord.id

    -- 对范围内所有单位造成伤害
    -- 对领主造成伤害
    local dToLord = Utils.dist(beast.x, beast.y, lord.x, lord.y)
    if dToLord < CONFIG.BeastAttackRadius then
        lord.hp = lord.hp - CONFIG.BeastAttackDamage
        lord.hitTimer = 0.3
        Entities.spawnDamageNumber(lord.x, lord.y, "-" .. CONFIG.BeastAttackDamage, 255, 80, 80)
        Entities.spawnParticle(lord.x, lord.y, 255, 100, 50, 6)
    end

    -- 对附近随从造成伤害
    for _, f in ipairs(nearbyFollowers) do
        local df = Utils.dist(beast.x, beast.y, f.x, f.y)
        if df < CONFIG.BeastAttackRadius then
            f.hp = f.hp - CONFIG.BeastAttackDamage
            f.hitTimer = 0.3
            if f.hp <= 0 then
                f.hp = 0
                -- 死亡由 Combat.processDeaths 处理
            end
        end
    end

    -- 记录图鉴遭遇
    CodexState.recordEnemyEncounter("map_giant_beast")

    -- 触发小队分散
    SquadSystem.triggerScatter(lord.id, beast.x, beast.y)

    -- 对没有小队的随从也施加分散效果（通过设置 squadStateCache）
    for _, f in ipairs(nearbyFollowers) do
        if f.alive and not SquadSystem.isInSquad(f.id) then
            -- 非小队成员也被吓散
            f.squadStateCache = "scattered"
            local dx, dy = Utils.normalize(f.x - beast.x, f.y - beast.y)
            local randAngle = (math.random() - 0.5) * math.pi * 0.6
            local cos_a, sin_a = math.cos(randAngle), math.sin(randAngle)
            local ndx = dx * cos_a - dy * sin_a
            local ndy = dx * sin_a + dy * cos_a
            local sDist = Utils.randomRange(CONFIG.ScatterMinDist, CONFIG.ScatterMaxDist)
            f.fleeTargetX = Utils.clamp(f.x + ndx * sDist, 50, CONFIG.MapWidth - 50)
            f.fleeTargetY = Utils.clamp(f.y + ndy * sDist, 50, CONFIG.MapHeight - 50)
            f.fleeTimer = CONFIG.ScatterDuration
        end
    end


    GS.eventNotification = { text = "巨兽咆哮！队伍四散！", timer = 2.5 }
    print("[BEAST] Beast attacked lord " .. lord.id .. " with " .. #nearbyFollowers .. " nearby followers")
end

-- =========================================================================
-- 查询接口
-- =========================================================================

--- 获取巨兽危险区数据（供 Renderer 和 Minimap 使用）
function BS.getBeasts()
    return GS.giantBeasts or {}
end

--- 检测某个位置是否在巨兽危险区内
function BS.isInDangerZone(x, y)
    if not GS.giantBeasts then return false end
    for _, beast in ipairs(GS.giantBeasts) do
        if beast.alive and Utils.dist(x, y, beast.x, beast.y) < CONFIG.BeastAggroRadius then
            return true
        end
    end
    return false
end

return BS
