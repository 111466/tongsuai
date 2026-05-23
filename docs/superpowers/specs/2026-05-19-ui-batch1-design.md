# 代号：统帅 — UI 第一批设计规格

## 概述

为「代号：统帅」2D 俯视角 RTS/IO 游戏设计第一批 UI 界面，使后端已实现的三种游戏模式（遭遇战/战役/无尽）和阵型系统可被玩家访问。

**目标平台：** 移动端竖屏
**视觉风格：** 明快卡通
**参考：** 球球大作战式布局（游戏世界作为背景，UI 叠加，底部操作区单手可达）
**技术栈：** UrhoX `urhox-libs/UI`（Yoga Flexbox + NanoVG 渲染）
**实现范围：** 4 个界面 — 主菜单、阵型选择、战役关卡选择、无尽商店

---

## 一、视觉主题

### 1.1 色板

| 语义名 | 用途 | RGBA |
|--------|------|------|
| `primary` | 按钮、标签选中、高亮 | `{70, 160, 255, 255}` |
| `accent` | CTA「开始游戏」按钮 | `{255, 150, 30, 255}` |
| `accentDark` | CTA 渐变底部 | `{235, 120, 10, 255}` |
| `success` | 已解锁、已完成、确认 | `{80, 200, 100, 255}` |
| `danger` | 锁定、消耗、警告 | `{255, 90, 70, 255}` |
| `gold` | 星星、战争币、奖励 | `{255, 210, 60, 255}` |
| `cardBg` | 半透明白色卡片 | `{255, 252, 245, 230}` |
| `overlay` | 遮罩、弹窗背景 | `{30, 35, 60, 200}` |
| `textPrimary` | 主要文字 | `{50, 50, 60, 255}` |
| `textSecondary` | 次要说明 | `{130, 135, 150, 255}` |
| `textOnDark` | 深色底上的白字 | `{255, 255, 255, 255}` |

### 1.2 风格规范

| 属性 | 值 |
|------|-----|
| 大组件圆角 | 16px |
| 卡片圆角 | 12px |
| 按钮圆角 | 24px（药丸形） |
| 小标签圆角 | 8px |
| 卡片阴影 | `boxShadow = {{ x=0, y=4, blur=12, spread=0, color={0,0,0,30} }}` |
| 字体 | MiSans-Regular（已加载） |
| 标题描边 | `textStroke = { width=2, color={255,255,255,200} }` |
| 按钮按压 | `transition = "scale 0.15s easeOut"`，按下 `scale=0.92` |
| 界面进场 | `translateY: 20→0` + `opacity: 0→1`，0.3s easeOutBack |

### 1.3 主题表（Lua 常量）

所有颜色、圆角、间距定义在一个 `MenuTheme` 表中，供四个界面共用：

```lua
local MenuTheme = {
    colors = {
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
    },
    radius = { lg = 16, md = 12, sm = 8, pill = 24 },
    shadow = { x=0, y=4, blur=12, spread=0, color={0,0,0,30} },
    fontSize = { title = 22, subtitle = 16, body = 13, small = 11, cta = 18 },
}
```

### 1.4 背景

主菜单背景为 NanoVG 渲染的游戏世界缩略预览：
- 绿色草地贴图平铺（复用 `Renderer.drawBackground(w, h)`）
- 随机撒几棵树和矿石（`Renderer.drawResources()` 内部已封装树/矿石绘制，需提前在 GS 中填充少量装饰用资源数据）
- 3-5 个 AI 小兵沿简单路径走动（复用 `Renderer.drawFollower(f)`，需构造简单的 follower 对象数组）
- 上方叠一层半透明渐变蒙版（顶部 `{30,35,60,180}` → 底部 `{30,35,60,80}`），确保 UI 文字可读
- 预览帧率降至 15fps 以节省性能
- **实现方案**：在 `MainMenuUI.lua` 中创建 `Renderer.drawMenuPreview(nvg, w, h)` 的封装函数，内部调用已有的 Renderer 方法绘制简化场景

---

## 二、主菜单

### 2.1 状态管理

新增 `GS.gameState` 值：`"main_menu"`。当 `gameState == "main_menu"` 时：
- NanoVG 渲染背景预览（低帧率）
- UI 组件显示主菜单
- 不执行 `updateGame()`

新增 GameState 字段：
- `GS.gameMode = "skirmish"` — 当前选中的模式标签（复用已有字段）
- `GS.menuFormationId = "cone"` — 主菜单当前选中的阵型 ID（新增，仅用于菜单显示；开局时写入 `GS.formationStates`）

### 2.2 布局

**顶栏**（fixed，高 48px）：
- 左侧：头像圆形 36x36（纯色圆圈 + 等级数字） + "统帅Lv.X" + 声望值 "♦128"
- 右侧：设置齿轮图标按钮 36x36
- 背景：半透明黑 `{0,0,0,80}`

**游戏标题**（absolute，屏幕 25% 高度位置）：
- "代号：统帅" 字号 28pt，白色，`textStroke={width=3, color={50,50,60,200}}`
- 副标题 "征服四方" 字号 14pt，白色半透明
- 标题呼吸动画：`scale` 在 1.0 ~ 1.03 间循环，2s alternate

**左侧功能栏**（absolute，屏幕左侧，垂直居中）：
- 3 个竖排图标按钮，每个 48x48，间距 8px
- 内容：天赋🏆、图鉴📖、预设📋
- 第一批全部灰显（`opacity=0.4`），点击弹 Toast "即将开放"
- 圆角 12，背景 `{0,0,0,60}`

**底部操作区**（absolute，屏幕底部，占约 45% 高度）：

1. **模式标签**（Tabs，pills 变体）：
   - 三个选项：⚔遭遇战 | 📜战役 | 🌊无尽
   - 选中态：`primary` 色填充 + 白字
   - 未选中态：透明底 + 白字
   - 切换时触发信息卡内容过渡

2. **模式信息卡**（Panel）：
   - 背景 `cardBg`，圆角 12，阴影
   - 宽度 90%，水平居中，高度自适应
   - 内容随 `GS.gameMode` 变化（transition `opacity 0.2s`）：

   | 模式 | 行1 | 行2 | 行3 |
   |------|-----|-----|-----|
   | skirmish | 📊 最高排名: --- | 🗡 最高击杀: --- | "4名领主混战，最后存活者胜" |
   | campaign | 📜 进度: 第X章 | ⭐ 已通关: N/17 | "挑战精心设计的关卡" |
   | endless | 🌊 最高波次: N | 💰 战争币: N | "抵御无尽敌潮，能撑多久？" |

   **数据来源（对应实际 API）**：
   - 遭遇战：暂无持久化统计，显示占位 "---"
   - 战役进度：`CampaignState.getCurrentChapter()` → 章节号，`#CampaignState.getClearedLevels()` → 已通关数，总关卡 17（3 章 6+6+5）
   - 无尽：`EndlessMode.getWaveInfo().bestWave` → 最高波次，`.warCoins` → 战争币

3. **CTA 按钮**「开始游戏」：
   - 宽 70%，高 52px，水平居中
   - 背景渐变：`accent` → `accentDark`（上→下）
   - 白字 18pt，`textStroke={width=1, color={200,100,0,150}}`
   - 药丸形圆角 26
   - 按压动画：`scale 0.92`

4. **阵型入口**：
   - 文字按钮 "🔰 阵型: 锥形阵"，居中（名称从 `FS.Formations[menuFormationId].name` 读取）
   - 字号 12pt，`textSecondary` 色
   - 点击打开阵型选择 Drawer

### 2.3 交互流程

```
点击「开始游戏」
  ├─ GS.gameMode == "skirmish"
  │   → GS.setFormation(1, GS.menuFormationId)
  │   → initGame("skirmish")
  │
  ├─ GS.gameMode == "campaign"
  │   → 切换到战役关卡选择界面（GS.gameState = "campaign_select"）
  │
  └─ GS.gameMode == "endless"
      → GS.setFormation(1, GS.menuFormationId)
      → initGame("endless")
```

---

## 三、阵型选择（底部 Drawer）

### 3.1 触发

- 主菜单点击「阵型: XX」文字按钮

### 3.2 布局

**Drawer**（从底部滑出，高度 65% 屏幕）：
- 顶部圆角 16px，背景 `cardBg`
- 上方遮罩 `overlay`

**标题行**：
- "选择阵型" 居中，字号 16pt，`textPrimary`

**阵型网格**（2 列，SimpleGrid，gap=12，padding=16）：

6 张卡片，每张包含：
- 阵型符号（大号文字 28pt 居中）：△ 锋矢 / ○ 方圆 / V 雁行 / ≋ 鱼鳞 / W 鹤翼 / ✦ 散星
- 阵型名称（14pt，居中）
- 核心 buff 一行文字（11pt，`textSecondary`）
- 未选中态：白底 + 灰色边框 1px
- 选中态：`primary` 色边框 2px + `scale=1.05` + 左上角蓝色角标 "✓"

阵型 ID 与 buff 描述（从 `FormationSystem.Formations` 表和 `FS.getBuffs(id)` 读取，遍历 `FS.FormationOrder` 获取顺序）：

| ID | 名称 | 符号 | buff 摘要 |
|----|------|------|----------|
| `cone` | 锥形阵 | △ | 速度+20%, 前方伤害+40% |
| `phalanx` | 方阵 | ▣ | 护甲+30%, 速度-15% |
| `arc` | 弧形阵 | ⌒ | 射程+25%, 远程伤害+20% |
| `crane_wing` | 鹤翼阵 | W | 侧翼伤害+50% |
| `chaos` | 混元阵 | ✦ | 全属性+10%, 20%减伤 |
| `celestial` | 天罡阵 | ☆ | 法术伤害+60%, CD-30% |

**确认按钮**：
- 宽 80%，高 44px，`primary` 色，白字 "确认选择"
- 点击 → 更新 `GS.menuFormationId` → 关闭 Drawer → 更新主菜单阵型文字

### 3.3 动画

- Drawer 滑入：`translateY: 100%→0`，0.3s easeOutBack
- 卡片选中切换：`transition = "scale 0.15s easeOut, borderColor 0.15s easeOut"`

---

## 四、战役关卡选择（全屏页）

### 4.1 触发

- 主菜单 selectedMode=="campaign" + 点击「开始游戏」

### 4.2 状态

新增 `GS.gameState` 值：`"campaign_select"`
新增字段：`GS.selectedChapter = 1`，`GS.selectedLevelId = nil`（字符串如 `"1-1"`）

### 4.3 布局

**顶栏**（fixed，高 48px）：
- 左侧："← 返回" 按钮（点击回主菜单）
- 中间：章节名（从 CampaignData 读取，如 "第一章: 崛起"）
- 背景：`primary` 色渐变

**章节标签**（Tabs，fixed，高 40px）：
- 三个 Tab：第一章 / 第二章🔒 / 第三章🔒（数据来源：`CampaignData.Chapters`）
- 已解锁：正常显示，可点击切换
- 未解锁：灰显 + 🔒图标，点击弹 Toast "通关前一章节后解锁"
- 解锁条件：前一章所有关卡已通关（`CampaignState.isCleared(levelId)` 逐一检查）

**关卡列表**（ScrollView，占据剩余空间减去底部栏）：

每个关卡卡片（Panel，高 72px，宽 92%，水平居中，margin-bottom=8）：
- 左侧色条 4px 宽：已通关 `success` 绿 / 未通关 `textSecondary` 灰 / 锁定无色条
- 关卡编号 + 名称（14pt，`textPrimary`），如 "1-1 初次集结"
- 通关标记：已通关显示 ✓ 绿色 / 未通关无标记（当前无星级系统）
- 敌人概要（11pt，`textSecondary`）：从 `level.enemies` 汇总单位类型和数量
- 锁定关卡：整体 `opacity=0.4`，右侧显示 🔒
- 选中态：`primary` 浅色背景 `{70,160,255,30}` + 左色条变 `primary`
- 解锁条件：`CampaignState.isLevelAccessible(levelId)` 判断（1-1 默认解锁）

**关卡数据来源**：`CampaignData.getLevelsByChapter(chapter)` → 返回该章关卡列表，每个关卡通过 `CampaignData.getLevel(levelId)` 获取详情
**通关状态来源**：`CampaignState.isCleared(levelId)` → 布尔值

**底部详情栏**（fixed，高约 120px，当有关卡选中时显示）：
- 背景 `cardBg`，顶部圆角 16
- 敌军组成：从 `CampaignData.getLevel(levelId).enemies` 读取，格式化显示如 "敌军: 8骑士 + 4弓手"
- 奖励信息：从 `level.reward` 读取，展示解锁内容（如新兵种/阵型）
- 「出战」按钮：`accent` 渐变，白字，药丸形
- 无选中关卡时：底部栏隐藏或显示 "选择一个关卡"

### 4.4 交互流程

```
点击已解锁关卡卡片
  → GS.selectedLevelId = levelId（如 "1-3"）
  → 底部栏显示关卡详情

点击「出战」
  → GS.setFormation(1, GS.menuFormationId)
  → GS.campaignLevelId = GS.selectedLevelId
  → initGame("campaign")

点击「返回」
  → GS.gameState = "main_menu"
  → 显示主菜单
```

---

## 五、无尽模式商店（波次间 Modal）

### 5.1 触发

- `EndlessMode.update()` 检测到一波清空后，设置 `GS.gameState = "endless_shop"`
- 游戏逻辑暂停（不调用 `updateGame`）

### 5.2 布局

**Modal**（居中弹窗，宽 90%，高自适应，最大 80% 屏幕高）：
- 背景 `cardBg`，圆角 16
- 外部遮罩 `overlay`

**头部**：
- "🌊 第 X 波 完成!" 字号 18pt，居中，`textPrimary`
- "💰 战争币: 85" 字号 14pt，居中，`gold` 色
- 分割线 Divider

**商品网格**（2 列 SimpleGrid，gap=10，padding=12）：

商品卡片（每个约 高 100px）：
- buff 图标（大号 emoji 居中，24pt）
- buff 名称（12pt，居中）
- 价格行："💰30"（`gold` 色，12pt）
- 购买按钮：
  - 可购买：`primary` 色小按钮 "购买"
  - 已拥有：`success` 色 "已拥有"，`opacity=0.7`
  - 余额不足：灰显 "不足"

商品列表（从 `ShopSystem.getItems()` 读取，返回当前波次的可购买物品数组）：

| buff | 图标 | 价格 | 效果 |
|------|------|------|------|
| 攻击强化 | ⚔ | 30 | 攻击+10% |
| 防御强化 | 🛡 | 30 | 受伤-10% |
| 生命恢复 | ❤ | 20 | 领主回血 30 |
| 移速提升 | ⚡ | 40 | 速度+15% |
| 招募补给 | 👥 | 50 | 获得 3 名士兵 |
| 暴击之刃 | 💥 | 60 | 暴击率+15% |

**底部**：
- 「下一波」按钮：`accent` 渐变，白字 "⚔ 下一波 (5s)"
- 5 秒倒计时，文字实时更新秒数
- 倒计时结束 → 自动关闭商店 → 开始下一波
- 玩家可提前点击立即开始

### 5.3 交互流程

```
点击「购买」
  → ShopSystem.buy(index)  -- index 为商品在 getItems() 返回数组中的位置（1-based）
  → 内部自动扣除战争币 → 刷新余额显示
  → 按钮变 "已拥有" 绿色
  → 余额数字跳动动画

倒计时归零 或 点击「下一波」
  → GS.gameState = "playing"
  → EndlessMode.nextWave()
  → 关闭 Modal
```

### 5.4 动画

- Modal 进场：`scale: 0.9→1.0` + `opacity: 0→1`，0.25s easeOutBack
- 购买成功：按钮 `scale` 弹跳 1.0→1.2→1.0
- 余额变化：数字颜色闪烁 `gold` → `danger` → `gold`

---

## 六、文件结构

```
scripts/
├── MenuTheme.lua         # 共享主题常量（色板、圆角、字号、阴影）
├── MainMenuUI.lua        # 主菜单界面（含背景预览逻辑）
├── FormationSelectUI.lua  # 阵型选择 Drawer
├── CampaignSelectUI.lua   # 战役关卡选择全屏页
├── EndlessShopUI.lua      # 无尽模式波次间商店 Modal
├── GameUI.lua             # 现有游戏 HUD（保持不变）
└── main.lua               # 更新路由逻辑
```

### 模块接口

**MenuTheme.lua**：
```lua
local T = {}
T.colors = { ... }
T.radius = { ... }
T.shadow = { ... }
T.fontSize = { ... }
return T
```

**MainMenuUI.lua**：
```lua
local M = {}
function M.show()              -- 构建并显示主菜单 UI
function M.hide()              -- 销毁主菜单 UI
function M.updatePreview(dt)   -- 更新背景预览动画（AI 小兵移动等）
function M.drawPreview(nvg, w, h)  -- NanoVG 绘制背景预览（在 NanoVGRender 事件中调用）
return M
```

**FormationSelectUI.lua**：
```lua
local M = {}
function M.show(currentFormationId, onConfirm)  -- 打开 Drawer
function M.hide()                                -- 关闭 Drawer
return M
```

**CampaignSelectUI.lua**：
```lua
local M = {}
function M.show(onStartLevel)  -- 打开关卡选择页
function M.hide()               -- 关闭
return M
```

**EndlessShopUI.lua**：
```lua
local M = {}
function M.show(waveNumber, onNextWave)  -- 打开商店 Modal
function M.hide()                         -- 关闭
function M.updateCountdown(dt)            -- 更新倒计时（在 HandleUpdate 中调用）
return M
```

---

## 七、main.lua 路由变更

### 7.1 gameState 新增值

| gameState | 含义 | 渲染 | 更新逻辑 |
|-----------|------|------|---------|
| `"main_menu"` | 主菜单 | 背景预览 + 菜单 UI | 仅更新背景预览 |
| `"campaign_select"` | 战役选关 | 无背景 + 选关 UI | 无游戏逻辑 |
| `"endless_shop"` | 无尽商店 | 游戏画面冻结 + 商店 Modal | 无游戏逻辑 |
| `"playing"` | 游戏中 | 游戏渲染 + HUD | 完整游戏逻辑 |
| `"gameover"` | 结算 | 游戏渲染 + 结算 UI | 无游戏逻辑 |

### 7.2 Start() 流程变更

```
云数据加载完成
  → GS.gameState = "main_menu"
  → MainMenuUI.show()
```

替代现有的 `GameUI.ShowTalentSelectUI(function() initGame("skirmish") end)`。

### 7.3 HandleUpdate 路由

```lua
if GS.gameState == "main_menu" then
    MainMenuUI.updatePreview(dt)
elseif GS.gameState == "campaign_select" then
    -- 无逻辑更新，纯 UI 交互
elseif GS.gameState == "endless_shop" then
    EndlessShopUI.updateCountdown(dt)
elseif GS.gameState == "playing" then
    updateGame(dt)
end
```

### 7.4 HandleNanoVGRender 路由

```lua
if GS.gameState == "main_menu" then
    MainMenuUI.drawPreview(nvg, w, h)  -- 低帧率背景预览（内部调用 Renderer 方法）
elseif GS.gameState == "playing" or GS.gameState == "gameover"
    or GS.gameState == "endless_shop" then
    -- 复用现有的完整游戏渲染流程
    Renderer.drawBackground(w, h)
    Renderer.drawResources()
    -- ...其余现有渲染调用
end
```

---

## 八、数据依赖

各界面读取已实现模块的数据，不引入新的持久化需求：

| 界面 | 读取模块 | 实际 API |
|------|---------|---------|
| 主菜单-遭遇战 | — | 暂无持久化统计，显示占位 "---" |
| 主菜单-战役 | `CampaignState` | `getCurrentChapter()`, `getClearedLevels()` → 计算已通关数 |
| 主菜单-无尽 | `EndlessMode` | `getWaveInfo()` → `.bestWave`, `.warCoins` |
| 主菜单-玩家 | `TalentSystem` | `getReputation()` → 计算等级 |
| 阵型选择 | `FormationSystem` | `FormationOrder`（遍历）, `Formations[id]`（定义）, `getBuffs(id)`, `getName(id)` |
| 战役选关 | `CampaignData`, `CampaignState` | `Chapters`, `getLevelsByChapter(ch)`, `getLevel(id)`, `isCleared(id)`, `isLevelAccessible(id)` |
| 无尽商店 | `ShopSystem`, `EndlessMode` | `getItems()`, `buy(index)`, `getWaveInfo()` → `.warCoins`, `.wave` |

---

## 九、不在范围内

以下内容明确不在第一批范围内：

- 天赋树界面（第二批）
- 图鉴画廊界面（第二批）
- 编队预设管理界面（第二批）
- 副将小队管理面板（第二批）
- 游戏结算/胜利/失败界面改造
- 音效和震动反馈
- 新兵种的 NanoVG 渲染图形（使用现有颜色圆圈 fallback）
- 设置界面（齿轮按钮暂时弹 Toast "即将开放"）
