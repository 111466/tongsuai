-- ============================================================================
-- GameState.lua - 共享游戏状态表
-- ============================================================================

local GS = {
    -- 实体数组
    lords = {},
    followers = {},
    resources = {},
    bosses = {},
    giantBeasts = {},           -- 巨兽危险区实体数组
    chests = {},
    lootBoxes = {},
    projectiles = {},
    particles = {},
    damageNumbers = {},
    respawning = {},        -- lordId -> { timer, lordRef } 正在复活的领主

    -- 计时器
    gameTime = 0,
    gameState = "loading",  -- loading, talent_select, playing, gameover, victory
    settledGlory = 0,       -- 本局结算获得的功勋
    bossSpawnTimer = 0,
    nextBossSpawnTime = 0,
    resourceRespawnTimer = 0,

    -- 相机与屏幕
    cameraX = 0,
    cameraY = 0,
    screenW = 0,
    screenH = 0,

    -- 输入
    joystickX = 0,
    joystickY = 0,

    -- 虚拟摇杆状态
    joystickActive = false,
    joystickCenterX = 0,
    joystickCenterY = 0,

    -- 攻击按钮状态
    attackBtnPressed = false,        -- 当前帧是否按下攻击按钮（用于视觉高亮）
    attackBtnTriggered = false,      -- 本帧触发了一次攻击（消费后清零）
    playerAttackTimer = 0,           -- 玩家攻击冷却（秒）
    playerAttackAnimTrigger = false, -- 通知 Renderer 强制播攻击动画（消费后清零）

    -- 随机事件系统状态
    eventTimer = 0,
    nextEventTime = 0,
    activeEvent = nil,          -- { name, desc, remaining, type, deactivate }
    eventNotification = nil,    -- { text, timer }
    bloodMoonActive = false,    -- 血月：全部战斗伤害+50%
    fogActive = false,          -- 迷雾：光环缩小30%

    -- 全局buff
    globalBuffs = {},   -- { type, remaining }

    -- 小地图
    minimapExpanded = false,    -- 小地图是否展开（放大模式）

    -- 无尽模式状态
    endlessWave = 0,            -- 当前波次
    endlessState = "idle",      -- idle, fighting, shop, settled
    endlessWaveTimer = 0,       -- 波次内计时
    endlessEnemies = {},        -- 当前波敌人 (lordId of wave-lord)
    endlessWarCoins = 0,        -- 战功币（当局货币）
    endlessBestWave = 0,        -- 历史最高波次（云端读取）
    endlessBuffs = {},          -- 商店购买的临时/永久增益

    -- 副将小队系统
    squads = {},                -- lordId -> { {squadLeaderId, memberIds, formation, state, targetX, targetY}, ... }

    -- 技能系统
    skillCooldowns = {},        -- skillName -> remainingCD
    skillStates = {},           -- 技能激活状态
    barricades = {},            -- 拒马实体数组
    bountyChests = {},          -- 悬赏金箱数组
    skillSelectingTarget = false, -- 集火目标选择模式

    -- UI引用
    uiRoot_ = nil,

    -- 当前游戏模式
    gameMode = "skirmish",  -- "skirmish" | "campaign" | "endless"
    -- 战役关卡选择
    selectedChapter = 1,
    selectedLevelId = nil,

    -- ID生成器
    nextId = 0,
}

-- ============================================================================
-- 双模式系统（attack / defend）
-- ============================================================================

local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

--- 切换领主阵型（charge <-> turtle 双向切换）
function GS.tcSetMode(lordId, targetMode)
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then
            local prevMode = l.lordMode
            if l.lordMode == targetMode then
                l.lordMode = "charge"  -- 再次按下相同模式 → 回到冲锋阵
            else
                l.lordMode = targetMode
            end
            -- 设置阵型切换提示文字
            if l.lordMode == "turtle" then
                l.modeSwitchText = { text = "铁桶阵！", timer = 1.0, r = 80, g = 160, b = 255 }
            else
                l.modeSwitchText = { text = "冲锋阵！", timer = 1.0, r = 255, g = 100, b = 80 }
            end
            -- 切换到冲锋阵时触发爆发移速
            if l.lordMode == "charge" and prevMode ~= "charge" then
                local cfg = CONFIG.LordModes["charge"]
                l.chargeBurstTimer = cfg.burstDuration or 0
            end
            return
        end
    end
end

function GS.tcGetMode(lordId)
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then
            return l.lordMode or "charge"
        end
    end
    return "charge"
end

function GS.tcReset()
    for _, l in ipairs(GS.lords) do
        l.lordMode = "charge"
    end
end

-- 根据模式返回搜索半径倍率
function GS.tcGetSearchRadiusMul(lordId)
    local mode = GS.tcGetMode(lordId)
    local modeConfig = CONFIG.LordModes[mode]
    return modeConfig and modeConfig.searchMul or 1.0
end

-- 随从移速倍率（与领主相同）
function GS.tcGetUnitSpeedMul(lordId)
    local mode = GS.tcGetMode(lordId)
    local modeConfig = CONFIG.LordModes[mode]
    return modeConfig and modeConfig.speedMul or 1.0
end

-- 领主移速倍率
function GS.tcGetLordSpeedMul(lordId)
    local mode = GS.tcGetMode(lordId)
    local modeConfig = CONFIG.LordModes[mode]
    return modeConfig and modeConfig.speedMul or 1.0
end

-- 是否免疫击退（铁桶阵全军免疫）
function GS.tcIsKnockbackImmune(lordId)
    local mode = GS.tcGetMode(lordId)
    local modeConfig = CONFIG.LordModes[mode]
    return modeConfig and modeConfig.knockbackImmune or false
end

-- 冲锋爆发移速倍率（基于领主的 chargeBurstTimer）
function GS.tcGetChargeBurstMul(lordId)
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then
            if (l.chargeBurstTimer or 0) > 0 then
                return CONFIG.LordModes["charge"].burstSpeedMul or 1.5
            end
            return 1.0
        end
    end
    return 1.0
end

-- ============================================================================
-- 工具方法
-- ============================================================================

function GS.newId()
    GS.nextId = GS.nextId + 1
    return GS.nextId
end

return GS
