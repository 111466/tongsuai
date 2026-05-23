# 战斗血量系统 + 领主即移动据点 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有一击必杀布尔战斗系统改为数值制 HP+伤害系统，同时将独立据点实体合并到领主身上，领主本身即为可移动据点，支持攻击/防守双模式切换。

**Architecture:** Config 新增三张数值表（UnitStats/DamageMultiplier/LordModes）驱动全部战斗和模式逻辑；删除独立 Stronghold 实体，将据点 HP、防御塔、复活逻辑全部迁移到 lord 实体上；GameState 战术指令从三档（default/defend/charge）改为两档（attack/defend）；Combat 从布尔生死表改为 attackTimer 周期性数值伤害。

**Tech Stack:** Lua 5.4, UrhoX NanoVG 渲染, urhox-libs/UI

---

## File Structure

| 操作 | 文件路径 | 职责 |
|------|---------|------|
| Modify | `scripts/Config.lua` | 新增 UnitStats/DamageMultiplier/LordModes 表，删除旧常量 |
| Modify | `scripts/Entities.lua` | follower 新增 hp/maxHp/attackTimer 字段，lord 新增据点字段，删除 knightHP |
| Modify | `scripts/GameState.lua` | 删除 strongholds 数组，三档战术改两档（attack/defend） |
| Modify | `scripts/Combat.lua` | 重写为数值制周期性伤害，删除 COMBAT_TABLE/LORD_DMG_MAP，删除据点攻击代码 |
| Modify | `scripts/Stronghold.lua` | 删除独立据点创建，防御塔迁移到领主，复活改为死亡位置，新增领域伤害 |
| Modify | `scripts/FollowerAI.lua` | 攻击状态下停下互砍（attackTimer），防守模式适配 |
| Modify | `scripts/LordAI.lua` | 删除据点引用，新增双模式自动切换决策 |
| Modify | `scripts/BossSystem.lua` | Boss 对单位改为数值伤害（不再一击杀） |
| Modify | `scripts/Renderer.lua` | 删除 drawStronghold，领主双血条，单位 HP 条，防守光环脉冲 |
| Modify | `scripts/GameUI.lua` | 两个战术按钮合并为一个模式切换按钮，删除 knightHP 赋值 |
| Modify | `scripts/main.lua` | 删除据点创建/渲染/崩溃预警，输入改为单键切换 |

---

### Task 1: Config — 新增数值表 & 清理旧常量

**Files:**
- Modify: `scripts/Config.lua`

- [ ] **Step 1: 新增 UnitStats 表**

在 `CONFIG` 表中 `BossRadius` 行之后（`UnitRingColors` 之前），新增：

```lua
-- ========== 数值制战斗系统 ==========
UnitStats = {
    peasant  = { hp = 20,  atk = 5,  atkInterval = 1.0 },
    soldier  = { hp = 60,  atk = 25, atkInterval = 0.8 },
    knight   = { hp = 120, atk = 35, atkInterval = 1.2 },
    archer   = { hp = 40,  atk = 20, atkInterval = 1.5 },
},
```

- [ ] **Step 2: 新增 DamageMultiplier 表**

紧接 UnitStats 之后新增：

```lua
DamageMultiplier = {
    soldier = { soldier = 1.0, knight = 0.6, archer = 1.5, peasant = 2.0 },
    knight  = { soldier = 1.3, knight = 1.0, archer = 1.0, peasant = 2.0 },
    archer  = { soldier = 0.7, knight = 1.3, archer = 1.0, peasant = 2.0 },
    peasant = { soldier = 0.5, knight = 0.3, archer = 0.5, peasant = 1.0 },
},
```

- [ ] **Step 3: 新增 LordModes 表**

紧接 DamageMultiplier 之后新增：

```lua
LordModes = {
    attack = {
        speedMul = 1.0,
        auraMul = 1.0,
        searchMul = 1.0,
        auraDamage = 0,
        auraDamageToLord = 0,
        auraSlowPct = 0,
        auraDmgInterval = 0.5,
    },
    defend = {
        speedMul = 0.7,
        auraMul = 1.5,
        searchMul = 0.4,
        auraDamage = 10,
        auraDamageToLord = 5,
        auraSlowPct = 0.3,
        auraDmgInterval = 0.5,
    },
},
```

- [ ] **Step 4: 删除旧常量**

从 CONFIG 表中删除以下行（用空行或直接移除）：

```lua
-- 删除这些行：
KnightHP = 2,
LordDamagePerSoldier = 20,
KnightDamageToLord = 35,
ArcherDamageToLord = 15,
StrongholdCollapseTime = 300,
StrongholdAttackDist = 25,
StrongholdUnitDamage = 20,
BossDamagePerSoldier = 20,
```

**保留**以下据点/防御塔常量（仍被领主防御塔使用）：

```lua
StrongholdHP = 300,             -- 据点生命值（领主身上的据点HP初始值）
StrongholdTowerRange = 150,     -- 防御塔射程
StrongholdTowerDamage = 15,     -- 防御塔伤害
StrongholdTowerInterval = 1.5,  -- 防御塔攻击间隔
RespawnTime = 3.0,              -- 复活倒计时
RespawnHpRatio = 0.5,           -- 复活血量比例
```

- [ ] **Step 5: 构建验证**

Run: UrhoX MCP build tool
Expected: 构建成功（其他模块引用已删常量会在后续 Task 修复）

- [ ] **Step 6: Commit**

```bash
git add scripts/Config.lua
git commit -m "feat(Config): add UnitStats/DamageMultiplier/LordModes tables, remove legacy constants"
```

---

### Task 2: Entities — 统一 HP 字段 & 领主据点字段

**Files:**
- Modify: `scripts/Entities.lua`

- [ ] **Step 1: 修改 createFollower — 新增通用 HP 字段，删除 knightHP**

在 `createFollower` 函数中，将：

```lua
        -- 骑士特有
        knightHP = (fType == "knight") and CONFIG.KnightHP or nil,
        -- 弓箭手特有
        fireTimer = (fType == "archer") and 0 or nil,
```

替换为：

```lua
        -- 通用HP系统
        hp = CONFIG.UnitStats[fType].hp,
        maxHp = CONFIG.UnitStats[fType].hp,
        attackTimer = 0,
        -- 弓箭手特有
        fireTimer = (fType == "archer") and 0 or nil,
```

- [ ] **Step 2: 修改 createLord — 新增据点字段**

在 `createLord` 函数的 `aiTargetId = nil,` 之后新增：

```lua
        -- 据点系统（领主即据点）
        strongholdHP = CONFIG.StrongholdHP,
        strongholdMaxHP = CONFIG.StrongholdHP,
        towerActive = true,
        towerTimer = 0,
        lordMode = "attack",    -- "attack" | "defend"
        auraDmgTimer = 0,       -- 领域伤害结算计时器
        deathX = nil,
        deathY = nil,
        -- 模式切换提示
        modeSwitchText = nil,    -- { text, timer }
```

- [ ] **Step 3: Commit**

```bash
git add scripts/Entities.lua
git commit -m "feat(Entities): add hp/maxHp/attackTimer to followers, stronghold fields to lord, remove knightHP"
```

---

### Task 3: GameState — 两档模式系统 & 清理据点状态

**Files:**
- Modify: `scripts/GameState.lua`

- [ ] **Step 1: 删除据点相关状态**

从 GS 表中删除以下行：

```lua
    strongholds = {},
```

和：

```lua
    -- 据点系统
    strongholdCollapseNotified = false,  -- 5分钟崩溃通知标志
```

- [ ] **Step 2: 重写战术指令系统**

将整个战术指令系统部分（从 `local lordTacticalModes = {}` 到 `tcGetLordSpeedMul` 结束）替换为：

```lua
-- ============================================================================
-- 双模式系统（attack / defend）
-- ============================================================================

--- 切换领主模式（attack <-> defend 双向切换）
function GS.tcSetMode(lordId, targetMode)
    -- 找到领主，直接切换 lordMode
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then
            if l.lordMode == targetMode then
                l.lordMode = "attack"  -- 再次按下相同模式 → 回到 attack
            else
                l.lordMode = targetMode
            end
            -- 设置模式切换提示文字
            if l.lordMode == "defend" then
                l.modeSwitchText = { text = "防守！", timer = 1.0, r = 80, g = 140, b = 255 }
            else
                l.modeSwitchText = { text = "进攻！", timer = 1.0, r = 255, g = 80, b = 80 }
            end
            return
        end
    end
end

function GS.tcGetMode(lordId)
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then
            return l.lordMode or "attack"
        end
    end
    return "attack"
end

function GS.tcReset()
    -- 重置所有领主模式为attack
    for _, l in ipairs(GS.lords) do
        l.lordMode = "attack"
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
```

- [ ] **Step 3: 添加 Config 引用**

在文件顶部添加：

```lua
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
```

- [ ] **Step 4: Commit**

```bash
git add scripts/GameState.lua
git commit -m "feat(GameState): replace 3-mode tactical system with 2-mode (attack/defend), remove strongholds state"
```

---

### Task 4: Combat — 数值制周期性伤害

**Files:**
- Modify: `scripts/Combat.lua`

- [ ] **Step 1: 删除旧的布尔表和常量映射**

删除文件顶部的 `COMBAT_TABLE` 整个 table 定义（约30行）和 `LORD_DMG_MAP` 定义。

- [ ] **Step 2: 新增伤害计算辅助函数**

在 `local Combat = {}` 之后新增：

```lua
-- 计算单位对单位的伤害
local function calcUnitDamage(attackerType, defenderType)
    local stats = CONFIG.UnitStats[attackerType]
    if not stats then return 0 end
    local mul = 1.0
    local mulTable = CONFIG.DamageMultiplier[attackerType]
    if mulTable and mulTable[defenderType] then
        mul = mulTable[defenderType]
    end
    local dmg = stats.atk * mul
    if GS.bloodMoonActive then dmg = dmg * 1.5 end
    return math.floor(dmg)
end

-- 获取单位半径
local function getUnitRadius(fType)
    if fType == "peasant" then return CONFIG.PeasantRadius
    elseif fType == "knight" then return CONFIG.KnightRadius
    elseif fType == "archer" then return CONFIG.ArcherRadius
    else return CONFIG.SoldierRadius end
end
```

- [ ] **Step 3: 重写 processCombat — 单位 vs 单位（周期性互砍）**

将整个 `Combat.processCombat()` 函数体替换为：

```lua
function Combat.processCombat(dt)
    -- 战斗单位 vs 战斗单位（近战碰撞 → 周期性伤害）
    for i = 1, #GS.followers do
        local fa = GS.followers[i]
        if fa.alive and fa.fType ~= "archer" and fa.state == "attacking" then
            for j = 1, #GS.followers do
                if i ~= j then
                    local fb = GS.followers[j]
                    if fb.alive and fb.factionId ~= fa.factionId then
                        local d = Utils.dist(fa.x, fa.y, fb.x, fb.y)
                        local raA = getUnitRadius(fa.fType)
                        local raB = getUnitRadius(fb.fType)
                        local hitDist = (raA + raB) * 0.8
                        if d < hitDist then
                            -- 在碰撞距离内：周期性攻击
                            fa.attackTimer = fa.attackTimer - dt
                            if fa.attackTimer <= 0 then
                                local dmg = calcUnitDamage(fa.fType, fb.fType)
                                fb.hp = fb.hp - dmg
                                fa.attackTimer = CONFIG.UnitStats[fa.fType].atkInterval
                                Entities.spawnDamageNumber(fb.x, fb.y, dmg, 255, 80, 80)
                                Entities.spawnParticle((fa.x + fb.x)/2, (fa.y + fb.y)/2, 255, 200, 50, 3)
                            end
                            -- 反击：被攻击方也可以攻击回来
                            if fb.fType ~= "archer" and fb.state == "attacking" then
                                fb.attackTimer = fb.attackTimer - dt
                                if fb.attackTimer <= 0 then
                                    local dmgBack = calcUnitDamage(fb.fType, fa.fType)
                                    fa.hp = fa.hp - dmgBack
                                    fb.attackTimer = CONFIG.UnitStats[fb.fType].atkInterval
                                    Entities.spawnDamageNumber(fa.x, fa.y, dmgBack, 255, 80, 80)
                                end
                            end
                            -- 检查死亡
                            if fa.hp <= 0 then fa.alive = false end
                            if fb.hp <= 0 then fb.alive = false end
                            -- 存活方重置到跟随状态寻找下一目标
                            if fa.alive and not fb.alive then
                                fa.state = "following"
                                fa.targetId = nil
                            end
                            if fb.alive and not fa.alive then
                                fb.state = "following"
                                fb.targetId = nil
                            end
                            break  -- fa 本轮只与一个敌人交战
                        end
                    end
                end
            end
        end
    end

    -- 战斗单位 vs 领主（持续输出，不再自杀）
    for i = 1, #GS.followers do
        local f = GS.followers[i]
        if f.alive and (f.fType == "soldier" or f.fType == "knight") and f.state == "attacking" then
            for _, l in ipairs(GS.lords) do
                if l.alive and l.faction ~= f.factionId then
                    local d = Utils.dist(f.x, f.y, l.x, l.y)
                    local fRadius = getUnitRadius(f.fType)
                    if d < (fRadius + CONFIG.LordRadiusMin) * 0.8 then
                        -- 周期性攻击领主
                        f.attackTimer = f.attackTimer - dt
                        if f.attackTimer <= 0 then
                            local dmg = CONFIG.UnitStats[f.fType].atk
                            if GS.bloodMoonActive then dmg = math.floor(dmg * 1.5) end
                            if l.invincibleTimer <= 0 then
                                l.hp = l.hp - dmg
                                l.invincibleTimer = 0.1  -- 短暂无敌防止同帧多次结算
                                Entities.spawnDamageNumber(l.x, l.y, dmg, 255, 50, 50)
                                Entities.spawnParticle(l.x, l.y, 255, 80, 80, 3)
                            end
                            f.attackTimer = CONFIG.UnitStats[f.fType].atkInterval
                        end
                        break
                    end
                end
            end
        end

        -- 战斗单位 vs Boss（持续输出，不再自杀）
        if f.alive and (f.fType == "soldier" or f.fType == "knight") and f.state == "attacking" then
            for _, b in ipairs(GS.bosses) do
                if b.alive and not b.isStealthed then
                    local d = Utils.dist(f.x, f.y, b.x, b.y)
                    if d < (CONFIG.BossRadius + getUnitRadius(f.fType)) * 0.8 then
                        f.attackTimer = f.attackTimer - dt
                        if f.attackTimer <= 0 then
                            local dmg = CONFIG.UnitStats[f.fType].atk
                            if GS.bloodMoonActive then dmg = math.floor(dmg * 1.5) end
                            b.hp = b.hp - dmg
                            f.attackTimer = CONFIG.UnitStats[f.fType].atkInterval
                            Entities.spawnDamageNumber(b.x, b.y, dmg, 255, 200, 50)
                            Entities.spawnParticle(b.x, b.y, 255, 150, 50, 3)
                        end
                        break
                    end
                end
            end
        end
    end
end
```

注意：`processCombat` 现在需要 `dt` 参数。

- [ ] **Step 4: 重写 processProjectiles — 箭矢数值伤害**

在命中敌方单位的部分，替换：

```lua
                            -- 箭矢命中：使用克制表中 archer 行
                            local result = COMBAT_TABLE.archer[f.fType]
                            if result then
                                local _, bDies, kDmg = result[1], result[2], result[3]
                                if kDmg > 0 and f.fType == "knight" and f.knightHP then
                                    f.knightHP = f.knightHP - kDmg
                                    if f.knightHP <= 0 then bDies = true end
                                end
                                if bDies then
                                    f.alive = false
                                    Entities.spawnParticle(f.x, f.y, 255, 150, 50, 4)
                                end
                            end
```

替换为：

```lua
                            -- 箭矢命中：数值制伤害
                            local dmg = calcUnitDamage("archer", f.fType)
                            f.hp = f.hp - dmg
                            Entities.spawnDamageNumber(f.x, f.y, dmg, 255, 150, 50)
                            if f.hp <= 0 then
                                f.alive = false
                                Entities.spawnParticle(f.x, f.y, 255, 150, 50, 4)
                            end
```

在命中领主部分，替换：

```lua
                            local lordDmg = CONFIG.ArcherDamageToLord
```

替换为：

```lua
                            local lordDmg = CONFIG.UnitStats.archer.atk  -- 20点，不乘克制
```

在命中 Boss 部分，替换：

```lua
                            local bossDmg = CONFIG.BossDamagePerSoldier
```

替换为：

```lua
                            local bossDmg = CONFIG.UnitStats.archer.atk  -- 20点
```

- [ ] **Step 5: 删除据点攻击代码**

删除 `processProjectiles` 末尾的整个"战斗单位 vs 据点"部分（约20行，从 `-- 战斗单位 vs 据点` 注释到对应的 `end` 结束）。

- [ ] **Step 6: 重写胜利检测**

在 `processDeaths` 中，将胜利检测部分（从 `-- 胜利检测` 注释开始到函数结束）替换为：

```lua
    -- 胜利检测：所有敌方领主的据点HP归零 + 领主本体也死亡
    if GS.gameState == "playing" then
        local allEnemiesEliminated = true
        for _, l in ipairs(GS.lords) do
            if l.faction ~= 1 then
                -- 敌方领主还活着，或据点HP还有（能复活）
                if l.alive or l.strongholdHP > 0 then
                    allEnemiesEliminated = false
                    break
                end
            end
        end
        -- 也检查是否有正在复活中的敌方领主
        if allEnemiesEliminated then
            for lordId, info in pairs(GS.respawning) do
                if info.lordRef and info.lordRef.faction ~= 1 then
                    allEnemiesEliminated = false
                    break
                end
            end
        end
        if allEnemiesEliminated then
            GS.gameState = "victory"
            GS.settledGlory = TS.settleGame(true, GS.gameTime)
        end
    end
```

- [ ] **Step 7: 删除据点死亡清理**

在 `processDeaths` 中，删除：

```lua
    -- 据点死亡清理
    for i = #GS.strongholds, 1, -1 do
        if not GS.strongholds[i].alive then table.remove(GS.strongholds, i) end
    end
```

- [ ] **Step 8: 删除 Stronghold require**

将文件顶部的 `local Stronghold = require("Stronghold")` 删除。

- [ ] **Step 9: 更新 main.lua 中 processCombat 调用**

在 `scripts/main.lua` 的 `updateGame` 函数中，将：

```lua
    Combat.processCombat()
```

改为：

```lua
    Combat.processCombat(dt)
```

- [ ] **Step 10: Commit**

```bash
git add scripts/Combat.lua scripts/main.lua
git commit -m "feat(Combat): rewrite to numeric HP damage system with attackTimer, remove COMBAT_TABLE and stronghold attack"
```

---

### Task 5: Stronghold — 重构为领主附属系统

**Files:**
- Modify: `scripts/Stronghold.lua`

- [ ] **Step 1: 删除独立据点实体函数**

删除 `Stronghold.createStronghold` 函数和 `Stronghold.findStrongholdByLordId` 函数。

删除 `Stronghold.damageStronghold` 函数。

- [ ] **Step 2: 重写 onLordDeath — 使用领主身上的据点HP**

```lua
--- 领主死亡时调用，返回 true 表示会复活，false 表示真正淘汰
function Stronghold.onLordDeath(lord)
    -- 记录死亡位置
    lord.deathX = lord.x
    lord.deathY = lord.y

    -- 扣据点HP
    local deathCost = 100
    if GS.bloodMoonActive then deathCost = 150 end
    lord.strongholdHP = lord.strongholdHP - deathCost

    if lord.strongholdHP <= 0 then
        lord.strongholdHP = 0
        lord.alive = false
        -- 惩罚：损失50%资源 & 掉落战利品
        local lootWood = math.floor(lord.wood * 0.5)
        local lootStone = math.floor(lord.stone * 0.5)
        lord.wood = lord.wood - lootWood
        lord.stone = lord.stone - lootStone
        for _, f in ipairs(GS.followers) do
            if f.lordId == lord.id and f.alive then
                f.alive = false
                Entities.spawnParticle(f.x, f.y, 150, 150, 150, 2)
            end
        end
        if lootWood > 0 or lootStone > 0 then
            Entities.createLootBox(lord.x, lord.y, lootWood, lootStone)
        end
        Entities.spawnParticle(lord.x, lord.y, 255, 50, 50, 20)
        return false  -- 永久淘汰
    end

    -- 据点HP > 0，进入复活流程
    lord.alive = false
    -- 惩罚
    local lootWood = math.floor(lord.wood * 0.5)
    local lootStone = math.floor(lord.stone * 0.5)
    lord.wood = lord.wood - lootWood
    lord.stone = lord.stone - lootStone
    for _, f in ipairs(GS.followers) do
        if f.lordId == lord.id and f.alive then
            f.alive = false
            Entities.spawnParticle(f.x, f.y, 150, 150, 150, 2)
        end
    end
    if lootWood > 0 or lootStone > 0 then
        Entities.createLootBox(lord.x, lord.y, lootWood, lootStone)
    end
    Entities.spawnParticle(lord.x, lord.y, 255, 50, 50, 20)
    GS.respawning[lord.id] = { timer = CONFIG.RespawnTime, lordRef = lord }
    print("[LORD] Faction " .. lord.faction .. " lord killed, strongholdHP=" .. lord.strongholdHP .. ", respawning in " .. CONFIG.RespawnTime .. "s...")
    return true
end
```

- [ ] **Step 3: 重写 respawnLord — 在死亡位置复活**

```lua
function Stronghold.respawnLord(lordId)
    local foundLord = nil
    for _, l in ipairs(GS.lords) do
        if l.id == lordId then foundLord = l break end
    end
    if not foundLord then return end
    if foundLord.strongholdHP <= 0 then return end  -- 据点HP耗尽不复活

    foundLord.alive = true
    foundLord.hp = math.floor(foundLord.maxHp * CONFIG.RespawnHpRatio)
    -- 在死亡位置复活（不是据点位置）
    foundLord.x = foundLord.deathX or foundLord.x
    foundLord.y = foundLord.deathY or foundLord.y
    foundLord.invincibleTimer = 3.0
    foundLord.lordMode = "defend"  -- 复活后默认防守模式
    -- 初始随从：2农民 + 1士兵
    Entities.createFollower(foundLord, "peasant")
    Entities.createFollower(foundLord, "peasant")
    Entities.createFollower(foundLord, "soldier")
    Entities.spawnParticle(foundLord.x, foundLord.y, 100, 200, 255, 15)
    print("[RESPAWN] Faction " .. foundLord.faction .. " lord respawned at death position!")
end
```

- [ ] **Step 4: 重写 updateStrongholds — 领主防御塔 + 领域伤害**

```lua
function Stronghold.updateStrongholds(dt)
    -- 遍历所有活着的领主，更新防御塔和领域伤害
    for _, lord in ipairs(GS.lords) do
        if not lord.alive then goto continueLord end

        -- 更新模式切换提示文字
        if lord.modeSwitchText then
            lord.modeSwitchText.timer = lord.modeSwitchText.timer - dt
            if lord.modeSwitchText.timer <= 0 then
                lord.modeSwitchText = nil
            end
        end

        -- ===== 防御塔攻击逻辑（跟随领主，不再崩溃） =====
        if lord.towerActive then
            lord.towerTimer = lord.towerTimer + dt
            if lord.towerTimer >= CONFIG.StrongholdTowerInterval then
                lord.towerTimer = 0
                local bestTarget = nil
                local bestDist = CONFIG.StrongholdTowerRange
                -- 寻找射程内最近的敌方单位
                for _, f in ipairs(GS.followers) do
                    if f.alive and f.factionId ~= lord.faction then
                        local d = Utils.dist(lord.x, lord.y, f.x, f.y)
                        if d < bestDist then
                            bestDist = d
                            bestTarget = f
                        end
                    end
                end
                -- 也检测敌方领主
                for _, l in ipairs(GS.lords) do
                    if l.alive and l.faction ~= lord.faction and l.invincibleTimer <= 0 then
                        local d = Utils.dist(lord.x, lord.y, l.x, l.y)
                        if d < bestDist then
                            bestDist = d
                            bestTarget = l
                        end
                    end
                end
                if bestTarget then
                    local towerDmg = CONFIG.StrongholdTowerDamage  -- 15点
                    if GS.bloodMoonActive then towerDmg = math.floor(towerDmg * 1.5) end
                    if bestTarget.fType then
                        -- 是随从：数值伤害（不再一击杀）
                        bestTarget.hp = bestTarget.hp - towerDmg
                        Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, towerDmg, 255, 200, 50)
                        if bestTarget.hp <= 0 then
                            bestTarget.alive = false
                        end
                    else
                        -- 是领主
                        bestTarget.hp = bestTarget.hp - towerDmg
                        bestTarget.invincibleTimer = 0.1
                        Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, towerDmg, 255, 200, 50)
                    end
                    Entities.spawnParticle(bestTarget.x, bestTarget.y, 255, 200, 50, 4)
                end
            end
        end

        -- ===== 防守模式领域持续伤害 =====
        if lord.lordMode == "defend" then
            lord.auraDmgTimer = lord.auraDmgTimer + dt
            local modeCfg = CONFIG.LordModes.defend
            if lord.auraDmgTimer >= modeCfg.auraDmgInterval then
                lord.auraDmgTimer = 0
                local auraRadius = CONFIG.AuraRadius * modeCfg.auraMul
                if GS.fogActive then auraRadius = auraRadius * 0.7 end
                local dmgPerTick = modeCfg.auraDamage * modeCfg.auraDmgInterval  -- 10 * 0.5 = 5
                local lordDmgPerTick = modeCfg.auraDamageToLord * modeCfg.auraDmgInterval  -- 5 * 0.5 = 2.5
                if GS.bloodMoonActive then
                    dmgPerTick = dmgPerTick * 1.5
                    lordDmgPerTick = lordDmgPerTick * 1.5
                end
                -- 对领域内敌方单位造成伤害
                for _, f in ipairs(GS.followers) do
                    if f.alive and f.factionId ~= lord.faction then
                        local d = Utils.dist(lord.x, lord.y, f.x, f.y)
                        if d < auraRadius then
                            f.hp = f.hp - math.floor(dmgPerTick)
                            if f.hp <= 0 then f.alive = false end
                        end
                    end
                end
                -- 对领域内敌方领主造成伤害
                for _, el in ipairs(GS.lords) do
                    if el.alive and el.faction ~= lord.faction and el.invincibleTimer <= 0 then
                        local d = Utils.dist(lord.x, lord.y, el.x, el.y)
                        if d < auraRadius then
                            el.hp = el.hp - math.floor(lordDmgPerTick)
                            el.invincibleTimer = 0.1
                        end
                    end
                end
            end
        else
            lord.auraDmgTimer = 0  -- 非防守模式重置计时器
        end

        ::continueLord::
    end

    -- 处理复活倒计时
    local toRemove = {}
    for lordId, info in pairs(GS.respawning) do
        info.timer = info.timer - dt
        if info.timer <= 0 then
            Stronghold.respawnLord(lordId)
            table.insert(toRemove, lordId)
        end
    end
    for _, lordId in ipairs(toRemove) do
        GS.respawning[lordId] = nil
    end
end
```

- [ ] **Step 5: Commit**

```bash
git add scripts/Stronghold.lua
git commit -m "feat(Stronghold): migrate tower/respawn/aura to lord entity, remove independent stronghold"
```

---

### Task 6: FollowerAI — attackTimer 持续战斗 & 领域减速

**Files:**
- Modify: `scripts/FollowerAI.lua`

- [ ] **Step 1: 近战攻击状态 — 停下互砍**

在 `elseif f.state == "attacking"` 分支中，找到士兵/骑士近战部分：

```lua
        else
            -- 士兵/骑士：近战冲锋
            if dToTarget > 12 then
                local dx, dy = normalize(tx - f.x, ty - f.y)
                local chargeMul = 1.2
                if f.fType == "knight" then
                    chargeMul = CONFIG.KnightChargeSpeedMul
                end
                f.x = f.x + dx * CONFIG.FollowerSpeed * chargeMul * atkSpeedMul * globalSpd * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * chargeMul * atkSpeedMul * globalSpd * dt
                f.angle = math.atan2(dy, dx)
            end
            -- 碰撞检测在主循环处理
        end
```

替换为：

```lua
        else
            -- 士兵/骑士：近战 — 先冲到碰撞距离内，然后停下互砍
            local contactDist = 20  -- 进入战斗的接触距离
            if dToTarget > contactDist then
                local dx, dy = normalize(tx - f.x, ty - f.y)
                local chargeMul = 1.2
                if f.fType == "knight" then
                    chargeMul = CONFIG.KnightChargeSpeedMul
                end
                -- 检查是否被敌方领主防守光环减速
                local slowMul = 1.0
                for _, el in ipairs(GS.lords) do
                    if el.alive and el.faction ~= f.factionId and el.lordMode == "defend" then
                        local dToLord = dist(f.x, f.y, el.x, el.y)
                        local defAura = CONFIG.AuraRadius * CONFIG.LordModes.defend.auraMul
                        if dToLord < defAura then
                            slowMul = 1.0 - CONFIG.LordModes.defend.auraSlowPct  -- 0.7
                            break
                        end
                    end
                end
                f.x = f.x + dx * CONFIG.FollowerSpeed * chargeMul * atkSpeedMul * globalSpd * slowMul * dt
                f.y = f.y + dy * CONFIG.FollowerSpeed * chargeMul * atkSpeedMul * globalSpd * slowMul * dt
                f.angle = math.atan2(dy, dx)
            else
                -- 已进入碰撞距离，停下来（Combat.processCombat 处理伤害）
                f.angle = math.atan2(ty - f.y, tx - f.x)
            end
        end
```

- [ ] **Step 2: 防守模式下不主动追击**

在 following 状态的战斗单位搜索敌人部分，在 `if bestTarget then` 之前添加模式检查：

```lua
            -- 防守模式：不主动追击领域外敌人
            local mode = GS.tcGetMode(lord.id)
            if mode == "defend" and bestTarget then
                -- 仅拦截已进入领域的敌人（不追出去）
                local enemyDist = dist(lord.x, lord.y, bestTarget.x, bestTarget.y)
                local defAura = CONFIG.AuraRadius * CONFIG.LordModes.defend.auraMul
                if GS.fogActive then defAura = defAura * 0.7 end
                if enemyDist > defAura then
                    bestTarget = nil  -- 目标在领域外，不追
                end
            end
```

- [ ] **Step 3: Commit**

```bash
git add scripts/FollowerAI.lua
git commit -m "feat(FollowerAI): stop-and-fight in contact range, defend mode suppresses pursuit, enemy aura slow"
```

---

### Task 7: LordAI — 删除据点引用 & 双模式自动切换

**Files:**
- Modify: `scripts/LordAI.lua`

- [ ] **Step 1: 删除 Stronghold require**

删除文件顶部的：

```lua
local Stronghold = require("Stronghold")
```

- [ ] **Step 2: 删除据点回防逻辑**

删除决策树中整个"据点回防/攻击逻辑"块（从 `local mySH = Stronghold.findStrongholdByLordId(lord.id)` 到其对应 `end` 块结束）。

- [ ] **Step 3: 重写敌方据点进攻为追击敌方领主**

将"进攻敌方据点"的整个块（从 `-- 进攻敌方据点` 注释到 `end` 结束）替换为：

```lua
    -- 兵力充足时追击敌方领主
    if myCombat >= 4 then
        local weakestEnemy = nil
        local weakestEnemyHP = 999999
        for _, el in ipairs(GS.lords) do
            if el.alive and el.faction ~= lord.faction then
                local d = dist(lord.x, lord.y, el.x, el.y)
                if d < 800 and el.hp < weakestEnemyHP then
                    weakestEnemyHP = el.hp
                    weakestEnemy = el
                end
            end
        end
        if weakestEnemy and myCombat >= 5 then
            lord.aiState = "attack"
            lord.targetX = weakestEnemy.x
            lord.targetY = weakestEnemy.y
            lord.aiTargetId = weakestEnemy.id
            return
        end
    end
```

- [ ] **Step 4: 删除 knightHP 赋值**

在升级骑士的代码块中，删除：

```lua
                        f.knightHP = CONFIG.KnightHP
```

- [ ] **Step 5: 替换底部 AI 战术指令设置**

将文件末尾的战术指令设置部分：

```lua
    -- AI根据决策状态设置战术指令
    if lord.aiState == "attack" then
        GS.tcSetMode(lord.id, "charge")
    elseif lord.aiState == "flee" then
        GS.tcSetMode(lord.id, "defend")
    else
        -- wander/gather时恢复默认（仅在非default时重置）
        if GS.tcGetMode(lord.id) ~= "default" then
            GS.tcSetMode(lord.id, "default")
        end
    end
```

替换为基于兵力/HP的双模式自动切换：

```lua
    -- AI领主双模式自动切换
    local currentMode = lord.lordMode or "attack"
    if myCombat < 3 or lord.hp < lord.maxHp * 0.3 then
        -- 兵少或血低 → 防守
        if currentMode ~= "defend" then
            lord.lordMode = "defend"
        end
    elseif myCombat >= 5 and lord.hp > lord.maxHp * 0.6 then
        -- 兵多且血高 → 攻击
        if currentMode ~= "attack" then
            lord.lordMode = "attack"
        end
    end
    -- 其他情况保持当前模式
```

- [ ] **Step 6: 删除函数中其他 GS.tcSetMode 调用**

搜索函数中所有剩余的 `GS.tcSetMode` 调用并删除（据点回防块里的已在 Step 2 删除，冲锋模式的在进攻据点块已在 Step 3 删除）。

- [ ] **Step 7: Commit**

```bash
git add scripts/LordAI.lua
git commit -m "feat(LordAI): remove stronghold refs, add auto attack/defend mode switching based on army/HP"
```

---

### Task 8: BossSystem — 数值制伤害

**Files:**
- Modify: `scripts/BossSystem.lua`

- [ ] **Step 1: 幽灵狼击杀落单单位改为数值伤害**

在幽灵狼追击落单单位部分，将：

```lua
            -- 碰到落单单位直接击杀
            local dToTarget = Utils.dist(boss.x, boss.y, bestTarget.x, bestTarget.y)
            if dToTarget < 20 then
                bestTarget.alive = false
                local contactDmg = cfg.contactDamage
                if GS.bloodMoonActive then contactDmg = math.floor(contactDmg * 1.5) end
                Entities.spawnParticle(bestTarget.x, bestTarget.y, 150, 100, 220, 6)
                Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, contactDmg, 150, 100, 220)
            end
```

替换为：

```lua
            -- 碰到落单单位造成数值伤害
            local dToTarget = Utils.dist(boss.x, boss.y, bestTarget.x, bestTarget.y)
            if dToTarget < 20 then
                local contactDmg = cfg.contactDamage
                if GS.bloodMoonActive then contactDmg = math.floor(contactDmg * 1.5) end
                bestTarget.hp = bestTarget.hp - contactDmg
                if bestTarget.hp <= 0 then bestTarget.alive = false end
                Entities.spawnParticle(bestTarget.x, bestTarget.y, 150, 100, 220, 6)
                Entities.spawnDamageNumber(bestTarget.x, bestTarget.y, contactDmg, 150, 100, 220)
            end
```

- [ ] **Step 2: 石甲蟹 AOE 改为数值伤害**

在石甲蟹 AOE 部分，将：

```lua
                    -- 对范围内所有敌方单位造成伤害（直接击杀）
                    for _, f in ipairs(GS.followers) do
                        if f.alive then
                            local d = Utils.dist(boss.x, boss.y, f.x, f.y)
                            if d < cfg.aoeRadius then
                                f.alive = false
                                Entities.spawnParticle(f.x, f.y, 120, 120, 140, 3)
                            end
                        end
                    end
```

替换为：

```lua
                    -- 对范围内所有单位造成数值伤害
                    for _, f in ipairs(GS.followers) do
                        if f.alive then
                            local d = Utils.dist(boss.x, boss.y, f.x, f.y)
                            if d < cfg.aoeRadius then
                                f.hp = f.hp - aoeDmg
                                if f.hp <= 0 then f.alive = false end
                                Entities.spawnParticle(f.x, f.y, 120, 120, 140, 3)
                                Entities.spawnDamageNumber(f.x, f.y, aoeDmg, 120, 120, 140)
                            end
                        end
                    end
```

- [ ] **Step 3: Commit**

```bash
git add scripts/BossSystem.lua
git commit -m "feat(BossSystem): change boss attacks from instant-kill to numeric HP damage"
```

---

### Task 9: Renderer — 删除据点绘制，新增双血条 & 单位HP条

**Files:**
- Modify: `scripts/Renderer.lua`

- [ ] **Step 1: 删除 drawStronghold 函数**

删除整个 `function M.drawStronghold(sh)` 函数（约60行）。

- [ ] **Step 2: 修改 drawLord — 双血条 + 防守光环脉冲**

在 `drawLord` 函数中，将光环部分（从 `-- 光环` 注释到冲锋脉冲效果结束）替换为：

```lua
    -- 光环（根据模式变化）
    if l.isPlayer or Utils.dist(GS.lords[1].x, GS.lords[1].y, l.x, l.y) < GS.screenW then
        local modeCfg = CONFIG.LordModes[l.lordMode or "attack"]
        local auraR = CONFIG.AuraRadius * modeCfg.auraMul
        if GS.fogActive then auraR = auraR * 0.7 end
        local asX, asY = Utils.worldToScreen(l.x, l.y)
        local aR, aG, aB = fc[1], fc[2], fc[3]
        local auraAlpha = 15

        if l.lordMode == "defend" then
            -- 防守模式：偏紫/红色脉冲
            aR, aG, aB = 200, 100, 255
            auraAlpha = math.floor(10 + math.sin(GS.gameTime * 3) * 10 + 10)  -- 0.1~0.3 alpha 脉冲 (约 25~76 of 255)
        end

        if GS.fogActive then
            aR = math.floor(aR * 0.6 + 128 * 0.4)
            aG = math.floor(aG * 0.6 + 128 * 0.4)
            aB = math.floor(aB * 0.6 + 128 * 0.4)
        end

        nvgBeginPath(ctx)
        nvgCircle(ctx, asX, asY, auraR)
        nvgFillColor(ctx, nvgRGBA(aR, aG, aB, auraAlpha))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, asX, asY, auraR)
        nvgStrokeColor(ctx, nvgRGBA(aR, aG, aB, 40))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)

        if l.lordMode == "defend" then
            -- 防守：内圈收缩效果
            nvgBeginPath(ctx)
            nvgCircle(ctx, asX, asY, auraR * 0.4)
            nvgStrokeColor(ctx, nvgRGBA(200, 100, 255, 80))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)
        end
    end
```

在血条部分，将现有单血条替换为双血条：

```lua
    -- 双血条
    local hpBarW = lordRadius * 2
    local hpBarH = 4

    -- 据点HP血条（上方，橙/金色，仅玩家显示）
    if l.isPlayer then
        local shRatio = (l.strongholdHP or 0) / (l.strongholdMaxHP or 1)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, sx - hpBarW/2, sy + lordRadius + 2, hpBarW, hpBarH, 2)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, sx - hpBarW/2, sy + lordRadius + 2, hpBarW * shRatio, hpBarH, 2)
        nvgFillColor(ctx, nvgRGBA(255, 180, 50, 255))
        nvgFill(ctx)
    end

    -- 领主HP血条（下方，绿→红渐变）
    local hpRatio = l.hp / l.maxHp
    local hpBarY = sy + lordRadius + (l.isPlayer and 8 or 4)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - hpBarW/2, hpBarY, hpBarW, hpBarH, 2)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - hpBarW/2, hpBarY, hpBarW * hpRatio, hpBarH, 2)
    local hpR = hpRatio > 0.5 and 80 or (hpRatio > 0.25 and 255 or 255)
    local hpG = hpRatio > 0.5 and 220 or (hpRatio > 0.25 and 180 or 50)
    local hpB = hpRatio > 0.5 and 80 or (hpRatio > 0.25 and 50 or 50)
    nvgFillColor(ctx, nvgRGBA(hpR, hpG, hpB, 255))
    nvgFill(ctx)
```

在领主标签之后，新增模式切换提示文字绘制：

```lua
    -- 模式切换提示文字
    if l.modeSwitchText then
        local t = l.modeSwitchText
        local alpha = math.floor((t.timer / 1.0) * 255)
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 16)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(t.r, t.g, t.b, alpha))
        nvgText(ctx, sx, sy - lordRadius - 14, t.text, nil)
    end
```

- [ ] **Step 3: 修改 drawFollower — 所有受伤单位显示HP条**

将骑士HP指示器部分（`-- 5) 骑士HP指示器`）替换为：

```lua
    -- 5) 通用HP条（受伤时显示）
    if f.hp and f.maxHp and f.hp < f.maxHp then
        local barW = radius * 2
        local barH = 2.5
        local barY = sy - radius - 5
        local ratio = f.hp / f.maxHp
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, sx - barW/2, barY, barW, barH, 1)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, sx - barW/2, barY, barW * ratio, barH, 1)
        local hpG = ratio > 0.5 and 220 or (ratio > 0.25 and 180 or 50)
        nvgFillColor(ctx, nvgRGBA(ratio > 0.25 and 80 or 255, hpG, ratio > 0.5 and 80 or 50, 220))
        nvgFill(ctx)
    end
```

- [ ] **Step 4: 修改 drawMinimap — 删除据点方块**

删除小地图中"据点（小方块标记）"部分（约15行，从 `-- 据点（小方块标记）` 注释到对应 `end` 结束）。

- [ ] **Step 5: 新增 LordModes config 引用**

确认文件顶部已有 `local CONFIG = ConfigModule.CONFIG`（已存在，无需修改）。

- [ ] **Step 6: Commit**

```bash
git add scripts/Renderer.lua
git commit -m "feat(Renderer): remove drawStronghold, add dual HP bars, unit HP bars, defend aura pulse"
```

---

### Task 10: GameUI — 单按钮模式切换

**Files:**
- Modify: `scripts/GameUI.lua`

- [ ] **Step 1: 替换两个战术按钮为单个模式切换按钮**

在 `CreateGameUI` 的底部按钮区域，将分隔线之后的两个按钮（`btnDefend` 和 `btnCharge`）替换为一个：

```lua
                    UI.Button {
                        id = "btnMode",
                        text = "防守[Q]",
                        fontSize = 13,
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 10, paddingBottom = 10,
                        onClick = function()
                            if GS.lords[1] and GS.lords[1].alive then
                                GS.tcSetMode(GS.lords[1].id, "defend")
                            end
                        end,
                    },
```

- [ ] **Step 2: 删除骑士升级按钮中的 knightHP 赋值**

在 `btnUpgradeKnight` 的 onClick 中，删除：

```lua
                        f.knightHP = CONFIG.KnightHP
```

- [ ] **Step 3: 更新 UpdateGameUI — 模式按钮高亮**

将 `btnDefend` 和 `btnCharge` 的更新逻辑替换为：

```lua
    -- 模式按钮高亮
    local mode = GS.tcGetMode(lord.id)
    local btnMode = GS.uiRoot_:FindById("btnMode")
    if btnMode then
        if mode == "defend" then
            btnMode:SetText("[防守中]")
            btnMode:SetStyle({ backgroundColor = {200, 100, 255, 200} })
        else
            btnMode:SetText("防守[Q]")
            btnMode:SetStyle({ backgroundColor = nil })
        end
    end
```

删除旧的 `btnDefend` 和 `btnCharge` 更新代码。

- [ ] **Step 4: Commit**

```bash
git add scripts/GameUI.lua
git commit -m "feat(GameUI): replace defend/charge buttons with single mode toggle, remove knightHP"
```

---

### Task 11: main.lua — 删除据点创建/渲染 & 输入改为单键

**Files:**
- Modify: `scripts/main.lua`

- [ ] **Step 1: 删除 initGame 中的据点创建**

删除：

```lua
    GS.strongholds = {}
```

和：

```lua
    GS.strongholdCollapseNotified = false
```

和：

```lua
    -- 创建玩家据点
    Stronghold.createStronghold(playerLord.id, playerLord.x, playerLord.y, playerLord.faction)
```

和（在 AI 领主创建循环中）：

```lua
        -- 创建AI据点
        Stronghold.createStronghold(aiLord.id, sp[1], sp[2], aiLord.faction)
```

- [ ] **Step 2: 删除据点渲染**

在 `HandleNanoVGRender` 中，删除：

```lua
    -- 绘制据点（在其他实体之下）
    for _, sh in ipairs(GS.strongholds) do Renderer.drawStronghold(sh) end
```

- [ ] **Step 3: 删除5分钟崩溃预警**

在 `updateGame` 中，删除整个5分钟崩溃预警块（从 `-- 5分钟崩溃预警` 注释到 `end` 结束，约10行）。

- [ ] **Step 4: 修改键盘输入 — Q 键切换模式，删除 E 键冲锋**

在 `HandleKeyDown` 中，将：

```lua
        if key == KEY_Q then
            GS.tcSetMode(GS.lords[1].id, "defend")
        elseif key == KEY_E then
            GS.tcSetMode(GS.lords[1].id, "charge")
        end
```

替换为：

```lua
        if key == KEY_Q then
            GS.tcSetMode(GS.lords[1].id, "defend")
        end
```

- [ ] **Step 5: 确认 Stronghold require 保留**

`main.lua` 仍然需要 `local Stronghold = require("Stronghold")`，因为 `updateGame` 调用 `Stronghold.updateStrongholds(dt)`。保留此 require 不变。

- [ ] **Step 6: 构建全项目**

Run: UrhoX MCP build tool
Expected: 构建成功，无错误

- [ ] **Step 7: Commit**

```bash
git add scripts/main.lua
git commit -m "feat(main): remove stronghold creation/rendering/collapse, simplify key input to single Q toggle"
```

---

## Self-Review Checklist

### 1. Spec Coverage

| 规格要求 | 对应 Task |
|---------|----------|
| UnitStats 数值表 | Task 1 Step 1 |
| DamageMultiplier 克制倍率表 | Task 1 Step 2 |
| LordModes 双模式配置 | Task 1 Step 3 |
| follower hp/maxHp/attackTimer | Task 2 Step 1 |
| 删除 knightHP | Task 2 Step 1, Task 7 Step 4, Task 10 Step 2 |
| lord 据点字段 | Task 2 Step 2 |
| 三档→两档模式 | Task 3 Step 2 |
| 删除 GS.strongholds | Task 3 Step 1 |
| 数值制近战互砍 | Task 4 Step 3 |
| 箭矢数值伤害 | Task 4 Step 4 |
| 单位持续攻击领主（不自杀） | Task 4 Step 3 |
| 单位持续攻击Boss（不自杀） | Task 4 Step 3 |
| 血月×1.5 | Task 4 Step 2 (calcUnitDamage), Task 5 Step 4 (领域伤害) |
| 删除据点实体 | Task 5 Step 1 |
| 据点HP扣减（100/血月150） | Task 5 Step 2 |
| 死亡位置复活 | Task 5 Step 3 |
| 防御塔迁移到领主（数值15伤害） | Task 5 Step 4 |
| 防御塔不再崩溃 | Task 5 Step 4 (无崩溃逻辑), Task 11 Step 3 |
| 领域持续伤害（防守模式） | Task 5 Step 4 |
| 领域减速30% | Task 6 Step 1 |
| 防守模式不主动追击 | Task 6 Step 2 |
| AI 双模式自动切换 | Task 7 Step 5 |
| Boss 数值伤害 | Task 8 |
| 删除据点建筑绘制 | Task 9 Step 1 |
| 领主双血条 | Task 9 Step 2 |
| 单位HP条 | Task 9 Step 3 |
| 防守光环脉冲动画 | Task 9 Step 2 |
| 模式切换文字提示 | Task 9 Step 2 |
| 按钮合并为一个 | Task 10 Step 1 |
| Q 键切换/E 键删除 | Task 11 Step 4 |
| 胜利条件更新 | Task 4 Step 6 |
| 小地图删除据点方块 | Task 9 Step 4 |
| 删除据点创建 | Task 11 Step 1 |
| 删除据点渲染循环 | Task 11 Step 2 |

### 2. Placeholder Scan

无 TBD/TODO/implement later/fill in details。所有步骤包含完整代码。

### 3. Type Consistency

- `calcUnitDamage` 在 Task 4 定义，在 Task 4 Steps 3/4 使用，签名一致 `(attackerType, defenderType)`
- `getUnitRadius` 在 Task 4 定义，在 Task 4 Step 3 和 Task 6 使用，签名一致 `(fType)`
- `lord.lordMode` 在 Task 2 创建（默认 `"attack"`），在 Task 3/5/6/7/9/10 使用，值域一致 `"attack"|"defend"`
- `lord.strongholdHP` 在 Task 2 创建，在 Task 4(胜利检测)/Task 5(扣减/复活) 使用，字段名一致
- `lord.modeSwitchText` 在 Task 2 创建，Task 3(赋值)/Task 9(渲染) 使用，结构一致 `{text,timer,r,g,b}`
- `f.hp`/`f.maxHp`/`f.attackTimer` 在 Task 2 创建，Task 4/6/8/9 使用，字段名一致
- `CONFIG.LordModes` 在 Task 1 定义，Task 3/5/6/9 引用，结构一致
- `CONFIG.UnitStats` 在 Task 1 定义，Task 2/4 引用，结构一致
- `CONFIG.DamageMultiplier` 在 Task 1 定义，Task 4 引用，结构一致
- `processCombat(dt)` 签名在 Task 4 Step 3 改为带参数，Task 4 Step 9 更新调用处
