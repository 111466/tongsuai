-- ============================================================================
-- 《代号：统帅》 Code: Commander
-- 俯视角2D 轻量RTS / IO街机竞技
-- 入口胶水文件 - 所有逻辑已模块化拆分
-- ============================================================================

local UI = require("urhox-libs/UI")
local TS = require("TalentSystem")

local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

local GS = require("GameState")
local Utils = require("Utils")
local Entities = require("Entities")
local Stronghold = require("Stronghold")
local EventSystem = require("EventSystem")
local FollowerAI = require("FollowerAI")
local LordAI = require("LordAI")
local BossSystem = require("BossSystem")
local Combat = require("Combat")
local Renderer = require("Renderer")
local GameUI = require("GameUI")
local SkillSystem = require("SkillSystem")
local CampaignState = require("CampaignState")
local CampaignData = require("CampaignData")
local PresetManager = require("PresetManager")
local EndlessMode = require("EndlessMode")
local ShopSystem = require("ShopSystem")
local SquadSystem = require("SquadSystem")
local GiantBeastSystem = require("GiantBeastSystem")
local CodexState = require("CodexState")

-- UI 菜单模块
local MainMenuUI = require("MainMenuUI")
local CampaignSelectUI = require("CampaignSelectUI")
local EndlessShopUI = require("EndlessShopUI")
local MenuTheme = require("MenuTheme")

-- NanoVG 上下文（仅入口持有，通过 Renderer.init 传递）
local nvg = nil

-- ============================================================================
-- 游戏初始化
-- ============================================================================

local function initGame(mode)
    mode = mode or "skirmish"
    GS.gameMode = mode

    math.randomseed(os.time())
    GS.lords = {}
    GS.followers = {}
    GS.resources = {}
    GS.bosses = {}
    GS.chests = {}
    GS.lootBoxes = {}
    GS.projectiles = {}
    GS.particles = {}
    GS.damageNumbers = {}
    GS.respawning = {}
    GS.globalBuffs = {}
    GS.gameTime = 0
    GS.gameState = "playing"
    GS.settledGlory = 0
    GS.nextId = 0
    GS.squads = {}
    GS.giantBeasts = {}

    -- 重置战术指令状态
    GS.tcReset()

    -- 初始化技能系统
    SkillSystem.init()

    -- 战役模式：用关卡数据覆盖地图尺寸和资源
    local campaignLevel = nil
    if mode == "campaign" and GS.selectedLevelId then
        campaignLevel = CampaignData.getLevel(GS.selectedLevelId)
        if campaignLevel then
            CONFIG.MapWidth = campaignLevel.map_size.w
            CONFIG.MapHeight = campaignLevel.map_size.h
            print("[CAMPAIGN] Level " .. GS.selectedLevelId .. " map=" .. CONFIG.MapWidth .. "x" .. CONFIG.MapHeight)
        end
    end

    -- 创建资源
    if mode == "skirmish" or mode == "endless" then
        for i = 1, CONFIG.ResourceCount do
            if math.random() < 0.7 then
                Entities.createResource("tree")
            else
                Entities.createResource("mine")
            end
        end
    elseif mode == "campaign" and campaignLevel then
        for i = 1, (campaignLevel.resources or 30) do
            if math.random() < 0.7 then
                Entities.createResource("tree")
            else
                Entities.createResource("mine")
            end
        end
    end

    -- 创建玩家领主 (阵营1)
    local playerLord = Entities.createLord(
        CONFIG.MapWidth / 2,
        CONFIG.MapHeight / 2,
        1, true
    )

    -- 给玩家初始兵种
    if mode == "campaign" and campaignLevel and campaignLevel.player_start then
        for unitType, count in pairs(campaignLevel.player_start) do
            for i = 1, count do
                Entities.createFollower(playerLord, unitType)
            end
        end
    else
        for i = 1, CONFIG.InitPeasants do
            Entities.createFollower(playerLord, "peasant")
        end
    end

    if mode == "skirmish" then
        -- 遭遇战模式：创建 AI 领主（与现有逻辑相同）
        local spawnPositions = {
            {CONFIG.MapWidth * 0.2, CONFIG.MapHeight * 0.2},
            {CONFIG.MapWidth * 0.8, CONFIG.MapHeight * 0.2},
            {CONFIG.MapWidth * 0.2, CONFIG.MapHeight * 0.8},
            {CONFIG.MapWidth * 0.8, CONFIG.MapHeight * 0.8},
        }
        for i = 1, CONFIG.AILordCount do
            local sp = spawnPositions[i]
            local aiLord = Entities.createLord(sp[1], sp[2], i + 1, false)
            aiLord.wood = 30
            for j = 1, CONFIG.InitPeasants do
                Entities.createFollower(aiLord, "peasant")
            end
        end

    elseif mode == "campaign" then
        -- 战役模式：根据关卡配置创建敌方领主和随从
        if campaignLevel and campaignLevel.enemies then
            -- 敌方出生点（分布在地图边缘区域，远离中心玩家）
            local enemySpawns = {
                {CONFIG.MapWidth * 0.2, CONFIG.MapHeight * 0.2},
                {CONFIG.MapWidth * 0.8, CONFIG.MapHeight * 0.2},
                {CONFIG.MapWidth * 0.2, CONFIG.MapHeight * 0.8},
                {CONFIG.MapWidth * 0.8, CONFIG.MapHeight * 0.8},
            }
            for i, enemyGroup in ipairs(campaignLevel.enemies) do
                local sp = enemySpawns[((i - 1) % #enemySpawns) + 1]
                local aiLord = Entities.createLord(sp[1], sp[2], i + 1, false)
                aiLord.wood = 20

                -- 创建该组的所有兵种
                for unitType, count in pairs(enemyGroup.units) do
                    for j = 1, count do
                        Entities.createFollower(aiLord, unitType)
                    end
                end

                print("[CAMPAIGN] Enemy lord " .. i .. " faction=" .. aiLord.faction
                    .. " at (" .. math.floor(sp[1]) .. "," .. math.floor(sp[2]) .. ")")
            end
        end

    elseif mode == "endless" then
        -- 无尽模式：EndlessMode 负责波次生成
        EndlessMode.start()
    end

    -- Boss 计时（遭遇战专属）
    GS.bossSpawnTimer = 0
    GS.nextBossSpawnTime = Utils.randomRange(CONFIG.BossSpawnMin, CONFIG.BossSpawnMax)
    GS.resourceRespawnTimer = 0

    -- 巨兽危险区初始化
    GiantBeastSystem.init()

    -- 事件系统初始化
    EventSystem.init()

    -- 相机
    GS.cameraX = playerLord.x
    GS.cameraY = playerLord.y

    print("=== Game Initialized [" .. mode .. "] ===")
end

-- ============================================================================
-- 全局速度buff
-- ============================================================================

--- 获取全局速度buff倍率
local function getGlobalSpeedMul()
    for _, buff in ipairs(GS.globalBuffs) do
        if buff.type == "speed" and buff.remaining > 0 then
            return buff.value
        end
    end
    return 1.0
end
-- 暴露为全局供 FollowerAI 等模块使用（保持兼容）
_G.getGlobalSpeedMul = getGlobalSpeedMul

--- 更新全局buff计时器
local function updateGlobalBuffs(dt)
    for i = #GS.globalBuffs, 1, -1 do
        GS.globalBuffs[i].remaining = GS.globalBuffs[i].remaining - dt
        if GS.globalBuffs[i].remaining <= 0 then
            print("[BUFF] " .. GS.globalBuffs[i].type .. " buff expired")
            table.remove(GS.globalBuffs, i)
        end
    end
end

-- ============================================================================
-- 主更新循环
-- ============================================================================

local function updateGame(dt)
    if GS.gameState ~= "playing" then return end

    GS.gameTime = GS.gameTime + dt

    -- 更新冲锋爆发计时器
    for _, l in ipairs(GS.lords) do
        if l.alive and (l.chargeBurstTimer or 0) > 0 then
            l.chargeBurstTimer = l.chargeBurstTimer - dt
            if l.chargeBurstTimer < 0 then l.chargeBurstTimer = 0 end
        end
    end

    -- 更新随机事件系统
    EventSystem.update(dt)

    -- 更新全局buff
    updateGlobalBuffs(dt)

    -- 玩家领主移动（受战术指令移速倍率影响）
    local playerLord = GS.lords[1]
    if playerLord and playerLord.alive then
        local moveLen = math.sqrt(GS.joystickX * GS.joystickX + GS.joystickY * GS.joystickY)
        if moveLen > 0.1 then
            local nx, ny = GS.joystickX / moveLen, GS.joystickY / moveLen
            local lordSpeedMul = GS.tcGetLordSpeedMul(playerLord.id)
            local burstMul = GS.tcGetChargeBurstMul(playerLord.id)
            local globalSpd = getGlobalSpeedMul()
            playerLord.x = playerLord.x + nx * CONFIG.LordSpeed * lordSpeedMul * burstMul * globalSpd * dt
            playerLord.y = playerLord.y + ny * CONFIG.LordSpeed * lordSpeedMul * burstMul * globalSpd * dt
            playerLord.angle = math.atan2(ny, nx)
        end
        playerLord.x = Utils.clamp(playerLord.x, 20, CONFIG.MapWidth - 20)
        playerLord.y = Utils.clamp(playerLord.y, 20, CONFIG.MapHeight - 20)
        playerLord.invincibleTimer = math.max(0, playerLord.invincibleTimer - dt)
        playerLord.hitAnimTimer = math.max(0, (playerLord.hitAnimTimer or 0) - dt)

        -- 玩家主动攻击（攻击按钮触发）
        GS.playerAttackTimer = math.max(0, GS.playerAttackTimer - dt)
        if GS.attackBtnTriggered and GS.playerAttackTimer <= 0 then
            GS.attackBtnTriggered = false
            GS.playerAttackTimer = 0.6  -- 攻击冷却 0.6 秒

            -- 通知 Renderer 触发攻击动画（Renderer.updateLordAnims 消费此标记）
            GS.playerAttackAnimTrigger = true

            -- 对范围内敌方造成伤害（近战扇形，半径 80，伤害 30）
            local ATK_RANGE = 80
            local ATK_DMG   = 30
            local hitCount = 0

            -- 攻击敌方随从
            for _, f in ipairs(GS.followers) do
                if f.alive and f.factionId ~= playerLord.faction then
                    local d = Utils.dist(playerLord.x, playerLord.y, f.x, f.y)
                    if d < ATK_RANGE then
                        f.hp = f.hp - ATK_DMG
                        f.hitTimer = 0.2
                        Entities.spawnDamageNumber(f.x, f.y, ATK_DMG, 255, 100, 50)
                        Entities.spawnParticle(f.x, f.y, 255, 120, 50, 2)
                        if f.hp <= 0 then f.alive = false end
                        hitCount = hitCount + 1
                    end
                end
            end

            -- 攻击敌方领主
            for _, l in ipairs(GS.lords) do
                if l.alive and l.faction ~= playerLord.faction and l.invincibleTimer <= 0 then
                    local d = Utils.dist(playerLord.x, playerLord.y, l.x, l.y)
                    if d < ATK_RANGE then
                        l.hp = l.hp - ATK_DMG
                        l.invincibleTimer = 0.3
                        l.hitTimer = 0.2
                        Entities.spawnDamageNumber(l.x, l.y, ATK_DMG, 255, 80, 50)
                        Entities.spawnParticle(l.x, l.y, 255, 100, 50, 3)
                        hitCount = hitCount + 1
                    end
                end
            end

            -- 攻击 Boss
            for _, b in ipairs(GS.bosses) do
                if b.alive and not b.isStealthed then
                    local d = Utils.dist(playerLord.x, playerLord.y, b.x, b.y)
                    if d < ATK_RANGE + CONFIG.BossRadius then
                        b.hp = b.hp - ATK_DMG
                        b.hitTimer = 0.3
                        Entities.spawnDamageNumber(b.x, b.y, ATK_DMG, 255, 150, 50)
                        Entities.spawnParticle(b.x, b.y, 255, 150, 50, 3)
                        hitCount = hitCount + 1
                    end
                end
            end

            if hitCount > 0 then
                print("[ATTACK] 玩家攻击命中 " .. hitCount .. " 个目标")
            end
        else
            GS.attackBtnTriggered = false  -- 冷却中丢弃本帧触发
        end
    end

    -- AI领主更新
    for _, l in ipairs(GS.lords) do
        if l.alive and not l.isPlayer then
            l.invincibleTimer = math.max(0, l.invincibleTimer - dt)
            l.hitAnimTimer = math.max(0, (l.hitAnimTimer or 0) - dt)
            LordAI.updateAILord(l, dt)

            -- 移动AI领主向目标（受战术指令移速倍率影响）
            if l.targetX and l.targetY then
                local d = Utils.dist(l.x, l.y, l.targetX, l.targetY)
                if d > 20 then
                    local dx, dy = Utils.normalize(l.targetX - l.x, l.targetY - l.y)
                    local aiLordSpeedMul = GS.tcGetLordSpeedMul(l.id)
                    local aiBurstMul = GS.tcGetChargeBurstMul(l.id)
                    local gSpd = getGlobalSpeedMul()
                    l.x = l.x + dx * CONFIG.LordSpeed * 0.9 * aiLordSpeedMul * aiBurstMul * gSpd * dt
                    l.y = l.y + dy * CONFIG.LordSpeed * 0.9 * aiLordSpeedMul * aiBurstMul * gSpd * dt
                    l.angle = math.atan2(dy, dx)
                end
            end
            l.x = Utils.clamp(l.x, 20, CONFIG.MapWidth - 20)
            l.y = Utils.clamp(l.y, 20, CONFIG.MapHeight - 20)
        end
    end

    -- 统一分配资源给空闲平民（先于个体AI更新，避免多个平民抢同一资源）
    FollowerAI.updateAll()

    -- 更新随从
    for _, f in ipairs(GS.followers) do
        if f.alive then
            FollowerAI.updateFollowerAI(f, dt)
        end
    end

    -- 更新Boss
    for _, b in ipairs(GS.bosses) do
        if b.alive then
            BossSystem.updateBossAI(b, dt)
        end
    end

    -- 技能系统更新
    SkillSystem.update(dt)

    -- 巨兽危险区更新（在小队之前，以便触发scatter）
    GiantBeastSystem.update(dt)

    -- 副将小队更新
    SquadSystem.update(dt)

    -- 无尽模式更新
    if GS.gameMode == "endless" then
        EndlessMode.update(dt)
        -- 检测波次清除后进入商店阶段
        if GS.endlessState == "shop" and GS.gameState == "playing" then
            GS.gameState = "endless_shop"
            local info = EndlessMode.getWaveInfo()
            EndlessShopUI.show(info.wave, function()
                GS.gameState = "playing"
                EndlessMode.nextWave()
            end)
        end
    end

    -- 战斗处理
    Combat.processCombat(dt)
    Combat.processProjectiles(dt)

    -- 拾取处理
    Combat.processPickups()

    -- 死亡处理
    Combat.processDeaths()

    -- 据点系统更新（防御塔攻击、崩溃计时、复活处理）
    Stronghold.updateStrongholds(dt)

    -- Boss 刷新（遭遇战专属）
    if GS.gameMode == "skirmish" then
    GS.bossSpawnTimer = GS.bossSpawnTimer + dt
    if GS.bossSpawnTimer >= GS.nextBossSpawnTime then
        GS.bossSpawnTimer = 0
        GS.nextBossSpawnTime = Utils.randomRange(CONFIG.BossSpawnMin, CONFIG.BossSpawnMax)
        -- 计算当前存活Boss数量
        local aliveBossCount = 0
        for _, b in ipairs(GS.bosses) do
            if b.alive then aliveBossCount = aliveBossCount + 1 end
        end
        if aliveBossCount < CONFIG.BossMaxOnMap then
            Entities.createBoss()
        end
    end
    end -- skirmish mode boss spawning

    -- 资源重新生成
    GS.resourceRespawnTimer = GS.resourceRespawnTimer + dt
    if GS.resourceRespawnTimer > 5 then
        GS.resourceRespawnTimer = 0
        local resCount = 0
        for _, r in ipairs(GS.resources) do
            if r.alive then resCount = resCount + 1 end
        end
        if resCount < CONFIG.ResourceCount * 0.7 then
            local toSpawn = math.min(5, CONFIG.ResourceCount - resCount)
            for i = 1, toSpawn do
                if math.random() < 0.7 then
                    Entities.createResource("tree")
                else
                    Entities.createResource("mine")
                end
            end
        end
    end

    -- ========== 动画计时器更新（Game Feel） ==========
    -- 随从：hitTimer衰减 + prevXY + 扬尘粒子
    for _, f in ipairs(GS.followers) do
        if f.alive then
            -- hitTimer 衰减
            if (f.hitTimer or 0) > 0 then
                f.hitTimer = math.max(0, f.hitTimer - dt)
            end
            -- 移动检测（用于弹跳动画 + 扬尘）
            local fdx = f.x - (f.prevX or f.x)
            local fdy = f.y - (f.prevY or f.y)
            local fMoveSpeed = math.sqrt(fdx * fdx + fdy * fdy)
            -- 扬尘粒子：移动速度较快时在身后生成灰色小粒子
            f.dustTimer = (f.dustTimer or 0) - dt
            if fMoveSpeed > 0.5 and f.dustTimer <= 0 then
                f.dustTimer = 0.08  -- 每0.08秒一颗
                local dustAlpha = math.min(255, math.floor(fMoveSpeed * 80))
                Entities.spawnParticle(
                    f.x - fdx * 0.5 + (math.random() - 0.5) * 4,
                    f.y - fdy * 0.5 + (math.random() - 0.5) * 4,
                    160, 160, 160,  -- 灰色
                    1  -- 少量粒子
                )
            end
            -- 记录上一帧位置
            f.prevX = f.x
            f.prevY = f.y
        end
    end
    -- Boss：hitTimer衰减 + prevXY
    for _, b in ipairs(GS.bosses) do
        if b.alive then
            if (b.hitTimer or 0) > 0 then
                b.hitTimer = math.max(0, b.hitTimer - dt)
            end
            b.prevX = b.x
            b.prevY = b.y
        end
    end
    -- 领主：hitTimer衰减
    for _, l in ipairs(GS.lords) do
        if l.alive then
            if (l.hitTimer or 0) > 0 then
                l.hitTimer = math.max(0, l.hitTimer - dt)
            end
        end
    end

    -- 粒子更新
    for i = #GS.particles, 1, -1 do
        local p = GS.particles[i]
        p.life = p.life - dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * 0.95
        p.vy = p.vy * 0.95
        if p.life <= 0 then
            table.remove(GS.particles, i)
        end
    end

    -- 伤害数字更新
    for i = #GS.damageNumbers, 1, -1 do
        local dn = GS.damageNumbers[i]
        dn.life = dn.life - dt
        dn.y = dn.y + dn.vy * dt
        if dn.life <= 0 then
            table.remove(GS.damageNumbers, i)
        end
    end

    -- 相机跟随玩家
    if playerLord and playerLord.alive then
        GS.cameraX = Utils.lerp(GS.cameraX, playerLord.x, 5 * dt)
        GS.cameraY = Utils.lerp(GS.cameraY, playerLord.y, 5 * dt)
    end

    -- 限制相机位置，防止视野超出地图边缘
    local halfW = GS.screenW / 2
    local halfH = GS.screenH / 2
    local minCX = math.min(halfW, CONFIG.MapWidth / 2)
    local maxCX = math.max(CONFIG.MapWidth - halfW, CONFIG.MapWidth / 2)
    local minCY = math.min(halfH, CONFIG.MapHeight / 2)
    local maxCY = math.max(CONFIG.MapHeight - halfH, CONFIG.MapHeight / 2)
    GS.cameraX = Utils.clamp(GS.cameraX, minCX, maxCX)
    GS.cameraY = Utils.clamp(GS.cameraY, minCY, maxCY)
end

-- ============================================================================
-- 引擎回调 (全局函数)
-- ============================================================================

function Start()
    -- UI 初始化
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 创建 NanoVG 上下文
    nvg = nvgCreate(1)
    if nvg == nil then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    if nvgCreateFont(nvg, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: Could not load font")
        return
    end

    -- 初始化渲染器（传入NanoVG上下文 + 加载精灵图资源）
    Renderer.init(nvg)
    Renderer.loadAssets()

    GS.screenW = graphics:GetWidth()
    GS.screenH = graphics:GetHeight()

    -- 初始化天赋系统
    TS.init(CONFIG)

    -- 订阅事件
    SubscribeToEvent(nvg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    -- 立即显示主菜单（不等云数据）
    GS.gameState = "main_menu"
    MainMenuUI.initGameFn = initGame
    GameUI.onQuitToMenu = function()
        GS.gameState = "main_menu"
        MainMenuUI.initGameFn = initGame
        MainMenuUI.show()
    end
    MainMenuUI.show()
    print("[UI] Main menu ready (cloud loading in background)")

    -- 云数据在后台并行加载（互不依赖，无需串行等待）
    TS.loadFromCloud(function()
        print("[CLOUD] TalentSystem loaded")
    end)
    CampaignState.loadFromCloud(function()
        print("[CLOUD] CampaignState loaded")
    end)
    PresetManager.loadFromCloud(function()
        print("[CLOUD] PresetManager loaded")
    end)
    CodexState.loadFromCloud(function()
        print("[CLOUD] CodexState loaded")
    end)

    print("=== Code: Commander Started ===")
end

function Stop()
    UI.Shutdown()
    if nvg then
        nvgDelete(nvg)
        nvg = nil
    end
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    GS.lastDt = dt
    GS.screenW = graphics:GetWidth()
    GS.screenH = graphics:GetHeight()

    -- 菜单状态路由
    if GS.gameState == "main_menu" then
        MainMenuUI.updatePreview(dt)
        return
    elseif GS.gameState == "campaign_select" then
        return
    elseif GS.gameState == "endless_shop" then
        EndlessShopUI.updateCountdown(dt)
        return
    end

    -- 非游戏状态跳过输入和逻辑
    if GS.gameState ~= "playing" and GS.gameState ~= "gameover" and GS.gameState ~= "victory" then
        return
    end

    -- PC键盘输入
    GS.joystickX = 0
    GS.joystickY = 0
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then GS.joystickY = -1 end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then GS.joystickY = 1 end
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then GS.joystickX = -1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then GS.joystickX = 1 end

    -- 空格键触发攻击（PC 快捷键）
    if input:GetKeyPress(KEY_SPACE) then
        GS.attackBtnTriggered = true
    end
    GS.attackBtnPressed = input:GetKeyDown(KEY_SPACE)

    -- 鼠标右键拖拽移动
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local mx = input:GetMousePosition().x
        local my = input:GetMousePosition().y
        local wx, wy = Utils.screenToWorld(mx, my)
        local lord = GS.lords[1]
        if lord and lord.alive then
            local dx, dy = Utils.normalize(wx - lord.x, wy - lord.y)
            local d = Utils.dist(wx, wy, lord.x, lord.y)
            if d > 15 then
                GS.joystickX = dx
                GS.joystickY = dy
            end
        end
    end

    -- 触摸输入（虚拟摇杆 + 攻击按钮）
    -- 攻击按钮热区（右下角，与绘制保持一致）
    local atkBtnR = 44
    local atkBtnMargin = 30
    local atkBtnX = GS.screenW - atkBtnMargin - atkBtnR
    local atkBtnY = GS.screenH - atkBtnMargin - atkBtnR

    local numTouches = input.numTouches
    local touchOnAtkBtn = false
    local joystickTouched = false

    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        if touch then
            local tx = touch.position.x
            local ty = touch.position.y

            -- 检测是否点击了攻击按钮热区（右下角圆形区域）
            local distToBtn = math.sqrt((tx - atkBtnX)^2 + (ty - atkBtnY)^2)
            if distToBtn <= atkBtnR * 1.3 then
                touchOnAtkBtn = true
                -- 新按下（touchedState 为 began）时触发一次攻击
                if touch.delta.x == 0 and touch.delta.y == 0 then
                    -- 刚按下（delta为零是新触点的特征），触发攻击
                    GS.attackBtnTriggered = true
                end
            elseif tx < GS.screenW / 2 then
                -- 左半屏为摇杆区域
                joystickTouched = true
                if not GS.joystickActive then
                    GS.joystickActive = true
                    GS.joystickCenterX = tx
                    GS.joystickCenterY = ty
                end
                local dx = tx - GS.joystickCenterX
                local dy = ty - GS.joystickCenterY
                local maxDist = 60
                local dLen = math.sqrt(dx * dx + dy * dy)
                if dLen > maxDist then
                    dx = dx / dLen * maxDist
                    dy = dy / dLen * maxDist
                end
                GS.joystickX = dx / maxDist
                GS.joystickY = dy / maxDist
            end
        end
    end

    -- 更新攻击按钮视觉状态
    if not input:GetKeyDown(KEY_SPACE) then
        GS.attackBtnPressed = touchOnAtkBtn
    end
    if not joystickTouched then
        GS.joystickActive = false
    end

    -- 归一化
    local jLen = math.sqrt(GS.joystickX * GS.joystickX + GS.joystickY * GS.joystickY)
    if jLen > 1 then
        GS.joystickX = GS.joystickX / jLen
        GS.joystickY = GS.joystickY / jLen
    end

    -- 更新游戏
    updateGame(dt)

    -- 更新UI
    GameUI.UpdateGameUI()
end

function HandleMouseDown(eventType, eventData)
    local btn = eventData["Button"]:GetInt()
    if btn == MOUSEB_LEFT then
        -- 小地图点击放大/缩小切换
        if GS.gameState == "playing" then
            local mx = input:GetMousePosition().x
            local my = input:GetMousePosition().y
            if Renderer.isMinimapClicked(mx, my, GS.screenW, GS.screenH) then
                GS.minimapExpanded = not GS.minimapExpanded
                return
            end
        end

        -- 集火目标选择模式：左键点击选目标
        if GS.skillSelectingTarget and GS.gameState == "playing" then
            local mx = input:GetMousePosition().x
            local my = input:GetMousePosition().y
            local wx, wy = Utils.screenToWorld(mx, my)

            -- 检测点击了哪个敌方领主或Boss
            local playerFaction = GS.lords[1] and GS.lords[1].faction or 1
            local found = false

            -- 优先检测Boss（更大的点击区域）
            for _, b in ipairs(GS.bosses) do
                if b.alive then
                    local d = Utils.dist(wx, wy, b.x, b.y)
                    if d < CONFIG.BossRadius + 10 then
                        SkillSystem.confirmFocusFireTarget(b.id, "boss")
                        found = true
                        break
                    end
                end
            end

            -- 然后检测敌方领主
            if not found then
                for _, l in ipairs(GS.lords) do
                    if l.alive and l.faction ~= playerFaction then
                        local d = Utils.dist(wx, wy, l.x, l.y)
                        if d < CONFIG.LordRadiusMax + 10 then
                            SkillSystem.confirmFocusFireTarget(l.id, "lord")
                            found = true
                            break
                        end
                    end
                end
            end

            if not found then
                print("[SKILL] No valid target clicked, keep selecting...")
            end
            return
        end

        if GS.gameState == "gameover" or GS.gameState == "victory" then
            GS.gameState = "main_menu"
            MainMenuUI.initGameFn = initGame
            MainMenuUI.show()
        end
    end
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_R then
        if GS.gameState == "gameover" or GS.gameState == "victory" then
            GS.gameState = "main_menu"
            MainMenuUI.initGameFn = initGame
            MainMenuUI.show()
        end
    end

    -- 战术指令快捷键
    if GS.gameState == "playing" and GS.lords[1] and GS.lords[1].alive then
        -- 突击出击/召回快捷键
        if key == KEY_E then
            local lordId = GS.lords[1].id
            if SquadSystem.hasChargingSquad(lordId) then
                SquadSystem.recallSquad(lordId, 1)
            else
                SquadSystem.startCharge(lordId, 1)
            end
        end

        -- 技能快捷键 KEY_1 ~ KEY_6
        local skillKeys = {
            [KEY_1] = "dash",
            [KEY_2] = "focusFire",
            [KEY_3] = "barricade",
            [KEY_4] = "repel",
            [KEY_5] = "bloodSacrifice",
            [KEY_6] = "bounty",
        }
        local skillId = skillKeys[key]
        if skillId then
            -- 集火选择模式下按其他键或再按2取消
            if GS.skillSelectingTarget then
                if skillId ~= "focusFire" then
                    SkillSystem.cancelFocusFire()
                else
                    SkillSystem.cancelFocusFire()
                    return
                end
            end
            SkillSystem.activate(skillId)
        end

        -- ESC 取消集火选择
        if key == KEY_ESCAPE and GS.skillSelectingTarget then
            SkillSystem.cancelFocusFire()
        end
    end
end

-- ============================================================================
-- NanoVG 渲染主入口
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if nvg == nil then return end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()

    nvgBeginFrame(nvg, w, h, 1.0)

    -- 主菜单状态：绘制背景预览
    if GS.gameState == "main_menu" then
        local ok, err = pcall(MainMenuUI.drawPreview, nvg, w, h)
        if not ok then print("[RENDER ERROR] drawPreview: " .. tostring(err)) end
        nvgEndFrame(nvg)
        return
    end

    -- 非游戏状态不绘制（但显示加载提示以区分黑屏原因）
    if GS.gameState == "talent_select" or GS.gameState == "loading"
        or GS.gameState == "campaign_select" then
        if GS.gameState == "loading" then
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 22)
            nvgFillColor(nvg, nvgRGBA(200, 200, 200, 180))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(nvg, w / 2, h / 2, "Loading...")
        end
        nvgEndFrame(nvg)
        return
    end

    -- 非 playing/gameover/victory 状态，显示调试提示
    if GS.gameState ~= "playing" and GS.gameState ~= "gameover" and GS.gameState ~= "victory" then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 20)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, 20, 30, "[DEBUG] Unknown gameState: " .. tostring(GS.gameState))
        nvgEndFrame(nvg)
        return
    end

    local ok, err = pcall(function()
        -- 绘制世界
        Renderer.drawBackground(w, h)

        -- 绘制拒马和悬赏金箱（技能系统实体，始终在角色脚下）
        Renderer.drawBarricades()
        Renderer.drawBountyChests()

        -- 绘制宝箱和遗产（地面物件，始终在角色脚下）
        for _, c in ipairs(GS.chests) do Renderer.drawChest(c) end
        for _, lb in ipairs(GS.lootBoxes) do Renderer.drawLootBox(lb) end

        -- 按 Y 坐标排序绘制：资源（树/矿石）、随从、Boss、领主，实现遮挡
        Renderer.updateLordAnims(GS.gameTime - (GS._lastRenderTime or GS.gameTime))
        GS._lastRenderTime = GS.gameTime
        Renderer.drawSceneWithOcclusion()

        -- 绘制箭矢（叠加在实体上方）
        Renderer.drawProjectiles()

        -- 绘制巨兽（体型特殊，不参与 Y 排序）
        Renderer.drawGiantBeasts()

        -- 治疗特效（叠加在角色上方）
        Renderer.drawHealEffects()

        -- 粒子和数字
        Renderer.drawParticles()
        Renderer.drawDamageNumbers()

        -- 技能视觉特效（斥力波纹、集火标记、狂暴光环等）
        Renderer.drawSkillEffects(w, h)

        -- 小地图
        Renderer.drawMinimap(w, h)

        -- 虚拟摇杆绘制
        Renderer.drawJoystick()

        -- 攻击按钮（仅游戏进行中显示）
        if GS.gameState == "playing" then
            Renderer.drawAttackButton(w, h)
        end

        -- 随机事件屏幕效果
        Renderer.drawEventEffects(w, h)

        -- 玩家复活倒计时覆盖
        Renderer.drawRespawnOverlay(w, h)

        -- 游戏结束/胜利画面
        if GS.gameState == "gameover" or GS.gameState == "victory" then
            Renderer.drawGameOverScreen(w, h)
        end
    end)

    if not ok then
        -- 发生渲染错误时在屏幕上显示
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 16)
        nvgFillColor(nvg, nvgRGBA(255, 80, 80, 255))
        nvgText(nvg, 10, 30, "[RENDER ERROR] " .. tostring(err))
    end

    nvgEndFrame(nvg)
end
