-- ============================================================================
-- Renderer.lua - 所有NanoVG绘制函数
-- 从 main.lua 逐字搬迁，仅变量引用前缀化
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local FACTION_COLORS = ConfigModule.FACTION_COLORS
local Utils = require("Utils")
local TS = require("TalentSystem")
local SkillSystem = require("SkillSystem")

local M = {}

-- NanoVG 上下文（由 main.lua 传入）
local ctx = nil

-- ============================================================================
-- 精灵图资源 & 常量
-- ============================================================================
local groundImage = -1
local GROUND_TILE_SIZE = 512
local treeSprites = {}
local TREE_SPRITE_FILES = {
    {file = "image/tree_pine1.png",  frameW = 192, frameH = 256, frames = 8},
    {file = "image/tree_pine2.png",  frameW = 192, frameH = 256, frames = 8},
    {file = "image/tree_leaf1.png",  frameW = 192, frameH = 192, frames = 8},
    {file = "image/tree_leaf2.png",  frameW = 192, frameH = 192, frames = 8},
}
local TREE_DRAW_SIZE = 72

local mineSprite = nil
local MINE_SPRITE_FILE = {file = "image/mine_ore.png", frameW = 128, frameH = 128, frames = 6}
local MINE_DRAW_SIZE = 54

-- ============================================================================
-- 领主动画精灵图资源
-- ============================================================================
-- 每张精灵图：768x80，横排8帧，每帧 96x80
local LORD_SPRITE_FRAME_W = 96
local LORD_SPRITE_FRAME_H = 80
local LORD_SPRITE_FRAMES  = 8
local LORD_DRAW_W = 192  -- 绘制宽度（世界像素，3x 原始帧宽）
local LORD_DRAW_H = math.floor(192 * LORD_SPRITE_FRAME_H / LORD_SPRITE_FRAME_W)
-- 透明边距（实测值，idle/run 基准）：
--   顶部：24px / 80px = 0.30   底部：22px / 80px = 0.275
--   左侧：18px / 96px = 0.188  右侧：22px / 96px = 0.229（取攻击动画最小值，保守裁剪）
-- 可见内容区：帧高 30%~72.5%，帧宽 18.8%~77.1%
-- drawY = sy - dh*0.75，脚底 feetY = drawY + dh*0.725 ≈ sy
local LORD_TOP_RATIO   = 0.30    -- 顶部透明区占帧高比例
local LORD_FEET_RATIO  = 0.725   -- 脚底在帧高中的比例（= 1 - 底部透明比例）
local LORD_LEFT_RATIO  = 0.188   -- 左侧透明区占帧宽比例
local LORD_RIGHT_RATIO = 0.229   -- 右侧透明区占帧宽比例
-- 可见角色宽度（用于阴影、血条等不应受透明像素拉宽的元素）
local LORD_VIS_W_RATIO = 1.0 - LORD_LEFT_RATIO - LORD_RIGHT_RATIO  -- ≈ 0.583

-- 动画名 -> 每帧时长（秒）
local LORD_ANIM_FPS = {
    idle    = 1/8,   -- 8帧 @ ~8fps
    run     = 1/10,  -- 8帧 @ ~10fps（稍快）
    attack1 = 1/10,
    attack2 = 1/10,
}

-- 每个领主的动画本地状态（id -> state table）
local lordAnimState = {}   -- { dir, anim, frame, timer, attackTimer }

-- 方向枚举
local DIR_DOWN  = "down"
local DIR_UP    = "up"
local DIR_LEFT  = "left"
local DIR_RIGHT = "right"

-- 精灵图句柄: lordSprites[anim][dir] = nvgImageHandle
local lordSprites = {}

local LORD_SPRITE_FILES = {
    idle    = { down="image/领主/idle_down.png",    up="image/领主/idle_up.png",    left="image/领主/idle_left.png",    right="image/领主/idle_right.png"    },
    run     = { down="image/领主/run_down.png",     up="image/领主/run_up.png",     left="image/领主/run_left.png",     right="image/领主/run_right.png"     },
    attack1 = { down="image/领主/attack1_down.png", up="image/领主/attack1_up.png", left="image/领主/attack1_left.png", right="image/领主/attack1_right.png" },
    attack2 = { down="image/领主/attack2_down.png", up="image/领主/attack2_up.png", left="image/领主/attack2_left.png", right="image/领主/attack2_right.png" },
}

-- ============================================================================
-- 多阵营精灵表：按 factionId → 颜色目录 → 兵种动画
-- Faction: 1=黑色(玩家) 2=红色 3=黄色 4=蓝色 5=紫色
-- ============================================================================
local FACTION_FOLDERS = {
    [1] = "黑色素材",
    [2] = "红色素材",
    [3] = "黄色素材",
    [4] = "蓝色素材",
    [5] = "紫色素材",
}

-- 各兵种动画定义（相对路径，不含颜色目录前缀）
-- fw/fh = 裁剪后单帧实际像素宽/高（Python Pillow 实测值）
local SPRITE_DEFS = {
    peasant = {
        idle    = { file = "农民/Pawn_Idle.png",             frames = 8,  fps = 8,  fw = 58,  fh = 74  },
        run     = { file = "农民/Pawn_Run.png",              frames = 6,  fps = 10, fw = 66,  fh = 77  },
        axe     = { file = "农民/Pawn_Interact Axe.png",     frames = 6,  fps = 8,  fw = 98,  fh = 75  },
        pickaxe = { file = "农民/Pawn_Interact Pickaxe.png", frames = 6,  fps = 8,  fw = 101, fh = 75  },
    },
    soldier = {
        idle    = { file = "士兵/Warrior_Idle.png",    frames = 8,  fps = 8,  fw = 84,  fh = 89  },
        run     = { file = "士兵/Warrior_Run.png",     frames = 6,  fps = 10, fw = 93,  fh = 91  },
        attack1 = { file = "士兵/Warrior_Attack1.png", frames = 4,  fps = 10, fw = 120, fh = 112 },
        attack2 = { file = "士兵/Warrior_Attack2.png", frames = 4,  fps = 10, fw = 118, fh = 104 },
        guard   = { file = "士兵/Warrior_Guard.png",   frames = 6,  fps = 8,  fw = 70,  fh = 93  },
    },
    archer = {
        idle  = { file = "弓箭手/Archer_Idle.png",  frames = 6,  fps = 8,  fw = 72,  fh = 89  },
        run   = { file = "弓箭手/Archer_Run.png",   frames = 4,  fps = 10, fw = 73,  fh = 90  },
        shoot = { file = "弓箭手/Archer_Shoot.png", frames = 8,  fps = 12, fw = 87,  fh = 90  },
    },
    healer = {
        idle = { file = "治愈师/Idle.png", frames = 6,  fps = 8,  fw = 58,  fh = 69  },
        run  = { file = "治愈师/Run.png",  frames = 4,  fps = 10, fw = 83,  fh = 71  },
        heal = { file = "治愈师/Heal.png", frames = 11, fps = 12, fw = 119, fh = 69  },
    },
}
local ARROW_REL_FILE    = "弓箭手/Arrow.png"
-- fw/fh: Arrow 43×12，Heal_Effect 98×125
local HEAL_EFF_DEF      = { file = "治愈师/Heal_Effect.png", frames = 11, fps = 12, fw = 98, fh = 125 }

-- 运行时：allSprites[factionId][unitType][animName] = {img, frames, fps}
local allSprites        = {}
-- 运行时：arrowSprites[factionId] = img
local arrowSprites      = {}
-- 运行时：healEffectSprites[factionId] = {img, frames, fps}
local healEffectSprites = {}

-- 角色绘制高度 = radius * UNIT_DRAW_SCALE（与 nvgImageSize 无关）
local UNIT_DRAW_SCALE = 3.5

-- 动画状态（per-unit，不区分阵营）
local peasantAnimState  = {}
local soldierAnimState  = {}
local archerAnimState   = {}
local healerAnimState   = {}
-- AI 领主精灵动画状态（per-lord）
local aiLordAnimState   = {}

-- ============================================================================
-- 兵种贴图资源
-- ============================================================================
local unitTextures = {}    -- unitTextures[fType] = nvgImageHandle
local UNIT_TEXTURE_FILES = {
    peasant        = "image/unit_peasant_20260521140902.png",
    soldier        = "image/unit_soldier_20260521140904.png",
    archer         = "image/unit_archer_20260521140903.png",
}

-- ============================================================================
-- 初始化 & 资源加载
-- ============================================================================

function M.init(nvgCtx)
    ctx = nvgCtx
end

function M.loadAssets()
    if not ctx then return end

    -- 加载地面瓦片贴图 (手动铺贴，不用REPEAT，用NEAREST避免边缘模糊)
    local repeatFlags = NVG_IMAGE_NEAREST
    groundImage = nvgCreateImage(ctx, "image/edited_ground_tile_green_20260517144628.png", repeatFlags)
    if groundImage and groundImage > 0 then
        print("[GROUND] Tile loaded, drawSize=" .. GROUND_TILE_SIZE)
    else
        print("[GROUND] Failed to load tile, falling back to solid color")
        groundImage = -1
    end

    -- 加载树木精灵图
    for i, info in ipairs(TREE_SPRITE_FILES) do
        local img = nvgCreateImage(ctx, info.file, 0)
        if img and img > 0 then
            treeSprites[i] = {img = img, frameW = info.frameW, frameH = info.frameH, frames = info.frames}
            print("[TREE] Sprite " .. i .. " loaded: " .. info.file)
        else
            print("[TREE] Failed to load: " .. info.file)
        end
    end

    -- 加载矿石精灵图
    local mineImg = nvgCreateImage(ctx, MINE_SPRITE_FILE.file, 0)
    if mineImg and mineImg > 0 then
        mineSprite = {img = mineImg, frameW = MINE_SPRITE_FILE.frameW, frameH = MINE_SPRITE_FILE.frameH, frames = MINE_SPRITE_FILE.frames}
        print("[MINE] Sprite loaded: " .. MINE_SPRITE_FILE.file)
    else
        print("[MINE] Failed to load: " .. MINE_SPRITE_FILE.file)
    end

    -- 按阵营加载所有兵种精灵表
    for factionId, folder in pairs(FACTION_FOLDERS) do
        allSprites[factionId]        = {}
        local prefix = "image/" .. folder .. "/"

        -- 各兵种动画
        for unitType, animDefs in pairs(SPRITE_DEFS) do
            allSprites[factionId][unitType] = {}
            for animName, def in pairs(animDefs) do
                local path = prefix .. def.file
                local img = nvgCreateImage(ctx, path, 0)
                if img and img > 0 then
                    allSprites[factionId][unitType][animName] = {
                        img = img, frames = def.frames, fps = def.fps,
                        fw = def.fw, fh = def.fh,
                    }
                else
                    print("[SPRITE] Failed: " .. path)
                end
            end
        end

        -- 箭矢
        local aImg = nvgCreateImage(ctx, prefix .. ARROW_REL_FILE, 0)
        if aImg and aImg > 0 then
            arrowSprites[factionId] = aImg
        end

        -- 治疗特效
        local heImg = nvgCreateImage(ctx, prefix .. HEAL_EFF_DEF.file, 0)
        if heImg and heImg > 0 then
            healEffectSprites[factionId] = {
                img = heImg, frames = HEAL_EFF_DEF.frames, fps = HEAL_EFF_DEF.fps,
                fw = HEAL_EFF_DEF.fw, fh = HEAL_EFF_DEF.fh,
            }
        end

        print("[SPRITES] Faction " .. factionId .. " (" .. folder .. ") loaded")
    end

    -- 加载兵种贴图
    for fType, path in pairs(UNIT_TEXTURE_FILES) do
        local img = nvgCreateImage(ctx, path, 0)
        if img and img > 0 then
            unitTextures[fType] = img
            print("[UNIT TEX] Loaded: " .. fType)
        else
            print("[UNIT TEX] Failed: " .. fType .. " (" .. path .. ")")
        end
    end

    -- 加载领主动画精灵图
    for animName, dirFiles in pairs(LORD_SPRITE_FILES) do
        lordSprites[animName] = {}
        for dir, path in pairs(dirFiles) do
            local img = nvgCreateImage(ctx, path, 0)
            if img and img > 0 then
                lordSprites[animName][dir] = img
                print("[LORD SPRITE] Loaded: " .. animName .. "_" .. dir)
            else
                print("[LORD SPRITE] Failed: " .. path)
            end
        end
    end
end

-- ============================================================================
-- 领主动画状态更新
-- ============================================================================

-- 根据领主速度推导移动方向
-- 优先级规则：上下 > 左右（避免双键同按时方向跳动）
-- 上下分量超过左右分量的 0.5 倍即优先取上下，否则取左右
local function getDir(dx, dy)
    local adx = math.abs(dx)
    local ady = math.abs(dy)
    if adx < 0.1 and ady < 0.1 then return nil end  -- 未移动，保留上一方向
    -- 上下优先：只有 adx 明显大于 ady 时才切左右（阈值 1.5 倍）
    if adx > ady * 1.5 then
        return dx > 0 and DIR_RIGHT or DIR_LEFT
    else
        return dy > 0 and DIR_DOWN or DIR_UP
    end
end

-- 每帧调用，更新单个领主的动画状态（需传入 dt 和移动增量）
local function updateLordAnim(l, dx, dy, dt)
    local id = l.id
    if not lordAnimState[id] then
        lordAnimState[id] = { dir = DIR_DOWN, anim = "idle", frame = 0, timer = 0, attackTimer = 0 }
    end
    local s = lordAnimState[id]

    -- 方向更新
    local newDir = getDir(dx, dy)
    if newDir then s.dir = newDir end

    -- 决定当前应播放哪个动画
    local moving = (math.abs(dx) > 0.5 or math.abs(dy) > 0.5)

    local targetAnim
    if s.attackTimer > 0 then
        -- 攻击动画播完前锁定（由 updateLordAnims 的攻击按钮触发写入）
        s.attackTimer = s.attackTimer - dt
        targetAnim = s.anim
    else
        -- 攻击动画结束后回归 idle / run
        targetAnim = moving and "run" or "idle"
    end

    -- 动画切换时重置帧
    if targetAnim ~= s.anim then
        s.anim = targetAnim
        s.frame = 0
        s.timer = 0
    end

    -- 帧推进
    local fps = LORD_ANIM_FPS[s.anim] or (1/8)
    s.timer = s.timer + dt
    while s.timer >= fps do
        s.timer = s.timer - fps
        s.frame = (s.frame + 1) % LORD_SPRITE_FRAMES
    end
end

-- 导出供 main.lua 调用（每帧在绘制前批量更新所有领主动画）
function M.updateLordAnims(dt)
    for _, l in ipairs(GS.lords) do
        if l.alive then
            -- 用上一帧位置差计算移动量
            local dx = l.x - (l._prevAnimX or l.x)
            local dy = l.y - (l._prevAnimY or l.y)
            updateLordAnim(l, dx, dy, dt)
            l._prevAnimX = l.x
            l._prevAnimY = l.y
        end
    end

    -- 消费主动攻击动画触发（由 main.lua 攻击按钮逻辑写入）
    if GS.playerAttackAnimTrigger then
        GS.playerAttackAnimTrigger = false
        local pl = GS.lords[1]
        if pl and pl.alive then
            local s = lordAnimState[pl.id]
            if s then
                s.anim = (math.floor(GS.gameTime * 0.8) % 2 == 0) and "attack1" or "attack2"
                s.frame = 0
                s.timer = 0
                s.attackTimer = LORD_SPRITE_FRAMES * LORD_ANIM_FPS["attack1"]
            end
        end
    end
end

-- ============================================================================
-- 绘制函数
-- ============================================================================

function M.drawBackground(w, h)
    if groundImage > 0 then
        -- 手动逐块铺贴地面，避免 REPEAT 模式的纹理过滤缝隙
        local tileS = GROUND_TILE_SIZE
        -- 计算屏幕左上角对应的世界坐标，找到起始tile
        local worldLeft = GS.cameraX - w / 2
        local worldTop  = GS.cameraY - h / 2
        local startTileX = math.floor(worldLeft / tileS) * tileS
        local startTileY = math.floor(worldTop  / tileS) * tileS

        for ty = startTileY, startTileY + h + tileS, tileS do
            for tx = startTileX, startTileX + w + tileS, tileS do
                local sx = math.floor(tx - GS.cameraX + w / 2)
                local sy = math.floor(ty - GS.cameraY + h / 2)
                -- 垂直方向多画3px重叠，消除水平接缝灰线
                local pat = nvgImagePattern(ctx, sx, sy, tileS, tileS + 3, 0, groundImage, 1.0)
                nvgBeginPath(ctx)
                nvgRect(ctx, sx, sy, tileS, tileS + 3)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
            end
        end
    else
        -- 降级：纯色背景
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, h)
        nvgFillColor(ctx, nvgRGBA(160, 190, 80, 255))
        nvgFill(ctx)
    end

    -- 地图边界外遮罩（用深色填充地图外区域，防止看到地图外的重复瓦片）
    local bx1, by1 = Utils.worldToScreen(0, 0)
    local bx2, by2 = Utils.worldToScreen(CONFIG.MapWidth, CONFIG.MapHeight)
    local edgeColor = nvgRGBA(30, 40, 20, 255)

    -- 左侧遮罩
    if bx1 > 0 then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, bx1, h)
        nvgFillColor(ctx, edgeColor)
        nvgFill(ctx)
    end
    -- 右侧遮罩
    if bx2 < w then
        nvgBeginPath(ctx)
        nvgRect(ctx, bx2, 0, w - bx2, h)
        nvgFillColor(ctx, edgeColor)
        nvgFill(ctx)
    end
    -- 顶部遮罩
    if by1 > 0 then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, by1)
        nvgFillColor(ctx, edgeColor)
        nvgFill(ctx)
    end
    -- 底部遮罩
    if by2 < h then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, by2, w, h - by2)
        nvgFillColor(ctx, edgeColor)
        nvgFill(ctx)
    end

    -- 地图边界线
    nvgBeginPath(ctx)
    nvgRect(ctx, bx1, by1, bx2 - bx1, by2 - by1)
    nvgStrokeColor(ctx, nvgRGBA(200, 100, 100, 150))
    nvgStrokeWidth(ctx, 3)
    nvgStroke(ctx)
end

-- 内部辅助：绘制单棵树精灵
local function drawTreeSprite(sx, sy, spriteType, spriteFrame)
    local spr = treeSprites[spriteType]
    if not spr then return false end

    local drawW = TREE_DRAW_SIZE
    local drawH = drawW * (spr.frameH / spr.frameW)

    -- nvgImagePattern 映射整张精灵图到一个虚拟区域
    -- 精灵图是横排8帧, 虚拟宽度 = drawW * 8, 高度 = drawH
    -- 通过偏移ox让指定帧对齐到绘制区域
    local totalW = drawW * spr.frames
    local ox = sx - drawW / 2 - spriteFrame * drawW
    local oy = sy - drawH

    local pat = nvgImagePattern(ctx, ox, oy, totalW, drawH, 0, spr.img, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, sx - drawW / 2, sy - drawH, drawW, drawH)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)
    return true
end

-- 内部辅助：绘制单个资源物件（树或矿石），sx/sy 为屏幕足部坐标
local function drawResourceItem(r)
    local sx, sy = Utils.worldToScreen(r.x, r.y)
    if r.rType == "tree" then
        if not drawTreeSprite(sx, sy, r.spriteType, r.spriteFrame) then
            -- 降级：简单圆形
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy - 8, 10)
            nvgFillColor(ctx, nvgRGBA(50, 160, 50, 255))
            nvgFill(ctx)
        end
    else
        -- 矿石：用精灵图绘制
        if mineSprite then
            local drawW = MINE_DRAW_SIZE
            local drawH = drawW * (mineSprite.frameH / mineSprite.frameW)
            local totalW = drawW * mineSprite.frames
            local ox = sx - drawW / 2 - r.mineFrame * drawW
            local oy = sy - drawH
            local pat = nvgImagePattern(ctx, ox, oy, totalW, drawH, 0, mineSprite.img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, sx - drawW / 2, sy - drawH, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
        else
            -- 降级：多边形
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx, sy - 10)
            nvgLineTo(ctx, sx + 10, sy)
            nvgLineTo(ctx, sx + 5, sy + 8)
            nvgLineTo(ctx, sx - 5, sy + 8)
            nvgLineTo(ctx, sx - 10, sy)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(140, 140, 160, 255))
            nvgFill(ctx)
        end
    end
end

function M.drawResources()
    for _, r in ipairs(GS.resources) do
        if not r.alive then goto continue end
        if not Utils.isOnScreen(r.x, r.y, 40) then goto continue end
        drawResourceItem(r)
        ::continue::
    end
end

-- 按世界 Y 坐标排序绘制资源、随从、领主，实现画家算法遮挡
-- 宝箱/遗物等地面物件在排序前先画（它们始终在角色脚下）
function M.drawSceneWithOcclusion()
    -- 1. 收集所有需要参与排序的实体
    local entities = {}

    for _, r in ipairs(GS.resources) do
        if r.alive and Utils.isOnScreen(r.x, r.y, 40) then
            entities[#entities + 1] = { kind = "resource", obj = r, worldY = r.y }
        end
    end

    for _, f in ipairs(GS.followers) do
        if f.alive and Utils.isOnScreen(f.x, f.y, 40) then
            entities[#entities + 1] = { kind = "follower", obj = f, worldY = f.y }
        end
    end

    for _, b in ipairs(GS.bosses) do
        if b.alive and Utils.isOnScreen(b.x, b.y, 80) then
            entities[#entities + 1] = { kind = "boss", obj = b, worldY = b.y }
        end
    end

    for _, l in ipairs(GS.lords) do
        if l.alive and Utils.isOnScreen(l.x, l.y, 80) then
            entities[#entities + 1] = { kind = "lord", obj = l, worldY = l.y }
        end
    end

    -- 2. 按世界 Y 升序排序（Y 越小越靠北，越先画，越容易被遮挡）
    table.sort(entities, function(a, b) return a.worldY < b.worldY end)

    -- 3. 按顺序绘制
    for _, e in ipairs(entities) do
        if e.kind == "resource" then
            drawResourceItem(e.obj)
        elseif e.kind == "follower" then
            M.drawFollower(e.obj)
        elseif e.kind == "boss" then
            M.drawBoss(e.obj)
        elseif e.kind == "lord" then
            M.drawLord(e.obj)
        end
    end
end

-- 计算领主的随从数量
local function countFollowers(lordId)
    local count = 0
    for _, f in ipairs(GS.followers) do
        if f.alive and f.lordId == lordId then
            count = count + 1
        end
    end
    return count
end

-- 根据兵力计算领主动态半径
local function getLordRadius(lordId)
    local count = countFollowers(lordId)
    local t = math.min(count / CONFIG.LordFollowerCap, 1.0)
    return CONFIG.LordRadiusMin + (CONFIG.LordRadiusMax - CONFIG.LordRadiusMin) * t
end

function M.drawLord(l)
    if not l.alive then return end
    if not Utils.isOnScreen(l.x, l.y, 80) then return end

    local sx, sy = Utils.worldToScreen(l.x, l.y)
    local fc = FACTION_COLORS[l.faction] or {200, 200, 200}

    -- 光环（根据模式变化）
    if l.isPlayer or Utils.dist(GS.lords[1].x, GS.lords[1].y, l.x, l.y) < GS.screenW then
        local auraR = CONFIG.AuraRadius
        if GS.fogActive then auraR = auraR * 0.7 end
        local asX, asY = Utils.worldToScreen(l.x, l.y)
        local aR, aG, aB = fc[1], fc[2], fc[3]
        local auraAlpha = 15

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
    end

    -- 领主身体 — 动态半径（用于UI层，如光环、血条）
    local lordRadius = getLordRadius(l.id)

    -- ========== 身体绘制：玩家用精灵图，AI 用圆形 ==========
    local crownY  -- 皇冠锚点，后续血条标签复用

    if l.isPlayer then
        -- ---------- 玩家领主：精灵图 ----------
        local anim = lordAnimState[l.id]
        local spriteDrawn = false
        if anim then
            local sheet = lordSprites[anim.anim]
            local img = sheet and sheet[anim.dir]
            if img then
                local dw = LORD_DRAW_W
                local dh = LORD_DRAW_H
                local drawX = sx - dw / 2
                local drawY = sy - dh * 0.75  -- 脚底约在 sy

                -- 脚底屏幕坐标（去除透明像素后）
                local feetY = drawY + dh * LORD_FEET_RATIO

                -- 可见角色中心X（排除左右透明像素后的实际中心）
                local visOffX = dw * (LORD_LEFT_RATIO - LORD_RIGHT_RATIO) * 0.5  -- 左右不对称时修正
                local visCx = sx + visOffX
                -- 可见角色宽度（用于阴影、血条）
                local visW = dw * LORD_VIS_W_RATIO

                -- 1) 脚底阴影（基于实际可见宽度，不受透明区域拉宽）
                local shadowRx = visW * 0.275
                local shadowRy = shadowRx * 0.28
                local shadowGrad = nvgRadialGradient(ctx,
                    visCx, feetY,
                    shadowRx * 0.2, shadowRx,
                    nvgRGBA(0, 0, 0, 80),
                    nvgRGBA(0, 0, 0, 0))
                nvgBeginPath(ctx)
                nvgEllipse(ctx, visCx, feetY + shadowRy * 0.3, shadowRx, shadowRy)
                nvgFillPaint(ctx, shadowGrad)
                nvgFill(ctx)

                -- 2) 精灵图本体（裁剪掉顶部和底部透明区域）
                -- 可见区域：跳过顶部 LORD_TOP_RATIO，底部到 LORD_FEET_RATIO
                local drawY_vis = drawY + dh * LORD_TOP_RATIO
                local dh_vis    = dh * (LORD_FEET_RATIO - LORD_TOP_RATIO)
                local totalW = dw * LORD_SPRITE_FRAMES
                local ox = drawX - anim.frame * dw
                -- pattern 仍然覆盖整帧（ox/drawY/totalW/dh），clip rect 只取可见部分
                local pat = nvgImagePattern(ctx, ox, drawY, totalW, dh, 0, img, 1.0)
                nvgBeginPath(ctx)
                nvgRect(ctx, drawX, drawY_vis, dw, dh_vis)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)

                crownY = drawY_vis - 4  -- 皇冠紧贴可见角色顶部
                spriteDrawn = true
            end
        end

        -- 精灵图加载失败时降级为圆形
        if not spriteDrawn then
            local glow = nvgRadialGradient(ctx, sx, sy, lordRadius * 0.3, lordRadius * 2,
                nvgRGBA(fc[1], fc[2], fc[3], 60), nvgRGBA(fc[1], fc[2], fc[3], 0))
            nvgBeginPath(ctx); nvgCircle(ctx, sx, sy, lordRadius * 2)
            nvgFillPaint(ctx, glow); nvgFill(ctx)
            nvgBeginPath(ctx); nvgCircle(ctx, sx, sy, lordRadius)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255)); nvgFill(ctx)
            nvgBeginPath(ctx); nvgCircle(ctx, sx, sy, lordRadius)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 150)); nvgStrokeWidth(ctx, 2); nvgStroke(ctx)
            crownY = sy - lordRadius - 4
        end
    else
        -- ---------- AI 领主：用阵营士兵精灵渲染 ----------
        local as = aiLordAnimState[l.id]
        if not as then
            as = { anim = "idle", frame = 0, timer = 0, facingRight = true, prevX = l.x, prevY = l.y }
            aiLordAnimState[l.id] = as
        end

        -- 根据移动方向更新朝向和动画
        local dx = l.x - as.prevX
        local dy = l.y - as.prevY
        local moving = (math.abs(dx) > 0.05 or math.abs(dy) > 0.05)
        if math.abs(dx) > 0.05 then as.facingRight = (dx > 0) end
        as.prevX = l.x; as.prevY = l.y

        local targetAnim = moving and "run" or "idle"
        if as.anim ~= targetAnim then
            as.anim = targetAnim; as.frame = 0; as.timer = 0
        end

        -- 推进动画帧
        local dt = GS.lastDt or (1/60)
        local facSprites = allSprites[l.faction]
        local spr = facSprites and facSprites.soldier and facSprites.soldier[as.anim]
        local spriteDrawn = false

        if spr then
            as.timer = as.timer + dt
            local frameDur = 1.0 / spr.fps
            while as.timer >= frameDur do
                as.timer = as.timer - frameDur
                as.frame = (as.frame + 1) % spr.frames
            end

            -- drawH/drawW：领主比普通士兵大（lordRadius > unitRadius）
            local drawH = lordRadius * UNIT_DRAW_SCALE
            local drawW = drawH * (spr.fw / spr.fh)
            local halfH = drawH * 0.5
            local halfW = drawW * 0.5
            local totalImgW = drawW * spr.frames
            local ox = sx - halfW - as.frame * drawW
            local oy = sy - halfH
            nvgSave(ctx)
            if not as.facingRight then
                nvgTranslate(ctx, sx * 2, 0); nvgScale(ctx, -1, 1)
            end
            local pat = nvgImagePattern(ctx, ox, oy, totalImgW, drawH, 0, spr.img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, sx - halfW, sy - halfH, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
            nvgRestore(ctx)
            crownY = sy - halfH - 4
            spriteDrawn = true
        end

        if not spriteDrawn then
            -- 精灵未加载时降级为圆形
            local glow = nvgRadialGradient(ctx, sx, sy, lordRadius * 0.3, lordRadius * 2,
                nvgRGBA(fc[1], fc[2], fc[3], 60), nvgRGBA(fc[1], fc[2], fc[3], 0))
            nvgBeginPath(ctx); nvgCircle(ctx, sx, sy, lordRadius * 2)
            nvgFillPaint(ctx, glow); nvgFill(ctx)
            nvgBeginPath(ctx); nvgCircle(ctx, sx, sy, lordRadius)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255)); nvgFill(ctx)
            nvgBeginPath(ctx); nvgCircle(ctx, sx, sy, lordRadius)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 150)); nvgStrokeWidth(ctx, 2); nvgStroke(ctx)
            crownY = sy - lordRadius - 4
        end
    end

    -- 皇冠标记（始终显示）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx - 7, crownY - 2)
    nvgLineTo(ctx, sx - 5, crownY - 8)
    nvgLineTo(ctx, sx, crownY - 4)
    nvgLineTo(ctx, sx + 5, crownY - 8)
    nvgLineTo(ctx, sx + 7, crownY - 2)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(255, 220, 50, 255))
    nvgFill(ctx)

    -- 双血条（根据玩家/AI采用不同的锚点）
    local hpBarW, barBaseY, hpBarCx
    if l.isPlayer then
        -- 血条宽度和中心基于可见角色宽度，不受透明像素拉宽
        local dw = LORD_DRAW_W
        local visW_lord = dw * LORD_VIS_W_RATIO
        local visOffX_lord = dw * (LORD_LEFT_RATIO - LORD_RIGHT_RATIO) * 0.5
        hpBarW   = visW_lord * 0.5
        hpBarCx  = sx + visOffX_lord
        barBaseY = sy + LORD_DRAW_H * 0.25 - 40  -- 精灵图实际底部，上移40px
    else
        -- AI 领主用士兵精灵渲染，血条宽度与高度基于精灵实际尺寸（保持帧宽高比）
        local aiSpr = allSprites[l.faction] and allSprites[l.faction].soldier
                      and allSprites[l.faction].soldier.idle
        if aiSpr then
            local aiDrawH = lordRadius * UNIT_DRAW_SCALE
            local aiDrawW = aiDrawH * (aiSpr.fw / aiSpr.fh)
            hpBarW   = aiDrawW * 0.6
            barBaseY = sy + aiDrawH * 0.5
        else
            hpBarW   = lordRadius * 2
            barBaseY = sy + lordRadius
        end
        hpBarCx = sx
    end
    local hpBarH = 4

    -- 据点HP血条（仅玩家）
    if l.isPlayer then
        local shRatio = (l.strongholdHP or 0) / (l.strongholdMaxHP or 1)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, hpBarCx - hpBarW/2, barBaseY + 2, hpBarW, hpBarH, 2)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, hpBarCx - hpBarW/2, barBaseY + 2, hpBarW * shRatio, hpBarH, 2)
        nvgFillColor(ctx, nvgRGBA(255, 180, 50, 255))
        nvgFill(ctx)
    end

    -- 领主HP血条（绿→红渐变）
    local hpRatio = l.hp / l.maxHp
    local hpBarY = barBaseY + (l.isPlayer and 8 or 2)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, hpBarCx - hpBarW/2, hpBarY, hpBarW, hpBarH, 2)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, hpBarCx - hpBarW/2, hpBarY, hpBarW * hpRatio, hpBarH, 2)
    local hpR = hpRatio > 0.5 and 80 or (hpRatio > 0.25 and 255 or 255)
    local hpG = hpRatio > 0.5 and 220 or (hpRatio > 0.25 and 180 or 50)
    local hpB = hpRatio > 0.5 and 80 or (hpRatio > 0.25 and 50 or 50)
    nvgFillColor(ctx, nvgRGBA(hpR, hpG, hpB, 255))
    nvgFill(ctx)

    -- 玩家标签
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    if l.isPlayer then
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgText(ctx, sx, crownY - 10, "玩家", nil)
    end

end

function M.drawFollower(f)
    if not f.alive then return end
    if not Utils.isOnScreen(f.x, f.y, 30) then return end

    local sx, sy = Utils.worldToScreen(f.x, f.y)
    local fc = FACTION_COLORS[f.factionId] or {200, 200, 200}

    -- 根据兵种获取半径
    local radius = CONFIG.UnitRadius[f.fType] or CONFIG.SoldierRadius

    -- 判断是否为玩家阵营精灵单位（农民/士兵/弓箭手使用精灵表）
    local playerFaction = GS.lords and GS.lords[1] and GS.lords[1].faction
    local isPlayerUnit  = (playerFaction ~= nil and f.factionId == playerFaction)
    -- 只要阵营有对应素材目录，该兵种就使用精灵表渲染
    local hasFactionSprites = (FACTION_FOLDERS[f.factionId] ~= nil)
    local isSpriteUnit  = hasFactionSprites and (f.fType == "peasant" or f.fType == "soldier" or f.fType == "archer" or f.fType == "healer")

    -- ========== 动画计算（仅非精灵单位需要缩放） ==========
    local scaleX, scaleY, bounceY = 1.0, 1.0, 0
    if not isSpriteUnit then
        local breathFreq = 5.0
        local breathAmpX = 0.04
        local breathAmpY = 0.05

        local breathVal = math.sin((f.breathPhase or 0) + GS.gameTime * breathFreq)
        scaleX = 1.0 + breathAmpX * breathVal
        scaleY = 1.0 - breathAmpY * breathVal

        local dx = f.x - (f.prevX or f.x)
        local dy = f.y - (f.prevY or f.y)
        local moveSpeed = math.sqrt(dx * dx + dy * dy)
        if moveSpeed > 0.5 then
            local bounceFreq = 12.0
            local bounceAmp = math.min(moveSpeed * 0.08, 4)
            bounceY = -math.abs(math.sin((f.bouncePhase or 0) + GS.gameTime * bounceFreq)) * bounceAmp
            local bPhase = math.sin((f.bouncePhase or 0) + GS.gameTime * bounceFreq)
            scaleY = scaleY + bPhase * 0.06
            scaleX = scaleX - bPhase * 0.04
        end

        if (f.hitTimer or 0) > 0 then
            local hitProg = f.hitTimer / 0.2
            local hitScale = 0.8 + 0.2 * (1.0 - hitProg)
            scaleX = scaleX * hitScale
            scaleY = scaleY * hitScale
        end
    end

    -- ========== 0) 阴影 ==========
    local shadowScaleY = 0.35
    local shadowAlpha = math.max(30, 80 - math.floor(math.abs(bounceY) * 8))
    local shadowRadius = radius * (1.0 + math.abs(bounceY) * 0.03)
    -- 精灵单位：帧以 sy 为中心上下各 halfH 绘制，脚底在 sy + halfH = sy + radius*1.75
    -- 非精灵单位：圆形单位，圆心在 sy，脚底在 sy + radius
    local shadowY = isSpriteUnit and (sy + radius * UNIT_DRAW_SCALE * 0.5)
                                  or  (sy + radius * 0.85)
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, shadowY, shadowRadius, radius * shadowScaleY)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, shadowAlpha))
    nvgFill(ctx)

    local drawY = sy + bounceY  -- 精灵单位 bounceY=0，非精灵单位有弹跳

    -- ========== 1) 保存变换 ==========
    nvgSave(ctx)
    nvgTranslate(ctx, sx, drawY)
    if not isSpriteUnit then
        nvgScale(ctx, scaleX, scaleY)
    end
    -- 接下来相对 (0,0) 绘制

    if f.fType == "peasant" and isSpriteUnit then
        -- ========== 农民：精灵表动画 ==========
        local as = peasantAnimState[f.id]
        if not as then
            as = { anim = "idle", frame = 0, timer = 0,
                   prevX = f.x, prevY = f.y, facingRight = true }
            peasantAnimState[f.id] = as
        end

        -- 用动画状态自己记录的位置差检测移动
        -- （f.prevX 在 Update 末尾已被更新为当前值，此处不可用）
        local adx = f.x - as.prevX
        local ady = f.y - as.prevY
        local moving = (math.abs(adx) > 0.1 or math.abs(ady) > 0.1)

        -- 更新水平朝向（用于镜像）
        if math.abs(adx) > 0.1 then
            as.facingRight = (adx > 0)
        end

        -- 决定目标动画（moving 优先：靠近目标途中用 run，到达后才用采集动画）
        local targetAnim
        if f.state == "working" and not moving then
            local res = nil
            for _, r in ipairs(GS.resources or {}) do
                if r.id == f.targetId then res = r; break end
            end
            targetAnim = (res and res.rType == "tree") and "axe" or "pickaxe"
        elseif moving then
            targetAnim = "run"
        else
            targetAnim = "idle"
        end

        if as.anim ~= targetAnim then
            as.anim = targetAnim; as.frame = 0; as.timer = 0
        end

        -- 推进帧
        local dt = GS.lastDt or (1/60)
        local facSprites = allSprites[f.factionId]
        local spr = facSprites and facSprites.peasant and facSprites.peasant[as.anim]
        if spr then
            as.timer = as.timer + dt
            local frameDur = 1.0 / spr.fps
            while as.timer >= frameDur do
                as.timer = as.timer - frameDur
                as.frame = (as.frame + 1) % spr.frames
            end

            local drawH = radius * UNIT_DRAW_SCALE
            local drawW = drawH * (spr.fw / spr.fh)
            local halfH = drawH * 0.5
            local halfW = drawW * 0.5
            local totalImgW = drawW * spr.frames
            local ox = -halfW - as.frame * drawW
            -- 向左镜像：绕 x=0 做水平翻转
            if not as.facingRight then nvgSave(ctx); nvgScale(ctx, -1, 1) end
            local pat = nvgImagePattern(ctx, ox, -halfH, totalImgW, drawH, 0, spr.img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, -halfW, -halfH, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
            if not as.facingRight then nvgRestore(ctx) end
        else
            -- 精灵未加载退回圆形
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255)); nvgFill(ctx)
        end

        -- 受击闪红
        if (f.hitTimer or 0) > 0 then
            local hitAlpha = math.floor((f.hitTimer / 0.2) * 100)
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(255, 50, 50, hitAlpha)); nvgFill(ctx)
        end

        -- 记录本帧位置（下帧用于计算移动差）
        as.prevX = f.x; as.prevY = f.y

    elseif f.fType == "soldier" and isSpriteUnit then
        -- ========== 士兵：精灵表动画 ==========
        local as = soldierAnimState[f.id]
        if not as then
            as = { anim = "idle", frame = 0, timer = 0,
                   prevX = f.x, prevY = f.y, facingRight = true,
                   attackVariant = 1, prevState = "" }
            soldierAnimState[f.id] = as
        end

        -- 用动画状态记录的位置差检测移动
        local adx = f.x - as.prevX
        local ady = f.y - as.prevY
        local moving = (math.abs(adx) > 0.1 or math.abs(ady) > 0.1)

        -- 更新朝向
        if math.abs(adx) > 0.1 then
            as.facingRight = (adx > 0)
        end

        -- 决定目标动画（moving 优先：靠近目标途中用 run，到达后才用攻击动画）
        local targetAnim
        if f.state == "attacking" and not moving then
            if as.prevState ~= "attacking" then
                as.attackVariant = (as.attackVariant == 1) and 2 or 1
                as.frame = 0; as.timer = 0
            end
            targetAnim = "attack" .. as.attackVariant
        elseif moving then
            targetAnim = "run"
        else
            targetAnim = "idle"
        end
        as.prevState = f.state

        if as.anim ~= targetAnim then
            as.anim = targetAnim
            if f.state ~= "attacking" then as.frame = 0; as.timer = 0 end
        end

        -- 推进帧
        local dt = GS.lastDt or (1/60)
        local facSprites = allSprites[f.factionId]
        local spr = facSprites and facSprites.soldier and facSprites.soldier[as.anim]
        if spr then
            as.timer = as.timer + dt
            local frameDur = 1.0 / spr.fps
            while as.timer >= frameDur do
                as.timer = as.timer - frameDur
                as.frame = (as.frame + 1) % spr.frames
            end

            local drawH = radius * UNIT_DRAW_SCALE
            local drawW = drawH * (spr.fw / spr.fh)
            local halfH = drawH * 0.5
            local halfW = drawW * 0.5
            local totalImgW = drawW * spr.frames
            local ox = -halfW - as.frame * drawW
            if not as.facingRight then nvgSave(ctx); nvgScale(ctx, -1, 1) end
            local pat = nvgImagePattern(ctx, ox, -halfH, totalImgW, drawH, 0, spr.img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, -halfW, -halfH, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
            if not as.facingRight then nvgRestore(ctx) end
        else
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255)); nvgFill(ctx)
        end

        -- 受击闪红
        if (f.hitTimer or 0) > 0 then
            local hitAlpha = math.floor((f.hitTimer / 0.2) * 100)
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(255, 50, 50, hitAlpha)); nvgFill(ctx)
        end

        -- 记录本帧位置
        as.prevX = f.x; as.prevY = f.y

    elseif f.fType == "archer" and isSpriteUnit then
        -- ========== 弓箭手：精灵表动画 ==========
        local as = archerAnimState[f.id]
        if not as then
            as = { anim = "idle", frame = 0, timer = 0,
                   prevX = f.x, prevY = f.y, facingRight = true }
            archerAnimState[f.id] = as
        end

        local adx = f.x - as.prevX
        local ady = f.y - as.prevY
        local moving = (math.abs(adx) > 0.1 or math.abs(ady) > 0.1)

        if math.abs(adx) > 0.1 then
            as.facingRight = (adx > 0)
        end

        -- 决定目标动画（到达目标后才播放射击动画）
        local targetAnim
        if f.state == "attacking" and not moving then
            targetAnim = "shoot"
        elseif moving then
            targetAnim = "run"
        else
            targetAnim = "idle"
        end

        if as.anim ~= targetAnim then
            as.anim = targetAnim; as.frame = 0; as.timer = 0
        end

        -- 推进帧
        local dt = GS.lastDt or (1/60)
        local facSprites = allSprites[f.factionId]
        local spr = facSprites and facSprites.archer and facSprites.archer[as.anim]
        if spr then
            as.timer = as.timer + dt
            local frameDur = 1.0 / spr.fps
            while as.timer >= frameDur do
                as.timer = as.timer - frameDur
                as.frame = (as.frame + 1) % spr.frames
            end

            local drawH = radius * UNIT_DRAW_SCALE
            local drawW = drawH * (spr.fw / spr.fh)
            local halfH = drawH * 0.5
            local halfW = drawW * 0.5
            local totalImgW = drawW * spr.frames
            local ox = -halfW - as.frame * drawW
            if not as.facingRight then nvgSave(ctx); nvgScale(ctx, -1, 1) end
            local pat = nvgImagePattern(ctx, ox, -halfH, totalImgW, drawH, 0, spr.img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, -halfW, -halfH, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
            if not as.facingRight then nvgRestore(ctx) end
        else
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255)); nvgFill(ctx)
        end

        -- 受击闪红
        if (f.hitTimer or 0) > 0 then
            local hitAlpha = math.floor((f.hitTimer / 0.2) * 100)
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(255, 50, 50, hitAlpha)); nvgFill(ctx)
        end

        as.prevX = f.x; as.prevY = f.y

    elseif f.fType == "healer" and isSpriteUnit then
        -- ========== 治愈师：精灵表动画（所有阵营）==========
        local as = healerAnimState[f.id]
        if not as then
            as = { anim = "idle", frame = 0, timer = 0,
                   prevX = f.x, prevY = f.y, facingRight = true }
            healerAnimState[f.id] = as
        end

        local adx = f.x - as.prevX
        local ady = f.y - as.prevY
        local moving = (math.abs(adx) > 0.1 or math.abs(ady) > 0.1)
        if math.abs(adx) > 0.1 then as.facingRight = (adx > 0) end

        local targetAnim
        if f.state == "healing" then
            targetAnim = "heal"
        elseif moving then
            targetAnim = "run"
        else
            targetAnim = "idle"
        end

        if as.anim ~= targetAnim then
            as.anim = targetAnim; as.frame = 0; as.timer = 0
        end

        local dt = GS.lastDt or (1/60)
        local facSprites = allSprites[f.factionId]
        local spr = facSprites and facSprites.healer and facSprites.healer[as.anim]
        if spr then
            as.timer = as.timer + dt
            local frameDur = 1.0 / spr.fps
            while as.timer >= frameDur do
                as.timer = as.timer - frameDur
                as.frame = (as.frame + 1) % spr.frames
            end

            local drawH = radius * UNIT_DRAW_SCALE
            local drawW = drawH * (spr.fw / spr.fh)
            local halfH = drawH * 0.5
            local halfW = drawW * 0.5
            local totalImgW = drawW * spr.frames
            local ox = -halfW - as.frame * drawW
            if not as.facingRight then nvgSave(ctx); nvgScale(ctx, -1, 1) end
            local pat = nvgImagePattern(ctx, ox, -halfH, totalImgW, drawH, 0, spr.img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, -halfW, -halfH, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
            if not as.facingRight then nvgRestore(ctx) end
        else
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255)); nvgFill(ctx)
        end

        -- 受击闪红
        if (f.hitTimer or 0) > 0 then
            local hitAlpha = math.floor((f.hitTimer / 0.2) * 100)
            nvgBeginPath(ctx); nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(255, 50, 50, hitAlpha)); nvgFill(ctx)
        end

        as.prevX = f.x; as.prevY = f.y

    else
        -- ========== 2) 色环（外圈） ==========
        local ringColor = CONFIG.UnitRingColors[f.fType] or {200, 200, 200}
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, radius + 2)
        nvgFillColor(ctx, nvgRGBA(ringColor[1], ringColor[2], ringColor[3], 200))
        nvgFill(ctx)

        -- ========== 3) 身体（阵营色圆形） ==========
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, radius)
        nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255))
        nvgFill(ctx)

        -- ========== 4) 贴图覆盖 ==========
        local tex = unitTextures[f.fType]
        if tex then
            local texSize = radius * 2
            local pat = nvgImagePattern(ctx, -radius, -radius, texSize, texSize, 0, tex, 0.92)
            nvgBeginPath(ctx)
            nvgCircle(ctx, 0, 0, radius)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
        end

        -- ========== 5) 白色高光（立体感） ==========
        local highlight = nvgRadialGradient(ctx, -radius * 0.25, -radius * 0.25,
            radius * 0.1, radius * 0.7,
            nvgRGBA(255, 255, 255, 50),
            nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, radius)
        nvgFillPaint(ctx, highlight)
        nvgFill(ctx)

        -- ========== 5.5) 受击闪红覆盖 ==========
        if (f.hitTimer or 0) > 0 then
            local hitAlpha = math.floor((f.hitTimer / 0.2) * 120)
            nvgBeginPath(ctx)
            nvgCircle(ctx, 0, 0, radius)
            nvgFillColor(ctx, nvgRGBA(255, 50, 50, hitAlpha))
            nvgFill(ctx)
        end
    end

    nvgRestore(ctx)  -- 恢复变换

    -- ========== 盾墙特效：蓝色护盾光环 ==========
    local shieldState = GS.skillStates.shieldWall
    if shieldState and f.fType == "soldier" and f.factionId == (GS.lords[1] and GS.lords[1].faction) then
        local swPulse = 0.7 + math.sin(GS.gameTime * 4 + (f.id or 0) * 0.3) * 0.3
        local swAlpha = math.floor(80 * swPulse)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, drawY, radius + 5)
        nvgStrokeColor(ctx, nvgRGBA(80, 160, 255, swAlpha + 60))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, drawY, radius + 5)
        nvgFillColor(ctx, nvgRGBA(80, 160, 255, math.floor(swAlpha * 0.3)))
        nvgFill(ctx)
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 9)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(120, 200, 255, swAlpha + 80))
        nvgText(ctx, sx, drawY - radius - 7, "盾", nil)
    end

    -- ========== 6) HP条（受伤时显示，不受缩放影响） ==========
    if f.hp and f.maxHp and f.hp < f.maxHp then
        local barW = radius * 2
        local barH = 2.5
        local barY = drawY - radius - 5
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

    -- ========== 9) 攻击/采集状态指示 ==========
    if f.state == "attacking" then
        local flashAlpha = 150 + math.floor(math.sin(GS.gameTime * 8) * 100)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, drawY - radius - 4, 3)
        nvgFillColor(ctx, nvgRGBA(255, 80, 80, flashAlpha))
        nvgFill(ctx)
    elseif f.state == "working" then
        local flashAlpha = 150 + math.floor(math.sin(GS.gameTime * 6) * 80)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, drawY - radius - 4, 3)
        nvgFillColor(ctx, nvgRGBA(255, 200, 50, flashAlpha))
        nvgFill(ctx)
    end

    -- ========== 11) 巨兽惊吓：蓝色闪烁 + 恐惧标记 ==========
    if f.beastScaredTimer and f.beastScaredTimer > 0 then
        -- 蓝白闪烁外环
        local scatterPulse = math.sin(GS.gameTime * 12 + (f.id or 0) * 0.5)
        local scatterAlpha = math.floor(100 + scatterPulse * 60)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, drawY, radius + 4)
        nvgStrokeColor(ctx, nvgRGBA(100, 180, 255, scatterAlpha))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
        -- 恐惧感叹号
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(255, 255, 100, scatterAlpha))
        nvgText(ctx, sx, drawY - radius - 6, "!", nil)
    end
end

function M.drawBoss(b)
    if not b.alive then return end
    if not Utils.isOnScreen(b.x, b.y, 100) then return end

    local sx, sy = Utils.worldToScreen(b.x, b.y)
    local bossRadius = CONFIG.BossRadius
    local cfg = CONFIG.BossTypes[b.bossType] or CONFIG.BossTypes.behemoth

    -- ========== Boss 动画计算 ==========
    local breathFreq = 2.0   -- Boss 呼吸频率（慢，~1/3秒一个周期）
    local breathAmpX = 0.03
    local breathAmpY = 0.04
    local breathVal = math.sin((b.breathPhase or 0) + GS.gameTime * breathFreq)
    local scaleX = 1.0 + breathAmpX * breathVal
    local scaleY = 1.0 - breathAmpY * breathVal

    -- 受击反馈缩放（Boss用0.3秒恢复，比士兵慢）
    local hitRecoverTime = 0.3
    if (b.hitTimer or 0) > 0 then
        local hitProg = b.hitTimer / hitRecoverTime
        local hitScale = 0.85 + 0.15 * (1.0 - hitProg)
        scaleX = scaleX * hitScale
        scaleY = scaleY * hitScale
    end

    -- 移动检测 & 缓慢摇摆
    local bdx = b.x - (b.prevX or b.x)
    local bdy = b.y - (b.prevY or b.y)
    local bMoveSpeed = math.sqrt(bdx * bdx + bdy * bdy)
    local swayX = 0  -- 水平摇摆偏移
    if bMoveSpeed > 0.3 then
        swayX = math.sin(GS.gameTime * 3.0) * 2.0  -- 慢速左右摆动
    end

    -- ========== 0) Boss 阴影 ==========
    local shadowAlpha = math.max(25, 60)
    local shadowRx = bossRadius * 1.1
    local shadowRy = bossRadius * 0.3
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + bossRadius * 0.6, shadowRx, shadowRy)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, shadowAlpha))
    nvgFill(ctx)

    -- ========== 1) 保存变换 ==========
    nvgSave(ctx)
    nvgTranslate(ctx, sx + swayX, sy)
    nvgScale(ctx, scaleX, scaleY)

    if b.bossType == "crab" then
        -- ======== 石甲蟹：六边形 + 灰色 + AOE范围指示 ========
        -- 灰蓝色光环
        local glow = nvgRadialGradient(ctx, 0, 0, bossRadius, bossRadius * 2.5,
            nvgRGBA(120, 120, 160, 35),
            nvgRGBA(120, 120, 160, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, bossRadius * 2.5)
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)

        -- AOE范围指示圈（脉冲效果）
        local aoePulse = 0.6 + math.sin(GS.gameTime * 3) * 0.3
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, cfg.aoeRadius * aoePulse)
        nvgStrokeColor(ctx, nvgRGBA(255, 100, 100, 40))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)

        -- 六边形身体
        nvgBeginPath(ctx)
        for i = 0, 5 do
            local a = (i / 6) * math.pi * 2 - math.pi / 6
            local r = bossRadius
            local px = math.cos(a) * r
            local py = math.sin(a) * r
            if i == 0 then nvgMoveTo(ctx, px, py) else nvgLineTo(ctx, px, py) end
        end
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(120, 120, 140, 255))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(180, 180, 200, 255))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 眼睛（小缝隙样式）- 发光
        local eyeGlow = 180 + math.floor(math.sin(GS.gameTime * 4) * 75)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, -8, -3)
        nvgLineTo(ctx, -3, -5)
        nvgMoveTo(ctx, 3, -5)
        nvgLineTo(ctx, 8, -3)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 50, eyeGlow))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

    elseif b.bossType == "wolf" then
        -- ======== 幽灵狼：三角形 + 紫色 + 隐身闪烁 ========
        local alpha = b.isStealthed and math.floor(80 + math.sin(GS.gameTime * 10) * 40) or 255

        -- 紫色光环
        local glow = nvgRadialGradient(ctx, 0, 0, bossRadius, bossRadius * 2.5,
            nvgRGBA(150, 100, 220, math.floor(alpha * 0.15)),
            nvgRGBA(150, 100, 220, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, bossRadius * 2.5)
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)

        -- 三角形身体（朝向移动方向）
        nvgSave(ctx)
        nvgRotate(ctx, b.angle)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, bossRadius, 0)
        nvgLineTo(ctx, -bossRadius * 0.8, -bossRadius * 0.6)
        nvgLineTo(ctx, -bossRadius * 0.5, 0)
        nvgLineTo(ctx, -bossRadius * 0.8, bossRadius * 0.6)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(150, 100, 220, alpha))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(200, 160, 255, alpha))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
        nvgRestore(ctx)

        -- 眼睛（隐身时也闪烁）- 发光脉冲
        local wolfEyeGlow = b.isStealthed and alpha or (200 + math.floor(math.sin(GS.gameTime * 5) * 55))
        nvgBeginPath(ctx)
        nvgCircle(ctx, math.cos(b.angle) * 5 - math.sin(b.angle) * 4,
                       math.sin(b.angle) * 5 + math.cos(b.angle) * 4, 3)
        nvgCircle(ctx, math.cos(b.angle) * 5 + math.sin(b.angle) * 4,
                       math.sin(b.angle) * 5 - math.cos(b.angle) * 4, 3)
        nvgFillColor(ctx, nvgRGBA(200, 150, 255, wolfEyeGlow))
        nvgFill(ctx)

    else
        -- ======== 巨兽：原有锯齿圆（红色） ========
        -- 红色光环
        local glow = nvgRadialGradient(ctx, 0, 0, bossRadius, bossRadius * 3,
            nvgRGBA(200, 50, 50, 40),
            nvgRGBA(200, 50, 50, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, bossRadius * 3)
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)

        -- 锯齿圆身体
        nvgBeginPath(ctx)
        local segments = 12
        for i = 0, segments - 1 do
            local a = (i / segments) * math.pi * 2 + GS.gameTime * 0.5
            local r = bossRadius + math.sin(a * 3) * 5
            local px = math.cos(a) * r
            local py = math.sin(a) * r
            if i == 0 then
                nvgMoveTo(ctx, px, py)
            else
                nvgLineTo(ctx, px, py)
            end
        end
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(180, 40, 40, 255))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(255, 100, 100, 255))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 眼睛 - 红色发光脉冲
        local eyePulse = 200 + math.floor(math.sin(GS.gameTime * 3) * 55)
        nvgBeginPath(ctx)
        nvgCircle(ctx, -6, -4, 4)
        nvgCircle(ctx, 6, -4, 4)
        nvgFillColor(ctx, nvgRGBA(255, eyePulse, 50, 255))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, -6, -4, 2)
        nvgCircle(ctx, 6, -4, 2)
        nvgFillColor(ctx, nvgRGBA(60, 0, 0, 255))
        nvgFill(ctx)
    end

    -- 受击闪红覆盖（所有Boss类型通用）
    if (b.hitTimer or 0) > 0 then
        local hitAlpha = math.floor((b.hitTimer / hitRecoverTime) * 100)
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, bossRadius)
        nvgFillColor(ctx, nvgRGBA(255, 50, 50, hitAlpha))
        nvgFill(ctx)
    end

    nvgRestore(ctx)  -- 恢复变换

    -- ========== 以下在屏幕空间绘制，不受缩放影响 ==========
    local drawSX = sx + swayX  -- 摇摆后的屏幕X

    -- 血条（通用）
    local hpBarW = 40
    local hpBarH = 5
    local hpRatio = b.hp / b.maxHp
    local barAlpha = (b.bossType == "wolf" and b.isStealthed) and 120 or 255
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, drawSX - hpBarW/2, sy + bossRadius + 6, hpBarW, hpBarH, 2)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(barAlpha * 0.6)))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, drawSX - hpBarW/2, sy + bossRadius + 6, hpBarW * hpRatio, hpBarH, 2)
    nvgFillColor(ctx, nvgRGBA(255, 80, 80, barAlpha))
    nvgFill(ctx)

    -- Boss 标签（使用cfg.name）
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(255, 100, 100, barAlpha))
    nvgText(ctx, drawSX, sy - bossRadius - 4, cfg.name, nil)
end

function M.drawChest(c)
    if not c.alive then return end
    if not Utils.isOnScreen(c.x, c.y, 30) then return end

    local sx, sy = Utils.worldToScreen(c.x, c.y)

    -- 发光效果
    local pulse = 0.8 + math.sin(GS.gameTime * 4) * 0.2
    local glow = nvgRadialGradient(ctx, sx, sy, 5, 35,
        nvgRGBA(255, 220, 50, math.floor(80 * pulse)),
        nvgRGBA(255, 220, 50, 0))
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy, 35)
    nvgFillPaint(ctx, glow)
    nvgFill(ctx)

    -- 宝箱
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - 10, sy - 7, 20, 14, 3)
    nvgFillColor(ctx, nvgRGBA(200, 160, 50, 255))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(160, 120, 30, 255))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    -- 锁扣
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy, 3)
    nvgFillColor(ctx, nvgRGBA(255, 230, 100, 255))
    nvgFill(ctx)
end

function M.drawLootBox(lb)
    if not lb.alive then return end
    if not Utils.isOnScreen(lb.x, lb.y, 30) then return end

    local sx, sy = Utils.worldToScreen(lb.x, lb.y)

    -- 紫色光芒
    local pulse = 0.7 + math.sin(GS.gameTime * 5) * 0.3
    local glow = nvgRadialGradient(ctx, sx, sy, 5, 40,
        nvgRGBA(200, 100, 255, math.floor(60 * pulse)),
        nvgRGBA(200, 100, 255, 0))
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy, 40)
    nvgFillPaint(ctx, glow)
    nvgFill(ctx)

    -- 菱形遗产包
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy - 12)
    nvgLineTo(ctx, sx + 10, sy)
    nvgLineTo(ctx, sx, sy + 12)
    nvgLineTo(ctx, sx - 10, sy)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(180, 80, 255, 255))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(255, 200, 255, 200))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
end

-- ============================================================================
-- 治疗特效：在被治疗目标位置播放 Heal_Effect 精灵动画
-- GS.healEffects = { {x, y, frame, timer, targetId}, ... }
-- 动画播完后移除
-- ============================================================================
function M.drawHealEffects()
    if not GS.healEffects then return end
    local dt = GS.lastDt or (1/60)
    local toRemove = {}

    for i, he in ipairs(GS.healEffects) do
        -- 按施法者阵营取对应治疗特效精灵
        local spr = healEffectSprites[he.factionId]
        if not spr then goto he_continue end

        local frameDur = 1.0 / spr.fps

        -- 更新目标位置（目标可能在移动）
        for _, f in ipairs(GS.followers) do
            if f.id == he.targetId then he.x, he.y = f.x, f.y; break end
        end
        for _, l in ipairs(GS.lords) do
            if l.id == he.targetId then he.x, he.y = l.x, l.y; break end
        end

        if not Utils.isOnScreen(he.x, he.y, 60) then goto he_continue end
        local sx, sy = Utils.worldToScreen(he.x, he.y)

        -- 推进帧
        he.timer = he.timer + dt
        while he.timer >= frameDur do
            he.timer = he.timer - frameDur
            he.frame = he.frame + 1
        end

        if he.frame >= spr.frames then
            table.insert(toRemove, i)
            goto he_continue
        end

        -- 绘制特效（正方形，略大于单位）
        local drawSize = 80  -- 固定大小，覆盖目标上方
        local half = drawSize * 0.5
        local totalDrawW = drawSize * spr.frames
        local ox = -half - he.frame * drawSize
        -- 进出场渐变透明度：前2帧淡入，后2帧淡出
        local alpha = 1.0
        if he.frame < 2 then
            alpha = (he.frame + he.timer / frameDur) / 2.0
        elseif he.frame >= spr.frames - 2 then
            alpha = (spr.frames - he.frame - he.timer / frameDur) / 2.0
        end
        alpha = math.max(0, math.min(1, alpha))

        nvgSave(ctx)
        nvgTranslate(ctx, sx, sy - half * 0.3)  -- 略上移，覆盖角色中上部
        local pat = nvgImagePattern(ctx, ox, -half, totalDrawW, drawSize, 0, spr.img, alpha)
        nvgBeginPath(ctx)
        nvgRect(ctx, -half, -half, drawSize, drawSize)
        nvgFillPaint(ctx, pat)
        nvgFill(ctx)
        nvgRestore(ctx)

        ::he_continue::
    end

    -- 逆序移除已完成特效
    for i = #toRemove, 1, -1 do
        table.remove(GS.healEffects, toRemove[i])
    end
end

function M.drawParticles()
    for _, p in ipairs(GS.particles) do
        if not Utils.isOnScreen(p.x, p.y, 10) then goto continue end
        local sx, sy = Utils.worldToScreen(p.x, p.y)
        local alpha = math.floor((p.life / p.maxLife) * 255)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, p.size * (p.life / p.maxLife))
        nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, alpha))
        nvgFill(ctx)
        ::continue::
    end
end

function M.drawDamageNumbers()
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, dn in ipairs(GS.damageNumbers) do
        if not Utils.isOnScreen(dn.x, dn.y, 30) then goto continue end
        local sx, sy = Utils.worldToScreen(dn.x, dn.y)
        local alpha = math.floor((dn.life / dn.maxLife) * 255)
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(dn.r, dn.g, dn.b, alpha))
        nvgText(ctx, sx, sy, dn.text, nil)
        ::continue::
    end
end



function M.drawRespawnOverlay(w, h)
    -- 玩家复活倒计时覆盖层
    local playerLord = GS.lords[1]
    if not playerLord then return end
    local info = GS.respawning[playerLord.id]
    if not info then return end

    -- 半透明遮罩
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 100))
    nvgFill(ctx)

    -- 复活倒计时文本
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(ctx, 36)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, w/2, h/2 - 20, "复活中...", nil)
    nvgFontSize(ctx, 48)
    nvgFillColor(ctx, nvgRGBA(100, 200, 255, 255))
    local timerText = string.format("%.1fs", math.max(0, info.timer))
    nvgText(ctx, w/2, h/2 + 30, timerText, nil)
end

-- 小地图点击检测（由 main.lua 调用）
function M.isMinimapClicked(mx, my, w, h)
    local mmSize = GS.minimapExpanded and 240 or 120
    local mmMargin = 10
    local mmX = w - mmSize - mmMargin
    local mmY = mmMargin
    return mx >= mmX and mx <= mmX + mmSize and my >= mmY and my <= mmY + mmSize
end

function M.drawMinimap(w, h)
    local mmSizeSmall = 120
    local mmSizeLarge = 240
    local mmSize = GS.minimapExpanded and mmSizeLarge or mmSizeSmall
    local mmMargin = 10
    local mmX = w - mmSize - mmMargin
    local mmY = mmMargin
    local scale = mmSize / CONFIG.MapWidth

    -- 放大模式下半透明点击提示的缩放倍率
    local dotScale = GS.minimapExpanded and 1.6 or 1.0

    -- 背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, mmX, mmY, mmSize, mmSize, 6)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, GS.minimapExpanded and 180 or 150))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(140, 140, 140, 220))
    nvgStrokeWidth(ctx, GS.minimapExpanded and 1.5 or 1)
    nvgStroke(ctx)

    -- 资源点
    for _, r in ipairs(GS.resources) do
        if r.alive then
            local rx = mmX + r.x * scale
            local ry = mmY + r.y * scale
            nvgBeginPath(ctx)
            nvgCircle(ctx, rx, ry, 1.5 * dotScale)
            if r.rType == "tree" then
                nvgFillColor(ctx, nvgRGBA(50, 180, 50, 200))
            else
                nvgFillColor(ctx, nvgRGBA(150, 150, 180, 200))
            end
            nvgFill(ctx)
        end
    end

    -- Boss（按类型着色）
    for _, b in ipairs(GS.bosses) do
        if b.alive then
            local bx = mmX + b.x * scale
            local by = mmY + b.y * scale
            local br, bg, bb = 255, 50, 50
            if b.bossType == "crab" then
                br, bg, bb = 120, 120, 180
            elseif b.bossType == "wolf" then
                br, bg, bb = 180, 120, 255
            end
            local bAlpha = (b.bossType == "wolf" and b.isStealthed) and 100 or 255
            nvgBeginPath(ctx)
            nvgCircle(ctx, bx, by, 3 * dotScale)
            nvgFillColor(ctx, nvgRGBA(br, bg, bb, bAlpha))
            nvgFill(ctx)
        end
    end

    -- 巨兽（深棕色大圆点 + 危险圈）
    for _, beast in ipairs(GS.giantBeasts) do
        if beast.alive then
            local bx = mmX + beast.x * scale
            local by = mmY + beast.y * scale
            local bc = CONFIG.BeastColor
            -- 危险范围淡圈
            nvgBeginPath(ctx)
            nvgCircle(ctx, bx, by, CONFIG.BeastAggroRadius * scale)
            nvgFillColor(ctx, nvgRGBA(200, 60, 40, 20))
            nvgFill(ctx)
            -- 身体
            nvgBeginPath(ctx)
            nvgCircle(ctx, bx, by, 4 * dotScale)
            nvgFillColor(ctx, nvgRGBA(bc[1], bc[2], bc[3], 255))
            nvgFill(ctx)
        end
    end

    -- 领主（大小随兵力变化）
    for _, l in ipairs(GS.lords) do
        if l.alive then
            local lx = mmX + l.x * scale
            local ly = mmY + l.y * scale
            local fc = FACTION_COLORS[l.faction] or {200, 200, 200}
            local fCount = countFollowers(l.id)
            local mmLordR = (3 + math.min(fCount / CONFIG.LordFollowerCap, 1.0) * 3) * dotScale
            nvgBeginPath(ctx)
            nvgCircle(ctx, lx, ly, mmLordR)
            nvgFillColor(ctx, nvgRGBA(fc[1], fc[2], fc[3], 255))
            nvgFill(ctx)
            if l.isPlayer then
                nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 200))
                nvgStrokeWidth(ctx, 1.5)
                nvgStroke(ctx)
            end
        end
    end

    -- 宝箱/遗产
    for _, c in ipairs(GS.chests) do
        if c.alive then
            local cx = mmX + c.x * scale
            local cy = mmY + c.y * scale
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, 2 * dotScale)
            nvgFillColor(ctx, nvgRGBA(255, 220, 50, 255))
            nvgFill(ctx)
        end
    end
    for _, lb in ipairs(GS.lootBoxes) do
        if lb.alive then
            local lx = mmX + lb.x * scale
            local ly = mmY + lb.y * scale
            nvgBeginPath(ctx)
            nvgCircle(ctx, lx, ly, 2 * dotScale)
            nvgFillColor(ctx, nvgRGBA(200, 100, 255, 255))
            nvgFill(ctx)
        end
    end

    -- 视野范围
    local vx = mmX + GS.cameraX * scale
    local vy = mmY + GS.cameraY * scale
    local vw = GS.screenW * scale
    local vh = GS.screenH * scale
    nvgBeginPath(ctx)
    nvgRect(ctx, vx - vw/2, vy - vh/2, vw, vh)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 150))
    nvgStrokeWidth(ctx, GS.minimapExpanded and 1.5 or 1)
    nvgStroke(ctx)

    -- 点击提示图标（右下角小放大镜/缩小图标）
    local iconSize = 14
    local iconX = mmX + mmSize - iconSize - 4
    local iconY = mmY + mmSize - iconSize - 4
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, iconX - 2, iconY - 2, iconSize + 4, iconSize + 4, 3)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 100))
    nvgFill(ctx)
    if GS.minimapExpanded then
        -- 缩小图标：两条对角线向内
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, iconX + 2, iconY + 2)
        nvgLineTo(ctx, iconX + iconSize - 2, iconY + iconSize - 2)
        nvgMoveTo(ctx, iconX + iconSize - 2, iconY + 2)
        nvgLineTo(ctx, iconX + 2, iconY + iconSize - 2)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    else
        -- 放大图标：圆圈 + 手柄
        nvgBeginPath(ctx)
        nvgCircle(ctx, iconX + iconSize * 0.4, iconY + iconSize * 0.4, iconSize * 0.3)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, iconX + iconSize * 0.6, iconY + iconSize * 0.6)
        nvgLineTo(ctx, iconX + iconSize - 1, iconY + iconSize - 1)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    end
end

-- ============================================================================
-- 随机事件屏幕效果
-- ============================================================================
function M.drawEventEffects(w, h)
    -- 血月：红色渐晕（四边红色半透明渐变）
    if GS.bloodMoonActive then
        local edgeW = w * 0.15
        local edgeH = h * 0.15
        -- 左
        local paint = nvgLinearGradient(ctx, 0, h * 0.5, edgeW, h * 0.5, nvgRGBA(180, 0, 0, 50), nvgRGBA(180, 0, 0, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, edgeW, h)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
        -- 右
        paint = nvgLinearGradient(ctx, w, h * 0.5, w - edgeW, h * 0.5, nvgRGBA(180, 0, 0, 50), nvgRGBA(180, 0, 0, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, w - edgeW, 0, edgeW, h)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
        -- 上
        paint = nvgLinearGradient(ctx, w * 0.5, 0, w * 0.5, edgeH, nvgRGBA(180, 0, 0, 50), nvgRGBA(180, 0, 0, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, edgeH)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
        -- 下
        paint = nvgLinearGradient(ctx, w * 0.5, h, w * 0.5, h - edgeH, nvgRGBA(180, 0, 0, 50), nvgRGBA(180, 0, 0, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, h - edgeH, w, edgeH)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
    end

    -- 迷雾：灰色半透明遮罩
    if GS.fogActive then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, h)
        nvgFillColor(ctx, nvgRGBA(180, 180, 200, 25))
        nvgFill(ctx)
    end

    -- 事件通知（顶部居中，带淡出）
    if GS.eventNotification then
        local alpha = math.min(1.0, GS.eventNotification.timer / 0.5) -- 最后0.5秒淡出
        local a = math.floor(alpha * 255)
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 22)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 背景条
        local tw = nvgTextBounds(ctx, 0, 0, GS.eventNotification.text)
        local bx = w * 0.5 - tw * 0.5 - 16
        local by = 50
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, bx, by - 16, tw + 32, 32, 6)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 160)))
        nvgFill(ctx)
        -- 文本
        nvgFillColor(ctx, nvgRGBA(255, 220, 100, a))
        nvgText(ctx, w * 0.5, by, GS.eventNotification.text)
    end

    -- 持续事件倒计时（小地图下方）
    if GS.activeEvent and GS.activeEvent.remaining > 0 then
        local mmSize = GS.minimapExpanded and 240 or 120
        local evtY = 10 + mmSize + 6
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 16)
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        local label = GS.activeEvent.name .. " " .. string.format("%.0f", GS.activeEvent.remaining) .. "s"
        local labelColor
        if GS.activeEvent.type == "blood_moon" then
            labelColor = nvgRGBA(255, 100, 100, 200)
        else
            labelColor = nvgRGBA(180, 180, 220, 200)
        end
        nvgFillColor(ctx, labelColor)
        nvgText(ctx, w - 16, evtY, label)
    end
end

-- ============================================================================
-- 箭矢绘制
-- ============================================================================
function M.drawProjectiles()
    for _, p in ipairs(GS.projectiles) do
        if p.alive and Utils.isOnScreen(p.x, p.y, 10) then
            local sx, sy = Utils.worldToScreen(p.x, p.y)
            local dx = p.tx - p.x
            local dy = p.ty - p.y
            local d = math.sqrt(dx * dx + dy * dy)
            local nx, ny = 0, 0
            if d > 0.01 then nx, ny = dx / d, dy / d end

            -- 使用各阵营的 Arrow.png 贴图（若已加载）
            local aImg = arrowSprites[p.factionId]

            if aImg then
                -- Arrow.png 贴图，按飞行方向旋转
                local angle = math.atan2(dy, dx)  -- 弧度，0 = 向右
                local arrowSize = 20
                local half = arrowSize * 0.5
                nvgSave(ctx)
                nvgTranslate(ctx, sx, sy)
                nvgRotate(ctx, angle)
                local pat = nvgImagePattern(ctx, -half, -half, arrowSize, arrowSize, 0, aImg, 1.0)
                nvgBeginPath(ctx)
                nvgRect(ctx, -half, -half, arrowSize, arrowSize)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
                nvgRestore(ctx)
            else
                -- 其他阵营：原有线段箭矢
                local pfc = FACTION_COLORS[p.factionId] or {200, 200, 200}
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx - nx * 6, sy - ny * 6)
                nvgLineTo(ctx, sx + nx * 6, sy + ny * 6)
                nvgStrokeColor(ctx, nvgRGBA(pfc[1], pfc[2], pfc[3], 230))
                nvgStrokeWidth(ctx, 2)
                nvgStroke(ctx)
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx + nx * 6, sy + ny * 6, 1.5)
                nvgFillColor(ctx, nvgRGBA(255, 255, 200, 255))
                nvgFill(ctx)
            end
        end
    end
end

-- ============================================================================
-- 虚拟摇杆绘制
-- ============================================================================
function M.drawJoystick()
    if GS.joystickActive then
        -- 底座
        nvgBeginPath(ctx)
        nvgCircle(ctx, GS.joystickCenterX, GS.joystickCenterY, 60)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 30))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 60))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 摇杆头
        local knobX = GS.joystickCenterX + GS.joystickX * 60
        local knobY = GS.joystickCenterY + GS.joystickY * 60
        nvgBeginPath(ctx)
        nvgCircle(ctx, knobX, knobY, 25)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 80))
        nvgFill(ctx)
    end
end

-- ============================================================================
-- 攻击按钮绘制
-- ============================================================================
function M.drawAttackButton(w, h)
    local r = 44          -- 按钮半径
    local margin = 30     -- 距右边/底边的距离
    local bx = w - margin - r
    local by = h - margin - r

    -- 按下时高亮
    local pressing = GS.attackBtnPressed
    local bgAlpha  = pressing and 160 or 80
    local rimAlpha = pressing and 255 or 140
    local scale    = pressing and 0.92 or 1.0

    nvgSave(ctx)
    nvgTranslate(ctx, bx, by)
    nvgScale(ctx, scale, scale)

    -- 外圈光晕
    local glow = nvgRadialGradient(ctx, 0, 0, r * 0.5, r * 1.6,
        nvgRGBA(255, 80, 80, pressing and 80 or 30),
        nvgRGBA(255, 80, 80, 0))
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r * 1.6)
    nvgFillPaint(ctx, glow)
    nvgFill(ctx)

    -- 按钮底色
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r)
    nvgFillColor(ctx, nvgRGBA(200, 50, 50, bgAlpha))
    nvgFill(ctx)

    -- 边框
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r)
    nvgStrokeColor(ctx, nvgRGBA(255, 120, 120, rimAlpha))
    nvgStrokeWidth(ctx, 2.5)
    nvgStroke(ctx)

    -- 剑形图标（简单叉形/闪电表示攻击）
    local sw = 3.5
    nvgLineCap(ctx, NVG_ROUND)
    -- 竖线（剑身）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, -18)
    nvgLineTo(ctx, 0, 14)
    nvgStrokeColor(ctx, nvgRGBA(255, 220, 220, 230))
    nvgStrokeWidth(ctx, sw)
    nvgStroke(ctx)
    -- 横线（护手）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, -12, -4)
    nvgLineTo(ctx, 12, -4)
    nvgStrokeColor(ctx, nvgRGBA(255, 220, 220, 230))
    nvgStrokeWidth(ctx, sw)
    nvgStroke(ctx)
    -- 剑尖（向下的小三角）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, -5, 8)
    nvgLineTo(ctx, 0, 16)
    nvgLineTo(ctx, 5, 8)
    nvgStrokeColor(ctx, nvgRGBA(255, 220, 220, 230))
    nvgStrokeWidth(ctx, sw - 0.5)
    nvgStroke(ctx)

    nvgRestore(ctx)

    -- 文字标签
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(255, 180, 180, pressing and 255 or 160))
    nvgText(ctx, bx, by + r + 4, "攻击", nil)
end

-- ============================================================================
-- 结算画面 (NanoVG)
-- ============================================================================
function M.drawGameOverScreen(w, h)
    -- 半透明遮罩
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
    nvgFill(ctx)

    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if GS.gameState == "gameover" then
        nvgFontSize(ctx, 48)
        nvgFillColor(ctx, nvgRGBA(255, 80, 80, 255))
        nvgText(ctx, w/2, h/2 - 40, "战败", nil)
    elseif GS.gameState == "victory" then
        nvgFontSize(ctx, 48)
        nvgFillColor(ctx, nvgRGBA(255, 220, 50, 255))
        nvgText(ctx, w/2, h/2 - 40, "胜利!", nil)
    end

    nvgFontSize(ctx, 20)
    nvgFillColor(ctx, nvgRGBA(200, 200, 200, 255))
    local timeStr = string.format("用时: %.0f秒", GS.gameTime)
    nvgText(ctx, w/2, h/2 + 10, timeStr, nil)

    -- 功勋结算显示
    nvgFontSize(ctx, 22)
    nvgFillColor(ctx, nvgRGBA(255, 200, 50, 255))
    nvgText(ctx, w/2, h/2 + 45, "功勋 +" .. GS.settledGlory, nil)

    nvgFontSize(ctx, 16)
    nvgFillColor(ctx, nvgRGBA(200, 180, 120, 200))
    nvgText(ctx, w/2, h/2 + 72, "累计声望: " .. TS.getReputation(), nil)

    nvgFontSize(ctx, 18)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 180))
    nvgText(ctx, w/2, h/2 + 110, "点击继续", nil)
end

-- ============================================================================
-- 悬赏金箱绘制
-- ============================================================================
function M.drawBountyChests()
    for _, c in ipairs(GS.bountyChests) do
        if not c.alive then goto continue end
        if not Utils.isOnScreen(c.x, c.y, 40) then goto continue end

        local sx, sy = Utils.worldToScreen(c.x, c.y)

        -- 金色光环（吸引范围脉冲）
        local pulse = 0.5 + math.sin(GS.gameTime * 2) * 0.5
        local glow = nvgRadialGradient(ctx, sx, sy, 10, 50,
            nvgRGBA(255, 215, 0, math.floor(50 * pulse)),
            nvgRGBA(255, 215, 0, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, 50)
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)

        -- 金箱主体（比普通宝箱更华丽）
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, sx - 12, sy - 9, 24, 18, 3)
        nvgFillColor(ctx, nvgRGBA(255, 200, 0, 255))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(200, 150, 0, 255))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 金币标记
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(139, 69, 0, 255))
        nvgText(ctx, sx, sy, "$", nil)

        -- 剩余时间指示（底部弧形倒计时）
        local lifeRatio = c.lifetime / CONFIG.Skills.bounty.lifetime
        if lifeRatio < 1.0 then
            nvgBeginPath(ctx)
            nvgArc(ctx, sx, sy, 16, -math.pi/2, -math.pi/2 + math.pi*2*lifeRatio, 1)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 100, 150))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)
        end

        ::continue::
    end
end

-- ============================================================================
-- 技能视觉特效（屏幕空间）
-- ============================================================================
function M.drawSkillEffects(w, h)
    -- 1) 冲锋拖尾效果
    local dashState = GS.skillStates.dash
    if dashState and dashState.timer < dashState.duration then
        local t = dashState.timer / dashState.duration
        local trailSX, trailSY = Utils.worldToScreen(
            Utils.lerp(dashState.startX, dashState.endX, t),
            Utils.lerp(dashState.startY, dashState.endY, t))
        local startSX, startSY = Utils.worldToScreen(dashState.startX, dashState.startY)
        -- 蓝色拖尾线
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, startSX, startSY)
        nvgLineTo(ctx, trailSX, trailSY)
        nvgStrokeColor(ctx, nvgRGBA(80, 160, 255, math.floor(200 * (1 - t))))
        nvgStrokeWidth(ctx, 4)
        nvgStroke(ctx)
    end

    -- 2) 箭雨特效
    local arrowRainState = SkillSystem.getArrowRainState()
    if arrowRainState then
        local arSX, arSY = Utils.worldToScreen(arrowRainState.x, arrowRainState.y)
        local cfg = CONFIG.Skills.arrowRain
        local arRadius = cfg.radius
        local progress = arrowRainState.timer / arrowRainState.maxTimer
        local pulse = 0.8 + math.sin(GS.gameTime * 6) * 0.2

        nvgBeginPath(ctx)
        nvgCircle(ctx, arSX, arSY, arRadius * pulse)
        nvgFillColor(ctx, nvgRGBA(255, 60, 60, 40))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, arSX, arSY, arRadius * pulse)
        nvgStrokeColor(ctx, nvgRGBA(255, 80, 80, 120))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        if arrowRainState.arrows then
            for _, ar in ipairs(arrowRainState.arrows) do
                if ar.life > 0 then
                    local asx, asy = Utils.worldToScreen(ar.x, ar.y)
                    local arAlpha = math.floor((ar.life / ar.maxLife) * 200)
                    nvgBeginPath(ctx)
                    nvgMoveTo(ctx, asx, asy - 12)
                    nvgLineTo(ctx, asx - 2, asy)
                    nvgLineTo(ctx, asx + 2, asy)
                    nvgClosePath(ctx)
                    nvgFillColor(ctx, nvgRGBA(255, 100, 80, arAlpha))
                    nvgFill(ctx)
                end
            end
        end

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(255, 120, 80, 200))
        nvgText(ctx, arSX, arSY - arRadius - 4, string.format("箭雨 %.1fs", arrowRainState.timer), nil)
    end

    -- 6) 冲锋随从加速指示（领主脚下蓝色光圈）
    if dashState and dashState.followerSpeedTimer > 0 and dashState.timer >= dashState.duration then
        local lord = GS.lords[1]
        if lord and lord.alive then
            local dSX, dSY = Utils.worldToScreen(lord.x, lord.y)
            local dAlpha = math.floor(60 * (dashState.followerSpeedTimer / CONFIG.Skills.dash.followerSpeedDur))
            nvgBeginPath(ctx)
            nvgCircle(ctx, dSX, dSY, 40)
            nvgFillColor(ctx, nvgRGBA(80, 160, 255, dAlpha))
            nvgFill(ctx)
        end
    end
end

-- ============================================================================
-- 巨兽危险区
-- ============================================================================
function M.drawGiantBeasts()
    for _, beast in ipairs(GS.giantBeasts) do
        if beast.alive then
            if not Utils.isOnScreen(beast.x, beast.y, CONFIG.BeastAggroRadius) then
                goto continueBeast
            end
            local sx, sy = Utils.worldToScreen(beast.x, beast.y)
            local bc = CONFIG.BeastColor

            -- 1) 危险区域指示圈（淡红色脉冲）
            local dangerPulse = 0.6 + math.sin(GS.gameTime * 2 + beast.breathPhase) * 0.15
            local dangerAlpha = math.floor(25 * dangerPulse)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, CONFIG.BeastAggroRadius)
            nvgFillColor(ctx, nvgRGBA(200, 60, 40, dangerAlpha))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, CONFIG.BeastAggroRadius)
            nvgStrokeColor(ctx, nvgRGBA(200, 60, 40, dangerAlpha + 20))
            nvgStrokeWidth(ctx, 1)
            nvgStroke(ctx)

            -- 2) 巨兽阴影
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy + CONFIG.BeastBodyRadius * 0.5, CONFIG.BeastBodyRadius * 1.2, CONFIG.BeastBodyRadius * 0.3)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 50))
            nvgFill(ctx)

            -- 3) 巨兽身体（大型深色圆形 + 呼吸动画）
            local breathVal = math.sin(beast.breathPhase + GS.gameTime * 1.5)
            local bScaleX = 1.0 + 0.03 * breathVal
            local bScaleY = 1.0 - 0.04 * breathVal

            nvgSave(ctx)
            nvgTranslate(ctx, sx, sy)
            nvgScale(ctx, bScaleX, bScaleY)

            -- 外圈光晕
            local glowGrad = nvgRadialGradient(ctx, 0, 0, CONFIG.BeastBodyRadius * 0.8, CONFIG.BeastBodyRadius * 1.5,
                nvgRGBA(bc[1], bc[2], bc[3], 30),
                nvgRGBA(bc[1], bc[2], bc[3], 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, 0, 0, CONFIG.BeastBodyRadius * 1.5)
            nvgFillPaint(ctx, glowGrad)
            nvgFill(ctx)

            -- 深色外环
            nvgBeginPath(ctx)
            nvgCircle(ctx, 0, 0, CONFIG.BeastBodyRadius + 3)
            nvgFillColor(ctx, nvgRGBA(60, 30, 20, 220))
            nvgFill(ctx)

            -- 主体
            nvgBeginPath(ctx)
            nvgCircle(ctx, 0, 0, CONFIG.BeastBodyRadius)
            nvgFillColor(ctx, nvgRGBA(bc[1], bc[2], bc[3], 255))
            nvgFill(ctx)

            -- 高光
            local hl = nvgRadialGradient(ctx, -CONFIG.BeastBodyRadius * 0.2, -CONFIG.BeastBodyRadius * 0.2,
                CONFIG.BeastBodyRadius * 0.1, CONFIG.BeastBodyRadius * 0.5,
                nvgRGBA(255, 255, 255, 35),
                nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, 0, 0, CONFIG.BeastBodyRadius)
            nvgFillPaint(ctx, hl)
            nvgFill(ctx)

            -- 眼睛（两只红色小点）
            local eyeR = CONFIG.BeastBodyRadius * 0.12
            local eyeOffX = CONFIG.BeastBodyRadius * 0.3
            local eyeOffY = -CONFIG.BeastBodyRadius * 0.15
            local eyeGlow = 180 + math.floor(math.sin(GS.gameTime * 3 + beast.breathPhase) * 75)
            nvgBeginPath(ctx)
            nvgCircle(ctx, -eyeOffX, eyeOffY, eyeR)
            nvgFillColor(ctx, nvgRGBA(255, 40, 20, eyeGlow))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, eyeOffX, eyeOffY, eyeR)
            nvgFillColor(ctx, nvgRGBA(255, 40, 20, eyeGlow))
            nvgFill(ctx)

            -- 4) 攻击动画闪光
            if beast.isAttacking and beast.attackAnimTimer and beast.attackAnimTimer > 0 then
                local atkProg = beast.attackAnimTimer / 0.5
                local atkAlpha = math.floor(180 * atkProg)
                local atkRadius = CONFIG.BeastAttackRadius * (1.0 - atkProg * 0.3)
                nvgBeginPath(ctx)
                nvgCircle(ctx, 0, 0, atkRadius)
                nvgStrokeColor(ctx, nvgRGBA(255, 80, 30, atkAlpha))
                nvgStrokeWidth(ctx, 3)
                nvgStroke(ctx)
                -- 内部闪光
                nvgBeginPath(ctx)
                nvgCircle(ctx, 0, 0, atkRadius * 0.6)
                nvgFillColor(ctx, nvgRGBA(255, 100, 40, math.floor(atkAlpha * 0.3)))
                nvgFill(ctx)
            end

            nvgRestore(ctx)

            -- 5) HP条
            if beast.hp < beast.maxHp then
                local barW = CONFIG.BeastBodyRadius * 2
                local barH = 4
                local barY = sy - CONFIG.BeastBodyRadius - 10
                local ratio = beast.hp / beast.maxHp
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, sx - barW/2, barY, barW, barH, 2)
                nvgFillColor(ctx, nvgRGBA(0, 0, 0, 160))
                nvgFill(ctx)
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, sx - barW/2, barY, barW * ratio, barH, 2)
                nvgFillColor(ctx, nvgRGBA(200, 60, 30, 220))
                nvgFill(ctx)
            end

            -- 6) "危" 文字标识
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 14)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 200, 150, 200))
            nvgText(ctx, sx, sy + CONFIG.BeastBodyRadius + 14, "危", nil)

            ::continueBeast::
        end
    end
end

return M
