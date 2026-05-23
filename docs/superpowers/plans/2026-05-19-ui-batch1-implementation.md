# UI 第一批界面实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 4 个 UI 界面（主菜单、阵型选择、战役关卡选择、无尽商店），使已实现的三种游戏模式可被玩家访问。

**Architecture:** 每个界面一个独立 Lua 模块（`show()/hide()` 接口），共享主题常量表 `MenuTheme.lua`。主菜单背景复用 Renderer 已有的 NanoVG 绘制方法。UI 使用 `urhox-libs/UI` 组件库（Yoga Flexbox + NanoVG 渲染），通过 `main.lua` 的 `gameState` 路由控制显隐。

**Tech Stack:** UrhoX Lua 5.4, urhox-libs/UI (Yoga Flexbox), NanoVG, FormationSystem, CampaignData/CampaignState, EndlessMode, ShopSystem

**Design Spec:** `docs/superpowers/specs/2026-05-19-ui-batch1-design.md`

---

### Task 1: MenuTheme — 共享主题常量

**Files:**
- Create: `scripts/MenuTheme.lua`

- [ ] **Step 1: 创建 MenuTheme.lua**

```lua
-- scripts/MenuTheme.lua
-- 共享视觉主题常量，供所有菜单界面引用

local T = {}

T.colors = {
    primary       = {70, 160, 255, 255},
    accent        = {255, 150, 30, 255},
    accentDark    = {235, 120, 10, 255},
    success       = {80, 200, 100, 255},
    danger        = {255, 90, 70, 255},
    gold          = {255, 210, 60, 255},
    cardBg        = {255, 252, 245, 230},
    overlay       = {30, 35, 60, 200},
    textPrimary   = {50, 50, 60, 255},
    textSecondary = {130, 135, 150, 255},
    textOnDark    = {255, 255, 255, 255},
}

T.radius = { lg = 16, md = 12, sm = 8, pill = 24 }

T.shadow = {{ x=0, y=4, blur=12, spread=0, color={0,0,0,30} }}

T.fontSize = { title = 22, subtitle = 16, body = 13, small = 11, cta = 18 }

return T
```

- [ ] **Step 2: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过，无语法错误。

- [ ] **Step 3: Commit**

```bash
git add scripts/MenuTheme.lua
git commit -m "feat(ui): add MenuTheme shared constants"
```

---

### Task 2: GameState 新增字段 + main.lua 路由框架

**Files:**
- Modify: `scripts/GameState.lua` — 添加 `menuFormationId` 字段
- Modify: `scripts/main.lua` — 更新 `Start()`、`HandleUpdate()`、`HandleNanoVGRender()` 路由

- [ ] **Step 1: GameState 添加新字段**

在 `scripts/GameState.lua` 的 GS 表中，找到 `gameMode = "skirmish"` 那行，在其后添加：

```lua
    -- 主菜单阵型选择（仅菜单显示用，开局时写入 formationStates）
    menuFormationId = "cone",
```

- [ ] **Step 2: main.lua — 添加新模块 require**

在 `scripts/main.lua` 顶部已有 require 列表末尾，添加：

```lua
local MainMenuUI = require("MainMenuUI")
local FormationSelectUI = require("FormationSelectUI")
local CampaignSelectUI = require("CampaignSelectUI")
local EndlessShopUI = require("EndlessShopUI")
local MenuTheme = require("MenuTheme")
```

注意：这些模块尚未创建，但 require 声明先占位。构建时会因为文件不存在而报错，我们在后续 Task 中逐步创建。此处的 require 会在 Task 7 所有文件就绪后才真正生效。

**临时方案**：在 Task 7 之前，先注释掉这些 require 以确保可以增量构建。

```lua
-- 下面的 require 在对应模块创建后取消注释
-- local MainMenuUI = require("MainMenuUI")
-- local FormationSelectUI = require("FormationSelectUI")
-- local CampaignSelectUI = require("CampaignSelectUI")
-- local EndlessShopUI = require("EndlessShopUI")
-- local MenuTheme = require("MenuTheme")
```

- [ ] **Step 3: main.lua — 更新 Start() 云加载完成回调**

在 `Start()` 函数中，找到云数据加载链的最内层回调：

```lua
                    -- 所有数据加载完成，显示天赋选择（临时入口，后续替换为主菜单）
                    GameUI.ShowTalentSelectUI(function() initGame("skirmish") end)
```

替换为：

```lua
                    -- 所有数据加载完成，显示主菜单
                    GS.gameState = "main_menu"
                    -- MainMenuUI.show()  -- Task 3 创建后取消注释
                    print("[UI] Main menu ready")
```

- [ ] **Step 4: main.lua — 更新 HandleUpdate() 路由**

找到 `HandleUpdate` 函数中的早期返回判断：

```lua
    -- 非游戏状态跳过输入和逻辑
    if GS.gameState ~= "playing" and GS.gameState ~= "gameover" and GS.gameState ~= "victory" then
        return
    end
```

替换为更精细的路由：

```lua
    -- 菜单状态路由
    if GS.gameState == "main_menu" then
        -- MainMenuUI.updatePreview(dt)  -- Task 3 创建后取消注释
        return
    elseif GS.gameState == "campaign_select" then
        return  -- 纯 UI 交互，无逻辑更新
    elseif GS.gameState == "endless_shop" then
        -- EndlessShopUI.updateCountdown(dt)  -- Task 6 创建后取消注释
        return
    end

    -- 非游戏状态跳过输入和逻辑
    if GS.gameState ~= "playing" and GS.gameState ~= "gameover" and GS.gameState ~= "victory" then
        return
    end
```

- [ ] **Step 5: main.lua — 更新 HandleNanoVGRender() 路由**

找到 `HandleNanoVGRender` 函数中的早期返回：

```lua
    -- 天赋选择/加载中状态不绘制游戏世界
    if GS.gameState == "talent_select" or GS.gameState == "loading" then
        nvgEndFrame(nvg)
        return
    end
```

替换为：

```lua
    -- 主菜单状态：绘制背景预览
    if GS.gameState == "main_menu" then
        -- MainMenuUI.drawPreview(nvg, w, h)  -- Task 3 创建后取消注释
        nvgEndFrame(nvg)
        return
    end

    -- 非游戏状态不绘制
    if GS.gameState == "talent_select" or GS.gameState == "loading"
        or GS.gameState == "campaign_select" then
        nvgEndFrame(nvg)
        return
    end
```

- [ ] **Step 6: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过。游戏启动后显示空白画面（gameState="main_menu"，但 UI 尚未构建）。

- [ ] **Step 7: Commit**

```bash
git add scripts/GameState.lua scripts/main.lua
git commit -m "feat(ui): add gameState routing for menu screens"
```

---

### Task 3: MainMenuUI — 主菜单界面

**Files:**
- Create: `scripts/MainMenuUI.lua`
- Modify: `scripts/main.lua` — 取消注释 MainMenuUI require 和调用

这是最复杂的界面，包含：顶栏、标题、左侧功能栏、底部模式标签+信息卡+CTA 按钮+阵型入口，以及背景预览渲染。

- [ ] **Step 1: 创建 MainMenuUI.lua 骨架**

```lua
-- scripts/MainMenuUI.lua
local UI = require("urhox-libs/UI")
local GS = require("GameState")
local TS = require("TalentSystem")
local FS = require("FormationSystem")
local CampaignState = require("CampaignState")
local EndlessMode = require("EndlessMode")
local Renderer = require("Renderer")
local T = require("MenuTheme")

local M = {}

-- 背景预览用的装饰数据
local previewEntities = {}
local previewTimer = 0
local PREVIEW_FPS = 15
local previewInterval = 1.0 / PREVIEW_FPS

-- UI 引用
local menuRoot = nil
local modeInfoLabel1 = nil
local modeInfoLabel2 = nil
local modeInfoLabel3 = nil
local formationLabel = nil

------------------------------------------------------------
-- 背景预览
------------------------------------------------------------

local function initPreviewEntities()
    previewEntities = {
        resources = {},
        followers = {},
    }
    -- 生成装饰用的树和矿石
    local mapW, mapH = 2000, 2000
    for i = 1, 20 do
        table.insert(previewEntities.resources, {
            alive = true,
            x = math.random(100, mapW - 100),
            y = math.random(100, mapH - 100),
            rType = math.random() < 0.7 and "tree" or "mine",
            spriteType = math.random(1, 4),
            spriteFrame = math.random(0, 7),
            mineFrame = math.random(0, 5),
        })
    end
    -- 生成装饰用的小兵
    for i = 1, 5 do
        local types = {"peasant", "soldier", "knight", "archer"}
        table.insert(previewEntities.followers, {
            alive = true,
            x = math.random(200, mapW - 200),
            y = math.random(200, mapH - 200),
            factionId = math.random(1, 4),
            fType = types[math.random(1, #types)],
            lordId = 0,
            hp = 100, maxHp = 100,
            state = "idle",
            angle = math.random() * math.pi * 2,
            isShielding = false,
            -- 巡逻目标
            targetX = 0, targetY = 0,
            speed = 30,
        })
    end
    -- 为每个小兵生成巡逻目标
    for _, f in ipairs(previewEntities.followers) do
        f.targetX = f.x + math.random(-200, 200)
        f.targetY = f.y + math.random(-200, 200)
    end
end

function M.updatePreview(dt)
    -- 简单巡逻 AI：小兵走向目标点，到达后换新目标
    for _, f in ipairs(previewEntities.followers) do
        local dx = f.targetX - f.x
        local dy = f.targetY - f.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 10 then
            f.targetX = f.x + math.random(-300, 300)
            f.targetY = f.y + math.random(-300, 300)
            f.targetX = math.max(100, math.min(1900, f.targetX))
            f.targetY = math.max(100, math.min(1900, f.targetY))
        else
            f.x = f.x + (dx / dist) * f.speed * dt
            f.y = f.y + (dy / dist) * f.speed * dt
            f.angle = math.atan(dy, dx)
        end
    end
end

function M.drawPreview(nvg, w, h)
    -- 设置相机到地图中心
    GS.cameraX = 1000
    GS.cameraY = 1000

    -- 绘制背景
    Renderer.drawBackground(w, h)

    -- 绘制装饰资源（临时写入 GS.resources）
    local origResources = GS.resources
    GS.resources = previewEntities.resources
    Renderer.drawResources()
    GS.resources = origResources

    -- 绘制装饰小兵
    for _, f in ipairs(previewEntities.followers) do
        Renderer.drawFollower(f)
    end

    -- 绘制渐变蒙版（上深下浅）
    local overlay = nvgLinearGradient(nvg, 0, 0, 0, h,
        nvgRGBA(30, 35, 60, 180),
        nvgRGBA(30, 35, 60, 60))
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, w, h)
    nvgFillPaint(nvg, overlay)
    nvgFill(nvg)
end

------------------------------------------------------------
-- 模式信息卡数据
------------------------------------------------------------

local function getModeInfo(mode)
    if mode == "skirmish" then
        return "最高排名: ---", "最高击杀: ---", "4名领主混战，最后存活者胜"
    elseif mode == "campaign" then
        local ch = CampaignState.getCurrentChapter()
        local cleared = CampaignState.getClearedLevels()
        local n = cleared and #cleared or 0
        return "进度: 第" .. ch .. "章", "已通关: " .. n .. "/17", "挑战精心设计的关卡"
    elseif mode == "endless" then
        local info = EndlessMode.getWaveInfo()
        local best = info and info.bestWave or 0
        local coins = info and info.warCoins or 0
        return "最高波次: " .. best, "战争币: " .. coins, "抵御无尽敌潮，能撑多久？"
    end
    return "", "", ""
end

local function updateModeInfoCard()
    local l1, l2, l3 = getModeInfo(GS.gameMode)
    if modeInfoLabel1 then modeInfoLabel1:SetText(l1) end
    if modeInfoLabel2 then modeInfoLabel2:SetText(l2) end
    if modeInfoLabel3 then modeInfoLabel3:SetText(l3) end
end

local function updateFormationLabel()
    if formationLabel then
        local name = FS.getName(GS.menuFormationId) or GS.menuFormationId
        formationLabel:SetText("🔰 阵型: " .. name)
    end
end

------------------------------------------------------------
-- 构建 UI
------------------------------------------------------------

function M.show()
    if menuRoot then return end  -- 已经显示

    initPreviewEntities()

    local FormationSelectUI = require("FormationSelectUI")

    -- 顶栏
    local rep = TS.getReputation()
    local level = math.floor(rep / 100) + 1  -- 每100声望升1级
    local topBar = UI.Panel {
        position = "fixed", top = 0, left = 0, right = 0,
        height = 48,
        backgroundColor = {0, 0, 0, 80},
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        children = {
            -- 头像
            UI.Panel {
                width = 36, height = 36,
                borderRadius = 18,
                backgroundColor = T.colors.primary,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label { text = tostring(level), fontSize = 14, fontColor = T.colors.textOnDark, textAlign = "center" },
                }
            },
            -- 玩家信息
            UI.Panel {
                marginLeft = 8, flexGrow = 1,
                children = {
                    UI.Label { text = "统帅Lv." .. level, fontSize = 13, fontColor = T.colors.textOnDark },
                    UI.Label { text = "♦" .. rep, fontSize = 11, fontColor = T.colors.gold },
                }
            },
            -- 设置按钮
            UI.Button {
                text = "⚙",
                fontSize = 20,
                width = 36, height = 36,
                backgroundColor = {0,0,0,0},
                textColor = T.colors.textOnDark,
                onClick = function(self)
                    UI.Toast.Show("即将开放", { variant = "info", position = "top" })
                end,
            },
        }
    }

    -- 游戏标题
    local titlePanel = UI.Panel {
        position = "absolute",
        top = "25%", left = 0, right = 0,
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            UI.Label {
                text = "代号：统帅",
                fontSize = 28,
                fontColor = T.colors.textOnDark,
                textStroke = { width = 3, color = {50, 50, 60, 200} },
                textAlign = "center",
            },
            UI.Label {
                text = "征服四方",
                fontSize = 14,
                fontColor = {255, 255, 255, 160},
                textAlign = "center",
                marginTop = 4,
            },
        }
    }

    -- 左侧功能栏
    local sideIcons = {"🏆", "📖", "📋"}
    local sideLabels = {"天赋", "图鉴", "预设"}
    local sideChildren = {}
    for i, icon in ipairs(sideIcons) do
        table.insert(sideChildren, UI.Button {
            text = icon,
            fontSize = 20,
            width = 48, height = 48,
            backgroundColor = {0, 0, 0, 60},
            borderRadius = T.radius.md,
            textColor = T.colors.textOnDark,
            opacity = 0.4,
            onClick = function(self)
                UI.Toast.Show(sideLabels[i] .. " - 即将开放", { variant = "info", position = "top" })
            end,
        })
    end
    local sideBar = UI.Panel {
        position = "absolute",
        left = 8, top = "35%",
        gap = 8,
        pointerEvents = "box-none",
        children = sideChildren,
    }

    -- 底部操作区 — 模式标签
    local modeTabs = UI.Tabs {
        tabs = {
            { id = "skirmish", label = "⚔遭遇战" },
            { id = "campaign", label = "📜战役" },
            { id = "endless",  label = "🌊无尽" },
        },
        activeTab = GS.gameMode,
        variant = "pills",
        orientation = "horizontal",
        onChange = function(self, tabId, tab)
            GS.gameMode = tabId
            updateModeInfoCard()
        end,
    }

    -- 模式信息卡
    local l1, l2, l3 = getModeInfo(GS.gameMode)
    modeInfoLabel1 = UI.Label { text = l1, fontSize = T.fontSize.body, fontColor = T.colors.textPrimary }
    modeInfoLabel2 = UI.Label { text = l2, fontSize = T.fontSize.body, fontColor = T.colors.textPrimary }
    modeInfoLabel3 = UI.Label { text = l3, fontSize = T.fontSize.small, fontColor = T.colors.textSecondary, marginTop = 4 }

    local infoCard = UI.Panel {
        width = "90%",
        backgroundColor = T.colors.cardBg,
        borderRadius = T.radius.md,
        boxShadow = T.shadow,
        padding = 12,
        alignSelf = "center",
        marginTop = 8,
        children = {
            modeInfoLabel1,
            modeInfoLabel2,
            modeInfoLabel3,
        }
    }

    -- CTA 按钮
    local ctaButton = UI.Button {
        text = "开始游戏",
        fontSize = T.fontSize.cta,
        width = "70%", height = 52,
        alignSelf = "center",
        marginTop = 12,
        borderRadius = 26,
        backgroundGradient = {
            type = "linear", direction = "to-bottom",
            from = T.colors.accent, to = T.colors.accentDark,
        },
        textColor = T.colors.textOnDark,
        textStroke = { width = 1, color = {200, 100, 0, 150} },
        transition = "scale 0.15s easeOut",
        onClick = function(self)
            M.onStartGame()
        end,
    }

    -- 阵型入口
    local fmtName = FS.getName(GS.menuFormationId) or GS.menuFormationId
    formationLabel = UI.Label {
        text = "🔰 阵型: " .. fmtName,
        fontSize = 12,
        fontColor = T.colors.textSecondary,
        textAlign = "center",
        marginTop = 8,
    }
    local formationBtn = UI.Panel {
        alignSelf = "center",
        marginTop = 0, marginBottom = 16,
        pointerEvents = "auto",
        onClick = function(self)
            FormationSelectUI.show(GS.menuFormationId, function(newId)
                GS.menuFormationId = newId
                updateFormationLabel()
            end)
        end,
        children = { formationLabel },
    }

    -- 底部容器
    local bottomArea = UI.Panel {
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        alignItems = "center",
        paddingTop = 8, paddingBottom = 16,
        pointerEvents = "box-none",
        children = {
            modeTabs,
            infoCard,
            ctaButton,
            formationBtn,
        }
    }

    -- 组装根节点
    menuRoot = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            topBar,
            titlePanel,
            sideBar,
            bottomArea,
        }
    }

    UI.SetRoot(menuRoot)
    print("[MainMenuUI] Shown")
end

function M.hide()
    if menuRoot then
        menuRoot:Destroy()
        menuRoot = nil
        modeInfoLabel1 = nil
        modeInfoLabel2 = nil
        modeInfoLabel3 = nil
        formationLabel = nil
    end
    print("[MainMenuUI] Hidden")
end

------------------------------------------------------------
-- 开始游戏逻辑
------------------------------------------------------------

function M.onStartGame()
    if GS.gameMode == "skirmish" then
        M.hide()
        GS.setFormation(1, GS.menuFormationId)
        -- initGame 由 main.lua 提供，通过闭包注入
        if M.initGameFn then M.initGameFn("skirmish") end
    elseif GS.gameMode == "campaign" then
        M.hide()
        GS.gameState = "campaign_select"
        local CampaignSelectUI = require("CampaignSelectUI")
        CampaignSelectUI.show(function(levelId)
            GS.setFormation(1, GS.menuFormationId)
            if M.initGameFn then M.initGameFn("campaign") end
        end)
    elseif GS.gameMode == "endless" then
        M.hide()
        GS.setFormation(1, GS.menuFormationId)
        if M.initGameFn then M.initGameFn("endless") end
    end
end

return M
```

- [ ] **Step 2: main.lua — 取消注释 MainMenuUI require 并连接**

在 `scripts/main.lua` 中：

1. 取消注释 `local MainMenuUI = require("MainMenuUI")`
2. 在 `Start()` 的云加载完成处，替换为：
```lua
                    GS.gameState = "main_menu"
                    MainMenuUI.initGameFn = initGame
                    MainMenuUI.show()
```
3. 在 `HandleUpdate` 路由中，取消注释：
```lua
        MainMenuUI.updatePreview(dt)
```
4. 在 `HandleNanoVGRender` 路由中，取消注释：
```lua
        MainMenuUI.drawPreview(nvg, w, h)
```

- [ ] **Step 3: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建可能因为 FormationSelectUI/CampaignSelectUI/EndlessShopUI 不存在而失败。如果 require 是延迟的（在函数内部），则应该通过。否则需要先创建空的占位模块。

- [ ] **Step 4: 创建占位模块（如需要）**

如果 Step 3 构建失败，创建三个空占位模块：

`scripts/FormationSelectUI.lua`:
```lua
local M = {}
function M.show(currentId, onConfirm) print("[FormationSelectUI] TODO") end
function M.hide() end
return M
```

`scripts/CampaignSelectUI.lua`:
```lua
local M = {}
function M.show(onStartLevel) print("[CampaignSelectUI] TODO") end
function M.hide() end
return M
```

`scripts/EndlessShopUI.lua`:
```lua
local M = {}
function M.show(waveNumber, onNextWave) print("[EndlessShopUI] TODO") end
function M.hide() end
function M.updateCountdown(dt) end
return M
```

- [ ] **Step 5: 再次构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过。启动后看到主菜单 UI 叠加在 NanoVG 背景预览上。

- [ ] **Step 6: Commit**

```bash
git add scripts/MainMenuUI.lua scripts/FormationSelectUI.lua scripts/CampaignSelectUI.lua scripts/EndlessShopUI.lua scripts/main.lua
git commit -m "feat(ui): add MainMenuUI with background preview and mode selection"
```

---

### Task 4: FormationSelectUI — 阵型选择 Drawer

**Files:**
- Modify: `scripts/FormationSelectUI.lua` — 替换占位实现

- [ ] **Step 1: 实现 FormationSelectUI.lua**

```lua
-- scripts/FormationSelectUI.lua
local UI = require("urhox-libs/UI")
local GS = require("GameState")
local FS = require("FormationSystem")
local T = require("MenuTheme")

local M = {}

local drawer = nil
local selectedId = nil
local onConfirmCb = nil
local cardWidgets = {}

-- 阵型符号映射
local symbols = {
    cone = "△", phalanx = "▣", arc = "⌒",
    crane_wing = "W", chaos = "✦", celestial = "☆",
}

-- 简要 buff 描述
local buffDesc = {
    cone = "速度+20%, 前方伤害+40%",
    phalanx = "护甲+30%, 速度-15%",
    arc = "射程+25%, 远程伤害+20%",
    crane_wing = "侧翼伤害+50%",
    chaos = "全属性+10%, 20%减伤",
    celestial = "法术伤害+60%, CD-30%",
}

local function updateSelection(newId)
    local oldId = selectedId
    selectedId = newId
    -- 更新卡片视觉
    for fmtId, card in pairs(cardWidgets) do
        if fmtId == newId then
            card:SetStyle({
                borderColor = T.colors.primary,
                borderWidth = 2,
                scale = 1.05,
            })
        else
            card:SetStyle({
                borderColor = {200, 200, 200, 255},
                borderWidth = 1,
                scale = 1.0,
            })
        end
    end
end

function M.show(currentFormationId, onConfirm)
    if drawer then return end

    selectedId = currentFormationId or "cone"
    onConfirmCb = onConfirm
    cardWidgets = {}

    -- 构建阵型卡片
    local cards = {}
    for _, fmtId in ipairs(FS.FormationOrder) do
        local fmt = FS.Formations[fmtId]
        local isSelected = (fmtId == selectedId)

        local card = UI.Panel {
            backgroundColor = {255, 255, 255, 255},
            borderRadius = T.radius.md,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and T.colors.primary or {200, 200, 200, 255},
            padding = 10,
            alignItems = "center",
            justifyContent = "center",
            transition = "scale 0.15s easeOut, borderColor 0.15s easeOut",
            scale = isSelected and 1.05 or 1.0,
            pointerEvents = "auto",
            onClick = function(self)
                updateSelection(fmtId)
            end,
            children = {
                UI.Label {
                    text = symbols[fmtId] or "?",
                    fontSize = 28,
                    fontColor = T.colors.primary,
                    textAlign = "center",
                },
                UI.Label {
                    text = fmt.name,
                    fontSize = 14,
                    fontColor = T.colors.textPrimary,
                    textAlign = "center",
                    marginTop = 4,
                },
                UI.Label {
                    text = buffDesc[fmtId] or "",
                    fontSize = 11,
                    fontColor = T.colors.textSecondary,
                    textAlign = "center",
                    marginTop = 2,
                },
            }
        }
        cardWidgets[fmtId] = card
        table.insert(cards, card)
    end

    -- 网格布局
    local grid = UI.SimpleGrid {
        columns = 2,
        gap = 12,
        padding = 16,
        children = cards,
    }

    -- 确认按钮
    local confirmBtn = UI.Button {
        text = "确认选择",
        fontSize = 15,
        width = "80%", height = 44,
        alignSelf = "center",
        marginTop = 12, marginBottom = 16,
        borderRadius = T.radius.pill,
        backgroundColor = T.colors.primary,
        textColor = T.colors.textOnDark,
        transition = "scale 0.15s easeOut",
        onClick = function(self)
            if onConfirmCb and selectedId then
                onConfirmCb(selectedId)
            end
            M.hide()
        end,
    }

    -- Drawer 内容
    local content = UI.Panel {
        width = "100%",
        backgroundColor = T.colors.cardBg,
        borderRadiusTopLeft = T.radius.lg,
        borderRadiusTopRight = T.radius.lg,
        borderRadiusBottomLeft = 0,
        borderRadiusBottomRight = 0,
        children = {
            -- 标题
            UI.Label {
                text = "选择阵型",
                fontSize = T.fontSize.subtitle,
                fontColor = T.colors.textPrimary,
                textAlign = "center",
                marginTop = 16, marginBottom = 4,
            },
            UI.Divider { spacing = 8, color = {200, 200, 200, 100} },
            grid,
            confirmBtn,
        }
    }

    drawer = UI.Drawer {
        position = "bottom",
        size = "65%",
        onClose = function(self)
            M.hide()
        end,
        children = { content },
    }

    drawer:Open()
    print("[FormationSelectUI] Shown")
end

function M.hide()
    if drawer then
        drawer:Close()
        drawer = nil
        cardWidgets = {}
        onConfirmCb = nil
    end
end

return M
```

- [ ] **Step 2: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过。在主菜单点击阵型入口可打开底部 Drawer。

- [ ] **Step 3: Commit**

```bash
git add scripts/FormationSelectUI.lua
git commit -m "feat(ui): implement FormationSelectUI drawer with grid cards"
```

---

### Task 5: CampaignSelectUI — 战役关卡选择

**Files:**
- Modify: `scripts/CampaignSelectUI.lua` — 替换占位实现

- [ ] **Step 1: 实现 CampaignSelectUI.lua**

```lua
-- scripts/CampaignSelectUI.lua
local UI = require("urhox-libs/UI")
local GS = require("GameState")
local CD = require("CampaignData")
local CS = require("CampaignState")
local T = require("MenuTheme")

local M = {}

local pageRoot = nil
local onStartLevelCb = nil
local selectedLevelId = nil
local selectedChapter = 1

-- UI 引用
local levelListContainer = nil
local detailPanel = nil
local detailEnemyLabel = nil
local detailRewardLabel = nil
local chapterTitleLabel = nil

------------------------------------------------------------
-- 辅助函数
------------------------------------------------------------

local function formatEnemies(enemies)
    if not enemies then return "未知" end
    local parts = {}
    for _, group in ipairs(enemies) do
        for uType, count in pairs(group.units) do
            table.insert(parts, count .. uType)
        end
    end
    return "敌军: " .. table.concat(parts, " + ")
end

local function formatReward(reward)
    if not reward then return "无特殊奖励" end
    if reward.type == "unit" then
        return "解锁兵种: " .. reward.id
    elseif reward.type == "formation" then
        return "解锁阵型: " .. reward.id
    end
    return "奖励: " .. tostring(reward.id)
end

------------------------------------------------------------
-- 关卡列表构建
------------------------------------------------------------

local function buildLevelList(chapter)
    if not levelListContainer then return end

    -- 清空现有子节点
    -- 通过重新构建方式
    local levels = CD.getLevelsByChapter(chapter)
    if not levels then return end

    local children = {}
    for _, levelId in ipairs(levels) do
        local level = CD.getLevel(levelId)
        if not level then goto continue end

        local cleared = CS.isCleared(levelId)
        local accessible = CS.isLevelAccessible(levelId)
        local isSelected = (levelId == selectedLevelId)

        -- 色条颜色
        local barColor = cleared and T.colors.success or T.colors.textSecondary
        if isSelected then barColor = T.colors.primary end

        -- 通关标记
        local statusText = cleared and "✓" or ""

        -- 敌人概要
        local enemySummary = ""
        if level.enemies and #level.enemies > 0 then
            local total = 0
            for _, g in ipairs(level.enemies) do
                for _, c in pairs(g.units) do total = total + c end
            end
            enemySummary = "👥" .. total .. "敌"
        end

        local card = UI.Panel {
            width = "92%",
            height = 72,
            alignSelf = "center",
            marginBottom = 8,
            flexDirection = "row",
            alignItems = "center",
            backgroundColor = isSelected and {70, 160, 255, 30} or T.colors.cardBg,
            borderRadius = T.radius.md,
            boxShadow = T.shadow,
            opacity = accessible and 1.0 or 0.4,
            transition = "backgroundColor 0.2s easeOut",
            pointerEvents = accessible and "auto" or "none",
            onClick = function(self)
                if accessible then
                    selectedLevelId = levelId
                    buildLevelList(chapter)  -- 刷新选中态
                    updateDetailPanel()
                end
            end,
            children = {
                -- 左侧色条
                UI.Panel {
                    width = 4, height = "100%",
                    backgroundColor = barColor,
                    borderRadiusTopLeft = T.radius.md,
                    borderRadiusBottomLeft = T.radius.md,
                },
                -- 主内容
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    paddingLeft = 12, paddingRight = 12,
                    justifyContent = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = levelId .. " " .. (level.name or ""),
                                    fontSize = 14, fontColor = T.colors.textPrimary,
                                    flexShrink = 1,
                                },
                                UI.Label {
                                    text = cleared and "✓ 已通关" or (not accessible and "🔒" or ""),
                                    fontSize = 12,
                                    fontColor = cleared and T.colors.success or T.colors.textSecondary,
                                },
                            }
                        },
                        UI.Label {
                            text = enemySummary,
                            fontSize = 11, fontColor = T.colors.textSecondary,
                            marginTop = 2,
                        },
                    }
                },
            }
        }
        table.insert(children, card)

        ::continue::
    end

    -- 重建列表内容 — 通过销毁旧的并创建新的 ScrollView
    if pageRoot then
        M.hide()
        M.show(onStartLevelCb)
    end
end

local function updateDetailPanel()
    if not selectedLevelId then
        if detailPanel then detailPanel:Hide() end
        return
    end
    local level = CD.getLevel(selectedLevelId)
    if not level then return end

    if detailPanel then detailPanel:Show() end
    if detailEnemyLabel then detailEnemyLabel:SetText(formatEnemies(level.enemies)) end
    if detailRewardLabel then detailRewardLabel:SetText(formatReward(level.reward)) end
end

------------------------------------------------------------
-- 检查章节是否解锁
------------------------------------------------------------

local function isChapterUnlocked(chapterIndex)
    if chapterIndex <= 1 then return true end
    -- 前一章所有关卡都已通关
    local prevChapter = CD.Chapters[chapterIndex - 1]
    if not prevChapter then return false end
    local prevLevels = CD.getLevelsByChapter(chapterIndex - 1)
    if not prevLevels then return false end
    for _, levelId in ipairs(prevLevels) do
        if not CS.isCleared(levelId) then return false end
    end
    return true
end

------------------------------------------------------------
-- 主界面
------------------------------------------------------------

function M.show(onStartLevel)
    if pageRoot then return end

    onStartLevelCb = onStartLevel
    selectedLevelId = nil
    selectedChapter = CS.getCurrentChapter()

    -- 顶栏
    local chName = CD.Chapters[selectedChapter] and CD.Chapters[selectedChapter].name or "未知"
    chapterTitleLabel = UI.Label {
        text = chName,
        fontSize = T.fontSize.subtitle,
        fontColor = T.colors.textOnDark,
        textAlign = "center",
        flexGrow = 1,
    }

    local topBar = UI.Panel {
        height = 48,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        backgroundGradient = {
            type = "linear", direction = "to-right",
            from = T.colors.primary, to = {100, 180, 255, 255},
        },
        children = {
            UI.Button {
                text = "← 返回",
                fontSize = 14,
                backgroundColor = {0,0,0,0},
                textColor = T.colors.textOnDark,
                onClick = function(self)
                    M.hide()
                    GS.gameState = "main_menu"
                    local MainMenuUI = require("MainMenuUI")
                    MainMenuUI.show()
                end,
            },
            chapterTitleLabel,
            UI.Panel { width = 60 },  -- spacer
        }
    }

    -- 章节标签
    local chapterTabData = {}
    for i, ch in ipairs(CD.Chapters) do
        local unlocked = isChapterUnlocked(i)
        table.insert(chapterTabData, {
            id = tostring(i),
            label = ch.name .. (unlocked and "" or "🔒"),
        })
    end

    local chapterTabs = UI.Tabs {
        tabs = chapterTabData,
        activeTab = tostring(selectedChapter),
        variant = "pills",
        onChange = function(self, tabId)
            local idx = tonumber(tabId)
            if not isChapterUnlocked(idx) then
                UI.Toast.Show("通关前一章节后解锁", { variant = "warning", position = "top" })
                return
            end
            selectedChapter = idx
            selectedLevelId = nil
            local ch = CD.Chapters[selectedChapter]
            if chapterTitleLabel and ch then
                chapterTitleLabel:SetText(ch.name)
            end
            -- 刷新列表需要重建
            M.hide()
            M.show(onStartLevelCb)
        end,
    }

    -- 关卡卡片列表
    local levels = CD.getLevelsByChapter(selectedChapter) or {}
    local levelCards = {}
    for _, levelId in ipairs(levels) do
        local level = CD.getLevel(levelId)
        if not level then goto continue end

        local cleared = CS.isCleared(levelId)
        local accessible = CS.isLevelAccessible(levelId)

        local enemySummary = ""
        if level.enemies and #level.enemies > 0 then
            local total = 0
            for _, g in ipairs(level.enemies) do
                for _, c in pairs(g.units) do total = total + c end
            end
            enemySummary = "👥" .. total .. "敌"
        end

        local card = UI.Panel {
            width = "92%", height = 72,
            alignSelf = "center", marginBottom = 8,
            flexDirection = "row", alignItems = "center",
            backgroundColor = T.colors.cardBg,
            borderRadius = T.radius.md,
            boxShadow = T.shadow,
            opacity = accessible and 1.0 or 0.4,
            pointerEvents = accessible and "auto" or "none",
            onClick = function(self)
                if accessible then
                    selectedLevelId = levelId
                    updateDetailPanel()
                    -- 视觉更新：重建
                    M.hide()
                    M.show(onStartLevelCb)
                end
            end,
            children = {
                UI.Panel {
                    width = 4, height = "100%",
                    backgroundColor = (selectedLevelId == levelId) and T.colors.primary or (cleared and T.colors.success or T.colors.textSecondary),
                    borderRadiusTopLeft = T.radius.md, borderRadiusBottomLeft = T.radius.md,
                },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    paddingLeft = 12, paddingRight = 12,
                    justifyContent = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            children = {
                                UI.Label { text = levelId .. " " .. (level.name or ""), fontSize = 14, fontColor = T.colors.textPrimary, flexShrink = 1 },
                                UI.Label {
                                    text = cleared and "✓" or (not accessible and "🔒" or ""),
                                    fontSize = 12, fontColor = cleared and T.colors.success or T.colors.textSecondary,
                                },
                            }
                        },
                        UI.Label { text = enemySummary, fontSize = 11, fontColor = T.colors.textSecondary, marginTop = 2 },
                    }
                },
            }
        }
        table.insert(levelCards, card)
        ::continue::
    end

    local scrollView = UI.ScrollView {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        scrollY = true,
        paddingTop = 8,
        children = levelCards,
    }

    -- 底部详情栏
    detailEnemyLabel = UI.Label { text = "", fontSize = T.fontSize.body, fontColor = T.colors.textPrimary }
    detailRewardLabel = UI.Label { text = "", fontSize = T.fontSize.small, fontColor = T.colors.textSecondary, marginTop = 4 }

    local startBtn = UI.Button {
        text = "⚔ 出战",
        fontSize = T.fontSize.subtitle,
        width = "70%", height = 44,
        alignSelf = "center",
        marginTop = 8,
        borderRadius = T.radius.pill,
        backgroundGradient = {
            type = "linear", direction = "to-bottom",
            from = T.colors.accent, to = T.colors.accentDark,
        },
        textColor = T.colors.textOnDark,
        transition = "scale 0.15s easeOut",
        onClick = function(self)
            if selectedLevelId and onStartLevelCb then
                GS.campaignLevelId = selectedLevelId
                M.hide()
                onStartLevelCb(selectedLevelId)
            else
                UI.Toast.Show("请先选择一个关卡", { variant = "warning", position = "bottom" })
            end
        end,
    }

    detailPanel = UI.Panel {
        height = 120,
        backgroundColor = T.colors.cardBg,
        borderRadiusTopLeft = T.radius.lg, borderRadiusTopRight = T.radius.lg,
        padding = 12,
        children = {
            detailEnemyLabel,
            detailRewardLabel,
            startBtn,
        }
    }
    if not selectedLevelId then detailPanel:Hide() end

    -- 组装
    pageRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = {240, 242, 248, 255},
        children = {
            topBar,
            chapterTabs,
            scrollView,
            detailPanel,
        }
    }

    UI.SetRoot(pageRoot)
    updateDetailPanel()
    print("[CampaignSelectUI] Shown, chapter=" .. selectedChapter)
end

function M.hide()
    if pageRoot then
        pageRoot:Destroy()
        pageRoot = nil
        detailPanel = nil
        detailEnemyLabel = nil
        detailRewardLabel = nil
        chapterTitleLabel = nil
    end
end

return M
```

- [ ] **Step 2: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过。主菜单选择"战役"模式后点击"开始游戏"进入关卡选择页。

- [ ] **Step 3: Commit**

```bash
git add scripts/CampaignSelectUI.lua
git commit -m "feat(ui): implement CampaignSelectUI with chapter tabs and level list"
```

---

### Task 6: EndlessShopUI — 无尽模式波次间商店

**Files:**
- Modify: `scripts/EndlessShopUI.lua` — 替换占位实现
- Modify: `scripts/main.lua` — 取消注释 EndlessShopUI 路由

- [ ] **Step 1: 实现 EndlessShopUI.lua**

```lua
-- scripts/EndlessShopUI.lua
local UI = require("urhox-libs/UI")
local GS = require("GameState")
local Shop = require("ShopSystem")
local EM = require("EndlessMode")
local T = require("MenuTheme")

local M = {}

local modal = nil
local onNextWaveCb = nil
local countdownTimer = 5.0
local countdownLabel = nil
local coinLabel = nil
local itemButtons = {}

-- buff 图标映射
local buffIcons = {
    "⚔", "🛡", "❤", "⚡", "👥", "💥",
    "🎯", "🔥", "💎", "🌟",
}

local function refreshUI()
    -- 更新余额
    local info = EM.getWaveInfo()
    local coins = info and info.warCoins or 0
    if coinLabel then coinLabel:SetText("💰 战争币: " .. coins) end

    -- 更新按钮状态
    local items = Shop.getItems()
    for i, btn in ipairs(itemButtons) do
        local item = items[i]
        if item then
            if item.bought then
                btn:SetText("已拥有")
                btn:SetStyle({ backgroundColor = T.colors.success, opacity = 0.7 })
                btn.disabled = true
            elseif coins < (item.cost or 0) then
                btn:SetText("不足")
                btn:SetStyle({ backgroundColor = {150, 150, 150, 255}, opacity = 0.5 })
                btn.disabled = true
            else
                btn:SetText("购买")
                btn:SetStyle({ backgroundColor = T.colors.primary, opacity = 1.0 })
                btn.disabled = false
            end
        end
    end
end

function M.updateCountdown(dt)
    if not modal then return end
    countdownTimer = countdownTimer - dt
    if countdownLabel then
        local sec = math.max(0, math.ceil(countdownTimer))
        countdownLabel:SetText("⚔ 下一波 (" .. sec .. "s)")
    end
    if countdownTimer <= 0 then
        M.startNextWave()
    end
end

local function startNextWave()
    if onNextWaveCb then onNextWaveCb() end
    M.hide()
end
M.startNextWave = startNextWave

function M.show(waveNumber, onNextWave)
    if modal then return end

    onNextWaveCb = onNextWave
    countdownTimer = 5.0
    itemButtons = {}

    local info = EM.getWaveInfo()
    local coins = info and info.warCoins or 0

    -- 商品列表
    local items = Shop.getItems()
    local cards = {}
    for i, item in ipairs(items) do
        local icon = buffIcons[i] or "?"
        local buyBtn = UI.Button {
            text = (coins >= (item.cost or 0)) and "购买" or "不足",
            fontSize = 12,
            height = 28,
            width = "80%",
            alignSelf = "center",
            marginTop = 6,
            borderRadius = T.radius.sm,
            backgroundColor = (coins >= (item.cost or 0)) and T.colors.primary or {150, 150, 150, 255},
            textColor = T.colors.textOnDark,
            transition = "scale 0.15s easeOut",
            onClick = function(self)
                if not self.disabled then
                    Shop.buy(i)
                    refreshUI()
                end
            end,
        }
        itemButtons[i] = buyBtn

        local card = UI.Panel {
            backgroundColor = {255, 255, 255, 255},
            borderRadius = T.radius.md,
            padding = 8,
            alignItems = "center",
            children = {
                UI.Label { text = icon, fontSize = 24, textAlign = "center" },
                UI.Label { text = item.name or ("buff" .. i), fontSize = 12, fontColor = T.colors.textPrimary, textAlign = "center", marginTop = 4 },
                UI.Label { text = "💰" .. (item.cost or 0), fontSize = 12, fontColor = T.colors.gold, textAlign = "center", marginTop = 2 },
                buyBtn,
            }
        }
        table.insert(cards, card)
    end

    local grid = UI.SimpleGrid {
        columns = 2,
        gap = 10,
        padding = 12,
        children = cards,
    }

    -- 倒计时按钮
    countdownLabel = UI.Label {
        text = "⚔ 下一波 (5s)",
        fontSize = T.fontSize.subtitle,
        fontColor = T.colors.textOnDark,
        textAlign = "center",
    }

    local nextWaveBtn = UI.Button {
        width = "80%", height = 44,
        alignSelf = "center",
        marginTop = 8, marginBottom = 12,
        borderRadius = T.radius.pill,
        backgroundGradient = {
            type = "linear", direction = "to-bottom",
            from = T.colors.accent, to = T.colors.accentDark,
        },
        textColor = T.colors.textOnDark,
        transition = "scale 0.15s easeOut",
        onClick = function(self)
            startNextWave()
        end,
        children = { countdownLabel },
    }

    -- 余额
    coinLabel = UI.Label {
        text = "💰 战争币: " .. coins,
        fontSize = 14,
        fontColor = T.colors.gold,
        textAlign = "center",
    }

    -- Modal
    modal = UI.Modal {
        size = "lg",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
        onClose = function(self) end,
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Label {
                text = "🌊 第 " .. waveNumber .. " 波 完成!",
                fontSize = T.fontSize.title,
                fontColor = T.colors.textPrimary,
                textAlign = "center",
                marginTop = 8,
            },
            coinLabel,
            UI.Divider { spacing = 8, color = {200, 200, 200, 100} },
            grid,
            nextWaveBtn,
        }
    })

    modal:Open()
    print("[EndlessShopUI] Shown, wave=" .. waveNumber)
end

function M.hide()
    if modal then
        modal:Close()
        modal = nil
        countdownLabel = nil
        coinLabel = nil
        itemButtons = {}
        onNextWaveCb = nil
    end
end

return M
```

- [ ] **Step 2: main.lua — 取消注释 EndlessShopUI 路由**

在 `HandleUpdate` 中取消注释：
```lua
        EndlessShopUI.updateCountdown(dt)
```

在 `main.lua` 顶部取消注释：
```lua
local EndlessShopUI = require("EndlessShopUI")
```

- [ ] **Step 3: 连接 EndlessMode 到商店 UI**

在 `scripts/main.lua` 中，找到 `updateGame(dt)` 函数调用处。在 EndlessMode 清波后触发商店需要从 EndlessMode 内部调用。

检查 `EndlessMode.lua` 是否已有商店触发逻辑（`onWaveCleared` 回调）。如果已有，需要在该回调中添加：

```lua
-- 在 EndlessMode.onWaveCleared() 或类似位置
GS.gameState = "endless_shop"
local EndlessShopUI = require("EndlessShopUI")
local info = EM.getWaveInfo()
EndlessShopUI.show(info.wave, function()
    GS.gameState = "playing"
    EM.nextWave()
end)
```

如果 EndlessMode 已自行处理商店阶段（检查 `endlessState == "shop"`），则保持原有逻辑，仅添加 UI 层。

- [ ] **Step 4: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过。

- [ ] **Step 5: Commit**

```bash
git add scripts/EndlessShopUI.lua scripts/main.lua
git commit -m "feat(ui): implement EndlessShopUI modal with countdown and buy"
```

---

### Task 7: 全模块集成 + 最终取消注释

**Files:**
- Modify: `scripts/main.lua` — 取消所有注释的 require 和调用

- [ ] **Step 1: 取消所有注释的 require**

在 `main.lua` 顶部，确保以下行全部取消注释：

```lua
local MainMenuUI = require("MainMenuUI")
local FormationSelectUI = require("FormationSelectUI")
local CampaignSelectUI = require("CampaignSelectUI")
local EndlessShopUI = require("EndlessShopUI")
local MenuTheme = require("MenuTheme")
```

- [ ] **Step 2: 确认所有路由调用已取消注释**

在 `HandleUpdate` 中确认：
```lua
    if GS.gameState == "main_menu" then
        MainMenuUI.updatePreview(dt)
        return
    elseif GS.gameState == "campaign_select" then
        return
    elseif GS.gameState == "endless_shop" then
        EndlessShopUI.updateCountdown(dt)
        return
    end
```

在 `HandleNanoVGRender` 中确认：
```lua
    if GS.gameState == "main_menu" then
        MainMenuUI.drawPreview(nvg, w, h)
        nvgEndFrame(nvg)
        return
    end
```

在 `Start()` 云加载完成处确认：
```lua
                    GS.gameState = "main_menu"
                    MainMenuUI.initGameFn = initGame
                    MainMenuUI.show()
```

- [ ] **Step 3: 添加游戏结束后返回主菜单**

在现有的游戏结束逻辑中（`Renderer.drawGameOverScreen` 或 `HandleMouseDown` 中处理结束屏幕点击的地方），添加返回主菜单的路径：

搜索 `gameover` 或 `victory` 相关的点击处理，在重新开始的逻辑处替换为：

```lua
-- 游戏结束后返回主菜单（替换直接 initGame）
GS.gameState = "main_menu"
MainMenuUI.initGameFn = initGame
MainMenuUI.show()
```

- [ ] **Step 4: 最终构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过。完整流程可测：主菜单 → 选模式 → 选阵型 → 开始游戏 → 游戏中 → 结束 → 返回主菜单。

- [ ] **Step 5: Commit**

```bash
git add scripts/main.lua
git commit -m "feat(ui): integrate all menu screens with full game flow"
```

---

### Task 8: 视觉打磨 + Bug 修复

**Files:**
- 可能修改: 所有 UI 模块

- [ ] **Step 1: 标题呼吸动画**

在 `MainMenuUI.lua` 的标题 Label 创建后，添加呼吸动画：

```lua
-- 标题呼吸动画
titleLabel:Animate({
    keyframes = {
        [0]   = { scale = 1.0 },
        [0.5] = { scale = 1.03 },
        [1]   = { scale = 1.0 },
    },
    duration = 2.0,
    loop = true,
    direction = "alternate",
    easing = "easeInOut",
})
```

- [ ] **Step 2: 按钮按压效果**

确认所有 CTA 按钮的 `transition` 和按压缩放已正确配置。如果 UI 库不自动处理 pressed 态的 scale，需要通过 `pressedScale` 或手动 `onTouchStart/onTouchEnd` 实现。

- [ ] **Step 3: 界面进场动画**

在 `M.show()` 最后，为 `menuRoot` 添加进场动画：

```lua
menuRoot:Animate({
    keyframes = {
        [0] = { opacity = 0, translateY = 20 },
        [1] = { opacity = 1, translateY = 0 },
    },
    duration = 0.3,
    easing = "easeOutBack",
})
```

- [ ] **Step 4: 构建验证**

运行 UrhoX MCP `build` 工具。
预期：构建通过，动画流畅。

- [ ] **Step 5: Commit**

```bash
git add scripts/MainMenuUI.lua scripts/FormationSelectUI.lua scripts/CampaignSelectUI.lua scripts/EndlessShopUI.lua
git commit -m "polish(ui): add animations and visual polish to menu screens"
```
