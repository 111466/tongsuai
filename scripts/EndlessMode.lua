-- ============================================================================
-- EndlessMode.lua — 无尽模式流程控制
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Entities = require("Entities")
local Utils = require("Utils")
local TS = require("TalentSystem")
local ShopSystem -- forward-declared, loaded lazily to break circular dep

local EM = {}

-- =========================================================================
-- 难度曲线配置
-- =========================================================================
local WAVE_CONFIG = {
    baseEnemyCount   = 5,
    countGrowthPct   = 10,
    eliteInterval    = 5,
    bossInterval     = 10,
    warCoinPerKill   = 2,
    eliteCoinMul     = 2,
}

-- 根据波次决定敌方可用兵种列表
local function getEnemyUnitPool()
    return { "soldier", "archer" }
end

-- =========================================================================
-- 初始化 / 重置
-- =========================================================================

--- 开始无尽模式（在 initGame 之后调用）
function EM.start()
    ShopSystem = ShopSystem or require("ShopSystem")
    GS.endlessWave = 0
    GS.endlessState = "idle"
    GS.endlessWarCoins = 0
    GS.endlessBuffs = {}
    EM.nextWave()
end

--- 推进到下一波
function EM.nextWave()
    -- 递减临时 buff（每进入新一波减 1 次）
    if GS.endlessWave > 0 then
        ShopSystem = ShopSystem or require("ShopSystem")
        ShopSystem.tickBuffs()
    end

    GS.endlessWave = GS.endlessWave + 1
    GS.endlessState = "fighting"
    GS.endlessWaveTimer = 0

    local wave = GS.endlessWave
    local isElite = (wave % WAVE_CONFIG.eliteInterval == 0)
    local isBoss  = (wave % WAVE_CONFIG.bossInterval == 0)

    -- 计算本波敌兵总数
    local growthMul = 1.0 + (wave - 1) * WAVE_CONFIG.countGrowthPct / 100
    local count = math.floor(WAVE_CONFIG.baseEnemyCount * growthMul)
    if isElite then count = math.floor(count * 1.3) end

    -- 创建波次敌方领主（非玩家、固定阵营 99）
    local spawnSide = math.random(1, 4)
    local sx, sy
    if spawnSide == 1 then
        sx = Utils.randomRange(200, CONFIG.MapWidth - 200); sy = 80
    elseif spawnSide == 2 then
        sx = Utils.randomRange(200, CONFIG.MapWidth - 200); sy = CONFIG.MapHeight - 80
    elseif spawnSide == 3 then
        sx = 80; sy = Utils.randomRange(200, CONFIG.MapHeight - 200)
    else
        sx = CONFIG.MapWidth - 80; sy = Utils.randomRange(200, CONFIG.MapHeight - 200)
    end

    local waveLord = Entities.createLord(sx, sy, 99, false)
    waveLord.isEndlessWaveLord = true
    waveLord.hp = 80 + wave * 10
    waveLord.maxHp = waveLord.hp
    GS.endlessEnemies = { waveLord.id }

    -- 获取兵种池并生成随从
    local pool = getEnemyUnitPool()
    for i = 1, count do
        local unitType = pool[math.random(1, #pool)]
        Entities.createFollower(waveLord, unitType)
    end

    -- Boss 波额外刷 Boss 实体
    if isBoss then
        Entities.createBoss()
    end

    print("[ENDLESS] Wave " .. wave .. " started — " .. count .. " enemies"
        .. (isElite and " (ELITE)" or "") .. (isBoss and " (BOSS)" or ""))
end

-- =========================================================================
-- 每帧更新
-- =========================================================================

function EM.update(dt)
    if GS.endlessState ~= "fighting" then return end

    GS.endlessWaveTimer = GS.endlessWaveTimer + dt

    -- 检测本波敌人是否全灭
    local allDead = true
    for _, lordId in ipairs(GS.endlessEnemies) do
        for _, l in ipairs(GS.lords) do
            if l.id == lordId and l.alive then
                allDead = false
                break
            end
        end
        if not allDead then break end
        -- 也检查该领主是否还有存活随从
        for _, f in ipairs(GS.followers) do
            if f.lordId == lordId and f.alive then
                allDead = false
                break
            end
        end
        if not allDead then break end
    end

    if allDead then
        EM.onWaveCleared()
    end

    -- 检测玩家是否全军覆没
    local playerLord = GS.lords[1]
    if playerLord and not playerLord.alive then
        local playerFollowersAlive = false
        for _, f in ipairs(GS.followers) do
            if f.lordId == playerLord.id and f.alive then
                playerFollowersAlive = true
                break
            end
        end
        if not playerFollowersAlive then
            EM.onPlayerDefeated()
        end
    end
end

-- =========================================================================
-- 波次结算
-- =========================================================================

function EM.onWaveCleared()
    local wave = GS.endlessWave
    local isElite = (wave % WAVE_CONFIG.eliteInterval == 0)

    -- 发放战功币
    local coinReward = 10 + wave * 2
    if isElite then coinReward = coinReward * WAVE_CONFIG.eliteCoinMul end
    GS.endlessWarCoins = GS.endlessWarCoins + coinReward

    -- 进入商店阶段
    GS.endlessState = "shop"
    ShopSystem = ShopSystem or require("ShopSystem")
    ShopSystem.refresh(wave)

    print("[ENDLESS] Wave " .. wave .. " cleared! +" .. coinReward .. " war coins. Total: " .. GS.endlessWarCoins)
end

--- 玩家跳过商店，直接下一波
function EM.skipShop()
    if GS.endlessState == "shop" then
        EM.nextWave()
    end
end

-- =========================================================================
-- 最终结算
-- =========================================================================

function EM.onPlayerDefeated()
    GS.endlessState = "settled"
    local wave = GS.endlessWave

    -- 更新最高波次
    if wave > GS.endlessBestWave then
        GS.endlessBestWave = wave
    end

    -- 声望奖励
    local reputation = 0
    if wave <= 9 then
        reputation = wave * 2                    -- 少量
    elseif wave <= 19 then
        reputation = 18 + (wave - 9) * 5         -- 中等
    else
        reputation = 68 + (wave - 19) * 8        -- 大量，每 5 波额外 +10
        local bonusBlocks = math.floor((wave - 20) / 5)
        reputation = reputation + bonusBlocks * 10
    end

    -- 应用声望到天赋系统
    TS.addReputation(reputation)

    print("[ENDLESS] Defeated at wave " .. wave .. ". Reputation +" .. reputation)
end

--- 查询当前波次信息（UI 用）
function EM.getWaveInfo()
    return {
        wave = GS.endlessWave,
        state = GS.endlessState,
        warCoins = GS.endlessWarCoins,
        bestWave = GS.endlessBestWave,
        isElite = (GS.endlessWave % WAVE_CONFIG.eliteInterval == 0),
        isBoss  = (GS.endlessWave % WAVE_CONFIG.bossInterval == 0),
    }
end

--- 战功币支出（ShopSystem 调用）
function EM.spendCoins(amount)
    if GS.endlessWarCoins >= amount then
        GS.endlessWarCoins = GS.endlessWarCoins - amount
        return true
    end
    return false
end

--- 当敌人被击杀时调用（Combat.lua 中集成）
function EM.onEnemyKilled()
    if GS.endlessState ~= "fighting" then return end
    local isElite = (GS.endlessWave % WAVE_CONFIG.eliteInterval == 0)
    local coins = WAVE_CONFIG.warCoinPerKill
    if isElite then coins = coins * WAVE_CONFIG.eliteCoinMul end
    GS.endlessWarCoins = GS.endlessWarCoins + coins
end

return EM
