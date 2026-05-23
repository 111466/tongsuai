# 代号：统帅 — 关卡 & 兵种系统实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为"代号：统帅"实现完整的兵种扩展（12种）、阵型系统（6种）、战役关卡（17关）、图鉴/预设/天赋树、无尽模式和副将系统。

**Architecture:** 在现有模块化架构基础上扩展。新增 9 个独立模块，修改 10 个现有模块。所有持久化数据通过 clientCloud BatchGet/BatchSet API 存取。游戏逻辑保持单线程同步更新，UI 使用 urhox-libs/UI 组件库，NanoVG 负责游戏画面渲染。

**Tech Stack:** UrhoX Engine / Lua 5.4 / NanoVG / clientCloud API / urhox-libs/UI

**Design Spec:** `docs/superpowers/specs/2026-05-19-campaign-troop-system-design.md`

---

## File Structure

### New Files (9)

| File | Responsibility |
|------|---------------|
| `scripts/FormationSystem.lua` | 阵型条件判断、站位计算、加成查询 |
| `scripts/CampaignData.lua` | 17 关配置数据（敌方、奖励、分支） |
| `scripts/CampaignState.lua` | 战役进度管理 + 云存档 |
| `scripts/CodexData.lua` | 图鉴配置（描述、经验曲线、等级加成） |
| `scripts/CodexState.lua` | 图鉴运行时状态（统计、经验、等级）+ 云存档 |
| `scripts/PresetManager.lua` | 编队预设 5 槽管理 + 云存档 |
| `scripts/EndlessMode.lua` | 无尽模式流程（波次、难度递增、结算） |
| `scripts/ShopSystem.lua` | 无尽模式商店（商品池、刷新、购买） |
| `scripts/SquadSystem.lua` | 副将小队管理（分兵、归队、独立 AI） |

### Modified Files (10+)

| File | Key Changes |
|------|-------------|
| `scripts/Config.lua` | +8 兵种属性、+兵种分类表、+招募成本、+阵型配置、+天赋树 |
| `scripts/GameState.lua` | +阵型状态字段、+游戏模式字段 |
| `scripts/Entities.lua` | 泛化 createFollower、泛化 countCombatFollowers |
| `scripts/FollowerAI.lua` | 阵型站位替换环形编队 |
| `scripts/Combat.lua` | 泛化 getUnitRadius、集成阵型加成 |
| `scripts/SkillSystem.lua` | +4 特殊兵种技能 |
| `scripts/Renderer.lua` | +8 兵种渲染标记 |
| `scripts/GameUI.lua` | +主菜单、战役地图、编队界面 |
| `scripts/LordAI.lua` | AI 使用新兵种 + 阵型 |
| `scripts/TalentSystem.lua` | 单选 → 三路天赋树 |
| `scripts/main.lua` | 新模块引入、多模式流程 |

---

## Phase 1: Troop & Formation Foundation

### Task 1: Expand Config.lua — New Unit Types & Categories

**Files:**
- Modify: `scripts/Config.lua`

- [ ] **Step 1: Add unit classification tables**

After `UnitRingColors` block (line ~168), add these lookup tables:

```lua
-- 兵种分类（用于阵型条件判断和通用查询）
UnitCategories = {
    melee    = { "soldier", "knight", "spearman", "paladin", "assassin" },
    ranged   = { "archer", "mage", "mounted_archer" },
    special  = { "advisor", "vice_general", "drummer" },
    gatherer = { "peasant" },
},
IsCombatUnit = {
    soldier = true, knight = true, archer = true,
    spearman = true, mage = true, mounted_archer = true,
    paladin = true, assassin = true,
},
IsRangedUnit = {
    archer = true, mage = true, mounted_archer = true,
},
IsSpecialUnit = {
    advisor = true, vice_general = true, drummer = true,
    paladin = true, assassin = true,
},
-- 特殊兵种编制占用
SpecialUnitSlots = {
    advisor = 2, vice_general = 3, drummer = 2,
    paladin = 3, assassin = 2,
},
```

- [ ] **Step 2: Expand UnitStats to 12 types**

Replace the existing `UnitStats` table (lines ~143-148) with:

```lua
UnitStats = {
    -- 已有基础兵种
    peasant        = { hp = 20,  atk = 5,  atkInterval = 1.0 },
    soldier        = { hp = 60,  atk = 25, atkInterval = 0.8 },
    knight         = { hp = 120, atk = 35, atkInterval = 1.2 },
    archer         = { hp = 40,  atk = 20, atkInterval = 1.5 },
    -- 新增基础兵种
    spearman       = { hp = 80,  atk = 30, atkInterval = 0.9 },
    mage           = { hp = 35,  atk = 45, atkInterval = 2.0, aoeRadius = 40 },
    mounted_archer = { hp = 35,  atk = 18, atkInterval = 1.3 },
    -- 新增特殊兵种
    advisor        = { hp = 30,  atk = 5,  atkInterval = 1.0 },
    vice_general   = { hp = 100, atk = 30, atkInterval = 1.0 },
    drummer        = { hp = 50,  atk = 10, atkInterval = 1.0 },
    paladin        = { hp = 150, atk = 40, atkInterval = 1.5 },
    assassin       = { hp = 45,  atk = 50, atkInterval = 0.6 },
},
```

- [ ] **Step 3: Expand DamageMultiplier with key matchups**

Replace the existing `DamageMultiplier` table (lines ~149-154). Use `nil` for default 1.0 — combat code will fallback to 1.0 (already does).

```lua
DamageMultiplier = {
    soldier        = { soldier = 1.0, knight = 0.6, archer = 1.5, peasant = 2.0, spearman = 0.8 },
    knight         = { soldier = 1.3, knight = 1.0, archer = 1.0, peasant = 2.0, spearman = 0.5 },
    archer         = { soldier = 0.7, knight = 1.3, archer = 1.0, peasant = 2.0 },
    peasant        = { soldier = 0.5, knight = 0.3, archer = 0.5, peasant = 1.0 },
    spearman       = { soldier = 0.9, knight = 1.8, archer = 0.7, peasant = 2.0, spearman = 1.0, mounted_archer = 1.6 },
    mage           = { soldier = 1.2, knight = 1.2, archer = 1.2, peasant = 2.0 },
    mounted_archer = { soldier = 0.8, knight = 1.1, archer = 1.0, peasant = 2.0 },
    paladin        = { soldier = 1.1, knight = 0.9, archer = 0.8, peasant = 2.0 },
    assassin       = { soldier = 1.5, knight = 1.0, archer = 1.8, peasant = 2.0, mage = 2.0 },
},
```

- [ ] **Step 4: Add display radii and ring colors for new types**

Add new radius constants alongside existing ones (lines ~133-136):

```lua
SpearmanRadius      = 18,
MageRadius          = 16,
MountedArcherRadius = 18,
AdvisorRadius       = 14,
ViceGeneralRadius   = 22,
DrummerRadius       = 16,
PaladinRadius       = 22,
AssassinRadius      = 16,
```

Add a unified lookup table (after the individual constants):

```lua
UnitRadius = {
    peasant = 12, soldier = 16, knight = 20, archer = 20,
    spearman = 18, mage = 16, mounted_archer = 18,
    advisor = 14, vice_general = 22, drummer = 16,
    paladin = 22, assassin = 16,
},
```

Expand `UnitRingColors` (lines ~164-169):

```lua
UnitRingColors = {
    peasant        = {120, 200, 80},
    soldier        = {220, 80, 80},
    knight         = {80, 130, 220},
    archer         = {240, 200, 50},
    spearman       = {180, 120, 60},
    mage           = {160, 50, 220},
    mounted_archer = {220, 180, 50},
    advisor        = {100, 200, 200},
    vice_general   = {200, 200, 200},
    drummer        = {200, 140, 60},
    paladin        = {255, 215, 0},
    assassin       = {80, 80, 80},
},
```

- [ ] **Step 5: Add recruitment costs for new types**

After `ArcherCostWood` (line ~95):

```lua
-- 新兵种招募成本
SpearmanCost       = { wood = 15, stone = 10 },
MageCost           = { wood = 10, stone = 25 },
MountedArcherCost  = { wood = 20, stone = 15 },
-- 特殊兵种招募成本（较高）
AdvisorCost        = { wood = 30, stone = 30 },
ViceGeneralCost    = { wood = 40, stone = 40 },
DrummerCost        = { wood = 25, stone = 20 },
PaladinCost        = { wood = 35, stone = 50 },
AssassinCost       = { wood = 30, stone = 35 },

-- 远程兵种配置
MageRange          = 130,
MageFireInterval   = 2.0,
MageFleeDistance   = 50,
MountedArcherRange = 120,
MountedArcherFireInterval = 1.3,
MountedArcherFleeDistance  = 60,
MountedArcherSpeedMul      = 1.3,  -- 骑马弓手移速倍率
```

- [ ] **Step 6: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. No runtime changes yet (new config entries unused).

- [ ] **Step 7: Commit**

```
git add scripts/Config.lua
git commit -m "feat(config): add 8 new unit types, categories, radii, ring colors, costs"
```

---

### Task 2: Genericize Hardcoded Type Checks

**Files:**
- Modify: `scripts/Combat.lua` (getUnitRadius)
- Modify: `scripts/Entities.lua` (createFollower, countCombatFollowers)
- Modify: `scripts/Renderer.lua` (drawFollower radius)
- Modify: `scripts/FollowerAI.lua` (combat unit check)

- [ ] **Step 1: Replace getUnitRadius in Combat.lua**

In `scripts/Combat.lua`, replace the `getUnitRadius` function (lines ~56-60):

```lua
-- OLD:
local function getUnitRadius(fType)
    if fType == "peasant" then return CONFIG.PeasantRadius
    elseif fType == "knight" then return CONFIG.KnightRadius
    elseif fType == "archer" then return CONFIG.ArcherRadius
    else return CONFIG.SoldierRadius end
end

-- NEW:
local function getUnitRadius(fType)
    return CONFIG.UnitRadius[fType] or CONFIG.SoldierRadius
end
```

- [ ] **Step 2: Update createFollower for new ranged types**

In `scripts/Entities.lua`, replace the `fireTimer` line in `createFollower` (line ~77):

```lua
-- OLD:
fireTimer = (fType == "archer") and 0 or nil,

-- NEW:
fireTimer = CONFIG.IsRangedUnit[fType] and 0 or nil,
```

- [ ] **Step 3: Genericize countCombatFollowers**

In `scripts/Entities.lua`, replace the `countCombatFollowers` function (lines ~230-243) with a generic version:

```lua
--- 统计领主的各类战斗随从数量
--- @param lordId number
--- @return table<string, number> counts  e.g. { soldier = 3, knight = 2, ... }
function Entities.countFollowersByType(lordId)
    local counts = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lordId and f.alive then
            counts[f.fType] = (counts[f.fType] or 0) + 1
        end
    end
    return counts
end

--- 向后兼容：返回 soldiers, knights, archers（旧调用点暂时保留）
function Entities.countCombatFollowers(lordId)
    local c = Entities.countFollowersByType(lordId)
    return c.soldier or 0, c.knight or 0, c.archer or 0
end
```

- [ ] **Step 4: Genericize combat unit detection in FollowerAI**

In `scripts/FollowerAI.lua`, replace the hardcoded combat unit check (line ~230):

```lua
-- OLD:
if f.fType == "soldier" or f.fType == "knight" or f.fType == "archer" then

-- NEW:
if CONFIG.IsCombatUnit[f.fType] then
```

- [ ] **Step 5: Genericize Combat vs lord/boss unit checks**

In `scripts/Combat.lua`, replace the hardcoded `soldier or knight` checks for attacking lord (line ~155) and boss (line ~176):

```lua
-- OLD (both places):
if f.alive and (f.fType == "soldier" or f.fType == "knight") and f.state == "attacking" then

-- NEW (both places):
if f.alive and CONFIG.IsCombatUnit[f.fType] and not CONFIG.IsRangedUnit[f.fType] and f.state == "attacking" then
```

- [ ] **Step 6: Genericize Renderer radius lookup**

In `scripts/Renderer.lua`, find the follower radius lookup in `drawFollower` (search for `CONFIG.SoldierRadius` / `CONFIG.PeasantRadius`) and replace:

```lua
-- OLD:
local radius = CONFIG.SoldierRadius
if f.fType == "peasant" then radius = CONFIG.PeasantRadius
elseif f.fType == "knight" then radius = CONFIG.KnightRadius
elseif f.fType == "archer" then radius = CONFIG.ArcherRadius end

-- NEW:
local radius = CONFIG.UnitRadius[f.fType] or CONFIG.SoldierRadius
```

- [ ] **Step 7: Build and verify**

Run: UrhoX MCP build tool
Expected: Game plays identically to before — existing 4 unit types use the same values via the new lookup paths.

- [ ] **Step 8: Commit**

```
git add scripts/Combat.lua scripts/Entities.lua scripts/FollowerAI.lua scripts/Renderer.lua
git commit -m "refactor: genericize unit type checks to support 12 unit types"
```

---

### Task 3: New Unit Rendering in Renderer.lua

**Files:**
- Modify: `scripts/Renderer.lua` (drawFollower visual markers section)

- [ ] **Step 1: Add visual markers for 8 new unit types**

Find the per-type visual marker drawing section in `drawFollower` (search for `-- 类型标记` or the peasant hoe drawing). After the existing archer bow-arc drawing, add markers for each new type. Each marker is a simple NanoVG shape drawn relative to the follower's center:

```lua
elseif f.fType == "spearman" then
    -- 长矛：竖线 + 尖端
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy - radius * 0.9)
    nvgLineTo(ctx, sx, sy + radius * 0.5)
    nvgStrokeColor(ctx, nvgRGBA(180, 120, 60, 220))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
    -- 矛尖三角
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy - radius * 1.1)
    nvgLineTo(ctx, sx - 3, sy - radius * 0.7)
    nvgLineTo(ctx, sx + 3, sy - radius * 0.7)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(200, 200, 200, 220))
    nvgFill(ctx)

elseif f.fType == "mage" then
    -- 魔法星：小星号
    nvgFontSize(ctx, radius * 0.9)
    nvgFillColor(ctx, nvgRGBA(160, 50, 220, 240))
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(ctx, sx, sy, "*")

elseif f.fType == "mounted_archer" then
    -- 弓 + 马蹄标记：弓弧（同弓箭手）+ 底部小 V
    nvgBeginPath(ctx)
    nvgArc(ctx, sx - radius * 0.3, sy, radius * 0.4, -1.2, 1.2, 1)
    nvgStrokeColor(ctx, nvgRGBA(220, 180, 50, 220))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx - 3, sy + radius * 0.6)
    nvgLineTo(ctx, sx, sy + radius * 0.9)
    nvgLineTo(ctx, sx + 3, sy + radius * 0.6)
    nvgStrokeColor(ctx, nvgRGBA(220, 180, 50, 180))
    nvgStroke(ctx)

elseif f.fType == "advisor" then
    -- 羽扇：小圆 + 扇形线
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy, radius * 0.25)
    nvgFillColor(ctx, nvgRGBA(100, 200, 200, 200))
    nvgFill(ctx)

elseif f.fType == "vice_general" then
    -- 将旗：小旗标
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx + radius * 0.3, sy - radius * 0.8)
    nvgLineTo(ctx, sx + radius * 0.3, sy + radius * 0.3)
    nvgStrokeColor(ctx, nvgRGBA(200, 200, 200, 220))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)
    nvgBeginPath(ctx)
    nvgRect(ctx, sx + radius * 0.35, sy - radius * 0.8, radius * 0.4, radius * 0.35)
    nvgFillColor(ctx, nvgRGBA(200, 50, 50, 200))
    nvgFill(ctx)

elseif f.fType == "drummer" then
    -- 鼓：小圆 + 交叉棒
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + radius * 0.1, radius * 0.35, radius * 0.25)
    nvgFillColor(ctx, nvgRGBA(200, 140, 60, 180))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(140, 90, 30, 220))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

elseif f.fType == "paladin" then
    -- 十字盾（同骑士但金色）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy - radius * 0.5)
    nvgLineTo(ctx, sx, sy + radius * 0.5)
    nvgMoveTo(ctx, sx - radius * 0.3, sy)
    nvgLineTo(ctx, sx + radius * 0.3, sy)
    nvgStrokeColor(ctx, nvgRGBA(255, 215, 0, 240))
    nvgStrokeWidth(ctx, 2.5)
    nvgStroke(ctx)

elseif f.fType == "assassin" then
    -- 匕首：斜短线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx - radius * 0.3, sy + radius * 0.3)
    nvgLineTo(ctx, sx + radius * 0.3, sy - radius * 0.3)
    nvgStrokeColor(ctx, nvgRGBA(180, 180, 180, 220))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
```

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. New units won't appear in default game mode yet, but the rendering code is ready.

- [ ] **Step 3: Commit**

```
git add scripts/Renderer.lua
git commit -m "feat(renderer): add visual markers for 8 new unit types"
```

---

### Task 4: FormationSystem.lua — Core Module

**Files:**
- Create: `scripts/FormationSystem.lua`

- [ ] **Step 1: Create the complete FormationSystem module**

```lua
-- ============================================================================
-- FormationSystem.lua — 阵型系统核心
-- 负责：阵型条件判断、站位计算、加成查询
-- ============================================================================

local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

local FS = {}

-- ============================================================================
-- 阵型定义
-- ============================================================================

FS.Formations = {
    cone = {
        name = "锥形阵",
        -- 使用条件：{ unitType = minCount, ... }
        requires = { knight = 3, soldier = 2 },
        buffs = { speedMul = 1.2, frontDamageMul = 1.4 },
        switchCooldown = 10,
    },
    phalanx = {
        name = "方阵",
        requires = { spearman = 3, soldier = 2 },
        buffs = { armorMul = 0.7, speedMul = 0.85 },  -- armorMul < 1 = damage reduction
        switchCooldown = 10,
    },
    arc = {
        name = "弧形阵",
        requires = { archer = 3, mounted_archer = 2 },
        buffs = { rangeMul = 1.25, rangedDamageMul = 1.2 },
        switchCooldown = 10,
    },
    crane_wing = {
        name = "鹤翼阵",
        requires = { knight = 2, mounted_archer = 2, soldier = 2 },
        buffs = { flankDamageMul = 1.5 },
        switchCooldown = 10,
    },
    chaos = {
        name = "混元阵",
        requires = { soldier = 1, knight = 1, archer = 1, spearman = 1, mage = 1, mounted_archer = 1, peasant = 1 },
        buffs = { allStatsMul = 1.1, damageReductionChance = 0.2, damageReductionMul = 0.5 },
        switchCooldown = 10,
    },
    celestial = {
        name = "天罡阵",
        requires = { mage = 3, advisor = 1 },  -- +2 任意 = 总兵力 >= 6
        minTotal = 6,
        buffs = { magicDamageMul = 1.6, cooldownMul = 0.7 },
        switchCooldown = 10,
    },
}

--- 阵型 ID 顺序（用于 UI 展示）
FS.FormationOrder = { "cone", "phalanx", "arc", "crane_wing", "chaos", "celestial" }

-- ============================================================================
-- 条件判断
-- ============================================================================

--- 检查是否满足阵型使用条件
--- @param formationId string
--- @param unitCounts table<string, number>  e.g. { soldier = 5, knight = 3, ... }
--- @return boolean
function FS.canActivate(formationId, unitCounts)
    local def = FS.Formations[formationId]
    if not def then return false end

    for unitType, minCount in pairs(def.requires) do
        if (unitCounts[unitType] or 0) < minCount then
            return false
        end
    end

    -- 天罡阵额外要求：总兵力 >= minTotal
    if def.minTotal then
        local total = 0
        for _, count in pairs(unitCounts) do
            total = total + count
        end
        if total < def.minTotal then return false end
    end

    return true
end

-- ============================================================================
-- 站位计算
-- ============================================================================

--- 计算阵型中每个单位的目标位置
--- @param formationId string
--- @param lordX number
--- @param lordY number
--- @param lordAngle number  领主面朝方向（弧度）
--- @param units table[]  该领主的 following 状态随从列表
--- @return table<number, {x:number, y:number}>  followerId -> {x, y} 目标位置
--- @return table[]  extras 不属于阵型的多余单位
function FS.calculatePositions(formationId, lordX, lordY, lordAngle, units)
    local def = FS.Formations[formationId]
    if not def then return {}, units end

    local positions = {}
    local extras = {}

    -- 按类型分组
    local byType = {}
    for _, u in ipairs(units) do
        byType[u.fType] = byType[u.fType] or {}
        table.insert(byType[u.fType], u)
    end

    -- 取出阵型所需的单位，多余归入 extras
    local assigned = {}  -- 被分配到阵型的单位列表
    for unitType, minCount in pairs(def.requires) do
        local pool = byType[unitType] or {}
        for i, u in ipairs(pool) do
            if i <= minCount then
                table.insert(assigned, { unit = u, role = unitType })
            else
                table.insert(extras, u)
            end
        end
    end
    -- 未被 requires 提及的类型全部归入 extras
    for unitType, pool in pairs(byType) do
        if not def.requires[unitType] then
            for _, u in ipairs(pool) do
                table.insert(extras, u)
            end
        end
    end

    -- 特殊兵种始终归入 extras（紧跟领主）
    local finalAssigned = {}
    for _, entry in ipairs(assigned) do
        if CONFIG.IsSpecialUnit[entry.unit.fType] and entry.unit.fType ~= "advisor" then
            -- 副将、战鼓手等特殊兵种不参与阵型排列（军师除外，天罡阵需要）
            table.insert(extras, entry.unit)
        else
            table.insert(finalAssigned, entry)
        end
    end

    -- 计算方向向量
    local cosA = math.cos(lordAngle)
    local sinA = math.sin(lordAngle)
    -- 左方向（垂直于前方）
    local cosL = math.cos(lordAngle - math.pi / 2)
    local sinL = math.sin(lordAngle - math.pi / 2)

    local baseOffset = CONFIG.LordRadiusMax + 20  -- 基准偏移

    -- 分发到具体阵型计算
    if formationId == "cone" then
        positions = FS._calcCone(finalAssigned, lordX, lordY, cosA, sinA, cosL, sinL, baseOffset)
    elseif formationId == "phalanx" then
        positions = FS._calcPhalanx(finalAssigned, lordX, lordY, cosA, sinA, cosL, sinL, baseOffset)
    elseif formationId == "arc" then
        positions = FS._calcArc(finalAssigned, lordX, lordY, cosA, sinA, cosL, sinL, baseOffset)
    elseif formationId == "crane_wing" then
        positions = FS._calcCraneWing(finalAssigned, lordX, lordY, cosA, sinA, cosL, sinL, baseOffset)
    elseif formationId == "chaos" then
        positions = FS._calcChaos(finalAssigned, lordX, lordY, baseOffset)
    elseif formationId == "celestial" then
        positions = FS._calcCelestial(finalAssigned, lordX, lordY, baseOffset)
    end

    return positions, extras
end

-- ============================================================================
-- 各阵型站位计算实现
-- ============================================================================

--- 锥形阵：骑士前方 V 尖，士兵后方两侧
function FS._calcCone(assigned, lx, ly, cosA, sinA, cosL, sinL, baseOff)
    local pos = {}
    local knights = {}
    local soldiers = {}
    for _, entry in ipairs(assigned) do
        if entry.role == "knight" then table.insert(knights, entry.unit)
        else table.insert(soldiers, entry.unit) end
    end

    -- 骑士：前方倒 V，领头骑士在最前
    for i, u in ipairs(knights) do
        local fwd = baseOff + 10 + (i - 1) * 15
        local side = (i - 1) * 20 * ((i % 2 == 0) and 1 or -1)
        pos[u.id] = {
            x = lx + cosA * fwd + cosL * side,
            y = ly + sinA * fwd + sinL * side,
        }
    end

    -- 士兵：后方两侧展开
    for i, u in ipairs(soldiers) do
        local fwd = baseOff - 10
        local side = 30 * ((i % 2 == 0) and 1 or -1) + (math.ceil(i / 2) - 1) * 15 * ((i % 2 == 0) and 1 or -1)
        pos[u.id] = {
            x = lx + cosA * fwd + cosL * side,
            y = ly + sinA * fwd + sinL * side,
        }
    end

    return pos
end

--- 方阵：枪兵前排横线，士兵后排横线
function FS._calcPhalanx(assigned, lx, ly, cosA, sinA, cosL, sinL, baseOff)
    local pos = {}
    local spearmen = {}
    local soldiers = {}
    for _, entry in ipairs(assigned) do
        if entry.role == "spearman" then table.insert(spearmen, entry.unit)
        else table.insert(soldiers, entry.unit) end
    end

    -- 枪兵前排
    local spacing = 25
    for i, u in ipairs(spearmen) do
        local side = (i - math.ceil(#spearmen / 2) - 0.5) * spacing
        pos[u.id] = {
            x = lx + cosA * (baseOff + 15) + cosL * side,
            y = ly + sinA * (baseOff + 15) + sinL * side,
        }
    end

    -- 士兵后排
    for i, u in ipairs(soldiers) do
        local side = (i - math.ceil(#soldiers / 2) - 0.5) * spacing
        pos[u.id] = {
            x = lx + cosA * (baseOff - 15) + cosL * side,
            y = ly + sinA * (baseOff - 15) + sinL * side,
        }
    end

    return pos
end

--- 弧形阵：弓箭手和骑马弓手排成弧线在后方
function FS._calcArc(assigned, lx, ly, cosA, sinA, cosL, sinL, baseOff)
    local pos = {}
    local allRanged = {}
    for _, entry in ipairs(assigned) do
        table.insert(allRanged, entry.unit)
    end

    local arcRadius = baseOff + 20
    local totalArc = math.pi * 0.8  -- 弧度范围
    local startAngle = math.pi + lordAngleToWorld(cosA, sinA) - totalArc / 2
    local step = #allRanged > 1 and (totalArc / (#allRanged - 1)) or 0

    for i, u in ipairs(allRanged) do
        local angle = startAngle + (i - 1) * step
        pos[u.id] = {
            x = lx + math.cos(angle) * arcRadius,
            y = ly + math.sin(angle) * arcRadius,
        }
    end

    return pos
end

--- 鹤翼阵：士兵居中，骑士和骑马弓手分两翼展开
function FS._calcCraneWing(assigned, lx, ly, cosA, sinA, cosL, sinL, baseOff)
    local pos = {}
    local center = {}
    local leftWing = {}
    local rightWing = {}

    for _, entry in ipairs(assigned) do
        if entry.role == "soldier" then
            table.insert(center, entry.unit)
        elseif entry.role == "knight" then
            table.insert(leftWing, entry.unit)
        else
            table.insert(rightWing, entry.unit)
        end
    end

    -- 中心士兵
    for i, u in ipairs(center) do
        local side = (i - math.ceil(#center / 2) - 0.5) * 20
        pos[u.id] = {
            x = lx + cosA * baseOff + cosL * side,
            y = ly + sinA * baseOff + sinL * side,
        }
    end

    -- 左翼骑士（斜向前方展开）
    for i, u in ipairs(leftWing) do
        local fwd = baseOff + i * 15
        local side = -(30 + i * 20)
        pos[u.id] = {
            x = lx + cosA * fwd + cosL * side,
            y = ly + sinA * fwd + sinL * side,
        }
    end

    -- 右翼骑马弓手
    for i, u in ipairs(rightWing) do
        local fwd = baseOff + i * 15
        local side = 30 + i * 20
        pos[u.id] = {
            x = lx + cosA * fwd + cosL * side,
            y = ly + sinA * fwd + sinL * side,
        }
    end

    return pos
end

--- 混元阵：近战内圈，远程外圈
function FS._calcChaos(assigned, lx, ly, baseOff)
    local pos = {}
    local inner = {}
    local outer = {}

    for _, entry in ipairs(assigned) do
        if CONFIG.IsRangedUnit[entry.unit.fType] then
            table.insert(outer, entry.unit)
        else
            table.insert(inner, entry.unit)
        end
    end

    -- 内圈
    local innerR = baseOff
    for i, u in ipairs(inner) do
        local angle = (math.pi * 2 / #inner) * (i - 1)
        pos[u.id] = { x = lx + math.cos(angle) * innerR, y = ly + math.sin(angle) * innerR }
    end

    -- 外圈
    local outerR = baseOff + 30
    for i, u in ipairs(outer) do
        local angle = (math.pi * 2 / #outer) * (i - 1) + 0.3  -- 偏移避免重叠
        pos[u.id] = { x = lx + math.cos(angle) * outerR, y = ly + math.sin(angle) * outerR }
    end

    return pos
end

--- 天罡阵：法师围绕领主成圆，军师紧跟领主
function FS._calcCelestial(assigned, lx, ly, baseOff)
    local pos = {}
    local mages = {}

    for _, entry in ipairs(assigned) do
        if entry.unit.fType == "advisor" then
            pos[entry.unit.id] = { x = lx + 15, y = ly + 15 }  -- 紧跟领主
        else
            table.insert(mages, entry.unit)
        end
    end

    local mageR = baseOff + 10
    for i, u in ipairs(mages) do
        local angle = (math.pi * 2 / #mages) * (i - 1)
        pos[u.id] = { x = lx + math.cos(angle) * mageR, y = ly + math.sin(angle) * mageR }
    end

    return pos
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 将 cos/sin 方向转换为角度（用于弧形阵计算）
local function lordAngleToWorld(cosA, sinA)
    return math.atan2(sinA, cosA)
end

-- ============================================================================
-- 加成查询
-- ============================================================================

--- 获取阵型加成
--- @param formationId string|nil
--- @return table  buffs（为空表示无加成）
function FS.getBuffs(formationId)
    if not formationId then return {} end
    local def = FS.Formations[formationId]
    if not def then return {} end
    return def.buffs
end

--- 获取阵型名称
function FS.getName(formationId)
    local def = FS.Formations[formationId]
    return def and def.name or ""
end

return FS
```

**注意：** `_calcArc` 中引用了 `lordAngleToWorld`，该函数定义在文件末尾。Lua 中 local 函数需要在调用之前定义——需将 `lordAngleToWorld` 移到 `_calcArc` 之前，或改为模块级函数。实现时将其移到阵型计算函数之前即可。

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. Module not yet require'd by other code.

- [ ] **Step 3: Commit**

```
git add scripts/FormationSystem.lua
git commit -m "feat: add FormationSystem module with 6 formations"
```

---

### Task 5: Integrate Formations into FollowerAI & GameState

**Files:**
- Modify: `scripts/GameState.lua`
- Modify: `scripts/FollowerAI.lua`

- [ ] **Step 1: Add formation state fields to GameState**

In `scripts/GameState.lua`, add these fields to the GS table:

```lua
-- 阵型状态（每个领主一个）
-- Key: lordId, Value: { formationId = "cone"|nil, switchCooldown = 0 }
formationStates = {},
-- 当前游戏模式
gameMode = "skirmish",  -- "skirmish" | "campaign" | "endless"
```

Add helper functions:

```lua
function GS.getFormationId(lordId)
    local state = GS.formationStates[lordId]
    return state and state.formationId or nil
end

function GS.setFormation(lordId, formationId)
    if not GS.formationStates[lordId] then
        GS.formationStates[lordId] = { formationId = nil, switchCooldown = 0 }
    end
    GS.formationStates[lordId].formationId = formationId
    GS.formationStates[lordId].switchCooldown = 10
end

function GS.clearFormation(lordId)
    if GS.formationStates[lordId] then
        GS.formationStates[lordId].formationId = nil
    end
end

function GS.updateFormationCooldowns(dt)
    for _, state in pairs(GS.formationStates) do
        if state.switchCooldown > 0 then
            state.switchCooldown = state.switchCooldown - dt
        end
    end
end
```

- [ ] **Step 2: Integrate formation positioning into FollowerAI**

In `scripts/FollowerAI.lua`, add `require` at top:

```lua
local FormationSystem = require("FormationSystem")
```

Replace the `following` state's circular formation logic (lines ~157-170, the block that calculates `formationRadius`, `angleStep`, `formAngle`, `goalX`, `goalY`) with formation-aware positioning:

```lua
    elseif f.state == "following" then
        -- 获取该领主的阵型
        local formationId = GS.getFormationId(lord.id)
        local goalX, goalY

        if formationId then
            -- 阵型模式：使用 FormationSystem 计算站位
            -- 收集同领主 following 状态的随从
            local followingUnits = {}
            for _, of in ipairs(GS.followers) do
                if of.alive and of.lordId == lord.id and of.state == "following" then
                    table.insert(followingUnits, of)
                end
            end

            local positions, extras = FormationSystem.calculatePositions(
                formationId, lord.x, lord.y, lord.angle, followingUnits
            )

            -- 检查阵型条件是否仍满足
            local unitCounts = Entities.countFollowersByType(lord.id)
            if not FormationSystem.canActivate(formationId, unitCounts) then
                GS.clearFormation(lord.id)
                -- 降级为无阵型环形跟随
                formationId = nil
            end

            if positions[f.id] then
                goalX = positions[f.id].x
                goalY = positions[f.id].y
            else
                -- 此单位是 extras 或未分配：环形跟随
                formationId = nil  -- 走下面的 fallback 逻辑
            end
        end

        if not formationId or not goalX then
            -- 无阵型 fallback：原有环形编队逻辑
            local myIndex = 0
            local totalFollowing = 0
            for _, of in ipairs(GS.followers) do
                if of.alive and of.lordId == lord.id and of.state == "following" then
                    totalFollowing = totalFollowing + 1
                    if of.id == f.id then myIndex = totalFollowing end
                end
            end
            local formationRadius = CONFIG.LordRadiusMax + CONFIG.SoldierRadius + math.min(totalFollowing, 12) * 5
            local formMul = GS.tcGetFormationMul(lord.id)
            formationRadius = formationRadius * formMul
            local angleStep = (math.pi * 2) / math.max(totalFollowing, 1)
            local formAngle = angleStep * (myIndex - 1) + GS.gameTime * 0.15
            goalX = lord.x + math.cos(formAngle) * formationRadius
            goalY = lord.y + math.sin(formAngle) * formationRadius
        end

        -- 以下移动逻辑保持不变（从原 separationRadius 开始到 state == "attacking" 检测之前）
```

- [ ] **Step 3: Add formation cooldown update to main loop**

In `scripts/main.lua`, in `updateGame(dt)` function, add after other system updates:

```lua
GS.updateFormationCooldowns(dt)
```

- [ ] **Step 4: Build and verify**

Run: UrhoX MCP build tool
Expected: Game plays normally with default no-formation behavior. Setting a formation via `GS.setFormation(lordId, "cone")` (debug) would activate cone formation positioning.

- [ ] **Step 5: Commit**

```
git add scripts/GameState.lua scripts/FollowerAI.lua scripts/main.lua
git commit -m "feat: integrate FormationSystem into FollowerAI with fallback"
```

---

### Task 6: Formation Buffs in Combat + Ranged AI for New Types

**Files:**
- Modify: `scripts/Combat.lua`
- Modify: `scripts/FollowerAI.lua`

- [ ] **Step 1: Apply formation buffs in damage calculation**

In `scripts/Combat.lua`, add at top:

```lua
local FormationSystem = require("FormationSystem")
```

Modify `calcUnitDamage` to accept attacker's lordId and apply formation buffs:

```lua
local function calcUnitDamage(attackerType, defenderType, attackerLordId)
    local stats = CONFIG.UnitStats[attackerType]
    if not stats then return 0 end
    local mul = 1.0
    local mulTable = CONFIG.DamageMultiplier[attackerType]
    if mulTable and mulTable[defenderType] then
        mul = mulTable[defenderType]
    end
    local dmg = stats.atk * mul
    if GS.bloodMoonActive then dmg = dmg * 1.5 end

    -- 阵型加成
    if attackerLordId then
        local formId = GS.getFormationId(attackerLordId)
        local buffs = FormationSystem.getBuffs(formId)
        if buffs.allStatsMul then
            dmg = dmg * buffs.allStatsMul
        end
        if buffs.rangedDamageMul and CONFIG.IsRangedUnit[attackerType] then
            dmg = dmg * buffs.rangedDamageMul
        end
        if buffs.magicDamageMul and attackerType == "mage" then
            dmg = dmg * buffs.magicDamageMul
        end
    end

    return math.floor(dmg)
end
```

Update all calls to `calcUnitDamage` to pass `fa.lordId` as the third argument. There are two call sites in `processCombat`:
- Line ~103: `calcUnitDamage(fa.fType, fb.fType)` → `calcUnitDamage(fa.fType, fb.fType, fa.lordId)`
- Line ~117: `calcUnitDamage(fb.fType, fa.fType)` → `calcUnitDamage(fb.fType, fa.fType, fb.lordId)`

- [ ] **Step 2: Apply formation armor buff**

Modify `applyKnightArmor` to also apply formation armor:

```lua
local function applyFormationArmor(dmg, defenderUnit)
    -- 现有骑士铁桶阵减伤
    if defenderUnit.fType == "knight" then
        local armorMul = GS.tcGetKnightArmorMul(defenderUnit.lordId)
        if armorMul < 1.0 then
            dmg = math.floor(dmg * armorMul)
        end
    end
    -- 阵型减伤（方阵护甲）
    local formId = GS.getFormationId(defenderUnit.lordId)
    local buffs = FormationSystem.getBuffs(formId)
    if buffs.armorMul then
        dmg = math.floor(dmg * buffs.armorMul)
    end
    -- 混元阵概率减伤
    if buffs.damageReductionChance and math.random() < buffs.damageReductionChance then
        dmg = math.floor(dmg * (buffs.damageReductionMul or 0.5))
    end
    return dmg
end
```

Rename the existing `applyKnightArmor` calls to `applyFormationArmor`.

- [ ] **Step 3: Add ranged AI for mage and mounted_archer in FollowerAI**

In `scripts/FollowerAI.lua`, in the `attacking` state section, expand the archer ranged logic to support new ranged types. Replace the `if f.fType == "archer" then` block:

```lua
        if CONFIG.IsRangedUnit[f.fType] then
            -- 远程单位：保持距离射击
            local unitRange = CONFIG.ArcherRange
            local unitFleeDistance = CONFIG.ArcherFleeDistance
            local unitFireInterval = CONFIG.ArcherFireInterval
            local unitSpeedMul = 1.0

            if f.fType == "mage" then
                unitRange = CONFIG.MageRange
                unitFleeDistance = CONFIG.MageFleeDistance
                unitFireInterval = CONFIG.MageFireInterval
            elseif f.fType == "mounted_archer" then
                unitRange = CONFIG.MountedArcherRange
                unitFleeDistance = CONFIG.MountedArcherFleeDistance
                unitFireInterval = CONFIG.MountedArcherFireInterval
                unitSpeedMul = CONFIG.MountedArcherSpeedMul
            end

            -- 鹰眼猎手天赋：玩家弓箭手射程+30%
            if f.fType == "archer" and lord.isPlayer and TS.getActiveTalent() == "eagle_eye" then
                unitRange = unitRange * 1.3
            end

            -- 阵型加成：弧形阵射程+25%
            local formId = GS.getFormationId(lord.id)
            local buffs = FormationSystem.getBuffs(formId)
            if buffs.rangeMul then
                unitRange = unitRange * buffs.rangeMul
            end

            if dToTarget < unitFleeDistance then
                -- 被贴近，逃跑
                local dx, dy = normalize(f.x - tx, f.y - ty)
                f.x = f.x + dx * CONFIG.FollowerSpeed * 1.1 * unitSpeedMul * atkSpeedMul * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * 1.1 * unitSpeedMul * atkSpeedMul * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            elseif dToTarget > unitRange then
                -- 太远，靠近
                local dx, dy = normalize(tx - f.x, ty - f.y)
                f.x = f.x + dx * CONFIG.FollowerSpeed * unitSpeedMul * atkSpeedMul * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * unitSpeedMul * atkSpeedMul * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            else
                -- 在射程内，射击
                f.angle = math.atan2(ty - f.y, tx - f.x)
                f.fireTimer = (f.fireTimer or 0) + dt
                if f.fireTimer >= unitFireInterval then
                    f.fireTimer = 0
                    if f.fType == "mage" and CONFIG.UnitStats.mage.aoeRadius then
                        -- 法师 AOE 弹射物
                        table.insert(GS.projectiles, {
                            x = f.x, y = f.y,
                            tx = tx, ty = ty,
                            speed = 250,
                            factionId = f.factionId,
                            fromArcherId = f.id,
                            alive = true,
                            isAOE = true,
                            aoeRadius = CONFIG.UnitStats.mage.aoeRadius,
                            attackerType = "mage",
                        })
                    else
                        table.insert(GS.projectiles, {
                            x = f.x, y = f.y,
                            tx = tx, ty = ty,
                            speed = 350,
                            factionId = f.factionId,
                            fromArcherId = f.id,
                            alive = true,
                            attackerType = f.fType,
                        })
                    end
                end
            end
        else
```

- [ ] **Step 4: Handle AOE projectile hits in Combat.processProjectiles**

In `scripts/Combat.lua`, in `processProjectiles`, after the single-target hit detection (line ~213, `if hitDist < 12 then`), add AOE logic:

```lua
                -- AOE 弹射物：对范围内所有敌方造成伤害
                if p.isAOE and p.aoeRadius then
                    for _, f2 in ipairs(GS.followers) do
                        if f2.alive and f2.factionId ~= p.factionId then
                            local aoeDist = Utils.dist(p.x, p.y, f2.x, f2.y)
                            if aoeDist < p.aoeRadius then
                                local aoeDmg = calcUnitDamage(p.attackerType or "mage", f2.fType, nil)
                                aoeDmg = math.floor(aoeDmg * 0.6)  -- AOE 60% 伤害
                                f2.hp = f2.hp - aoeDmg
                                Entities.spawnDamageNumber(f2.x, f2.y, aoeDmg, 160, 50, 220)
                                if f2.hp <= 0 then
                                    f2.alive = false
                                    Entities.spawnParticle(f2.x, f2.y, 160, 50, 220, 4)
                                end
                            end
                        end
                    end
                    Entities.spawnParticle(p.x, p.y, 160, 50, 220, 10)  -- AOE 爆炸特效
                else
                    -- 原有单体命中逻辑（保持不变）
```

- [ ] **Step 5: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. Formation buffs and new ranged AI ready for use.

- [ ] **Step 6: Commit**

```
git add scripts/Combat.lua scripts/FollowerAI.lua
git commit -m "feat: formation buffs in combat, ranged AI for mage/mounted_archer"
```

---

## Phase 2: Campaign System

### Task 7: CampaignData.lua — Level Configurations

**Files:**
- Create: `scripts/CampaignData.lua`

- [ ] **Step 1: Create the complete CampaignData module**

```lua
-- ============================================================================
-- CampaignData.lua — 战役关卡配置数据
-- ============================================================================

local CD = {}

--- 章节信息
CD.Chapters = {
    { id = 1, name = "边境烽烟", levelCount = 6 },
    { id = 2, name = "深入腹地", levelCount = 6 },
    { id = 3, name = "王都之战", levelCount = 5 },
}

--- 所有关卡配置
--- enemies: { { units = {type=count,...}, formation = id|nil, aiLevel = 1-3 }, ... }
--- player_start: { type = count, ... }
--- reward: { type = "unit"|"formation", id = string }
CD.Levels = {
    ["1-1"] = {
        name = "初战告捷", chapter = 1,
        map_size = { w = 2000, h = 2000 },
        player_start = { peasant = 5, soldier = 3 },
        resources = 40,
        enemies = {
            { units = { peasant = 3, soldier = 5 }, formation = nil, aiLevel = 1 },
        },
        reward = nil,  -- 教学关无特殊奖励
        next = { "1-2" },
        unlock_condition = nil,
    },
    ["1-2"] = {
        name = "资源争夺", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 4 },
        resources = 50,
        enemies = {
            { units = { peasant = 4, soldier = 6, archer = 2 }, formation = nil, aiLevel = 1 },
        },
        reward = nil,
        next = { "1-3" },
        unlock_condition = { "1-1" },
    },
    ["1-3"] = {
        name = "骑兵突袭", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 5, knight = 2 },
        resources = 50,
        enemies = {
            { units = { peasant = 3, soldier = 5, knight = 3 }, formation = nil, aiLevel = 1 },
        },
        reward = { type = "formation", id = "cone" },
        next = { "1-4A", "1-4B" },
        unlock_condition = { "1-2" },
    },
    ["1-4A"] = {
        name = "山贼巢穴", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 4, knight = 2 },
        resources = 45,
        enemies = {
            { units = { peasant = 2, soldier = 8, archer = 3 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "unit", id = "spearman" },
        next = { "1-5" },
        unlock_condition = { "1-3" },
    },
    ["1-4B"] = {
        name = "兽群侵袭", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 4, knight = 2 },
        resources = 45,
        enemies = {
            { units = { peasant = 2, soldier = 6, knight = 4 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "unit", id = "mounted_archer" },
        next = { "1-5" },
        unlock_condition = { "1-3" },
    },
    ["1-5"] = {
        name = "边境要塞", chapter = 1,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 5, soldier = 5, knight = 3, archer = 2 },
        resources = 60,
        enemies = {
            { units = { peasant = 3, soldier = 7, knight = 3, archer = 3 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "formation", id = "phalanx" },
        next = { "2-1" },
        unlock_condition = { "1-4A", "1-4B", mode = "any" },
    },

    -- 第二章
    ["2-1"] = {
        name = "密林遭遇", chapter = 2,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 5, knight = 2, archer = 2 },
        resources = 50,
        enemies = {
            { units = { soldier = 6, knight = 2, archer = 4 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "unit", id = "mage" },
        next = { "2-2" },
        unlock_condition = { "1-5" },
    },
    ["2-2"] = {
        name = "伏击战", chapter = 2,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 5, knight = 2, archer = 3 },
        resources = 50,
        enemies = {
            { units = { soldier = 5, archer = 5, mounted_archer = 2 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "formation", id = "arc" },
        next = { "2-3" },
        unlock_condition = { "2-1" },
    },
    ["2-3"] = {
        name = "副将来投", chapter = 2,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 5, knight = 3, archer = 3 },
        resources = 55,
        enemies = {
            { units = { soldier = 6, knight = 3, spearman = 3 }, formation = "phalanx", aiLevel = 2 },
        },
        reward = { type = "unit", id = "vice_general" },
        next = { "2-4A", "2-4B" },
        unlock_condition = { "2-2" },
    },
    ["2-4A"] = {
        name = "平原决战", chapter = 2,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 5, knight = 3, archer = 3, spearman = 2 },
        resources = 55,
        enemies = {
            { units = { soldier = 5, knight = 4, mounted_archer = 3 }, formation = "cone", aiLevel = 2 },
            { units = { soldier = 4, archer = 4 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "formation", id = "crane_wing" },
        next = { "2-5" },
        unlock_condition = { "2-3" },
    },
    ["2-4B"] = {
        name = "河谷阻击", chapter = 2,
        map_size = { w = 2500, h = 3000 },
        player_start = { peasant = 4, soldier = 5, knight = 2, archer = 3, spearman = 2 },
        resources = 55,
        enemies = {
            { units = { soldier = 6, spearman = 4, archer = 3 }, formation = "phalanx", aiLevel = 2 },
        },
        reward = { type = "unit", id = "drummer" },
        next = { "2-5" },
        unlock_condition = { "2-3" },
    },
    ["2-5"] = {
        name = "攻城战", chapter = 2,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 5, soldier = 6, knight = 3, archer = 3, spearman = 2 },
        resources = 60,
        enemies = {
            { units = { soldier = 7, knight = 3, archer = 4, spearman = 3 }, formation = "phalanx", aiLevel = 3 },
        },
        reward = { type = "unit", id = "advisor" },
        next = { "3-1" },
        unlock_condition = { "2-4A", "2-4B", mode = "any" },
    },

    -- 第三章
    ["3-1"] = {
        name = "王都外围", chapter = 3,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 6, knight = 3, archer = 3, spearman = 3, mage = 1 },
        resources = 55,
        enemies = {
            { units = { soldier = 6, knight = 4, archer = 3, mage = 2 }, formation = "cone", aiLevel = 3 },
            { units = { soldier = 5, spearman = 4 }, formation = "phalanx", aiLevel = 2 },
        },
        reward = nil,
        next = { "3-2" },
        unlock_condition = { "2-5" },
    },
    ["3-2"] = {
        name = "内城突破", chapter = 3,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 6, knight = 3, archer = 3, spearman = 3, mage = 2 },
        resources = 55,
        enemies = {
            { units = { soldier = 7, knight = 4, archer = 4, paladin = 1 }, formation = "crane_wing", aiLevel = 3 },
            { units = { soldier = 5, mage = 3, spearman = 3 }, formation = nil, aiLevel = 3 },
        },
        reward = { type = "unit", id = "paladin" },
        next = { "3-3" },
        unlock_condition = { "3-1" },
    },
    ["3-3"] = {
        name = "王宫之战", chapter = 3,
        map_size = { w = 3500, h = 3500 },
        player_start = { peasant = 5, soldier = 7, knight = 4, archer = 4, spearman = 3, mage = 2 },
        resources = 60,
        enemies = {
            { units = { soldier = 8, knight = 5, archer = 4, spearman = 3, mage = 2 }, formation = "crane_wing", aiLevel = 3 },
            { units = { soldier = 5, knight = 3, mage = 2, drummer = 1 }, formation = "cone", aiLevel = 3 },
        },
        reward = { type = "formation", id = "chaos" },
        next = { "3-4", "3-S" },
        unlock_condition = { "3-2" },
    },
    ["3-4"] = {
        name = "正面决战", chapter = 3,
        map_size = { w = 3500, h = 3500 },
        player_start = { peasant = 5, soldier = 8, knight = 4, archer = 4, spearman = 3, mage = 3 },
        resources = 65,
        enemies = {
            { units = { soldier = 8, knight = 5, archer = 5, spearman = 4, mage = 3, paladin = 1 }, formation = "chaos", aiLevel = 3 },
            { units = { soldier = 6, knight = 4, mounted_archer = 3 }, formation = "crane_wing", aiLevel = 3 },
            { units = { soldier = 5, mage = 3, advisor = 1 }, formation = "celestial", aiLevel = 3 },
        },
        reward = { type = "formation", id = "celestial" },
        next = nil,  -- 终章
        unlock_condition = { "3-3" },
    },
    ["3-S"] = {
        name = "暗影小径", chapter = 3,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 3, soldier = 6, knight = 3, archer = 3, spearman = 2, mage = 2 },
        resources = 40,
        enemies = {
            { units = { soldier = 10, knight = 4, assassin = 2 }, formation = nil, aiLevel = 3 },
        },
        reward = { type = "unit", id = "assassin" },
        next = nil,
        unlock_condition = { "3-3", special = "3-3_low_casualties" },  -- 通关 3-3 损失 <= 5 单位
    },
}

--- 获取章节所有关卡 ID
function CD.getLevelsByChapter(chapter)
    local result = {}
    for id, level in pairs(CD.Levels) do
        if level.chapter == chapter then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

--- 获取关卡配置
function CD.getLevel(levelId)
    return CD.Levels[levelId]
end

return CD
```

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
git add scripts/CampaignData.lua
git commit -m "feat: add CampaignData module with 17 level configurations"
```

---

### Task 8: CampaignState.lua — Progress & Cloud Persistence

**Files:**
- Create: `scripts/CampaignState.lua`

- [ ] **Step 1: Create the CampaignState module**

```lua
-- ============================================================================
-- CampaignState.lua — 战役进度管理 + 云存档
-- ============================================================================

local CampaignData = require("CampaignData")

local CS = {}

-- 本地缓存
local state = {
    chapter = 1,
    cleared = {},           -- set: levelId -> true
    unlocked_units = {},    -- set: unitId -> true
    unlocked_formations = {},-- set: formationId -> true
}
local loaded = false

-- ============================================================================
-- 云端存取
-- ============================================================================

--- 序列化为 JSON 字符串存云端
local function serialize()
    local cleared_list = {}
    for id in pairs(state.cleared) do table.insert(cleared_list, id) end
    local units_list = {}
    for id in pairs(state.unlocked_units) do table.insert(units_list, id) end
    local formations_list = {}
    for id in pairs(state.unlocked_formations) do table.insert(formations_list, id) end

    return require("cjson").encode({
        chapter = state.chapter,
        cleared = cleared_list,
        unlocked_units = units_list,
        unlocked_formations = formations_list,
    })
end

--- 从 JSON 字符串反序列化
local function deserialize(jsonStr)
    if not jsonStr or jsonStr == "" then return end
    local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
    if not ok or not data then return end

    state.chapter = data.chapter or 1
    state.cleared = {}
    for _, id in ipairs(data.cleared or {}) do state.cleared[id] = true end
    state.unlocked_units = {}
    for _, id in ipairs(data.unlocked_units or {}) do state.unlocked_units[id] = true end
    state.unlocked_formations = {}
    for _, id in ipairs(data.unlocked_formations or {}) do state.unlocked_formations[id] = true end
end

function CS.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("campaign_data")
            :Fetch({
                ok = function(values)
                    deserialize(values.campaign_data)
                    loaded = true
                    print("[CS] Campaign data loaded: chapter=" .. state.chapter)
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[CS] Campaign load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function CS.saveToCloud()
    if clientCloud then
        clientCloud:BatchSet()
            :Set("campaign_data", serialize())
            :Save("战役进度", {
                ok = function() print("[CS] Campaign data saved") end,
                error = function(_, reason) print("[CS] Campaign save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function CS.isLoaded() return loaded end
function CS.getCurrentChapter() return state.chapter end
function CS.isCleared(levelId) return state.cleared[levelId] == true end
function CS.isUnitUnlocked(unitId) return state.unlocked_units[unitId] == true end
function CS.isFormationUnlocked(formId) return state.unlocked_formations[formId] == true end

function CS.isLevelAccessible(levelId)
    local level = CampaignData.getLevel(levelId)
    if not level then return false end
    if not level.unlock_condition then return true end  -- 1-1 无条件

    if level.unlock_condition.mode == "any" then
        for _, reqId in ipairs(level.unlock_condition) do
            if type(reqId) == "string" and state.cleared[reqId] then return true end
        end
        return false
    else
        for _, reqId in ipairs(level.unlock_condition) do
            if type(reqId) == "string" and not state.cleared[reqId] then return false end
        end
    end

    -- 特殊条件
    if level.unlock_condition.special == "3-3_low_casualties" then
        -- 由通关 3-3 时记录的损失数判断（存在 state 中）
        return (state.casualties_3_3 or 999) <= 5
    end

    return true
end

-- ============================================================================
-- 状态更新
-- ============================================================================

--- 记录关卡通关，返回首通奖励（或 nil）
function CS.clearLevel(levelId, casualties)
    local isFirstClear = not state.cleared[levelId]
    state.cleared[levelId] = true

    -- 更新章节进度
    local level = CampaignData.getLevel(levelId)
    if level and level.chapter > state.chapter then
        state.chapter = level.chapter
    end

    -- 记录 3-3 损失数（用于隐藏关卡解锁）
    if levelId == "3-3" then
        state.casualties_3_3 = casualties
    end

    local reward = nil
    if isFirstClear and level and level.reward then
        reward = level.reward
        if reward.type == "unit" then
            state.unlocked_units[reward.id] = true
        elseif reward.type == "formation" then
            state.unlocked_formations[reward.id] = true
        end
    end

    CS.saveToCloud()
    return reward
end

--- 获取已通关关卡列表
function CS.getClearedLevels()
    local list = {}
    for id in pairs(state.cleared) do table.insert(list, id) end
    table.sort(list)
    return list
end

--- 获取已解锁兵种列表
function CS.getUnlockedUnits()
    local list = {}
    for id in pairs(state.unlocked_units) do table.insert(list, id) end
    return list
end

--- 获取已解锁阵型列表
function CS.getUnlockedFormations()
    local list = {}
    for id in pairs(state.unlocked_formations) do table.insert(list, id) end
    return list
end

return CS
```

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
git add scripts/CampaignState.lua
git commit -m "feat: add CampaignState module with cloud persistence"
```

---

## Phase 3: Meta-Progression

### Task 9: CodexData.lua — Unit Codex Configuration

**Files:**
- Create: `scripts/CodexData.lua`

- [ ] **Step 1: Create the CodexData module**

```lua
-- ============================================================================
-- CodexData.lua — 兵种图鉴配置数据
-- ============================================================================

local CodexData = {}

--- 经验曲线（等级 N→N+1 所需击杀数）
CodexData.ExpCurve = { 20, 30, 40, 50, 60, 70, 80, 90, 100 }
CodexData.MaxLevel = 10

--- 每级全属性加成（2%）
CodexData.LevelBonusPct = 0.02

--- 累计经验需求（方便查询）
CodexData.CumulativeExp = {}
do
    local sum = 0
    for i, v in ipairs(CodexData.ExpCurve) do
        sum = sum + v
        CodexData.CumulativeExp[i] = sum  -- CumulativeExp[1]=20, [2]=50, [3]=90, ...
    end
end

--- 兵种描述文本
CodexData.Descriptions = {
    peasant         = { name = "农民",     role = "采集",   desc = "基础采集单位，战斗力低但数量多" },
    soldier         = { name = "士兵",     role = "近战",   desc = "标准近战步兵，攻守平衡" },
    knight          = { name = "骑士",     role = "重装",   desc = "重甲骑兵，高防御和冲击力" },
    archer          = { name = "弓箭手",   role = "远程",   desc = "远程射手，擅长风筝战术" },
    spearman        = { name = "枪兵",     role = "近战",   desc = "克制骑兵的长枪步兵" },
    mage            = { name = "法师",     role = "远程",   desc = "魔法攻击，可造成范围伤害" },
    mounted_archer  = { name = "骑马弓手", role = "远程",   desc = "高机动远程射手" },
    drummer         = { name = "鼓手",     role = "辅助",   desc = "战鼓鼓舞士气，提升周围友军攻速" },
    advisor         = { name = "军师",     role = "辅助",   desc = "可揭示战场迷雾与敌军阵型" },
    paladin         = { name = "圣骑士",   role = "重装",   desc = "可释放神圣护盾保护友军" },
    assassin        = { name = "刺客",     role = "近战",   desc = "潜行突袭，对落单目标造成致命伤害" },
    vice_general    = { name = "副将",     role = "统领",   desc = "率领一支分队独立作战" },
}

--- 获取等级加成倍率（1.0 = 无加成）
function CodexData.getLevelMultiplier(level)
    if not level or level <= 1 then return 1.0 end
    return 1.0 + (level - 1) * CodexData.LevelBonusPct
end

--- 计算当前经验对应的等级和剩余经验
function CodexData.calcLevel(totalExp)
    local level = 1
    local remaining = totalExp
    for i, req in ipairs(CodexData.ExpCurve) do
        if remaining >= req then
            level = i + 1
            remaining = remaining - req
        else
            return level, remaining, req
        end
    end
    return CodexData.MaxLevel, 0, 0  -- 满级
end

return CodexData
```

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
git add scripts/CodexData.lua
git commit -m "feat: add CodexData module with exp curve and descriptions"
```

---

### Task 10: CodexState.lua — Codex Progress & Cloud Persistence

**Files:**
- Create: `scripts/CodexState.lua`

- [ ] **Step 1: Create the CodexState module**

```lua
-- ============================================================================
-- CodexState.lua — 兵种图鉴进度管理 + 云存档
-- ============================================================================

local CodexData = require("CodexData")

local CXS = {}

-- 本地缓存
local units = {}   -- { [unitId] = { exp=0, kills=0, deaths=0, recruited=0 } }
local loaded = false

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化所有兵种条目（确保每个兵种都有记录）
local function ensureEntry(unitId)
    if not units[unitId] then
        units[unitId] = { exp = 0, kills = 0, deaths = 0, recruited = 0 }
    end
end

-- ============================================================================
-- 云端存取
-- ============================================================================

function CXS.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("codex_data")
            :Fetch({
                ok = function(values)
                    local jsonStr = values.codex_data
                    if jsonStr and jsonStr ~= "" then
                        local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
                        if ok and data then
                            for unitId, info in pairs(data) do
                                units[unitId] = {
                                    exp = info.exp or 0,
                                    kills = info.kills or 0,
                                    deaths = info.deaths or 0,
                                    recruited = info.recruited or 0,
                                }
                            end
                        end
                    end
                    loaded = true
                    print("[CXS] Codex data loaded")
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[CXS] Codex load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function CXS.saveToCloud()
    if clientCloud then
        local jsonStr = require("cjson").encode(units)
        clientCloud:BatchSet()
            :Set("codex_data", jsonStr)
            :Save("图鉴进度", {
                ok = function() print("[CXS] Codex data saved") end,
                error = function(_, reason) print("[CXS] Codex save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 战斗统计记录（每局结束时调用）
-- ============================================================================

--- 记录一个单位的击杀（同时累加经验）
function CXS.recordKill(unitId)
    ensureEntry(unitId)
    units[unitId].kills = units[unitId].kills + 1
    units[unitId].exp = units[unitId].exp + 1  -- 1 击杀 = 1 经验
end

--- 记录一个单位的阵亡
function CXS.recordDeath(unitId)
    ensureEntry(unitId)
    units[unitId].deaths = units[unitId].deaths + 1
end

--- 记录招募
function CXS.recordRecruit(unitId, count)
    ensureEntry(unitId)
    units[unitId].recruited = units[unitId].recruited + (count or 1)
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function CXS.isLoaded() return loaded end

--- 获取兵种等级
function CXS.getLevel(unitId)
    ensureEntry(unitId)
    local level = CodexData.calcLevel(units[unitId].exp)
    return level
end

--- 获取兵种等级加成倍率
function CXS.getLevelMultiplier(unitId)
    return CodexData.getLevelMultiplier(CXS.getLevel(unitId))
end

--- 获取兵种详细进度
function CXS.getUnitInfo(unitId)
    ensureEntry(unitId)
    local info = units[unitId]
    local level, remainingExp, nextReq = CodexData.calcLevel(info.exp)
    return {
        level = level,
        exp = info.exp,
        remainingExp = remainingExp,
        nextReq = nextReq,
        kills = info.kills,
        deaths = info.deaths,
        recruited = info.recruited,
    }
end

--- 获取已解锁兵种总数（有任何记录即视为已解锁）
function CXS.getUnlockedCount()
    local count = 0
    for _ in pairs(units) do count = count + 1 end
    return count
end

--- 检查是否全图鉴解锁（12种）
function CXS.isFullCodex()
    return CXS.getUnlockedCount() >= 12
end

--- 获取全图鉴加成（全军+5%）
function CXS.getFullCodexBonus()
    return CXS.isFullCodex() and 1.05 or 1.0
end

return CXS
```

- [ ] **Step 2: Integrate codex level bonus into Combat.lua**

In `scripts/Combat.lua`, add at top:

```lua
local CodexState = require("CodexState")
```

In `calcUnitDamage`, after the formation buff block but before `return`, add codex level bonus:

```lua
    -- 图鉴等级加成
    dmg = dmg * CodexState.getLevelMultiplier(attackerType)

    -- 全图鉴解锁加成
    dmg = dmg * CodexState.getFullCodexBonus()

    return math.floor(dmg)
```

- [ ] **Step 3: Hook codex recording into combat events**

In `scripts/Combat.lua`, in the follower-vs-follower kill section (where `f.alive = false` is set after HP drops to 0), add:

```lua
    -- 记录图鉴统计
    CodexState.recordKill(attacker.fType)
    CodexState.recordDeath(f.fType)
```

Similarly for follower-vs-lord kills and boss kills.

- [ ] **Step 4: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```
git add scripts/CodexState.lua scripts/Combat.lua
git commit -m "feat: add CodexState module with combat stat tracking"
```

---

### Task 11: PresetManager.lua — Squad Presets

**Files:**
- Create: `scripts/PresetManager.lua`

- [ ] **Step 1: Create the PresetManager module**

```lua
-- ============================================================================
-- PresetManager.lua — 编队预设保存/加载/管理（5 个槽位）
-- ============================================================================

local PM = {}

local MAX_PRESETS = 5

-- 本地缓存
local presets = {}  -- [1..5] = { name, units, formation, squad } or nil
local loaded = false

-- ============================================================================
-- 云端存取
-- ============================================================================

function PM.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("presets_data")
            :Fetch({
                ok = function(values)
                    local jsonStr = values.presets_data
                    if jsonStr and jsonStr ~= "" then
                        local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
                        if ok and data then
                            -- cjson 可能把数组 key 1..5 序列化为字符串 key
                            for i = 1, MAX_PRESETS do
                                presets[i] = data[tostring(i)] or data[i] or nil
                            end
                        end
                    end
                    loaded = true
                    print("[PM] Presets loaded")
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[PM] Presets load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function PM.saveToCloud()
    if clientCloud then
        local jsonStr = require("cjson").encode(presets)
        clientCloud:BatchSet()
            :Set("presets_data", jsonStr)
            :Save("编队预设", {
                ok = function() print("[PM] Presets saved") end,
                error = function(_, reason) print("[PM] Presets save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 预设操作
-- ============================================================================

--- 保存预设到指定槽位
--- @param slot number 1-5
--- @param preset table { name=string, units={type=count,...}, formation=string|nil, squad={formation=string|nil, units={type=count,...}}|nil }
function PM.save(slot, preset)
    if slot < 1 or slot > MAX_PRESETS then return false end
    presets[slot] = {
        name = preset.name or ("预设" .. slot),
        units = preset.units or {},
        formation = preset.formation,
        squad = preset.squad,
    }
    PM.saveToCloud()
    return true
end

--- 加载指定槽位的预设
--- @param slot number 1-5
--- @return table|nil preset
function PM.load(slot)
    return presets[slot]
end

--- 删除指定槽位
function PM.delete(slot)
    if slot < 1 or slot > MAX_PRESETS then return end
    presets[slot] = nil
    PM.saveToCloud()
end

--- 重命名指定槽位
function PM.rename(slot, newName)
    if presets[slot] then
        presets[slot].name = newName
        PM.saveToCloud()
    end
end

--- 获取所有槽位概要
function PM.listAll()
    local result = {}
    for i = 1, MAX_PRESETS do
        if presets[i] then
            result[i] = { name = presets[i].name, hasData = true }
        else
            result[i] = { name = "空槽位", hasData = false }
        end
    end
    return result
end

function PM.isLoaded() return loaded end
function PM.getMaxSlots() return MAX_PRESETS end

return PM
```

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
git add scripts/PresetManager.lua
git commit -m "feat: add PresetManager module with 5 preset slots"
```

---

### Task 12: TalentSystem Redesign — 3-Path Talent Tree

**Files:**
- Modify: `scripts/Config.lua`
- Modify: `scripts/TalentSystem.lua`

- [ ] **Step 1: Replace Talents config in Config.lua**

Replace the existing `CONFIG.Talents` block with the new 3-path structure:

```lua
    -- ================================================================
    -- 天赋树（三条路线 × 5 节点）
    -- ================================================================
    TalentPaths = {
        commander = {
            name = "统帅之道", desc = "阵型与编队增强",
            nodes = {
                { id = "cmd_1", name = "阵型精通 I",    desc = "阵型加成+5%",       effect = { formationBuffMul = 1.05 }, cost = 1 },
                { id = "cmd_2", name = "扩编 I",        desc = "编制上限+1",         effect = { unitCapBonus = 1 },       cost = 2 },
                { id = "cmd_3", name = "兵贵神速",      desc = "阵型切换冷却-3秒",   effect = { formationCdReduce = 3 },  cost = 3 },
                { id = "cmd_4", name = "阵型精通 II",   desc = "阵型加成+10%",       effect = { formationBuffMul = 1.10 }, cost = 4 },
                { id = "cmd_5", name = "扩编 II",       desc = "编制上限+2",         effect = { unitCapBonus = 2 },       cost = 5 },
            },
        },
        warfare = {
            name = "战争之道", desc = "战斗数值增强",
            nodes = {
                { id = "war_1", name = "攻击强化 I",    desc = "全军攻击+3%",        effect = { atkMul = 1.03 },          cost = 1 },
                { id = "war_2", name = "暴击锋芒",      desc = "暴击率+2%",          effect = { critChance = 0.02 },      cost = 2 },
                { id = "war_3", name = "精锐编制",      desc = "特殊兵种编制占用-1", effect = { specialSlotReduce = 1 },   cost = 3 },
                { id = "war_4", name = "攻击强化 II",   desc = "全军攻击+5%",        effect = { atkMul = 1.05 },          cost = 4 },
                { id = "war_5", name = "致命打击",      desc = "暴击伤害+20%",       effect = { critDamageMul = 1.20 },   cost = 5 },
            },
        },
        economy = {
            name = "经略之道", desc = "资源与成长增强",
            nodes = {
                { id = "eco_1", name = "充裕资源 I",    desc = "初始资源+10%",       effect = { startResourceMul = 1.10 }, cost = 1 },
                { id = "eco_2", name = "精研兵法",      desc = "兵种经验获取+10%",   effect = { codexExpMul = 1.10 },     cost = 2 },
                { id = "eco_3", name = "军需折扣",      desc = "无尽商店折扣10%",    effect = { shopDiscount = 0.90 },     cost = 3 },
                { id = "eco_4", name = "充裕资源 II",   desc = "初始资源+20%",       effect = { startResourceMul = 1.20 }, cost = 4 },
                { id = "eco_5", name = "名将之师",      desc = "兵种经验获取+15%",   effect = { codexExpMul = 1.15 },     cost = 5 },
            },
        },
    },

    -- 声望相关
    ReputationPerFirstClear = 3,   -- 关卡首通声望
    ReputationPerEndless5 = 1,     -- 无尽每5波声望
```

Remove the old `CONFIG.Talents` array (the flat list with `conscript`, `ore_sense`, `iron_vanguard`, `eagle_eye`).

Also remove the old `GloryPerVictory`, `GloryPerDefeat`, `GloryPerSurvival30s` entries — they are replaced by reputation points.

- [ ] **Step 2: Rewrite TalentSystem.lua for 3-path tree**

Replace the entire `scripts/TalentSystem.lua` with:

```lua
-- ============================================================================
-- TalentSystem.lua — 三路线天赋树 + 声望点数系统
-- ============================================================================

local TS = {}

local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

-- ============================================================================
-- 本地缓存
-- ============================================================================
local state = {
    reputation = 0,         -- 可用声望点数
    -- 每条路线已解锁的节点数（0-5）
    paths = {
        commander = 0,
        warfare = 0,
        economy = 0,
    },
}
local loaded = false

-- ============================================================================
-- 云端存取
-- ============================================================================

function TS.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("talent_data")
            :Fetch({
                ok = function(values)
                    local jsonStr = values.talent_data
                    if jsonStr and jsonStr ~= "" then
                        local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
                        if ok and data then
                            state.reputation = data.reputation or 0
                            if data.paths then
                                state.paths.commander = data.paths.commander or 0
                                state.paths.warfare = data.paths.warfare or 0
                                state.paths.economy = data.paths.economy or 0
                            end
                        end
                    end
                    loaded = true
                    print("[TS] Talent data loaded: rep=" .. state.reputation)
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[TS] Talent load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function TS.saveToCloud()
    if clientCloud then
        local jsonStr = require("cjson").encode({
            reputation = state.reputation,
            paths = state.paths,
        })
        clientCloud:BatchSet()
            :Set("talent_data", jsonStr)
            :Save("天赋进度", {
                ok = function() print("[TS] Talent data saved") end,
                error = function(_, reason) print("[TS] Talent save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 天赋操作
-- ============================================================================

--- 解锁路线的下一个节点
--- @param pathId string "commander"|"warfare"|"economy"
--- @return boolean success
--- @return string|nil errorMsg
function TS.unlockNext(pathId)
    local pathConfig = CONFIG.TalentPaths[pathId]
    if not pathConfig then return false, "无效路线" end

    local currentLevel = state.paths[pathId] or 0
    if currentLevel >= #pathConfig.nodes then return false, "已满级" end

    local nextNode = pathConfig.nodes[currentLevel + 1]
    if state.reputation < nextNode.cost then
        return false, "声望不足（需要 " .. nextNode.cost .. "，当前 " .. state.reputation .. "）"
    end

    state.reputation = state.reputation - nextNode.cost
    state.paths[pathId] = currentLevel + 1
    TS.saveToCloud()
    return true
end

--- 重置所有天赋（免费洗点），返还声望
function TS.resetAll()
    local refund = 0
    for pathId, level in pairs(state.paths) do
        local pathConfig = CONFIG.TalentPaths[pathId]
        if pathConfig then
            for i = 1, level do
                refund = refund + pathConfig.nodes[i].cost
            end
        end
        state.paths[pathId] = 0
    end
    state.reputation = state.reputation + refund
    TS.saveToCloud()
    return refund
end

--- 添加声望点数（关卡首通/无尽结算时调用）
function TS.addReputation(amount)
    state.reputation = state.reputation + amount
    TS.saveToCloud()
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function TS.isLoaded() return loaded end
function TS.getReputation() return state.reputation end

--- 获取路线当前解锁等级
function TS.getPathLevel(pathId)
    return state.paths[pathId] or 0
end

--- 获取路线配置
function TS.getPathConfig(pathId)
    return CONFIG.TalentPaths[pathId]
end

--- 获取下一个可解锁节点信息（或 nil 表示满级）
function TS.getNextNode(pathId)
    local pathConfig = CONFIG.TalentPaths[pathId]
    if not pathConfig then return nil end
    local level = state.paths[pathId] or 0
    if level >= #pathConfig.nodes then return nil end
    return pathConfig.nodes[level + 1]
end

--- 收集所有已解锁天赋的累积效果
--- @return table effects 合并后的效果表
function TS.getActiveEffects()
    local effects = {
        formationBuffMul = 1.0,
        unitCapBonus = 0,
        formationCdReduce = 0,
        atkMul = 1.0,
        critChance = 0,
        specialSlotReduce = 0,
        critDamageMul = 1.0,
        startResourceMul = 1.0,
        codexExpMul = 1.0,
        shopDiscount = 1.0,
    }

    for pathId, level in pairs(state.paths) do
        local pathConfig = CONFIG.TalentPaths[pathId]
        if pathConfig then
            for i = 1, level do
                local eff = pathConfig.nodes[i].effect
                -- 乘法类效果：叠乘
                if eff.formationBuffMul then effects.formationBuffMul = effects.formationBuffMul * eff.formationBuffMul end
                if eff.atkMul then effects.atkMul = effects.atkMul * eff.atkMul end
                if eff.critDamageMul then effects.critDamageMul = effects.critDamageMul * eff.critDamageMul end
                if eff.startResourceMul then effects.startResourceMul = effects.startResourceMul * eff.startResourceMul end
                if eff.codexExpMul then effects.codexExpMul = effects.codexExpMul * eff.codexExpMul end
                if eff.shopDiscount then effects.shopDiscount = effects.shopDiscount * eff.shopDiscount end
                -- 加法类效果：累加
                if eff.unitCapBonus then effects.unitCapBonus = effects.unitCapBonus + eff.unitCapBonus end
                if eff.formationCdReduce then effects.formationCdReduce = effects.formationCdReduce + eff.formationCdReduce end
                if eff.critChance then effects.critChance = effects.critChance + eff.critChance end
                if eff.specialSlotReduce then effects.specialSlotReduce = effects.specialSlotReduce + eff.specialSlotReduce end
            end
        end
    end

    return effects
end

--- 获取旧版兼容接口（Combat 等模块查询用）
function TS.getActiveTalent()
    return nil  -- 旧版单选天赋已废弃，各系统改为查询 getActiveEffects()
end

function TS.init(config)
    -- 保持旧接口兼容，新版无需传入 CONFIG（直接 require）
end

return TS
```

- [ ] **Step 3: Update Combat.lua to use new talent effects**

In `scripts/Combat.lua`, replace any `TS.getActiveTalent()` checks with the new effects system. Locate the `eagle_eye` talent check in FollowerAI (if any) and the `iron_vanguard` check in Combat, and replace:

```lua
-- 旧代码（删除）：
-- if TS.getActiveTalent() == "iron_vanguard" then dmg = dmg * 1.1 end

-- 新代码：
local talentEffects = TS.getActiveEffects()
dmg = dmg * talentEffects.atkMul

-- 暴击
if talentEffects.critChance > 0 and math.random() < talentEffects.critChance then
    dmg = math.floor(dmg * talentEffects.critDamageMul)
end
```

- [ ] **Step 4: Update FormationSystem buff application to use talent multiplier**

In `scripts/Combat.lua`, in the formation buff block of `calcUnitDamage`, wrap the formation buff with talent multiplier:

```lua
    -- 阵型加成（乘以天赋 formationBuffMul）
    if attackerLordId then
        local formId = GS.getFormationId(attackerLordId)
        local buffs = FormationSystem.getBuffs(formId)
        if buffs.allStatsMul then
            local boosted = buffs.allStatsMul
            -- 天赋增强阵型加成
            local talentEff = TS.getActiveEffects()
            local bonusPart = boosted - 1.0  -- 例如 1.10 → 0.10
            bonusPart = bonusPart * talentEff.formationBuffMul  -- 例如 0.10 * 1.05 → 0.105
            dmg = dmg * (1.0 + bonusPart)
        end
        -- ... 其他阵型加成保持不变
    end
```

- [ ] **Step 5: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. Old talent system replaced.

- [ ] **Step 6: Commit**

```
git add scripts/Config.lua scripts/TalentSystem.lua scripts/Combat.lua
git commit -m "feat: redesign TalentSystem to 3-path tree with reputation"
```

---

### Task 13: Special Unit Skills — 4 New Skills in SkillSystem

**Files:**
- Modify: `scripts/Config.lua`
- Modify: `scripts/SkillSystem.lua`

- [ ] **Step 1: Add special unit skill configs in Config.lua**

In `CONFIG.Skills`, add 4 new entries:

```lua
    -- 特殊兵种技能（由阵型中对应兵种自动触发）
    advisorReveal = {
        name = "洞察全局",
        desc = "军师揭示附近迷雾，标记隐藏敌人",
        cd = 30,
        duration = 8,
        revealRadius = 400,
    },
    drummerWarDrum = {
        name = "战鼓激励",
        desc = "鼓手擂鼓，周围友军攻速+30%",
        cd = 25,
        duration = 6,
        buffRadius = 200,
        atkSpeedMul = 1.3,
    },
    paladinShield = {
        name = "神圣护盾",
        desc = "圣骑士释放护盾，周围友军免疫伤害",
        cd = 40,
        duration = 3,
        shieldRadius = 150,
    },
    assassinStrike = {
        name = "暗影突袭",
        desc = "刺客潜行至目标身后，造成3倍伤害",
        cd = 20,
        stealthDuration = 2,
        damageMul = 3.0,
        targetSearchRadius = 300,
    },
```

- [ ] **Step 2: Add skill entries to SkillSystem**

In `scripts/SkillSystem.lua`, expand `SKILL_ORDER` and `SKILL_NAMES`:

```lua
local SKILL_ORDER = { "dash", "focusFire", "barricade", "repel", "bloodSacrifice", "bounty",
                       "advisorReveal", "drummerWarDrum", "paladinShield", "assassinStrike" }

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
```

In `SkillSystem.init()`, add new state fields:

```lua
    GS.advisorRevealState = nil   -- { active=bool, x, y, timer, radius }
    GS.drummerBuffState = nil     -- { active=bool, x, y, timer, radius, mul }
    GS.paladinShieldState = nil   -- { active=bool, x, y, timer, radius }
    GS.assassinStrikeState = nil  -- { active=bool, unitId, targetId, timer, phase }
```

- [ ] **Step 3: Implement _activate and _update for each special skill**

Add these functions before the `return SkillSystem` line:

```lua
-- ============================================================================
-- 军师：洞察全局
-- ============================================================================

local function _activateAdvisorReveal(lord)
    -- 找到该领主的军师单位
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

local function _activateDrummerWarDrum(lord)
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

local function _activatePaladinShield(lord)
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
        followUnit = paladin,  -- 护盾跟随圣骑士移动
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

local function _activateAssassinStrike(lord)
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
        phase = "stealth",  -- "stealth" → "strike"
        damageMul = cfg.damageMul,
    }
    -- 刺客进入隐身状态
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
        -- 隐身期间快速移向目标背后
        local dx, dy = Utils.normalize(target.x - assassin.x, target.y - assassin.y)
        assassin.x = assassin.x + dx * CONFIG.FollowerSpeed * 3.0 * dt
        assassin.y = assassin.y + dy * CONFIG.FollowerSpeed * 3.0 * dt

        local dist = Utils.dist(assassin.x, assassin.y, target.x, target.y)
        if dist < 15 or s.timer <= 0 then
            -- 到达目标身边：执行致命一击
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
```

- [ ] **Step 4: Wire up activation and update in SkillSystem**

In `SkillSystem.canActivate(skillId)` (or where activation is checked), add entries for the new skills:

```lua
    -- 特殊兵种技能只有拥有对应兵种时才能激活
    if skillId == "advisorReveal" then
        return hasUnitType(lord, "advisor")
    elseif skillId == "drummerWarDrum" then
        return hasUnitType(lord, "drummer")
    elseif skillId == "paladinShield" then
        return hasUnitType(lord, "paladin")
    elseif skillId == "assassinStrike" then
        return hasUnitType(lord, "assassin")
    end
```

Add helper `hasUnitType`:

```lua
local function hasUnitType(lord, fType)
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lord.id and f.fType == fType then return true end
    end
    return false
end
```

In `SkillSystem.activate(skillId)`, add dispatch entries:

```lua
    elseif skillId == "advisorReveal" then
        return _activateAdvisorReveal(lord)
    elseif skillId == "drummerWarDrum" then
        return _activateDrummerWarDrum(lord)
    elseif skillId == "paladinShield" then
        return _activatePaladinShield(lord)
    elseif skillId == "assassinStrike" then
        return _activateAssassinStrike(lord)
```

In `SkillSystem.update(dt)`, add update calls:

```lua
    _updateAdvisorReveal(dt)
    _updateDrummerWarDrum(dt)
    _updatePaladinShield(dt)
    _updateAssassinStrike(dt)
```

- [ ] **Step 5: Integrate shield check in Combat.lua**

In `scripts/Combat.lua`, before applying damage to a follower, add shield check:

```lua
    -- 圣骑士护盾免疫
    if SkillSystem.isShielded(defender.x, defender.y, defender.factionId) then
        -- 免疫伤害，显示 "护盾" 文字
        Entities.spawnDamageNumber(defender.x, defender.y, 0, 200, 200, 255)
        return  -- 跳过伤害
    end
```

- [ ] **Step 6: Integrate drummer buff in Combat.lua**

In `calcUnitDamage`, factor in drummer buff:

```lua
    -- 鼓手攻速加成（影响 DPS，通过攻击倍率间接体现）
    -- 注：攻速实际在 FollowerAI 的攻击间隔中处理，这里无需修改
    -- 但鼓手 buff 提升攻击力也合理，在此叠加
```

Actually, the drummer buff is an attack *speed* multiplier. This is applied in FollowerAI's attack interval logic, not in damage calculation. In `scripts/FollowerAI.lua`, in the melee attack timer check:

```lua
    -- 鼓手攻速加成
    local drummerMul = SkillSystem.getDrummerAtkSpeedMul(f.x, f.y, f.factionId)
    local effectiveInterval = atkInterval / drummerMul  -- 间隔缩短 = 攻速提升
```

- [ ] **Step 7: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. 4 new special unit skills operational.

- [ ] **Step 8: Commit**

```
git add scripts/Config.lua scripts/SkillSystem.lua scripts/Combat.lua scripts/FollowerAI.lua
git commit -m "feat: add 4 special unit skills (advisor, drummer, paladin, assassin)"
```

---

### Task 14: Integrate Codex Experience with Talent Bonus

**Files:**
- Modify: `scripts/CodexState.lua`
- Modify: `scripts/Combat.lua`

- [ ] **Step 1: Apply talent codexExpMul in CodexState.recordKill**

In `scripts/CodexState.lua`, add at top:

```lua
local TS = require("TalentSystem")
```

Modify `recordKill`:

```lua
function CXS.recordKill(unitId)
    ensureEntry(unitId)
    units[unitId].kills = units[unitId].kills + 1
    -- 经验获取受天赋加成
    local talentEffects = TS.getActiveEffects()
    local expGain = math.floor(1 * talentEffects.codexExpMul)
    units[unitId].exp = units[unitId].exp + math.max(1, expGain)
end
```

- [ ] **Step 2: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
git add scripts/CodexState.lua
git commit -m "feat: talent codexExpMul bonus applied to codex kills"
```

---

## Phase 4: Endless Mode, Squad System & Final Integration

### Task 15: EndlessMode.lua — Wave Controller

**Files:**
- Create: `scripts/EndlessMode.lua`
- Modify: `scripts/GameState.lua`

- [ ] **Step 1: Add endless-mode fields to GameState.lua**

In `scripts/GameState.lua`, add these fields inside the GS table (after `minimapExpanded`):

```lua
    -- 无尽模式状态
    endlessWave = 0,            -- 当前波次
    endlessState = "idle",      -- idle, fighting, shop, settled
    endlessWaveTimer = 0,       -- 波次内计时
    endlessEnemies = {},        -- 当前波敌人 (lordId of wave-lord)
    endlessWarCoins = 0,        -- 战功币（当局货币）
    endlessBestWave = 0,        -- 历史最高波次（云端读取）
    endlessBuffs = {},          -- 商店购买的临时/永久增益
```

- [ ] **Step 2: Create EndlessMode.lua core module**

Create `scripts/EndlessMode.lua`:

```lua
-- ============================================================================
-- EndlessMode.lua — 无尽模式流程控制
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Entities = require("Entities")
local Utils = require("Utils")
local TS = require("TalentSystem")
local CodexState = require("CodexState")
local ShopSystem -- forward-declared, loaded lazily to break circular dep

local EM = {}

-- =========================================================================
-- 难度曲线配置
-- =========================================================================
local WAVE_CONFIG = {
    baseEnemyCount   = 5,      -- 第 1 波敌兵数
    countGrowthPct   = 10,     -- 每波兵力 +10%
    eliteInterval    = 5,      -- 每 5 波一次精英波
    bossInterval     = 10,     -- 每 10 波一次 Boss 波
    formationWave    = 10,     -- 第 10 波起敌方使用阵型
    specialUnitWave  = 20,     -- 第 20 波起敌方出现特殊兵种
    warCoinPerKill   = 2,      -- 每击杀获得战功币
    eliteCoinMul     = 2,      -- 精英波双倍货币
}

-- 根据波次决定敌方可用兵种列表
local function getEnemyUnitPool(wave)
    local pool = { "soldier", "archer" }
    if wave >= 3 then pool[#pool + 1] = "knight" end
    if wave >= 5 then pool[#pool + 1] = "spearman" end
    if wave >= 8 then pool[#pool + 1] = "mage" end
    if wave >= 12 then pool[#pool + 1] = "mounted_archer" end
    if wave >= WAVE_CONFIG.specialUnitWave then
        pool[#pool + 1] = "paladin"
        pool[#pool + 1] = "assassin"
    end
    return pool
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
    local pool = getEnemyUnitPool(wave)
    for i = 1, count do
        local unitType = pool[math.random(1, #pool)]
        Entities.createFollower(waveLord, unitType)
    end

    -- 第 10 波起敌方使用阵型（设计规范 §7.3）
    if wave >= WAVE_CONFIG.formationWave then
        local formations = { "cone", "phalanx", "arc", "crane_wing" }
        local pick = formations[math.random(1, #formations)]
        GS.setFormation(waveLord.id, pick)
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
```

- [ ] **Step 3: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. Module loads without runtime error.

- [ ] **Step 4: Commit**

```bash
git add scripts/EndlessMode.lua scripts/GameState.lua
git commit -m "feat: add EndlessMode wave controller with difficulty scaling"
```

---

### Task 16: ShopSystem.lua — Endless Mode Shop

**Files:**
- Create: `scripts/ShopSystem.lua`

- [ ] **Step 1: Create ShopSystem.lua with 3-tier item pools**

Create `scripts/ShopSystem.lua`:

```lua
-- ============================================================================
-- ShopSystem.lua — 无尽模式商店（商品池、刷新、购买）
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Entities = require("Entities")
local EndlessMode -- lazy-loaded to break circular dep

local Shop = {}

-- =========================================================================
-- 商品池定义
-- =========================================================================

-- 每个商品: { id, name, desc, cost, tier, apply(playerLord) }
-- tier: "normal" | "rare" | "legendary"

local ALL_ITEMS = {
    -- ===== 普通 (每波可出) =====
    {
        id = "recruit_soldiers_3", name = "补充 3 个士兵",
        desc = "立即招募 3 个士兵", cost = 15, tier = "normal",
        apply = function(lord)
            for i = 1, 3 do Entities.createFollower(lord, "soldier") end
        end,
    },
    {
        id = "heal_all_20", name = "全军回复 20%",
        desc = "所有随从回复 20% 生命", cost = 10, tier = "normal",
        apply = function(lord)
            for _, f in ipairs(GS.followers) do
                if f.lordId == lord.id and f.alive then
                    f.hp = math.min(f.maxHp, f.hp + math.floor(f.maxHp * 0.2))
                end
            end
        end,
    },
    {
        id = "temp_atk_10", name = "攻击 +10%（3 波）",
        desc = "全军攻击临时提升 10%", cost = 12, tier = "normal",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "atkMul", value = 1.1, remaining = 3, permanent = false,
            })
        end,
    },
    {
        id = "recruit_archers_2", name = "补充 2 个弓箭手",
        desc = "立即招募 2 个弓箭手", cost = 18, tier = "normal",
        apply = function(lord)
            for i = 1, 2 do Entities.createFollower(lord, "archer") end
        end,
    },
    {
        id = "recruit_knights_2", name = "补充 2 个骑士",
        desc = "立即招募 2 个骑士", cost = 20, tier = "normal",
        apply = function(lord)
            for i = 1, 2 do Entities.createFollower(lord, "knight") end
        end,
    },
    {
        id = "lord_heal_full", name = "领主满血恢复",
        desc = "领主生命值完全回满", cost = 8, tier = "normal",
        apply = function(lord)
            lord.hp = lord.maxHp
        end,
    },
    -- ===== 稀有 (每 5 波新增) =====
    {
        id = "recruit_special_1", name = "招募 1 个特殊兵种",
        desc = "随机招募一个圣骑/刺客/鼓手", cost = 30, tier = "rare",
        apply = function(lord)
            local specials = { "paladin", "assassin", "drummer" }
            local pick = specials[math.random(1, #specials)]
            Entities.createFollower(lord, pick)
        end,
    },
    {
        id = "armor_20_perm", name = "全军护甲 +20%（永久）",
        desc = "本局剩余所有波次生效", cost = 35, tier = "rare",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "armorMul", value = 0.8, remaining = 999, permanent = true,
            })
        end,
    },
    {
        id = "recruit_spearman_3", name = "补充 3 个枪兵",
        desc = "立即招募 3 个枪兵", cost = 25, tier = "rare",
        apply = function(lord)
            for i = 1, 3 do Entities.createFollower(lord, "spearman") end
        end,
    },
    {
        id = "heal_all_50", name = "全军回复 50%",
        desc = "所有随从回复 50% 生命", cost = 28, tier = "rare",
        apply = function(lord)
            for _, f in ipairs(GS.followers) do
                if f.lordId == lord.id and f.alive then
                    f.hp = math.min(f.maxHp, f.hp + math.floor(f.maxHp * 0.5))
                end
            end
        end,
    },
    -- ===== 传说 (每 10 波新增) =====
    {
        id = "capacity_5", name = "编制上限 +5",
        desc = "永久增加可带兵数量", cost = 50, tier = "legendary",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "unitCapBonus", value = 5, remaining = 999, permanent = true,
            })
        end,
    },
    {
        id = "formation_double_5", name = "阵型加成翻倍（5 波）",
        desc = "所有阵型效果翻倍", cost = 45, tier = "legendary",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "formationBuffMul", value = 2.0, remaining = 5, permanent = false,
            })
        end,
    },
    {
        id = "skill_cd_reset", name = "技能冷却清零",
        desc = "所有领主技能立即可用", cost = 40, tier = "legendary",
        apply = function(lord)
            for k, _ in pairs(GS.skillCooldowns) do
                GS.skillCooldowns[k] = 0
            end
        end,
    },
}

-- =========================================================================
-- 状态
-- =========================================================================
local currentItems = {}   -- 当前展示的 4 件商品

-- =========================================================================
-- 刷新
-- =========================================================================

--- 按波次刷新商店（每波 4 件）
function Shop.refresh(wave)
    local pool = {}
    for _, item in ipairs(ALL_ITEMS) do
        if item.tier == "normal" then
            table.insert(pool, item)
        elseif item.tier == "rare" and wave >= 5 then
            table.insert(pool, item)
        elseif item.tier == "legendary" and wave >= 10 then
            table.insert(pool, item)
        end
    end

    -- 天赋折扣（shopDiscount 为乘数：0.90 表示打九折，即付原价的 90%）
    local talentEffects = require("TalentSystem").getActiveEffects()
    local discountMul = talentEffects.shopDiscount or 1.0

    -- 随机抽取 4 件（不重复）
    currentItems = {}
    local poolCopy = {}
    for i, v in ipairs(pool) do poolCopy[i] = v end

    local pickCount = math.min(4, #poolCopy)
    for i = 1, pickCount do
        local idx = math.random(1, #poolCopy)
        local item = poolCopy[idx]
        -- 应用折扣（直接乘以折扣乘数）
        local finalCost = math.max(1, math.floor(item.cost * discountMul))
        table.insert(currentItems, {
            id = item.id,
            name = item.name,
            desc = item.desc,
            cost = finalCost,
            tier = item.tier,
            apply = item.apply,
        })
        table.remove(poolCopy, idx)
    end
end

-- =========================================================================
-- 购买
-- =========================================================================

--- 购买商品（index: 1-4）
function Shop.buy(index)
    EndlessMode = EndlessMode or require("EndlessMode")
    local item = currentItems[index]
    if not item then
        print("[SHOP] Invalid item index: " .. tostring(index))
        return false
    end
    if not EndlessMode.spendCoins(item.cost) then
        print("[SHOP] Not enough war coins (" .. GS.endlessWarCoins .. " < " .. item.cost .. ")")
        return false
    end

    -- 找到玩家领主
    local playerLord = GS.lords[1]
    if playerLord and playerLord.alive then
        item.apply(playerLord)
    end

    -- 移除已购买商品
    table.remove(currentItems, index)
    print("[SHOP] Bought: " .. item.name)
    return true
end

-- =========================================================================
-- 查询
-- =========================================================================

--- 获取当前商店商品列表（UI 用）
function Shop.getItems()
    local result = {}
    for i, item in ipairs(currentItems) do
        result[i] = {
            id = item.id,
            name = item.name,
            desc = item.desc,
            cost = item.cost,
            tier = item.tier,
        }
    end
    return result
end

--- 获取无尽模式 buff 的攻击倍率（Combat.lua 调用）
function Shop.getEndlessAtkMul()
    local mul = 1.0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "atkMul" and buff.remaining > 0 then
            mul = mul * buff.value
        end
    end
    return mul
end

--- 获取无尽模式 buff 的护甲倍率（Combat.lua 调用）
function Shop.getEndlessArmorMul()
    local mul = 1.0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "armorMul" and buff.remaining > 0 then
            mul = mul * buff.value
        end
    end
    return mul
end

--- 获取阵型加成倍率（FormationSystem 调用）
function Shop.getEndlessFormationMul()
    local mul = 1.0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "formationBuffMul" and buff.remaining > 0 then
            mul = mul * buff.value
        end
    end
    return mul
end

--- 获取编制上限加成（Entities/UI 调用）
function Shop.getEndlessCapBonus()
    local bonus = 0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "unitCapBonus" and buff.remaining > 0 then
            bonus = bonus + buff.value
        end
    end
    return bonus
end

--- 波次结束时递减临时 buff 计数器
function Shop.tickBuffs()
    for i = #GS.endlessBuffs, 1, -1 do
        local buff = GS.endlessBuffs[i]
        if not buff.permanent then
            buff.remaining = buff.remaining - 1
            if buff.remaining <= 0 then
                table.remove(GS.endlessBuffs, i)
            end
        end
    end
end

return Shop
```

- [ ] **Step 2: Integrate buff tick into EndlessMode.nextWave**

In `scripts/EndlessMode.lua`, at the top of `EM.nextWave()`, before incrementing wave counter, add:

```lua
function EM.nextWave()
    -- 递减临时 buff（每进入新一波减 1 次）
    if GS.endlessWave > 0 then
        ShopSystem = ShopSystem or require("ShopSystem")
        ShopSystem.tickBuffs()
    end

    GS.endlessWave = GS.endlessWave + 1
    -- ... rest unchanged
```

- [ ] **Step 3: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add scripts/ShopSystem.lua scripts/EndlessMode.lua
git commit -m "feat: add ShopSystem with 3-tier item pools and buff management"
```

---

### Task 17: SquadSystem.lua — Vice General Sub-Formation

**Files:**
- Create: `scripts/SquadSystem.lua`
- Modify: `scripts/GameState.lua`
- Modify: `scripts/FollowerAI.lua`

- [ ] **Step 1: Add squad fields to GameState.lua**

In `scripts/GameState.lua`, add after the endless-mode fields:

```lua
    -- 副将小队
    squads = {},                -- lordId -> { squadLeaderId, memberIds, formation, state }
```

- [ ] **Step 2: Create SquadSystem.lua**

Create `scripts/SquadSystem.lua`:

```lua
-- ============================================================================
-- SquadSystem.lua — 副将小队管理（分兵、归队、独立 AI）
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local SQ = {}

-- =========================================================================
-- 分兵：将指定随从分配给副将，组成小队
-- =========================================================================

--- 创建副将小队
--- @param lordId number 所属领主 ID
--- @param viceGeneralId number 副将随从 ID
--- @param memberIds number[] 分配给小队的随从 ID 列表
--- @param formation string|nil 小队阵型（可选，默认跟随主队）
function SQ.createSquad(lordId, viceGeneralId, memberIds, formation)
    if not GS.squads then GS.squads = {} end

    -- 设计规范：同一时间最多 1 个副将小队生效
    if GS.squads[lordId] and #GS.squads[lordId] >= 1 then
        print("[SQUAD] Lord " .. lordId .. " already has an active squad — disband first")
        return false
    end

    -- 验证副将存在
    local vg = nil
    for _, f in ipairs(GS.followers) do
        if f.id == viceGeneralId and f.alive and f.fType == "vice_general" then
            vg = f
            break
        end
    end
    if not vg then
        print("[SQUAD] Vice general not found: " .. tostring(viceGeneralId))
        return false
    end

    -- 验证成员存在且属于同一领主
    local validMembers = {}
    for _, mid in ipairs(memberIds) do
        for _, f in ipairs(GS.followers) do
            if f.id == mid and f.alive and f.lordId == lordId and f.id ~= viceGeneralId then
                table.insert(validMembers, mid)
                break
            end
        end
    end

    local squad = {
        squadLeaderId = viceGeneralId,
        lordId = lordId,
        memberIds = validMembers,
        formation = formation or "circle",
        state = "active",     -- active, returning
        targetX = vg.x,
        targetY = vg.y,
        aiTimer = 0,
    }

    GS.squads[lordId] = GS.squads[lordId] or {}
    table.insert(GS.squads[lordId], squad)

    -- 标记成员归属小队
    vg.squadRole = "leader"
    vg.squadIdx = #GS.squads[lordId]
    for _, mid in ipairs(validMembers) do
        for _, f in ipairs(GS.followers) do
            if f.id == mid then
                f.squadRole = "member"
                f.squadLeaderId = viceGeneralId
                break
            end
        end
    end

    print("[SQUAD] Created squad with " .. #validMembers .. " members under vice general " .. viceGeneralId)
    return true
end

-- =========================================================================
-- 归队：解散小队，成员回到主队
-- =========================================================================

function SQ.disbandSquad(lordId, squadIndex)
    if not GS.squads or not GS.squads[lordId] then return end
    local squad = GS.squads[lordId][squadIndex]
    if not squad then return end

    -- 清除成员标记
    for _, f in ipairs(GS.followers) do
        if f.squadLeaderId == squad.squadLeaderId then
            f.squadRole = nil
            f.squadLeaderId = nil
        end
        if f.id == squad.squadLeaderId then
            f.squadRole = nil
            f.squadIdx = nil
        end
    end

    table.remove(GS.squads[lordId], squadIndex)
    print("[SQUAD] Disbanded squad " .. squadIndex .. " for lord " .. lordId)
end

--- 解散领主的所有小队
function SQ.disbandAll(lordId)
    if not GS.squads or not GS.squads[lordId] then return end
    while #GS.squads[lordId] > 0 do
        SQ.disbandSquad(lordId, #GS.squads[lordId])
    end
end

-- =========================================================================
-- 小队 AI（每帧调用）
-- =========================================================================

function SQ.update(dt)
    if not GS.squads then return end
    for lordId, squads in pairs(GS.squads) do
        for i = #squads, 1, -1 do
            local squad = squads[i]
            SQ.updateSquadAI(squad, dt)
            -- 如果副将死亡，自动解散
            local leaderAlive = false
            for _, f in ipairs(GS.followers) do
                if f.id == squad.squadLeaderId and f.alive then
                    leaderAlive = true
                    break
                end
            end
            if not leaderAlive then
                SQ.disbandSquad(lordId, i)
            end
        end
    end
end

--- 单个小队的 AI 决策
function SQ.updateSquadAI(squad, dt)
    squad.aiTimer = squad.aiTimer - dt
    if squad.aiTimer > 0 then return end
    squad.aiTimer = 0.8 + math.random() * 0.5

    -- 找到副将
    local leader = nil
    for _, f in ipairs(GS.followers) do
        if f.id == squad.squadLeaderId and f.alive then
            leader = f
            break
        end
    end
    if not leader then return end

    -- 找到所属领主
    local lord = nil
    for _, l in ipairs(GS.lords) do
        if l.id == squad.lordId and l.alive then
            lord = l
            break
        end
    end
    if not lord then return end

    -- 小队独立 AI：在领主附近一定范围内自主行动
    -- 策略：向最近敌人移动，或在领主后方巡逻
    local nearestEnemy = nil
    local nearestDist = 999999
    for _, f in ipairs(GS.followers) do
        if f.alive and f.factionId ~= leader.factionId then
            local d = Utils.dist(leader.x, leader.y, f.x, f.y)
            if d < 300 and d < nearestDist then
                nearestDist = d
                nearestEnemy = f
            end
        end
    end

    if nearestEnemy then
        -- 有敌人时追击
        squad.targetX = nearestEnemy.x
        squad.targetY = nearestEnemy.y
    else
        -- 无敌人时在领主侧后方巡逻
        local offsetAngle = lord.angle + math.pi + (math.random() - 0.5) * 1.0
        local patrolDist = 100 + math.random() * 80
        squad.targetX = lord.x + math.cos(offsetAngle) * patrolDist
        squad.targetY = lord.y + math.sin(offsetAngle) * patrolDist
    end

    -- 保持在地图内
    squad.targetX = Utils.clamp(squad.targetX, 50, CONFIG.MapWidth - 50)
    squad.targetY = Utils.clamp(squad.targetY, 50, CONFIG.MapHeight - 50)
end

-- =========================================================================
-- 查询
-- =========================================================================

--- 判断随从是否属于某个小队
function SQ.isInSquad(followerId)
    for _, f in ipairs(GS.followers) do
        if f.id == followerId then
            return f.squadRole ~= nil
        end
    end
    return false
end

--- 获取随从所在小队的目标位置（FollowerAI 调用）
function SQ.getSquadTarget(followerId)
    if not GS.squads then return nil, nil end
    for _, f in ipairs(GS.followers) do
        if f.id == followerId and f.squadLeaderId then
            -- 找到所属小队
            for _, squads in pairs(GS.squads) do
                for _, squad in ipairs(squads) do
                    if squad.squadLeaderId == f.squadLeaderId then
                        return squad.targetX, squad.targetY
                    end
                end
            end
        end
    end
    return nil, nil
end

--- 获取领主的小队列表（UI 用）
function SQ.getSquads(lordId)
    if not GS.squads or not GS.squads[lordId] then return {} end
    local result = {}
    for i, squad in ipairs(GS.squads[lordId]) do
        local memberCount = 0
        for _, mid in ipairs(squad.memberIds) do
            for _, f in ipairs(GS.followers) do
                if f.id == mid and f.alive then
                    memberCount = memberCount + 1
                    break
                end
            end
        end
        result[i] = {
            index = i,
            leaderId = squad.squadLeaderId,
            memberCount = memberCount,
            formation = squad.formation,
            state = squad.state,
        }
    end
    return result
end

return SQ
```

- [ ] **Step 3: Integrate squad target into FollowerAI**

In `scripts/FollowerAI.lua`, at the top add:

```lua
local SquadSystem = require("SquadSystem")
```

In the `updateFollowerAI(f, dt)` function, at the beginning of the "following" state handler (before existing formation/follow logic), add squad override:

```lua
    if f.state == "following" then
        -- 小队成员跟随副将而非领主
        if SquadSystem.isInSquad(f.id) and f.squadRole == "member" then
            local tx, ty = SquadSystem.getSquadTarget(f.id)
            if tx and ty then
                local d = Utils.dist(f.x, f.y, tx, ty)
                if d > 25 then
                    local dx, dy = Utils.normalize(tx - f.x, ty - f.y)
                    local spd = CONFIG.FollowerSpeed * GS.tcGetUnitSpeedMul(f.lordId) * getGlobalSpeedMul()
                    f.x = f.x + dx * spd * dt
                    f.y = f.y + dy * spd * dt
                    f.angle = math.atan2(dy, dx)
                end
                return  -- 小队成员不执行主队跟随逻辑
            end
        end
        -- ... existing following logic continues
```

- [ ] **Step 4: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add scripts/SquadSystem.lua scripts/GameState.lua scripts/FollowerAI.lua
git commit -m "feat: add SquadSystem for vice general sub-formation management"
```

---

### Task 18: Final Integration — Multi-Mode Routing & LordAI Expansion

**Files:**
- Modify: `scripts/main.lua`
- Modify: `scripts/LordAI.lua`
- Modify: `scripts/GameState.lua`
- Modify: `scripts/Combat.lua`

This task wires everything together: the main entry point routes between skirmish/campaign/endless modes, LordAI is expanded to use new unit types, and Combat integrates endless-mode buffs.

- [ ] **Step 1: Verify game mode field in GameState.lua**

> `gameMode` was already added to `scripts/GameState.lua` in Task 5 Step 1. Verify it exists with the correct type annotation:

```lua
    -- 游戏模式（已在 Task 5 添加）
    gameMode = "skirmish",      -- "skirmish" | "campaign" | "endless"
```

If already present, no changes needed. Proceed to Step 2.

- [ ] **Step 2: Expand LordAI to use new unit types**

In `scripts/LordAI.lua`, replace the `countCombatFollowers` usage and upgrade logic.

First, replace the local requires at top to include FormationSystem:

```lua
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")
local FormationSystem = require("FormationSystem")
```

Replace the existing `updateAILord` function's unit-counting block (the first ~15 lines that count peasant/soldier/knight/archer):

```lua
function LordAI.updateAILord(lord, dt)
    lord.aiTimer = lord.aiTimer - dt

    -- 通用计数：使用 CONFIG 分类表
    local totalCombat = 0
    local typeCounts = {}
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            typeCounts[f.fType] = (typeCounts[f.fType] or 0) + 1
            if CONFIG.IsCombatUnit[f.fType] then
                totalCombat = totalCombat + 1
            end
        end
    end
    local peasantCount = typeCounts["peasant"] or 0
```

Replace the upgrade decision block (the section that converts soldiers to knights/archers) with a generalized version:

```lua
    -- AI 兵种升级决策（泛化版 — 根据可用兵种和敌方构成决策）
    if (typeCounts["soldier"] or 0) >= 2 then
        -- 寻找最近敌方领主
        local nearEnemy = nil
        local nearEnemyDist = 999999
        for _, el in ipairs(GS.lords) do
            if el.alive and el.faction ~= lord.faction then
                local d = Utils.dist(lord.x, lord.y, el.x, el.y)
                if d < nearEnemyDist then
                    nearEnemyDist = d
                    nearEnemy = el
                end
            end
        end
        if nearEnemy then
            -- 统计敌方兵种
            local enemyCounts = {}
            for _, f in ipairs(GS.followers) do
                if f.lordId == nearEnemy.id and f.alive then
                    enemyCounts[f.fType] = (enemyCounts[f.fType] or 0) + 1
                end
            end

            -- 升级优先级：缺什么补什么
            local upgrades = {
                -- { targetType, condition, stoneCost, woodCost }
                { "knight",   (enemyCounts["soldier"] or 0) > (enemyCounts["knight"] or 0), CONFIG.KnightCostStone, 0 },
                { "archer",   (enemyCounts["knight"] or 0) > (enemyCounts["soldier"] or 0), CONFIG.ArcherCostStone, CONFIG.ArcherCostWood },
                { "spearman", (enemyCounts["knight"] or 0) + (enemyCounts["mounted_archer"] or 0) > 3, 12, 0 },
            }

            for _, upg in ipairs(upgrades) do
                local targetType, shouldUpgrade, stoneCost, woodCost = upg[1], upg[2], upg[3], upg[4]
                if shouldUpgrade and lord.stone >= stoneCost and lord.wood >= woodCost then
                    for _, f in ipairs(GS.followers) do
                        if f.lordId == lord.id and f.alive and f.fType == "soldier" and f.state == "following" then
                            f.fType = targetType
                            f.hp = CONFIG.UnitStats[targetType].hp
                            f.maxHp = CONFIG.UnitStats[targetType].hp
                            lord.stone = lord.stone - stoneCost
                            lord.wood = lord.wood - woodCost
                            Entities.spawnParticle(f.x, f.y, 255, 200, 50, 3)
                            break
                        end
                    end
                    break  -- 每次决策只升级一个
                end
            end
        end
    end
```

Replace the hardcoded `myCombat = soldierCount + knightCount + archerCount` in the decision tree with `totalCombat`:

```lua
    -- 决策树（使用 totalCombat 替代硬编码的三兵种求和）
    -- 1. 检测附近的Boss
    -- ... (keep existing boss/enemy/loot detection logic unchanged)
    -- ... replace all occurrences of `myCombat` with `totalCombat`
```

In the AI formation switching block at the bottom, add new formation options:

```lua
    -- AI 阵型自动切换（扩展版）
    local currentMode = lord.lordMode or "charge"
    if totalCombat < 3 or lord.hp < lord.maxHp * 0.3 then
        if currentMode ~= "turtle" then
            lord.lordMode = "turtle"
        end
    elseif totalCombat >= 5 and lord.hp > lord.maxHp * 0.6 then
        if currentMode ~= "charge" then
            lord.lordMode = "charge"
        end
    end
```

- [ ] **Step 3: Integrate endless-mode buffs into Combat.lua**

In `scripts/Combat.lua`, add at the top:

```lua
local ShopSystem = require("ShopSystem")
```

In the `calcUnitDamage` function (already modified in Task 6 to accept `attackerLordId`), add endless buff after the formation buff block:

```lua
local function calcUnitDamage(attackerType, defenderType, attackerLordId)
    local stats = CONFIG.UnitStats[attackerType]
    if not stats then return 0 end
    local mul = 1.0
    local mulTable = CONFIG.DamageMultiplier[attackerType]
    if mulTable and mulTable[defenderType] then
        mul = mulTable[defenderType]
    end
    local dmg = stats.atk * mul
    if GS.bloodMoonActive then dmg = dmg * 1.5 end
    -- 阵型攻击 buff（Task 6 中已添加）
    if attackerLordId then
        local formId = GS.getFormationId(attackerLordId)
        local buffs = FormationSystem.getBuffs(formId)
        if buffs.atkMul then dmg = dmg * buffs.atkMul end
    end
    -- 图鉴等级加成（Task 10 中已添加）
    local CodexData = require("CodexData")
    local CodexState = require("CodexState")
    local lvl = CodexState.getLevel(attackerType)
    dmg = dmg * CodexData.getLevelMultiplier(lvl)
    -- 天赋战斗加成（Task 14 中已添加）
    local talentEffects = require("TalentSystem").getActiveEffects()
    if talentEffects.atkBonus then dmg = dmg * (1 + talentEffects.atkBonus) end
    -- 无尽模式攻击 buff
    if GS.gameMode == "endless" then
        dmg = dmg * ShopSystem.getEndlessAtkMul()
    end
    return math.floor(dmg)
end
```

> **Note:** This is the final cumulative version of `calcUnitDamage` incorporating changes from Tasks 6, 10, 14, and 18. The 3-parameter signature `(attackerType, defenderType, attackerLordId)` established in Task 6 is preserved.

In the `applyFormationArmor` function (already renamed in Task 6 from `applyKnightArmor`), add endless armor buff:

```lua
local function applyFormationArmor(dmg, defenderUnit)
    -- 现有骑士铁桶阵减伤
    if defenderUnit.fType == "knight" then
        local armorMul = GS.tcGetKnightArmorMul(defenderUnit.lordId)
        if armorMul < 1.0 then
            dmg = math.floor(dmg * armorMul)
        end
    end
    -- 阵型减伤（Task 6 中已添加）
    local formId = GS.getFormationId(defenderUnit.lordId)
    local buffs = FormationSystem.getBuffs(formId)
    if buffs.armorMul then
        dmg = math.floor(dmg * buffs.armorMul)
    end
    if buffs.damageReductionChance and math.random() < buffs.damageReductionChance then
        dmg = math.floor(dmg * (buffs.damageReductionMul or 0.5))
    end
    -- 无尽模式护甲 buff（适用于所有兵种）
    if GS.gameMode == "endless" then
        dmg = math.floor(dmg * ShopSystem.getEndlessArmorMul())
    end
    return dmg
end
```

> **Note:** This is the final cumulative version of `applyFormationArmor` incorporating changes from Tasks 6 and 18. The function was renamed from `applyKnightArmor` in Task 6.

- [ ] **Step 4: Update main.lua — multi-mode game initialization**

In `scripts/main.lua`, add new module requires at the top (after existing requires):

```lua
local FormationSystem = require("FormationSystem")
local CampaignState = require("CampaignState")
local CodexState = require("CodexState")
local PresetManager = require("PresetManager")
local EndlessMode = require("EndlessMode")
local ShopSystem = require("ShopSystem")
local SquadSystem = require("SquadSystem")
```

Replace the `initGame()` function to support multi-mode:

```lua
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

    GS.tcReset()
    SkillSystem.init()

    -- 创建资源（遭遇战和无尽模式）
    if mode == "skirmish" or mode == "endless" then
        for i = 1, CONFIG.ResourceCount do
            if math.random() < 0.7 then
                Entities.createResource("tree")
            else
                Entities.createResource("mine")
            end
        end
    end

    -- 创建玩家领主
    local playerLord = Entities.createLord(
        CONFIG.MapWidth / 2,
        CONFIG.MapHeight / 2,
        1, true
    )
    for i = 1, CONFIG.InitPeasants do
        Entities.createFollower(playerLord, "peasant")
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
        -- 战役模式：CampaignState 负责创建敌人
        -- （在关卡准备界面确认后由 CampaignState.startLevel 填充）

    elseif mode == "endless" then
        -- 无尽模式：EndlessMode 负责波次生成
        EndlessMode.start()
    end

    -- Boss 计时（遭遇战专属）
    GS.bossSpawnTimer = 0
    GS.nextBossSpawnTime = Utils.randomRange(CONFIG.BossSpawnMin, CONFIG.BossSpawnMax)
    GS.resourceRespawnTimer = 0

    EventSystem.init()

    GS.cameraX = playerLord.x
    GS.cameraY = playerLord.y

    print("=== Game Initialized [" .. mode .. "] ===")
end
```

- [ ] **Step 5: Update updateGame to call new systems**

In `scripts/main.lua`, in the `updateGame(dt)` function, add new system updates after the existing `SkillSystem.update(dt)` line:

```lua
    -- 技能系统更新
    SkillSystem.update(dt)

    -- 阵型冷却更新（Task 5 中定义的 helper）
    GS.updateFormationCooldowns(dt)

    -- 副将小队更新
    SquadSystem.update(dt)

    -- 无尽模式更新
    if GS.gameMode == "endless" then
        EndlessMode.update(dt)
    end
```

Wrap boss spawning in a mode check (only for skirmish):

```lua
    -- Boss 刷新（遭遇战专属）
    if GS.gameMode == "skirmish" then
        GS.bossSpawnTimer = GS.bossSpawnTimer + dt
        if GS.bossSpawnTimer >= GS.nextBossSpawnTime then
            -- ... existing boss spawn logic unchanged
        end
    end
```

- [ ] **Step 6: Update Start() for cloud data orchestration**

In `scripts/main.lua`, modify the `Start()` function's cloud loading to load all cloud modules:

```lua
    -- 加载所有云端数据，完成后显示主菜单
    TS.loadFromCloud(function()
        print("[CLOUD] TalentSystem loaded")
        CodexState.loadFromCloud(function()
            print("[CLOUD] CodexState loaded")
            CampaignState.loadFromCloud(function()
                print("[CLOUD] CampaignState loaded")
                PresetManager.loadFromCloud(function()
                    print("[CLOUD] PresetManager loaded")
                    -- 所有数据加载完成，显示主菜单
                    -- TODO-UI: GameUI.ShowMainMenu 将在 UI 任务中实现
                    -- 临时：直接进入遭遇战（兼容现有流程）
                    GameUI.ShowTalentSelectUI(function() initGame("skirmish") end)
                end)
            end)
        end)
    end)
```

- [ ] **Step 7: Build and verify**

Run: UrhoX MCP build tool
Expected: Build succeeds. Game starts in skirmish mode with existing behavior preserved.

- [ ] **Step 8: Commit**

```bash
git add scripts/main.lua scripts/LordAI.lua scripts/GameState.lua scripts/Combat.lua
git commit -m "feat: multi-mode routing, LordAI expansion, endless buff integration"
```

---

## Post-Implementation Notes

### UI Tasks (Not in This Plan)

The following UI screens are referenced but **intentionally deferred** to a separate UI-focused plan:

1. **Main Menu** — Mode selection (skirmish / campaign / endless / codex / talents / presets)
2. **Campaign Map** — Chapter/level selection with branching routes
3. **Level Preparation** — Enemy intel, squad config, formation selection
4. **Codex Gallery** — Unit cards with level progress bars
5. **Talent Tree UI** — 3-path visual tree with unlock/reset buttons
6. **Preset Editor** — 5-slot save/load interface
7. **Endless Mode HUD** — Wave counter, war coin display, shop overlay
8. **Squad Management Panel** — Drag-assign units to vice general

These screens use `urhox-libs/UI` components and are purely presentational — they call into the modules built in this plan but contain no game logic.

### Renderer Extensions (Not in This Plan)

New unit type rendering (8 additional NanoVG draw functions in Renderer.lua) is deferred to a visual polish pass. During development, new unit types will render using fallback shapes (circle with type-specific color, already handled by the generic `drawFollower` path established in Task 5's `UnitRingColors` expansion).
