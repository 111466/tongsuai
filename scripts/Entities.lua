-- ============================================================================
-- Entities.lua - 实体创建与查找辅助
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local CodexState = require("CodexState")
local Entities = {}

-- 树精灵图有4种（与 Renderer.lua 的 TREE_SPRITE_FILES 对应）
local TREE_SPRITE_COUNT = 4

-- ============================================================================
-- 实体创建
-- ============================================================================

function Entities.createLord(x, y, faction, isPlayer)
    local lord = {
        id = GS.newId(),
        x = x, y = y,
        hp = CONFIG.LordHP,
        maxHp = CONFIG.LordHP,
        faction = faction,
        isPlayer = isPlayer or false,
        wood = 50,       -- 初始木材
        stone = 0,
        invincibleTimer = 0,
        alive = true,
        angle = 0,       -- 面朝方向
        targetX = nil,
        targetY = nil,
        -- AI 参数
        aiState = "wander",  -- wander, gather, attack, flee
        aiTimer = 0,
        aiTargetId = nil,
        -- 据点系统（领主即据点）
        strongholdHP = CONFIG.StrongholdHP,
        strongholdMaxHP = CONFIG.StrongholdHP,
        towerActive = true,
        towerTimer = 0,
        deathX = nil,
        deathY = nil,
    }
    table.insert(GS.lords, lord)
    return lord
end

function Entities.createFollower(lord, fType)
    local angle = math.random() * math.pi * 2
    local offset = 30 + math.random() * 20
    local f = {
        id = GS.newId(),
        x = lord.x + math.cos(angle) * offset,
        y = lord.y + math.sin(angle) * offset,
        factionId = lord.faction,
        lordId = lord.id,
        fType = fType,  -- "peasant", "soldier", "archer", "healer"
        state = "following", -- following, working, attacking, returning
        targetId = nil,
        targetX = nil,
        targetY = nil,
        workTimer = 0,
        alive = true,
        angle = 0,
        -- 通用HP系统
        hp = CONFIG.UnitStats[fType].hp,
        maxHp = CONFIG.UnitStats[fType].hp,
        attackTimer = 0,
        -- 弓箭手特有
        fireTimer = CONFIG.IsRangedUnit[fType] and 0 or nil,
        -- ========== 动画状态 ==========
        breathPhase = math.random() * math.pi * 2,  -- 呼吸相位（随机错开）
        hitTimer = 0,           -- 受击反馈计时器（>0 时缩放）
        prevX = lord.x + math.cos(angle) * offset,   -- 上一帧位置（用于检测移动）
        prevY = lord.y + math.sin(angle) * offset,
        bouncePhase = math.random() * math.pi * 2,   -- 弹跳相位
        dustTimer = 0,          -- 扬尘粒子冷却
        -- 治愈师特有
        healTimer = (fType == "healer") and 0 or nil,
    }
    table.insert(GS.followers, f)
    return f
end

function Entities.createResource(rType)
    local r = {
        id = GS.newId(),
        x = Utils.randomRange(80, CONFIG.MapWidth - 80),
        y = Utils.randomRange(80, CONFIG.MapHeight - 80),
        rType = rType,  -- "tree" or "mine"
        alive = true,
        amount = rType == "tree" and CONFIG.TreeWood or CONFIG.MineStone,
        -- 外观：随机选择精灵图类型和帧
        spriteType = math.random(1, TREE_SPRITE_COUNT),  -- 4种树
        spriteFrame = math.random(0, 7),                   -- 树8帧随机取1帧
        mineFrame = math.random(0, 5),                     -- 矿6帧随机取1帧
    }
    table.insert(GS.resources, r)
    return r
end

function Entities.createResourceAt(x, y, rType)
    local r = {
        id = GS.newId(),
        x = x,
        y = y,
        rType = rType,
        alive = true,
        amount = rType == "tree" and CONFIG.TreeWood or CONFIG.MineStone,
        spriteType = math.random(1, TREE_SPRITE_COUNT),
        spriteFrame = math.random(0, 7),
        mineFrame = math.random(0, 5),
    }
    table.insert(GS.resources, r)
    return r
end

function Entities.randomBossType()
    local types = CONFIG.BossTypes
    local totalWeight = 0
    for _, v in pairs(types) do totalWeight = totalWeight + v.weight end
    local roll = math.random() * totalWeight
    local acc = 0
    for k, v in pairs(types) do
        acc = acc + v.weight
        if roll <= acc then return k end
    end
    return "behemoth"
end

function Entities.createBoss(bossType)
    bossType = bossType or Entities.randomBossType()
    local cfg = CONFIG.BossTypes[bossType]

    -- 在地图边缘随机刷新
    local side = math.random(1, 4)
    local x, y
    if side == 1 then     -- 上
        x = Utils.randomRange(100, CONFIG.MapWidth - 100)
        y = 50
    elseif side == 2 then -- 下
        x = Utils.randomRange(100, CONFIG.MapWidth - 100)
        y = CONFIG.MapHeight - 50
    elseif side == 3 then -- 左
        x = 50
        y = Utils.randomRange(100, CONFIG.MapHeight - 100)
    else                  -- 右
        x = CONFIG.MapWidth - 50
        y = Utils.randomRange(100, CONFIG.MapHeight - 100)
    end

    local boss = {
        id = GS.newId(),
        x = x, y = y,
        hp = cfg.hp,
        maxHp = cfg.hp,
        bossType = bossType,
        alive = true,
        targetLordId = nil,
        angle = 0,
        -- 石甲蟹AOE计时
        aoeTimer = 0,
        -- 幽灵狼隐身
        stealthTimer = 0,
        isStealthed = false,
        -- ========== Boss 动画状态 ==========
        breathPhase = math.random() * math.pi * 2,
        hitTimer = 0,
        prevX = x,
        prevY = y,
        stepTimer = 0,       -- 脚步震动计时器
    }
    table.insert(GS.bosses, boss)
    print("[BOSS] " .. cfg.name .. " spawned at " .. math.floor(x) .. "," .. math.floor(y))
    return boss
end

function Entities.createGiantBeast(x, y)
    local beast = {
        id = GS.newId(),
        x = x, y = y,
        hp = CONFIG.BeastHP,
        maxHp = CONFIG.BeastHP,
        alive = true,
        attackTimer = 0,            -- 攻击间隔计时
        aggroTarget = nil,          -- 当前仇恨目标领主ID
        isAttacking = false,        -- 是否正在攻击（用于视觉效果）
        attackAnimTimer = 0,        -- 攻击动画计时
        breathPhase = math.random() * math.pi * 2,
    }
    table.insert(GS.giantBeasts, beast)
    print("[BEAST] Giant beast spawned at " .. math.floor(x) .. "," .. math.floor(y))
    return beast
end

function Entities.createChest(x, y, wood, heal)
    local c = {
        id = GS.newId(),
        x = x, y = y,
        wood = wood,
        heal = heal,
        alive = true,
        spawnTime = GS.gameTime,
    }
    table.insert(GS.chests, c)
    return c
end

function Entities.createLootBox(x, y, wood, stone)
    local lb = {
        id = GS.newId(),
        x = x, y = y,
        wood = wood,
        stone = stone,
        alive = true,
        spawnTime = GS.gameTime,
    }
    table.insert(GS.lootBoxes, lb)
    return lb
end

function Entities.spawnParticle(x, y, r, g, b, count)
    count = count or 5
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = 60 + math.random() * 80
        table.insert(GS.particles, {
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.4 + math.random() * 0.3,
            maxLife = 0.7,
            r = r, g = g, b = b,
            size = 2 + math.random() * 3,
        })
    end
end

function Entities.spawnDamageNumber(x, y, value, r, g, b)
    table.insert(GS.damageNumbers, {
        x = x, y = y - 10,
        text = tostring(value),
        life = 1.0,
        maxLife = 1.0,
        r = r or 255, g = g or 50, b = b or 50,
        vy = -40,
    })
end

-- ============================================================================
-- 查找辅助
-- ============================================================================

function Entities.findLordById(id)
    for _, l in ipairs(GS.lords) do
        if l.id == id and l.alive then return l end
    end
    return nil
end

function Entities.findResourceById(id)
    for _, r in ipairs(GS.resources) do
        if r.id == id and r.alive then return r end
    end
    return nil
end

function Entities.findBossById(id)
    for _, b in ipairs(GS.bosses) do
        if b.id == id and b.alive then return b end
    end
    return nil
end

function Entities.countFollowers(lordId, fType)
    local count = 0
    for _, f in ipairs(GS.followers) do
        if f.lordId == lordId and f.alive then
            if fType == nil or f.fType == fType then
                count = count + 1
            end
        end
    end
    return count
end

function Entities.getLordFollowers(lordId)
    local result = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lordId and f.alive then
            table.insert(result, f)
        end
    end
    return result
end

--- 统计领主的各类随从数量
--- @param lordId number
--- @return table<string, number> counts  e.g. { soldier = 3, archer = 2, ... }
function Entities.countFollowersByType(lordId)
    local counts = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lordId and f.alive then
            counts[f.fType] = (counts[f.fType] or 0) + 1
        end
    end
    return counts
end

--- 返回战斗随从数量
function Entities.countCombatFollowers(lordId)
    local c = Entities.countFollowersByType(lordId)
    local total = (c.soldier or 0) + (c.archer or 0)
    return total
end

return Entities
