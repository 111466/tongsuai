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
-- 工具方法
-- ============================================================================

function GS.newId()
    GS.nextId = GS.nextId + 1
    return GS.nextId
end

return GS
