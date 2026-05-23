# 代号：统帅 — 玩法优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为"代号：统帅"添加兵种克制、战术指令、Boss多样化、据点系统和天赋成长五大玩法模块。

**Architecture:** 将现有 2130 行单文件拆分为模块化架构，每个新系统独立为一个模块。所有模块通过 `GameState` 共享表通信，`main.lua` 作为入口负责胶水逻辑。

**Tech Stack:** UrhoX Lua 5.4 + NanoVG 矢量渲染 + urhox-libs/UI + clientCloud 云存储

**Design Spec:** `docs/superpowers/specs/2026-05-17-gameplay-optimization-design.md`

---

## 文件结构

当前：`scripts/main.lua`（2130 行单文件）

目标结构：

```
scripts/
├── main.lua              -- 入口：Start/Stop、事件分发、模块组装（~250行）
├── Config.lua            -- 所有常量和配置表（~100行）
├── Utils.lua             -- 工具函数（~70行）
├── GameState.lua         -- 共享游戏状态表（实体数组、计时器等）（~50行）
├── Entities.lua          -- 实体创建函数（领主/随从/资源/Boss/宝箱等）（~200行）
├── FollowerAI.lua        -- 随从AI状态机（含弓箭手/骑士行为）（~300行）
├── LordAI.lua            -- AI领主决策树（含兵种克制决策）（~200行）
├── Combat.lua            -- 战斗结算+拾取+死亡处理（~250行）
├── BossSystem.lua        -- Boss三类型+刷新+AI（~200行）
├── EventSystem.lua       -- 随机事件（资源潮汐/血月/迷雾）（~120行）
├── Stronghold.lua        -- 据点系统+复活逻辑（~180行）
├── TacticalCommand.lua   -- 战术指令状态管理（~80行）
├── TalentSystem.lua      -- 天赋选择+功勋+云存储（~200行）
├── Renderer.lua          -- 所有NanoVG绘制函数（~550行）
└── GameUI.lua            -- UI面板创建和更新（~250行）
```

模块间通信规则：
- `GameState` 是全局共享数据表（实体列表、计时器、游戏状态等）
- 各模块通过 `require` 获取 `GameState` 和 `Config`
- 各模块导出函数，由 `main.lua` 在合适时机调用

---

## Task 1: 代码模块化拆分

将现有单文件拆分为模块，**不改变任何游戏行为**，拆完后构建验证功能完全一致。

**Files:**
- Create: `scripts/Config.lua`, `scripts/Utils.lua`, `scripts/GameState.lua`, `scripts/Entities.lua`, `scripts/FollowerAI.lua`, `scripts/LordAI.lua`, `scripts/Combat.lua`, `scripts/BossSystem.lua`, `scripts/Renderer.lua`, `scripts/GameUI.lua`
- Modify: `scripts/main.lua`（从2130行缩减到~250行）

### 原则

- 逐字搬迁，不修改逻辑
- 所有模块 return 一个 table 导出函数
- `GameState.lua` 持有所有共享状态（lords、followers、resources 等数组）
- 各模块通过 `local GS = require("GameState")` 访问 `GS.lords`、`GS.followers` 等

- [ ] **Step 1: 创建 Config.lua**

从 `main.lua` 第 14-50 行搬迁 `CONFIG` 表和 `FACTION_COLORS` 表：

```lua
-- scripts/Config.lua
local CONFIG = {
    -- 从 main.lua 原样搬迁全部 CONFIG 字段
    Title = "代号：统帅",
    MapWidth  = 3000,
    MapHeight = 3000,
    AuraRadius = 220,
    LordSpeed  = 180,
    LordHP     = 100,
    -- ... 其余字段原样搬迁
}

local FACTION_COLORS = {
    {80, 160, 255},
    {255, 80, 80},
    {80, 255, 80},
    {255, 200, 50},
}

return { CONFIG = CONFIG, FACTION_COLORS = FACTION_COLORS }
```

- [ ] **Step 2: 创建 Utils.lua**

从 `main.lua` 搬迁 `dist`、`clamp`、`lerp`、`randomRange`、`worldToScreen`、`screenToWorld`、`normalize`、`isOnScreen` 函数。

注意：`worldToScreen` 和 `isOnScreen` 依赖 `cameraX`/`cameraY`/`screenW`/`screenH`，这些变量移到 `GameState`。函数签名改为从 `GS` 读取：

```lua
-- scripts/Utils.lua
local GS = require("GameState")

local Utils = {}

function Utils.dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function Utils.worldToScreen(wx, wy)
    local sx = (wx - GS.cameraX) + GS.screenW / 2
    local sy = (wy - GS.cameraY) + GS.screenH / 2
    return sx, sy
end

-- ... 其余函数原样搬迁

return Utils
```

- [ ] **Step 3: 创建 GameState.lua**

将所有共享状态变量集中到一个表中：

```lua
-- scripts/GameState.lua
local GS = {
    -- 实体数组
    lords = {},
    followers = {},
    resources = {},
    bosses = {},
    chests = {},
    lootBoxes = {},
    particles = {},
    damageNumbers = {},

    -- 计时器
    gameTime = 0,
    gameState = "playing",  -- playing, gameover, victory
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

    -- ID生成器
    nextId = 0,
}

function GS.newId()
    GS.nextId = GS.nextId + 1
    return GS.nextId
end

return GS
```

- [ ] **Step 4: 创建 Entities.lua**

搬迁 `createLord`、`createFollower`、`createResource`、`createBoss`、`createChest`、`createLootBox`、`spawnParticle`、`spawnDamageNumber` 以及查找辅助函数 `findLordById`、`findResourceById`、`findBossById`、`countFollowers`、`getLordFollowers`。

所有函数内将直接引用的全局变量改为从 `GS` 读取，如 `table.insert(lords, lord)` → `table.insert(GS.lords, lord)`。

- [ ] **Step 5: 创建 FollowerAI.lua**

搬迁 `updateFollowerAI` 函数，内部引用改为模块引用。

- [ ] **Step 6: 创建 LordAI.lua**

搬迁 `updateAILord` 函数。

- [ ] **Step 7: 创建 Combat.lua**

搬迁 `processCombat`、`processPickups`、`processDeaths` 函数。

- [ ] **Step 8: 创建 BossSystem.lua**

搬迁 `updateBossAI` 函数，导出为模块。

- [ ] **Step 9: 创建 Renderer.lua**

搬迁所有 `draw*` 函数（`drawBackground`、`drawResources`、`drawTreeSprite`、`drawLord`、`drawFollower`、`drawBoss`、`drawChest`、`drawLootBox`、`drawParticles`、`drawDamageNumbers`、`drawMinimap`、`drawGameOverScreen`）。

NanoVG 上下文 `nvg` 和精灵图句柄 (`treeSprites`、`mineSprite`、`groundImage`) 作为模块局部变量，提供 `init(nvgCtx)` 和 `loadAssets()` 函数供 `main.lua` 调用。

- [ ] **Step 10: 创建 GameUI.lua**

搬迁 `CreateGameUI` 和 `UpdateGameUI` 函数。

- [ ] **Step 11: 重写 main.lua 为入口胶水**

`main.lua` 只保留：
- `require` 所有模块
- `Start()`：初始化引擎、创建NanoVG、调用各模块init、调用 `initGame()`
- `Stop()`：清理
- `HandleUpdate()`：读取输入 → 调用各模块update → 更新UI
- `HandleNanoVGRender()`：调用 Renderer 各绘制函数
- `HandleMouseDown()` / `HandleKeyDown()`
- `initGame()`：重置 GameState、创建初始实体

- [ ] **Step 12: 构建验证**

调用 UrhoX MCP build 工具构建，确认游戏行为与拆分前完全一致。

---

## Task 2: 新增骑士和弓箭手兵种

**Files:**
- Modify: `scripts/Config.lua`（新增兵种常量）
- Modify: `scripts/Entities.lua`（createFollower 支持新类型）
- Modify: `scripts/FollowerAI.lua`（骑士/弓箭手行为逻辑）
- Modify: `scripts/Combat.lua`（克制结算规则）
- Modify: `scripts/Renderer.lua`（骑士/弓箭手绘制）
- Modify: `scripts/GameUI.lua`（新增2个升级按钮）
- Modify: `scripts/LordAI.lua`（AI兵种决策）

- [ ] **Step 1: Config.lua 新增兵种常量**

```lua
-- 在 CONFIG 表中新增：
KnightCostStone = 15,       -- 骑士升级成本（石头）
ArcherCostStone = 10,       -- 弓箭手升级成本（石头）
ArcherCostWood  = 10,       -- 弓箭手升级成本（木头）
KnightHP = 2,               -- 骑士生命格数
KnightDamageToLord = 35,    -- 骑士对领主伤害
ArcherDamageToLord = 15,    -- 弓箭手对领主伤害
ArcherRange = 150,           -- 弓箭手射程（像素）
ArcherFireInterval = 1.5,   -- 弓箭手射击间隔（秒）
ArcherKeepDistMin = 0.7,    -- 弓箭手保持距离（光环半径的比例）
ArcherKeepDistMax = 0.9,
ArcherFleeDistance = 40,     -- 被贴近到此距离时逃跑
KnightChargeSpeedMul = 1.4, -- 骑士冲锋速度倍率
```

- [ ] **Step 2: Entities.lua 扩展 createFollower**

`fType` 新增 `"knight"` 和 `"archer"` 两种类型，骑士增加 `knightHP = 2` 字段，弓箭手增加 `fireTimer = 0` 字段：

```lua
local function createFollower(lord, fType)
    local f = {
        -- ... 现有字段不变
        fType = fType,  -- "peasant", "soldier", "knight", "archer"
        knightHP = (fType == "knight") and CONFIG.KnightHP or nil,
        fireTimer = (fType == "archer") and 0 or nil,
    }
    table.insert(GS.followers, f)
    return f
end
```

同时更新 `countFollowers`，支持按类型统计（已支持，无需改动）。

新增 `countCombatFollowers` 辅助函数，统计某领主的各兵种数量：

```lua
function Entities.countCombatFollowers(lordId)
    local soldiers, knights, archers = 0, 0, 0
    for _, f in ipairs(GS.followers) do
        if f.lordId == lordId and f.alive then
            if f.fType == "soldier" then soldiers = soldiers + 1
            elseif f.fType == "knight" then knights = knights + 1
            elseif f.fType == "archer" then archers = archers + 1
            end
        end
    end
    return soldiers, knights, archers
end
```

- [ ] **Step 3: FollowerAI.lua 新增骑士行为**

骑士行为与士兵类似，但冲锋时速度加成：

```lua
-- 在 following 状态的敌人搜索中，骑士逻辑与士兵共享
-- 搜索条件：fType == "soldier" or fType == "knight"

-- 在 attacking 状态中，骑士使用更高移速：
if f.fType == "knight" then
    speed = CONFIG.FollowerSpeed * CONFIG.KnightChargeSpeedMul
end
```

- [ ] **Step 4: FollowerAI.lua 新增弓箭手行为**

弓箭手在 `following` 状态中同样搜索敌人，但进入 `attacking` 状态后行为不同：

```lua
-- 弓箭手 attacking 状态：
if f.fType == "archer" then
    local dToTarget = Utils.dist(f.x, f.y, tx, ty)

    -- 如果敌人贴近（< ArcherFleeDistance），逃离
    if dToTarget < CONFIG.ArcherFleeDistance then
        local dx, dy = Utils.normalize(f.x - tx, f.y - ty)
        f.x = f.x + dx * CONFIG.FollowerSpeed * 1.1 * dt
        f.y = f.y + dy * CONFIG.FollowerSpeed * 1.1 * dt
        f.angle = math.atan2(dy, dx)
    elseif dToTarget > CONFIG.ArcherRange then
        -- 太远，靠近到射程内
        local dx, dy = Utils.normalize(tx - f.x, ty - f.y)
        f.x = f.x + dx * CONFIG.FollowerSpeed * dt
        f.y = f.y + dy * CONFIG.FollowerSpeed * dt
        f.angle = math.atan2(dy, dx)
    else
        -- 在射程内，站定射击
        f.angle = math.atan2(ty - f.y, tx - f.x)
        f.fireTimer = (f.fireTimer or 0) + dt
        if f.fireTimer >= CONFIG.ArcherFireInterval then
            f.fireTimer = 0
            -- 发射箭矢（添加到 GS.projectiles 表）
            table.insert(GS.projectiles, {
                x = f.x, y = f.y,
                tx = tx, ty = ty,
                speed = 350,
                factionId = f.factionId,
                fromArcherId = f.id,
                alive = true,
            })
        end
    end
    return  -- 不执行后续通用 attacking 逻辑
end
```

在 `GameState.lua` 中新增 `projectiles = {}` 数组。

- [ ] **Step 5: Combat.lua 实现克制结算**

重写 `processCombat` 中的近战结算逻辑，使用查表法：

```lua
-- 克制结算表：result[攻击方类型][防守方类型] = {attackerDies, defenderDies, knightDmg}
local COMBAT_TABLE = {
    soldier = {
        soldier = {true, true, 0},     -- 同归于尽
        knight  = {true, false, 1},    -- 士兵死，骑士扣1格
        archer  = {false, true, 0},    -- 弓箭手死，士兵活
        peasant = {false, true, 0},    -- 农民死，士兵活
    },
    knight = {
        soldier = {false, true, 0},    -- 士兵死，骑士不受伤
        knight  = {true, true, 0},     -- 同归于尽
        archer  = {true, true, 0},     -- 同归于尽
        peasant = {false, true, 0},    -- 农民死，骑士活
    },
    archer = {
        soldier = {true, false, 0},    -- 弓箭手死（近身后），士兵活
        knight  = {false, true, 0},    -- 骑士死，弓箭手活
        archer  = {true, true, 0},     -- 同归于尽
        peasant = {false, true, 0},    -- 农民死，弓箭手活
    },
}
```

近战碰撞距离 15px 以内触发结算。弓箭手的远程伤害通过 `projectiles` 处理。

新增 `processProjectiles(dt)` 函数：箭矢飞行 → 命中目标 → 按克制表结算。

- [ ] **Step 6: Combat.lua 更新对领主伤害**

单位攻击领主时，根据兵种类型取不同伤害值：

```lua
local dmgMap = {
    soldier = CONFIG.LordDamagePerSoldier,  -- 20
    knight  = CONFIG.KnightDamageToLord,     -- 35
    archer  = CONFIG.ArcherDamageToLord,     -- 15
}
local dmg = dmgMap[f.fType] or 20
```

- [ ] **Step 7: Renderer.lua 绘制骑士和弓箭手**

```lua
-- 骑士：菱形 + 阵营色，略大于士兵
if f.fType == "knight" then
    local s = 9
    nvgSave(ctx)
    nvgTranslate(ctx, sx, sy)
    nvgRotate(ctx, f.angle)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, s, 0)
    nvgLineTo(ctx, 0, -s * 0.6)
    nvgLineTo(ctx, -s * 0.7, 0)
    nvgLineTo(ctx, 0, s * 0.6)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255))
    nvgFill(ctx)
    -- 白色十字标记（骑士标志）
    nvgBeginPath(ctx)
    nvgRect(ctx, -2, -5, 4, 10)
    nvgRect(ctx, -5, -2, 10, 4)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 180))
    nvgFill(ctx)
    nvgRestore(ctx)

-- 弓箭手：小圆 + 弧线弓标记
elseif f.fType == "archer" then
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy, 5)
    nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255))
    nvgFill(ctx)
    -- 弓的弧线
    nvgSave(ctx)
    nvgTranslate(ctx, sx, sy)
    nvgRotate(ctx, f.angle)
    nvgBeginPath(ctx)
    nvgArc(ctx, -2, 0, 7, -1.2, 1.2, 1)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 200))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)
    nvgRestore(ctx)
end
```

绘制箭矢（`GS.projectiles`）：短线段。

- [ ] **Step 8: GameUI.lua 新增升级按钮**

在底部操作栏添加"升级骑士"和"升级弓箭手"按钮：

```lua
UI.Button {
    id = "btnUpgradeKnight",
    text = "骑士(15石)",
    fontSize = 13,
    paddingLeft = 12, paddingRight = 12,
    paddingTop = 10, paddingBottom = 10,
    onClick = function()
        local lord = GS.lords[1]
        if lord and lord.alive and lord.stone >= CONFIG.KnightCostStone then
            for _, f in ipairs(GS.followers) do
                if f.lordId == lord.id and f.alive and f.fType == "soldier" and f.state == "following" then
                    f.fType = "knight"
                    f.knightHP = CONFIG.KnightHP
                    lord.stone = lord.stone - CONFIG.KnightCostStone
                    Entities.spawnParticle(f.x, f.y, 255, 180, 50, 5)
                    Entities.spawnDamageNumber(f.x, f.y, "骑士!", 255, 200, 50)
                    break
                end
            end
        end
    end,
},
UI.Button {
    id = "btnUpgradeArcher",
    text = "弓手(10石+10木)",
    fontSize = 13,
    paddingLeft = 12, paddingRight = 12,
    paddingTop = 10, paddingBottom = 10,
    onClick = function()
        local lord = GS.lords[1]
        if lord and lord.alive and lord.stone >= CONFIG.ArcherCostStone and lord.wood >= CONFIG.ArcherCostWood then
            for _, f in ipairs(GS.followers) do
                if f.lordId == lord.id and f.alive and f.fType == "soldier" and f.state == "following" then
                    f.fType = "archer"
                    f.fireTimer = 0
                    lord.stone = lord.stone - CONFIG.ArcherCostStone
                    lord.wood = lord.wood - CONFIG.ArcherCostWood
                    Entities.spawnParticle(f.x, f.y, 100, 200, 255, 5)
                    Entities.spawnDamageNumber(f.x, f.y, "弓手!", 100, 220, 255)
                    break
                end
            end
        end
    end,
},
```

更新 `UpdateGameUI` 中的军队标签显示四种单位数量。

- [ ] **Step 9: LordAI.lua AI兵种决策**

在 AI 自动购买逻辑中加入兵种克制决策：

```lua
-- 分析最近敌方领主的兵种构成
local enemySoldiers, enemyKnights, enemyArchers = Entities.countCombatFollowers(nearestEnemy.id)

-- 对手多士兵 → 升级骑士
if enemySoldiers > enemyKnights + enemyArchers and lord.stone >= CONFIG.KnightCostStone then
    -- 找士兵升级为骑士
    upgradeSoldierTo(lord, "knight")
-- 对手多骑士 → 升级弓箭手
elseif enemyKnights > enemySoldiers and lord.stone >= CONFIG.ArcherCostStone and lord.wood >= CONFIG.ArcherCostWood then
    upgradeSoldierTo(lord, "archer")
-- 对手多弓箭手 → 保持士兵
else
    -- 不升级，保持士兵贴脸
end
```

- [ ] **Step 10: 构建验证**

调用 UrhoX MCP build 工具。验证：招募农民→转化士兵→升级骑士/弓箭手按钮可用，新兵种外观正确显示，克制战斗结算正确，AI 会升级兵种。

---

## Task 3: 战术指令系统

**Files:**
- Create: `scripts/TacticalCommand.lua`
- Modify: `scripts/Config.lua`（指令常量）
- Modify: `scripts/FollowerAI.lua`（搜索范围受指令影响）
- Modify: `scripts/main.lua`（领主移速受指令影响，快捷键）
- Modify: `scripts/Renderer.lua`（光环颜色变化）
- Modify: `scripts/GameUI.lua`（新增2个指令按钮）
- Modify: `scripts/LordAI.lua`（AI使用指令）

- [ ] **Step 1: 创建 TacticalCommand.lua**

```lua
-- scripts/TacticalCommand.lua
local TC = {}

-- 指令状态：每个领主一个
-- mode: "default" | "defend" | "charge"
local lordModes = {}  -- lordId -> mode

function TC.getMode(lordId)
    return lordModes[lordId] or "default"
end

function TC.setMode(lordId, mode)
    local current = lordModes[lordId] or "default"
    if current == mode then
        lordModes[lordId] = "default"  -- 再次点击取消
    else
        lordModes[lordId] = mode
    end
end

function TC.reset()
    lordModes = {}
end

-- 根据模式返回倍率
function TC.getSearchRadiusMul(lordId)
    local mode = TC.getMode(lordId)
    if mode == "defend" then return 0.4
    elseif mode == "charge" then return 1.5
    else return 1.0 end
end

function TC.getUnitSpeedMul(lordId)
    local mode = TC.getMode(lordId)
    if mode == "defend" then return 0.8
    elseif mode == "charge" then return 1.3
    else return 1.0 end
end

function TC.getLordSpeedMul(lordId)
    local mode = TC.getMode(lordId)
    if mode == "defend" then return 0.85
    elseif mode == "charge" then return 1.15
    else return 1.0 end
end

return TC
```

- [ ] **Step 2: FollowerAI.lua 集成搜索范围**

在士兵/骑士/弓箭手搜索敌人时，将 `CONFIG.AuraRadius` 替换为：

```lua
local TC = require("TacticalCommand")
local searchRadius = CONFIG.AuraRadius * TC.getSearchRadiusMul(lord.id)
```

随从移速也乘以 `TC.getUnitSpeedMul(lord.id)`。

防守集结时，编队半径缩小到光环40%。

- [ ] **Step 3: main.lua 领主移速集成**

玩家领主移动时乘以指令倍率：

```lua
local speedMul = TC.getLordSpeedMul(playerLord.id)
playerLord.x = playerLord.x + nx * CONFIG.LordSpeed * speedMul * dt
```

添加快捷键 Q/E：

```lua
if key == KEY_Q then
    TC.setMode(GS.lords[1].id, "defend")
elseif key == KEY_E then
    TC.setMode(GS.lords[1].id, "charge")
end
```

- [ ] **Step 4: Renderer.lua 光环颜色变化**

```lua
local TC = require("TacticalCommand")
local mode = TC.getMode(l.id)
local auraAlpha = 15
local auraR, auraG, auraB = fc[1], fc[2], fc[3]

if mode == "defend" then
    auraR, auraG, auraB = 80, 140, 255  -- 蓝色
    auraAlpha = 25
    -- 绘制内圈收缩效果
    nvgBeginPath(ctx)
    nvgCircle(ctx, asX, asY, auraR_radius * 0.4)
    nvgStrokeColor(ctx, nvgRGBA(80, 140, 255, 80))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
elseif mode == "charge" then
    auraR, auraG, auraB = 255, 80, 80  -- 红色
    auraAlpha = 20
    -- 外扩脉冲效果
    local pulse = math.sin(GS.gameTime * 4) * 0.1
    nvgBeginPath(ctx)
    nvgCircle(ctx, asX, asY, auraR_radius * (1.0 + pulse))
    nvgStrokeColor(ctx, nvgRGBA(255, 80, 80, 60))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
end
```

- [ ] **Step 5: GameUI.lua 新增指令按钮**

在操作栏末尾添加分隔线和两个切换按钮：

```lua
-- 分隔线
UI.Panel {
    width = 1, height = 30,
    backgroundColor = {255, 255, 255, 60},
},
UI.Button {
    id = "btnDefend",
    text = "集结[Q]",
    fontSize = 13,
    paddingLeft = 12, paddingRight = 12,
    paddingTop = 10, paddingBottom = 10,
    onClick = function()
        TC.setMode(GS.lords[1].id, "defend")
    end,
},
UI.Button {
    id = "btnCharge",
    text = "冲锋[E]",
    fontSize = 13,
    paddingLeft = 12, paddingRight = 12,
    paddingTop = 10, paddingBottom = 10,
    onClick = function()
        TC.setMode(GS.lords[1].id, "charge")
    end,
},
```

更新 `UpdateGameUI` 根据当前指令高亮对应按钮。

- [ ] **Step 6: LordAI.lua AI使用指令**

```lua
if lord.aiState == "attack" then
    TC.setMode(lord.id, "charge")
elseif lord.aiState == "flee" then
    TC.setMode(lord.id, "defend")
else
    TC.setMode(lord.id, "default")
end
```

- [ ] **Step 7: initGame 中重置指令状态**

在 `initGame()` 中调用 `TC.reset()`。

- [ ] **Step 8: 构建验证**

调用 UrhoX MCP build 工具。验证：Q/E键切换指令，光环颜色变化，单位搜索范围和移速随指令变化，AI会在进攻/逃跑时切换指令。

---

## Task 4: Boss 多样化

**Files:**
- Modify: `scripts/Config.lua`（三种Boss配置）
- Modify: `scripts/BossSystem.lua`（重写为三类型）
- Modify: `scripts/Entities.lua`（createBoss 支持类型）
- Modify: `scripts/Combat.lua`（石甲蟹范围伤害、幽灵狼隐身）
- Modify: `scripts/Renderer.lua`（三种Boss外观）

- [ ] **Step 1: Config.lua 新增Boss类型配置**

```lua
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
        contactDamage = 15, -- 对落单单位
        stealthInterval = 5.0, stealthDuration = 2.0,
        loot = { wood = 50, stone = 50, heal = 0, speedBuff = 10.0 },
        weight = 25,
    },
},
BossMaxOnMap = 2,
```

- [ ] **Step 2: Entities.lua createBoss 支持类型**

```lua
function Entities.createBoss(bossType)
    -- bossType: "behemoth", "crab", "wolf"
    local cfg = CONFIG.BossTypes[bossType]
    -- 边缘刷新位置逻辑不变
    local boss = {
        id = GS.newId(),
        x = x, y = y,
        hp = cfg.hp,
        maxHp = cfg.hp,
        bossType = bossType,
        alive = true,
        targetLordId = nil,
        angle = 0,
        -- 类型特有
        aoeTimer = 0,          -- 石甲蟹AOE计时
        stealthTimer = 0,      -- 幽灵狼隐身计时
        isStealthed = false,   -- 幽灵狼当前是否隐身
    }
    table.insert(GS.bosses, boss)
    return boss
end
```

新增加权随机选择函数：

```lua
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
```

- [ ] **Step 3: BossSystem.lua 三种Boss AI**

```lua
function BossSystem.updateBoss(boss, dt)
    local cfg = CONFIG.BossTypes[boss.bossType]

    if boss.bossType == "behemoth" then
        -- 原有逻辑：追击最近领主，接触扣血
        updateBehemoth(boss, dt, cfg)

    elseif boss.bossType == "crab" then
        -- 缓慢追击，周期性AOE
        updateCrab(boss, dt, cfg)

    elseif boss.bossType == "wolf" then
        -- 高速追击落单单位，周期性隐身
        updateWolf(boss, dt, cfg)
    end
end
```

石甲蟹：每 `aoeInterval` 秒对 `aoeRadius` 内所有敌方单位造成伤害（直接杀死）。

幽灵狼：优先追击落单的农民/弓箭手（离领主最远的），每5秒隐身2秒（`isStealthed=true` 时不可被攻击）。

- [ ] **Step 4: Combat.lua 适配Boss类型**

- 士兵/骑士/弓箭手攻击 Boss：伤害值不变（20），但幽灵狼隐身时跳过碰撞
- Boss 死亡掉落根据 `cfg.loot` 生成：石甲蟹掉石头为主，幽灵狼掉移速 buff

新增全局 buff 机制：`GS.globalBuffs` 表存储临时效果。

- [ ] **Step 5: Renderer.lua 三种Boss外观**

```lua
-- 巨兽：保持原有锯齿圆（不变）
-- 石甲蟹：六边形 + 灰色
if boss.bossType == "crab" then
    nvgBeginPath(ctx)
    for i = 0, 5 do
        local a = (i / 6) * math.pi * 2 - math.pi / 6
        local r = bossRadius
        local px = sx + math.cos(a) * r
        local py = sy + math.sin(a) * r
        if i == 0 then nvgMoveTo(ctx, px, py) else nvgLineTo(ctx, px, py) end
    end
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(120, 120, 140, 255))
    nvgFill(ctx)
    -- AOE范围指示圈
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy, cfg.aoeRadius)
    nvgStrokeColor(ctx, nvgRGBA(255, 100, 100, 40))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

-- 幽灵狼：三角形 + 半透明闪烁
elseif boss.bossType == "wolf" then
    local alpha = boss.isStealthed and (80 + math.sin(GS.gameTime * 10) * 40) or 255
    nvgSave(ctx)
    nvgTranslate(ctx, sx, sy)
    nvgRotate(ctx, boss.angle)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, bossRadius, 0)
    nvgLineTo(ctx, -bossRadius * 0.8, -bossRadius * 0.6)
    nvgLineTo(ctx, -bossRadius * 0.5, 0)
    nvgLineTo(ctx, -bossRadius * 0.8, bossRadius * 0.6)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(150, 100, 220, alpha))
    nvgFill(ctx)
    nvgRestore(ctx)
end
```

Boss标签文字改为读取 `cfg.name`。

- [ ] **Step 6: BossSystem.lua 刷新逻辑更新**

Boss刷新时检查当前地图上数量 `<= BossMaxOnMap`，类型通过 `Entities.randomBossType()` 加权随机。

- [ ] **Step 7: 构建验证**

调用 UrhoX MCP build 工具。验证：三种Boss随机刷新，外观各不相同，石甲蟹AOE伤害生效，幽灵狼隐身闪烁，击杀奖励正确。

---

## Task 5: 局内随机事件

**Files:**
- Create: `scripts/EventSystem.lua`
- Modify: `scripts/GameState.lua`（事件状态）
- Modify: `scripts/main.lua`（每帧调用事件更新）
- Modify: `scripts/Renderer.lua`（事件通知绘制）
- Modify: `scripts/FollowerAI.lua`（血月伤害加成读取）

- [ ] **Step 1: 创建 EventSystem.lua**

```lua
-- scripts/EventSystem.lua
local GS = require("GameState")
local CONFIG = require("Config").CONFIG
local Entities = require("Entities")

local ES = {}

local eventTimer = 0
local nextEventTime = 0
local activeEvent = nil  -- { name, desc, remaining, type }
local notification = nil -- { text, timer }

local EVENT_DEFS = {
    {
        type = "resource_tide", name = "资源潮汐",
        desc = "地图中心出现大量资源！",
        duration = 0,  -- 永久（一次性效果）
        activate = function()
            -- 在地图中心附近刷新8-12个资源
            local cx, cy = CONFIG.MapWidth / 2, CONFIG.MapHeight / 2
            local count = math.random(8, 12)
            for i = 1, count do
                local rx = cx + (math.random() - 0.5) * 400
                local ry = cy + (math.random() - 0.5) * 400
                if math.random() < 0.6 then
                    Entities.createResourceAt(rx, ry, "tree")
                else
                    Entities.createResourceAt(rx, ry, "mine")
                end
            end
        end,
    },
    {
        type = "blood_moon", name = "血月",
        desc = "所有战斗单位伤害+50%！",
        duration = 15,
        activate = function() GS.bloodMoonActive = true end,
        deactivate = function() GS.bloodMoonActive = false end,
    },
    {
        type = "fog", name = "迷雾",
        desc = "所有领主光环缩小30%！",
        duration = 20,
        activate = function() GS.fogActive = true end,
        deactivate = function() GS.fogActive = false end,
    },
}

function ES.init()
    eventTimer = 0
    nextEventTime = math.random(60, 90)
    activeEvent = nil
    notification = nil
    GS.bloodMoonActive = false
    GS.fogActive = false
end

function ES.update(dt)
    -- 更新活跃事件
    if activeEvent and activeEvent.remaining > 0 then
        activeEvent.remaining = activeEvent.remaining - dt
        if activeEvent.remaining <= 0 then
            if activeEvent.deactivate then activeEvent.deactivate() end
            activeEvent = nil
        end
    end

    -- 通知倒计时
    if notification then
        notification.timer = notification.timer - dt
        if notification.timer <= 0 then notification = nil end
    end

    -- 触发新事件
    eventTimer = eventTimer + dt
    if eventTimer >= nextEventTime then
        eventTimer = 0
        nextEventTime = math.random(60, 90)
        local def = EVENT_DEFS[math.random(1, #EVENT_DEFS)]
        def.activate()
        if def.duration > 0 then
            activeEvent = {
                name = def.name, remaining = def.duration,
                deactivate = def.deactivate, type = def.type,
            }
        end
        notification = { text = def.name .. " — " .. def.desc, timer = 3.0 }
    end
end

function ES.getNotification()
    return notification
end

function ES.getActiveEvent()
    return activeEvent
end

return ES
```

- [ ] **Step 2: 各模块读取事件状态**

`FollowerAI.lua` 中光环半径需考虑迷雾：

```lua
local auraRadius = CONFIG.AuraRadius * TC.getSearchRadiusMul(lord.id)
if GS.fogActive then auraRadius = auraRadius * 0.7 end
```

`Combat.lua` 中血月时伤害加成（骑士对领主伤害*1.5 等）。

- [ ] **Step 3: Renderer.lua 事件通知绘制**

在屏幕顶部居中绘制事件通知文字，带淡出效果：

```lua
local notif = ES.getNotification()
if notif then
    local alpha = math.min(255, math.floor(notif.timer / 0.5 * 255))
    nvgFontSize(ctx, 22)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(255, 220, 80, alpha))
    nvgText(ctx, w / 2, 50, notif.text, nil)
end
```

血月期间屏幕边缘加红色晕染，迷雾期间加灰色半透明覆盖。

- [ ] **Step 4: 构建验证**

调用 UrhoX MCP build 工具。可将 `nextEventTime` 临时改为 5 秒加速测试，验证三种事件效果，然后改回 60-90。

---

## Task 6: 据点系统与胜负条件重构

**Files:**
- Create: `scripts/Stronghold.lua`
- Modify: `scripts/GameState.lua`（据点数组、复活状态）
- Modify: `scripts/Entities.lua`（创建据点）
- Modify: `scripts/Combat.lua`（据点受攻击、胜负条件重写）
- Modify: `scripts/main.lua`（复活倒计时、5分钟防御崩溃）
- Modify: `scripts/Renderer.lua`（据点绘制、小地图标记、复活倒计时）
- Modify: `scripts/LordAI.lua`（AI据点行为）

- [ ] **Step 1: GameState.lua 新增据点相关状态**

```lua
GS.strongholds = {}  -- 据点数组
GS.respawning = {}   -- lordId -> { timer, lordData } 正在复活的领主
```

- [ ] **Step 2: 创建 Stronghold.lua**

```lua
-- scripts/Stronghold.lua
local GS = require("GameState")
local CONFIG = require("Config").CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local SH = {}

function SH.createStronghold(lordId, x, y, faction)
    local sh = {
        id = GS.newId(),
        lordId = lordId,
        x = x, y = y,
        faction = faction,
        hp = 300,
        maxHp = 300,
        alive = true,
        towerActive = true,
        towerTimer = 0,
        towerRange = 150,
        towerDamage = 15,
        towerInterval = 1.5,
    }
    table.insert(GS.strongholds, sh)
    return sh
end

function SH.update(dt)
    -- 5分钟后防御塔停止
    if GS.gameTime >= 300 then
        for _, sh in ipairs(GS.strongholds) do
            if sh.towerActive then
                sh.towerActive = false
            end
        end
    end

    -- 防御塔攻击
    for _, sh in ipairs(GS.strongholds) do
        if not sh.alive or not sh.towerActive then goto continue end
        sh.towerTimer = sh.towerTimer + dt
        if sh.towerTimer >= sh.towerInterval then
            sh.towerTimer = 0
            -- 找范围内敌方单位攻击
            local bestTarget = nil
            local bestDist = sh.towerRange
            for _, f in ipairs(GS.followers) do
                if f.alive and f.factionId ~= sh.faction then
                    local d = Utils.dist(sh.x, sh.y, f.x, f.y)
                    if d < bestDist then
                        bestDist = d
                        bestTarget = f
                    end
                end
            end
            if bestTarget then
                bestTarget.alive = false
                Entities.spawnParticle(bestTarget.x, bestTarget.y, 255, 200, 50, 4)
            end
        end
        ::continue::
    end

    -- 处理复活倒计时
    for lordId, info in pairs(GS.respawning) do
        info.timer = info.timer - dt
        if info.timer <= 0 then
            SH.respawnLord(lordId)
            GS.respawning[lordId] = nil
        end
    end
end

function SH.onLordDeath(lord)
    -- 查找该领主的据点
    local sh = SH.findByLordId(lord.id)
    if not sh or not sh.alive then
        -- 据点已毁，真正死亡
        return false  -- 不复活
    end
    -- 进入复活流程
    lord.alive = false
    -- 惩罚：损失50%资源，随从消散
    local lootWood = math.floor(lord.wood * 0.5)
    local lootStone = math.floor(lord.stone * 0.5)
    lord.wood = lord.wood - lootWood
    lord.stone = lord.stone - lootStone
    -- 随从消散
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            f.alive = false
            Entities.spawnParticle(f.x, f.y, 150, 150, 150, 2)
        end
    end
    -- 掉落战利品
    if lootWood > 0 or lootStone > 0 then
        Entities.createLootBox(lord.x, lord.y, lootWood, lootStone)
    end
    Entities.spawnParticle(lord.x, lord.y, 255, 50, 50, 20)
    -- 设置复活倒计时
    GS.respawning[lord.id] = { timer = 3.0, lordRef = lord }
    return true  -- 会复活
end

function SH.respawnLord(lordId)
    local sh = SH.findByLordId(lordId)
    if not sh or not sh.alive then return end
    local lord = Entities.findLordById(lordId)
    if not lord then return end
    lord.alive = true
    lord.hp = math.floor(lord.maxHp * 0.5)
    lord.x = sh.x
    lord.y = sh.y
    lord.invincibleTimer = 3.0
    -- 初始随从：2农民 + 1士兵
    Entities.createFollower(lord, "peasant")
    Entities.createFollower(lord, "peasant")
    Entities.createFollower(lord, "soldier")
end

function SH.findByLordId(lordId)
    for _, sh in ipairs(GS.strongholds) do
        if sh.lordId == lordId and sh.alive then return sh end
    end
    return nil
end

-- 据点受到攻击（被敌方单位碰到时调用）
function SH.damageStronghold(sh, damage)
    sh.hp = sh.hp - damage
    if sh.hp <= 0 then
        sh.alive = false
        sh.hp = 0
        Entities.spawnParticle(sh.x, sh.y, 255, 100, 50, 20)
    end
end

return SH
```

- [ ] **Step 3: Combat.lua 胜负条件重写**

`processDeaths` 中领主死亡不再直接设 `gameState`，改为调用 `SH.onLordDeath`：

```lua
if l.alive and l.hp <= 0 then
    local willRespawn = SH.onLordDeath(l)
    if not willRespawn then
        -- 据点已毁，真正淘汰
        if l.isPlayer then
            GS.gameState = "gameover"
        end
    end
end
```

胜利条件改为检查敌方据点：

```lua
local enemyStrongholdsAlive = 0
for _, sh in ipairs(GS.strongholds) do
    if sh.faction ~= 1 and sh.alive then  -- 非玩家阵营
        enemyStrongholdsAlive = enemyStrongholdsAlive + 1
    end
end
if enemyStrongholdsAlive == 0 and GS.gameState == "playing" then
    GS.gameState = "victory"
end
```

新增：士兵/骑士/弓箭手攻击据点的逻辑（在 `processCombat` 中）。战斗单位靠近敌方据点 20px 时，对据点造成伤害后死亡。

- [ ] **Step 4: initGame 中创建据点**

玩家据点在地图中心，AI据点在各自出生点：

```lua
SH.createStronghold(playerLord.id, playerLord.x, playerLord.y, playerLord.faction)
-- AI领主
for i, aiLord in ... do
    SH.createStronghold(aiLord.id, sp[1], sp[2], aiLord.faction)
end
```

- [ ] **Step 5: Renderer.lua 绘制据点**

```lua
function Renderer.drawStronghold(ctx, sh)
    local sx, sy = Utils.worldToScreen(sh.x, sh.y)
    local fc = FACTION_COLORS[sh.faction]
    local size = 20

    -- 堡垒主体（方形 + 城垛）
    nvgBeginPath(ctx)
    nvgRect(ctx, sx - size, sy - size, size * 2, size * 2)
    nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 200))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 150))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    -- 城垛（顶部4个小方块）
    for i = 0, 3 do
        local bx = sx - size + i * (size * 2 / 4) + 2
        nvgBeginPath(ctx)
        nvgRect(ctx, bx, sy - size - 6, 8, 6)
        nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 220))
        nvgFill(ctx)
    end

    -- 旗帜
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy - size - 6)
    nvgLineTo(ctx, sx, sy - size - 22)
    nvgStrokeColor(ctx, nvgRGBA(200, 200, 200, 255))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy - size - 22)
    nvgLineTo(ctx, sx + 12, sy - size - 18)
    nvgLineTo(ctx, sx, sy - size - 14)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255))
    nvgFill(ctx)

    -- 防御塔射程圈（仅towerActive时显示）
    if sh.towerActive then
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, sh.towerRange)
        nvgStrokeColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 30))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
    end

    -- 血条
    local hpRatio = sh.hp / sh.maxHp
    local barW = 40
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - barW/2, sy + size + 4, barW, 4, 2)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - barW/2, sy + size + 4, barW * hpRatio, 4, 2)
    nvgFillColor(ctx, nvgRGBA(80, 200, 80, 255))
    nvgFill(ctx)
end
```

小地图上用小方块标记据点位置。

复活倒计时：玩家死亡时屏幕中央显示"复活中... 3.0s"。

5分钟提示：`GS.gameTime` 接近300秒时弹出"据点防御崩溃！"全局通知。

- [ ] **Step 6: LordAI.lua AI据点行为**

新增据点相关决策：

```lua
-- 自己据点被攻击（有敌人在据点附近） → 回防
local mySH = SH.findByLordId(lord.id)
if mySH then
    local enemyNearBase = false
    for _, ef in ipairs(GS.followers) do
        if ef.alive and ef.factionId ~= lord.faction then
            if Utils.dist(mySH.x, mySH.y, ef.x, ef.y) < 200 then
                enemyNearBase = true
                break
            end
        end
    end
    if enemyNearBase then
        lord.aiState = "flee"  -- 回防
        lord.targetX = mySH.x
        lord.targetY = mySH.y
        return
    end
end

-- 击杀敌方领主后 → 冲向敌方据点拆家
-- 5分钟后 → 更积极进攻据点
```

- [ ] **Step 7: 构建验证**

调用 UrhoX MCP build 工具。验证：据点显示在地图四角，防御塔攻击敌人，领主死亡后在据点复活（带2农民+1士兵），据点被摧毁后真正淘汰，5分钟后防御塔停止。

---

## Task 7: 天赋系统与功勋云存储

**Files:**
- Create: `scripts/TalentSystem.lua`
- Modify: `scripts/GameState.lua`（当前天赋、功勋值）
- Modify: `scripts/main.lua`（游戏流程：天赋选择→开始游戏→结算）
- Modify: `scripts/GameUI.lua`（天赋选择界面、结算界面）
- Modify: `scripts/Config.lua`（天赋定义）
- Modify: `scripts/Entities.lua`（天赋效果应用）
- Modify: `scripts/FollowerAI.lua`（天赋效果：采集速度、射程）

- [ ] **Step 1: Config.lua 天赋定义**

```lua
Talents = {
    {
        id = "conscript", name = "征召令",
        desc = "开局额外2个农民",
        unlockCost = 0,  -- 默认解锁
        apply = function(lord)
            local Entities = require("Entities")
            Entities.createFollower(lord, "peasant")
            Entities.createFollower(lord, "peasant")
        end,
    },
    {
        id = "ore_sense", name = "矿脉嗅觉",
        desc = "采集速度+40%，采集时额外获石头",
        unlockCost = 200,
    },
    {
        id = "iron_vanguard", name = "铁血先锋",
        desc = "骑士升级成本减半(15→8石)",
        unlockCost = 500,
    },
    {
        id = "eagle_eye", name = "鹰眼猎手",
        desc = "弓箭手射程+30%，升级成本减半",
        unlockCost = 800,
    },
},

GloryPerVictory = 100,
GloryPerDefeat = 20,
GloryPerStronghold = 30,
GloryPerBossKill = 20,
GloryPerSurvival30s = 5,
```

- [ ] **Step 2: 创建 TalentSystem.lua**

```lua
-- scripts/TalentSystem.lua
local GS = require("GameState")
local CONFIG = require("Config").CONFIG

local TS = {}

local cloudData = {
    glory_total = 0,
    games_played = 0,
    games_won = 0,
    best_time = 999999,
}
local selectedTalentId = "conscript"
local loaded = false

function TS.loadFromCloud(callback)
    if clientCloud then
        clientCloud:Get("glory_total", function(val)
            if val then cloudData.glory_total = tonumber(val) or 0 end
            clientCloud:Get("games_played", function(val2)
                if val2 then cloudData.games_played = tonumber(val2) or 0 end
                clientCloud:Get("games_won", function(val3)
                    if val3 then cloudData.games_won = tonumber(val3) or 0 end
                    clientCloud:Get("best_time", function(val4)
                        if val4 then cloudData.best_time = tonumber(val4) or 999999 end
                        loaded = true
                        if callback then callback() end
                    end)
                end)
            end)
        end)
    else
        loaded = true
        if callback then callback() end
    end
end

function TS.saveToCloud()
    if clientCloud then
        clientCloud:Set("glory_total", tostring(cloudData.glory_total))
        clientCloud:Set("games_played", tostring(cloudData.games_played))
        clientCloud:Set("games_won", tostring(cloudData.games_won))
        clientCloud:Set("best_time", tostring(cloudData.best_time))
    end
end

function TS.getGlory() return cloudData.glory_total end
function TS.getSelectedTalent() return selectedTalentId end
function TS.setSelectedTalent(id) selectedTalentId = id end

function TS.getUnlockedTalents()
    local result = {}
    for _, t in ipairs(CONFIG.Talents) do
        if cloudData.glory_total >= t.unlockCost then
            table.insert(result, t)
        end
    end
    return result
end

function TS.applyTalent(lord)
    local talent = nil
    for _, t in ipairs(CONFIG.Talents) do
        if t.id == selectedTalentId then talent = t; break end
    end
    if not talent then return end

    GS.activeTalentId = selectedTalentId

    if talent.id == "conscript" then
        local Entities = require("Entities")
        Entities.createFollower(lord, "peasant")
        Entities.createFollower(lord, "peasant")
    end
    -- ore_sense, iron_vanguard, eagle_eye 通过 GS.activeTalentId 在各系统中检查
end

function TS.settleGame(won, bossKills, strongholdKills)
    local glory = won and CONFIG.GloryPerVictory or CONFIG.GloryPerDefeat
    glory = glory + (strongholdKills or 0) * CONFIG.GloryPerStronghold
    glory = glory + (bossKills or 0) * CONFIG.GloryPerBossKill
    glory = glory + math.floor(GS.gameTime / 30) * CONFIG.GloryPerSurvival30s

    cloudData.glory_total = cloudData.glory_total + glory
    cloudData.games_played = cloudData.games_played + 1
    if won then
        cloudData.games_won = cloudData.games_won + 1
        if GS.gameTime < cloudData.best_time then
            cloudData.best_time = math.floor(GS.gameTime)
        end
    end
    TS.saveToCloud()
    return glory
end

return TS
```

- [ ] **Step 3: 各模块读取天赋效果**

`FollowerAI.lua` 中：矿脉嗅觉 → 采集时间 `* 0.6`，采集完成时额外给石头。

`GameUI.lua` 中：铁血先锋 → 骑士按钮显示"骑士(8石)"，升级扣 8 石头。

`Config.lua` / `FollowerAI.lua`：鹰眼猎手 → 弓箭手射程 `* 1.3`，升级成本减半。

- [ ] **Step 4: GameUI.lua 天赋选择界面**

游戏状态新增 `"talent_select"` 阶段。用 UI 组件创建全屏天赋选择面板：

```lua
function GameUI.showTalentSelect()
    local talents = TS.getUnlockedTalents()
    if #talents <= 1 then
        -- 只有默认天赋，跳过选择
        TS.setSelectedTalent("conscript")
        startGame()
        return
    end
    -- 创建选择面板，每个天赋一个卡片，点击选中后点"开始"
end
```

- [ ] **Step 5: GameUI.lua 结算界面增加功勋显示**

游戏结束时显示：

```
胜利！
用时: 180秒
获得功勋: +135
累计功勋: 580
```

- [ ] **Step 6: main.lua 游戏流程调整**

```
Start() → 加载云数据 → 显示天赋选择
天赋选择 → 点击开始 → initGame() + applyTalent()
游戏结束 → settleGame() → 显示结算
点击重新开始 → 显示天赋选择
```

- [ ] **Step 7: 构建验证**

调用 UrhoX MCP build 工具。验证：天赋选择界面显示正确，默认天赋（征召令）效果生效，游戏结束后功勋结算正确，功勋值持久化。

---

## 自检结果

- **Spec 覆盖**：5个模块全部对应到 Task 2-7，模块化拆分为 Task 1
- **占位符**：无 TBD/TODO
- **类型一致性**：`fType` 统一使用 `"peasant"/"soldier"/"knight"/"archer"`；Boss 类型统一使用 `"behemoth"/"crab"/"wolf"`；天赋 ID 统一使用 `"conscript"/"ore_sense"/"iron_vanguard"/"eagle_eye"`
- **接口一致性**：所有模块通过 `require("GameState")` 访问共享数据，通过 `require("Config").CONFIG` 读取配置
