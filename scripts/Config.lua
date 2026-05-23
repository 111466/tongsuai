-- ============================================================================
-- Config.lua - 全局常量和配置表
-- ============================================================================

local CONFIG = {
    Title = "代号：统帅",
    MapWidth  = 3000,   -- 世界宽度 (像素)
    MapHeight = 3000,   -- 世界高度 (像素)
    AuraRadius = 220,   -- 领主光环半径
    LordSpeed  = 180,   -- 领主移动速度
    LordHP     = 150,   -- 领主初始血量

    FollowerSpeed = 160, -- 随从移动速度
    PeasantGatherTime = 1.8, -- 平民采集时间(秒)
    PeasantCost = 10,   -- 平民造价(木材)
    SoldierCost = 20,   -- 士兵造价(木材，需要1平民转化)
    TreeWood    = 15,   -- 每棵树产出
    MineStone   = 20,   -- 每个矿产出
    ResourceCount = 60, -- 初始资源数量
    BossSpawnMin = 30,  -- Boss刷新最短间隔
    BossSpawnMax = 45,  -- Boss刷新最长间隔
    BossMaxOnMap = 2,   -- 地图上最大Boss数量

    -- Boss类型配置
    BossTypes = {
        behemoth = {
            name = "巨兽", hp = 100, speed = 100, contactDamage = 30,
            loot = { wood = 100, stone = 0, heal = 50 },
            weight = 40,
        },
        crab = {
            name = "石甲蟹", hp = 160, speed = 60, contactDamage = 0,
            aoeDamage = 25, aoeRadius = 80, aoeInterval = 2.0,
            loot = { wood = 30, stone = 80, heal = 0 },
            weight = 35,
        },
        wolf = {
            name = "幽灵狼", hp = 60, speed = 180,
            contactDamage = 15,
            stealthInterval = 5.0, stealthDuration = 2.0,
            loot = { wood = 50, stone = 50, heal = 0, speedBuff = 10.0 },
            weight = 25,
        },
    },
    AILordCount  = 4,   -- AI领主数量
    InitPeasants = 3,   -- 初始平民数量
    InvincibleTime = 0.8, -- 无敌帧时间(秒)
    CameraZoom = 1.0,   -- 相机缩放
    -- 弓箭手
    ArcherCostStone = 10,       -- 弓箭手升级成本（石头）
    ArcherCostWood  = 10,       -- 弓箭手升级成本（木头）

    ArcherRange = 440,          -- 弓箭手射程（像素，= 领主光环半径 × 2）
    ArcherFireInterval = 1.2,   -- 弓箭手射击间隔（秒）
    ArcherFleeDistance = 80,    -- 被贴近到此距离时逃跑

    -- 治愈师招募成本
    HealerCost         = { wood = 15, stone = 15 },
    HealerRange        = 120,   -- 治愈师治疗范围
    HealerHealAmount   = 25,   -- 每次治疗量
    HealerInterval     = 2.0,  -- 治疗间隔（秒）

    -- 据点系统
    StrongholdHP = 300,             -- 据点生命值
    StrongholdTowerRange = 150,     -- 防御塔射程（像素）
    StrongholdTowerDamage = 15,     -- 防御塔伤害
    StrongholdTowerInterval = 1.5,  -- 防御塔攻击间隔（秒）

    RespawnTime = 3.0,              -- 复活倒计时（秒）
    RespawnHpRatio = 0.5,           -- 复活血量比例


    -- ================================================================
    -- 天赋树（三条路线 × 5 节点）
    -- ================================================================
    TalentPaths = {
        commander = {
            name = "统帅之道", desc = "编队与指挥增强",
            nodes = {
                { id = "cmd_1", name = "扩编 I",    desc = "编制上限+1",  effect = { unitCapBonus = 1 }, cost = 1 },
                { id = "cmd_2", name = "扩编 II",   desc = "编制上限+2",  effect = { unitCapBonus = 2 }, cost = 3 },
                { id = "cmd_3", name = "扩编 III",  desc = "编制上限+3",  effect = { unitCapBonus = 3 }, cost = 5 },
            },
        },
        warfare = {
            name = "战争之道", desc = "战斗数值增强",
            nodes = {
                { id = "war_1", name = "攻击强化 I",  desc = "全军攻击+3%",   effect = { atkMul = 1.03 },        cost = 1 },
                { id = "war_2", name = "暴击锋芒",    desc = "暴击率+2%",     effect = { critChance = 0.02 },    cost = 2 },
                { id = "war_3", name = "攻击强化 II", desc = "全军攻击+5%",   effect = { atkMul = 1.05 },        cost = 4 },
                { id = "war_4", name = "致命打击",    desc = "暴击伤害+20%",  effect = { critDamageMul = 1.20 }, cost = 5 },
            },
        },
        economy = {
            name = "经略之道", desc = "资源与成长增强",
            nodes = {
                { id = "eco_1", name = "充裕资源 I",  desc = "初始资源+10%",  effect = { startResourceMul = 1.10 }, cost = 1 },
                { id = "eco_2", name = "军需折扣",    desc = "无尽商店折扣10%", effect = { shopDiscount = 0.90 },   cost = 3 },
                { id = "eco_3", name = "充裕资源 II", desc = "初始资源+20%",  effect = { startResourceMul = 1.20 }, cost = 5 },
            },
        },
    },

    -- 声望相关
    ReputationPerFirstClear = 3,   -- 关卡首通声望
    ReputationPerEndless5 = 1,     -- 无尽每5波声望

    -- ========== 单位显示尺寸（圆形半径，像素） ==========
    -- 随从尺寸
    PeasantRadius  = 12,   -- 农民（最小单位）
    SoldierRadius  = 16,   -- 士兵
    ArcherRadius   = 20,   -- 弓箭手
    HealerRadius   = 15,   -- 治愈师
    -- 统一半径查找表
    UnitRadius = {
        peasant = 12, soldier = 16, archer = 20,
        healer = 15,
    },
    -- 领主尺寸（随兵力动态变化）
    LordRadiusMin  = 22,   -- 领主最小半径（0兵）
    LordRadiusMax  = 34,   -- 领主最大半径（满兵）
    LordFollowerCap = 25,  -- 兵力达到此数量时领主达到最大尺寸
    -- Boss尺寸
    BossRadius     = 38,   -- Boss基础半径

    -- ========== 数值制战斗系统 ==========
    UnitStats = {
        peasant  = { hp = 30,  atk = 5,  atkInterval = 1.0 },
        soldier  = { hp = 60,  atk = 20, atkInterval = 0.8 },
        archer   = { hp = 50,  atk = 20, atkInterval = 1.2 },
        healer   = { hp = 45,  atk = 0,  atkInterval = 99  },
    },
    DamageMultiplierDisabled = true,


    -- ========== 领主主动技能 ==========
    Skills = {
        dash = {
            cd = 8,
            dist = 440,
            duration = 0.25,
            interruptRadius = 60,
            knockback = 30,
            followerSpeedDur = 2.0,
            followerSpeedMul = 1.2,
        },
        bounty = {
            cd = 25,
            resourceCost = 30,
            lifetime = 8,
            lureRadius = 100,
            stunDur = 1.5,
        },
        arrowRain = {
            cd = 15,
            baseRadius = 60,
            radiusPerLevel = 20,
            baseWaves = 2,
            wavesPerLevel = 1,
            baseDamage = 8,
            damagePerArcher = 4,
            waveInterval = 1.0,
        },
        shieldWall = {
            cd = 12,
            baseDuration = 3.0,
            durationPerLevel = 0.5,
            damageReduction = 0.5,
            rowSize = 5,
            spacing = 30,
        },
    },

    -- 单位色环颜色（用于类型识别，叠加在阵营色圆形外围）
    UnitRingColors = {
        peasant  = {120, 200, 80},    -- 绿色环（采集者）
        soldier  = {220, 80, 80},     -- 红色环（战斗）
        archer   = {240, 200, 50},    -- 黄色环（远程）
        healer   = {80, 220, 160},    -- 青绿环（治愈）
    },

    -- 兵种分类
    UnitCategories = {
        gatherer = { "peasant" },
    },
    IsCombatUnit = {
        soldier = true, archer = true,
    },
    IsRangedUnit = {
        archer = true,
    },

    -- ========== 巨兽危险区系统 ==========
    BeastBodyRadius       = 50,    -- 巨兽身体半径（像素）
    BeastAggroRadius      = 250,   -- 巨兽仇恨感知半径
    BeastGroupThreshold   = 5,     -- 触发攻击的最小群体数量（领主+随从）
    BeastAttackDamage     = 40,    -- 巨兽单次攻击伤害
    BeastAttackInterval   = 2.5,   -- 巨兽攻击间隔（秒）
    BeastAttackRadius     = 180,   -- 巨兽攻击范围（冲击波）
    ScatterDuration       = 4.0,   -- 队伍分散持续时间（秒）
    ScatterSpeed          = 2.5,   -- 分散逃窜移速倍率
    ScatterMinDist        = 200,   -- 分散最小距离
    ScatterMaxDist        = 400,   -- 分散最大距离
    BeastMaxOnMap         = 2,     -- 地图上最大巨兽数量
    BeastSpawnMargin      = 300,   -- 巨兽距地图边缘最小距离
    BeastHP               = 999,   -- 巨兽生命值（极高，基本无法击杀）
    BeastColor            = {100, 60, 40},  -- 巨兽颜色（深棕色）
}

-- 阵营颜色
local FACTION_COLORS = {
    {50, 50, 50},     -- 黑(玩家)
    {220, 60, 60},    -- 红
    {240, 200, 40},   -- 黄
    {60, 140, 240},   -- 蓝
    {160, 80, 240},   -- 紫
}

return { CONFIG = CONFIG, FACTION_COLORS = FACTION_COLORS }
