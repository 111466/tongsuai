-- scripts/MainMenuUI.lua
-- 主菜单界面：背景预览 + 顶栏 + 标题 + 模式选择 + CTA + 阵型入口
local UI = require("urhox-libs/UI")
local GS = require("GameState")
local TS = require("TalentSystem")
local CampaignState = require("CampaignState")
local EndlessMode = require("EndlessMode")
local Renderer = require("Renderer")
local T = require("MenuTheme")

local M = {}

-- 背景预览用的装饰数据
local previewEntities = {}

-- UI 引用
local menuRoot = nil
local modeInfoLabel1 = nil
local modeInfoLabel2 = nil
local modeInfoLabel3 = nil

------------------------------------------------------------
-- 背景预览
------------------------------------------------------------

local function initPreviewEntities()
    previewEntities = {
        resources = {},
        followers = {},
    }
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
    local types = {"peasant", "soldier", "archer", "healer"}
    for i = 1, 5 do
        table.insert(previewEntities.followers, {
            id = -i,  -- 负数唯一ID，避免动画状态表用nil键导致共享
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
            targetX = 0, targetY = 0,
            speed = 30,
        })
    end
    for _, f in ipairs(previewEntities.followers) do
        f.targetX = f.x + math.random(-200, 200)
        f.targetY = f.y + math.random(-200, 200)
    end
end

function M.updatePreview(dt)
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
    GS.cameraX = 1000
    GS.cameraY = 1000

    -- 先铺一层纯色底，防止底层 3D 场景透出导致闪烁
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, w, h)
    nvgFillColor(nvg, nvgRGBA(30, 40, 20, 255))
    nvgFill(nvg)

    Renderer.drawBackground(w, h)

    local origResources = GS.resources
    GS.resources = previewEntities.resources
    Renderer.drawResources()
    GS.resources = origResources

    for _, f in ipairs(previewEntities.followers) do
        Renderer.drawFollower(f)
    end
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

------------------------------------------------------------
-- 模式图标（文字简化版）
------------------------------------------------------------
local MODE_ICONS = {
    skirmish = { icon = "X", color = {255, 90, 70} },
    campaign = { icon = "C", color = {120, 120, 120} },
    endless  = { icon = "E", color = {120, 120, 120} },
}

------------------------------------------------------------
-- 构建 UI
------------------------------------------------------------

local toastPanel = nil
local toastLabel = nil

local function showToast(message)
    if not toastLabel or not toastPanel then return end
    toastLabel:SetText(message)
    toastPanel:SetVisible(true)
    toastPanel:SetStyle({ opacity = 1 })
    toastPanel:Animate({
        keyframes = {
            [0] = { opacity = 1 },
            [1] = { opacity = 0 },
        },
        duration = 1.0,
        delay = 0.8,
        easing = "easeOut",
        onComplete = function()
            if toastPanel then
                toastPanel:SetVisible(false)
                toastPanel:SetStyle({ opacity = 1 })
            end
        end,
    })
end

function M.show()
    if menuRoot then return end

    initPreviewEntities()

    -- 顶栏
    local rep = TS.getReputation()
    local level = math.floor(rep / 100) + 1

    local topBar = UI.Panel {
        position = "fixed", top = 0, left = 0, right = 0,
        height = 50,
        backgroundGradient = {
            type = "linear", direction = "to-bottom",
            from = {0, 0, 0, 120}, to = {0, 0, 0, 0},
        },
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14, paddingRight = 14,
        children = {
            -- 等级头像
            UI.Panel {
                width = 38, height = 38,
                borderRadius = 19,
                backgroundColor = T.colors.primary,
                borderWidth = 2, borderColor = {100, 180, 255, 150},
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label { text = tostring(level), fontSize = 15, fontWeight = "bold", fontColor = T.colors.textOnDark, textAlign = "center" },
                }
            },
            UI.Panel {
                marginLeft = 10, flexGrow = 1,
                children = {
                    UI.Label { text = "统帅 Lv." .. level, fontSize = 14, fontWeight = "bold", fontColor = T.colors.textOnDark },
                    UI.Label { text = "声望 " .. rep, fontSize = 11, fontColor = T.colors.gold },
                }
            },
            -- 招募按钮
            UI.Panel {
                width = 36, height = 36, borderRadius = 18,
                backgroundColor = {70, 200, 120, 40},
                borderWidth = 1, borderColor = {70, 200, 120, 100},
                justifyContent = "center", alignItems = "center",
                cursor = "pointer",
                children = {
                    UI.Label { text = "+", fontSize = 20, fontColor = {70, 200, 120, 255}, textAlign = "center" },
                },
            },
            -- 设置按钮
            UI.Button {
                text = "设置",
                fontSize = 12,
                marginLeft = 10,
                width = 50, height = 32,
                borderRadius = 8,
                backgroundColor = {255, 255, 255, 15},
                textColor = {255, 255, 255, 180},
                onClick = function(self)
                    M.hide()
                    local SettingsUI = require("SettingsUI")
                    SettingsUI.show()
                end,
            },
        }
    }

    -- 游戏标题
    local titleLabel = UI.Label {
        text = "代号：统帅",
        fontSize = 32, fontWeight = "bold",
        fontColor = T.colors.textOnDark,
        textStroke = { width = 3, color = {0, 0, 0, 120} },
        textAlign = "center",
    }
    local titlePanel = UI.Panel {
        position = "absolute",
        top = "20%", left = 0, right = 0,
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            titleLabel,
            UI.Label {
                text = "- 征服四方 -",
                fontSize = 13,
                fontColor = {255, 255, 255, 120},
                textAlign = "center",
                marginTop = 6,
                letterSpacing = 4,
            },
        }
    }
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

    -- 左侧功能栏
    local function sideBtn(label, iconText, iconColor, onClick)
        return UI.Panel {
            width = 52, height = 52,
            borderRadius = 12,
            backgroundColor = {0, 0, 0, 50},
            borderWidth = 1, borderColor = {255, 255, 255, 20},
            justifyContent = "center", alignItems = "center",
            gap = 2,
            cursor = "pointer",
            onClick = onClick,
            children = {
                UI.Label { text = iconText, fontSize = 16, fontColor = iconColor },
                UI.Label { text = label, fontSize = 10, fontColor = {255, 255, 255, 160} },
            },
        }
    end

    local sideBar = UI.Panel {
        position = "absolute",
        left = 8, top = "35%",
        gap = 6,
        pointerEvents = "box-none",
        children = {
            sideBtn("天赋", "T", {255, 210, 60, 255}, function()
                M.hide()
                local TalentUI = require("TalentUI")
                TalentUI.show()
            end),

            sideBtn("图鉴", "B", {100, 200, 255, 255}, function()
                M.hide()
                local CodexUI = require("CodexUI")
                CodexUI.show()
            end),
        },
    }

    -- ========== 底部操作区 ==========

    -- 模式选项卡
    local modeTabs = UI.Tabs {
        tabs = {
            { id = "skirmish", label = "遭遇战" },
            { id = "campaign", label = "战役（未解锁）", disabled = true },
            { id = "endless",  label = "无尽（未解锁）", disabled = true },
        },
        activeTab = GS.gameMode,
        variant = "pills",
        orientation = "horizontal",
        width = "80%",
        height = 38,
        tabGap = 6,
        alignSelf = "center",
        onChange = function(self, tabId, tab)
            if tabId == "campaign" or tabId == "endless" then
                GS.gameMode = "skirmish"
                updateModeInfoCard()
                showToast("即将开放")
                return
            end
            GS.gameMode = tabId
            updateModeInfoCard()
        end,
    }

    -- 模式信息卡 — 暗色半透明风格
    local l1, l2, l3 = getModeInfo(GS.gameMode)
    modeInfoLabel1 = UI.Label { text = l1, fontSize = 13, fontWeight = "bold", fontColor = {255, 255, 255, 220} }
    modeInfoLabel2 = UI.Label { text = l2, fontSize = 13, fontColor = {255, 255, 255, 180} }
    modeInfoLabel3 = UI.Label { text = l3, fontSize = 11, fontColor = {255, 255, 255, 100}, marginTop = 4 }

    local infoCard = UI.Panel {
        width = "80%",
        backgroundColor = {0, 0, 0, 40},
        borderRadius = 12,
        borderWidth = 1, borderColor = {255, 255, 255, 15},
        paddingLeft = 16, paddingRight = 16, paddingTop = 10, paddingBottom = 10,
        alignSelf = "center",
        marginTop = 8,
        flexDirection = "row", alignItems = "center",
        children = {
            -- 左侧信息
            UI.Panel {
                flexGrow = 1, gap = 2,
                children = {
                    modeInfoLabel1,
                    modeInfoLabel2,
                    modeInfoLabel3,
                }
            },
        }
    }

    -- CTA 按钮
    local ctaButton = UI.Button {
        text = "开始游戏",
        fontSize = 18, fontWeight = "bold",
        width = "70%", height = 50,
        alignSelf = "center",
        marginTop = 12,
        borderRadius = 25,
        backgroundGradient = {
            type = "linear", direction = "to-bottom",
            from = {255, 160, 40, 255}, to = {240, 120, 10, 255},
        },
        textColor = {255, 255, 255, 255},
        textStroke = { width = 1, color = {180, 80, 0, 120} },
        boxShadow = {{ x=0, y=4, blur=16, spread=0, color={255, 140, 30, 80} }},
        transition = "scale 0.15s easeOut",
        onClick = function(self)
            M.onStartGame()
        end,
    }

    -- 底部容器
    local bottomArea = UI.Panel {
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        alignItems = "center",
        paddingTop = 8, paddingBottom = 12,
        pointerEvents = "box-none",
        backgroundGradient = {
            type = "linear", direction = "to-top",
            from = {15, 20, 35, 200}, to = {15, 20, 35, 0},
        },
        children = {
            modeTabs,
            infoCard,
            ctaButton,
        }
    }

    -- 组装根节点
    toastPanel = UI.Panel {
        id = "toastPanel",
        position = "absolute",
        top = "40%",
        left = 0, right = 0,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "none",
        visible = false,
        children = {
            UI.Panel {
                backgroundColor = {0, 0, 0, 200},
                borderRadius = 10,
                paddingLeft = 24, paddingRight = 24,
                paddingTop = 12, paddingBottom = 12,
                children = {
                    toastLabel = UI.Label {
                        id = "toastLabel",
                        text = "",
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = {255, 220, 100, 255},
                        textAlign = "center",
                    },
                },
            },
        },
    }

    menuRoot = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            topBar,
            titlePanel,
            sideBar,
            bottomArea,
            toastPanel,
        }
    }

    UI.SetRoot(menuRoot)

    -- 进场动画：底部区域从下方滑入
    bottomArea:Animate({
        keyframes = {
            [0] = { opacity = 0, translateY = 40 },
            [1] = { opacity = 1, translateY = 0 },
        },
        duration = 0.45,
        easing = "easeOut",
    })
    -- 标题淡入
    titlePanel:Animate({
        keyframes = {
            [0] = { opacity = 0, translateY = -15 },
            [1] = { opacity = 1, translateY = 0 },
        },
        duration = 0.5,
        easing = "easeOut",
    })
    -- 侧栏滑入
    sideBar:Animate({
        keyframes = {
            [0] = { opacity = 0, translateX = -20 },
            [1] = { opacity = 1, translateX = 0 },
        },
        duration = 0.4,
        delay = 0.15,
        easing = "easeOut",
    })

    print("[MainMenuUI] Shown")
end

function M.hide()
    if menuRoot then
        menuRoot:Destroy()
        menuRoot = nil
        modeInfoLabel1 = nil
        modeInfoLabel2 = nil
        modeInfoLabel3 = nil
        toastPanel = nil
        toastLabel = nil
    end
    print("[MainMenuUI] Hidden")
end

------------------------------------------------------------
-- 开始游戏逻辑
------------------------------------------------------------

function M.onStartGame()
    if GS.gameMode == "campaign" or GS.gameMode == "endless" then
        showToast("即将开放")
        return
    end
    local GameUI = require("GameUI")
    if GS.gameMode == "skirmish" then
        M.hide()
        if M.initGameFn then M.initGameFn("skirmish") end
        GameUI.CreateGameUI()
    end
end

return M
