-- ============================================================================
-- CodexUI.lua — 图鉴界面（角色Tab + BossTab，无阵法Tab）
-- ============================================================================

local UI = require("urhox-libs/UI")
local T  = require("MenuTheme")
local CodexData  = require("CodexData")
local CodexState = require("CodexState")

local M = {}

local pageRoot = nil
local activeTab = "units"   -- "units" | "bosses"
local contentRef = nil      -- 中间内容区引用

-- ============================================================================
-- 颜色主题
-- ============================================================================
local C = {
    bg         = {18, 22, 40, 248},
    panel      = {32, 38, 60, 255},
    card       = {42, 50, 75, 255},
    cardHover  = {55, 65, 95, 255},
    border     = {70, 85, 120, 100},
    title      = {255, 255, 255, 255},
    body       = {200, 210, 230, 255},
    dim        = {130, 145, 170, 255},
    accent     = {80, 160, 255, 255},
    success    = {70, 200, 130, 255},
    gold       = {255, 210, 60,  255},
    locked     = {80, 85, 110, 200},
    lockedText = {100, 110, 140, 200},
}

-- ============================================================================
-- 角色卡片
-- ============================================================================
local function buildUnitCard(entry)
    local unlocked = CodexState.isUnlocked(entry.id)
    local rc = entry.color
    local stats = entry.stats

    local colorPanel = UI.Panel {
        width = 48, height = 48, borderRadius = 24,
        backgroundColor = unlocked
            and {rc[1], rc[2], rc[3], 220}
            or  {60, 65, 90, 200},
        borderWidth = 2,
        borderColor = unlocked
            and {rc[1], rc[2], rc[3], 180}
            or  {70, 80, 110, 150},
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label {
                text = unlocked and string.sub(entry.name, 1, 2) or "?",
                fontSize = 14, fontWeight = "bold",
                fontColor = unlocked and {255,255,255,255} or C.lockedText,
                textAlign = "center",
            },
        },
    }

    local nameLabel = UI.Label {
        text = unlocked and entry.name or "???",
        fontSize = 15, fontWeight = "bold",
        fontColor = unlocked and C.title or C.lockedText,
    }

    local roleLabel = UI.Label {
        text = unlocked and entry.role or "未解锁",
        fontSize = 11,
        fontColor = unlocked and {rc[1], rc[2], rc[3], 200} or C.lockedText,
        marginBottom = 4,
    }

    local descLabel = UI.Label {
        text = unlocked and entry.desc or "与该兵种的首次遭遇后解锁。",
        fontSize = 11, fontColor = unlocked and C.body or C.lockedText,
        flexShrink = 1,
    }

    local statsRow
    if unlocked and stats then
        statsRow = UI.Panel {
            flexDirection = "row", gap = 12, marginTop = 6,
            children = {
                UI.Label { text = "HP " .. stats.hp,  fontSize = 11, fontColor = {255, 120, 100, 220} },
                UI.Label { text = "ATK " .. stats.atk, fontSize = 11, fontColor = {255, 200, 80,  220} },
                stats.atkInterval < 90 and
                UI.Label { text = "速度 " .. string.format("%.1f/s", 1/stats.atkInterval), fontSize = 11, fontColor = {100, 200, 255, 220} }
                or
                UI.Label { text = "不攻击", fontSize = 11, fontColor = C.dim },
            },
        }
    end

    local tipsRow
    if unlocked and entry.tips then
        tipsRow = UI.Panel {
            marginTop = 6,
            paddingLeft = 8, paddingTop = 4, paddingBottom = 4, paddingRight = 8,
            borderRadius = 6,
            backgroundColor = {rc[1], rc[2], rc[3], 20},
            borderWidth = 1, borderColor = {rc[1], rc[2], rc[3], 60},
            children = {
                UI.Label {
                    text = "💡 " .. entry.tips,
                    fontSize = 10, fontColor = {rc[1]+40, rc[2]+40, rc[3]+40, 200},
                    flexShrink = 1,
                },
            },
        }
    end

    local cardChildren = { colorPanel, UI.Panel {
        flexGrow = 1, flexShrink = 1, gap = 0,
        children = {
            nameLabel, roleLabel, descLabel,
            statsRow or UI.Panel {},
            tipsRow  or UI.Panel {},
        },
    }}

    return UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "flex-start", gap = 12,
        padding = 14, borderRadius = 12,
        backgroundColor = unlocked and C.card or C.locked,
        borderWidth = 1,
        borderColor = unlocked
            and {rc[1], rc[2], rc[3], 60}
            or  C.border,
        marginBottom = 8,
        children = cardChildren,
    }
end

-- ============================================================================
-- Boss卡片
-- ============================================================================
local function buildBossCard(entry)
    local unlocked = CodexState.isUnlocked(entry.id)
    local rc = entry.color

    return UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "flex-start", gap = 12,
        padding = 14, borderRadius = 12,
        backgroundColor = unlocked and C.card or C.locked,
        borderWidth = 1,
        borderColor = unlocked and {rc[1], rc[2], rc[3], 80} or C.border,
        marginBottom = 8,
        children = {
            -- 图标
            UI.Panel {
                width = 48, height = 48, borderRadius = 8,
                backgroundColor = unlocked and {rc[1], rc[2], rc[3], 180} or {55, 60, 85, 200},
                borderWidth = 2,
                borderColor = unlocked and {rc[1], rc[2], rc[3], 150} or C.border,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = unlocked and "👾" or "?",
                        fontSize = unlocked and 20 or 16,
                        fontColor = unlocked and {255,255,255,255} or C.lockedText,
                        textAlign = "center",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 3,
                children = {
                    UI.Label {
                        text = unlocked and entry.name or "???",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = unlocked and C.title or C.lockedText,
                    },
                    UI.Label {
                        text = unlocked and entry.type or "未遭遇",
                        fontSize = 11,
                        fontColor = unlocked and {rc[1], rc[2], rc[3], 200} or C.lockedText,
                    },
                    UI.Label {
                        text = unlocked and entry.desc or "在野外遭遇此Boss后解锁。",
                        fontSize = 11, fontColor = unlocked and C.body or C.lockedText,
                        flexShrink = 1,
                        marginTop = 2,
                    },
                    unlocked and UI.Panel {
                        marginTop = 4,
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { text = "掉落：", fontSize = 10, fontColor = C.gold },
                            UI.Label { text = entry.loot, fontSize = 10, fontColor = C.body },
                        },
                    } or UI.Panel {},
                    unlocked and entry.tips and UI.Panel {
                        marginTop = 4,
                        paddingLeft = 8, paddingTop = 3, paddingBottom = 3, paddingRight = 8,
                        borderRadius = 6,
                        backgroundColor = {rc[1], rc[2], rc[3], 18},
                        borderWidth = 1, borderColor = {rc[1], rc[2], rc[3], 50},
                        children = {
                            UI.Label {
                                text = "💡 " .. entry.tips,
                                fontSize = 10,
                                fontColor = {rc[1]+40, rc[2]+40, rc[3]+40, 200},
                                flexShrink = 1,
                            },
                        },
                    } or UI.Panel {},
                },
            },
        },
    }
end

-- ============================================================================
-- 内容区构建
-- ============================================================================
local function buildContent()
    local cards = {}

    if activeTab == "units" then
        for _, entry in ipairs(CodexData.Units) do
            cards[#cards + 1] = buildUnitCard(entry)
        end
    else
        for _, entry in ipairs(CodexData.Bosses) do
            cards[#cards + 1] = buildBossCard(entry)
        end
    end

    return UI.Panel {
        width = "100%", gap = 0,
        children = cards,
    }
end

-- ============================================================================
-- 刷新内容区
-- ============================================================================
local function refreshContent()
    if not contentRef then return end
    contentRef:RemoveAllChildren()
    contentRef:AddChild(buildContent())
end

-- ============================================================================
-- Tab按钮
-- ============================================================================
local tabRefs = {}

local function buildTabBar()
    local function tab(id, label, icon)
        local isActive = activeTab == id
        local btn = UI.Panel {
            paddingLeft = 16, paddingRight = 16, paddingTop = 8, paddingBottom = 8,
            borderRadius = 20,
            backgroundColor = isActive and {70, 140, 255, 50} or {0, 0, 0, 0},
            borderWidth = isActive and 1 or 0,
            borderColor = {70, 140, 255, 120},
            flexDirection = "row", alignItems = "center", gap = 6,
            cursor = "pointer",
            onClick = function()
                if activeTab ~= id then
                    activeTab = id
                    refreshContent()
                    -- 更新tab样式
                    for tid, ref in pairs(tabRefs) do
                        local active = (tid == id)
                        ref:SetStyle({
                            backgroundColor = active and {70, 140, 255, 50} or {0, 0, 0, 0},
                            borderWidth = active and 1 or 0,
                        })
                    end
                end
            end,
            children = {
                UI.Label { text = icon, fontSize = 14 },
                UI.Label {
                    text = label, fontSize = 13,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and C.accent or C.dim,
                },
            },
        }
        tabRefs[id] = btn
        return btn
    end

    return UI.Panel {
        flexDirection = "row", gap = 6,
        alignItems = "center",
        paddingLeft = 16, paddingTop = 8, paddingBottom = 8,
        borderBottomWidth = 1, borderColor = C.border,
        children = {
            tab("units",  "角色", "⚔️"),
            tab("bosses", "Boss", "💀"),
        },
    }
end

-- ============================================================================
-- 主入口
-- ============================================================================
function M.show()
    if pageRoot then return end
    activeTab = "units"
    tabRefs = {}

    -- 统计解锁数
    local unitTotal  = #CodexData.Units
    local bossTotal  = #CodexData.Bosses
    local unitUnlocked, bossUnlocked = 0, 0
    for _, e in ipairs(CodexData.Units)  do if CodexState.isUnlocked(e.id) then unitUnlocked = unitUnlocked + 1 end end
    for _, e in ipairs(CodexData.Bosses) do if CodexState.isUnlocked(e.id) then bossUnlocked = bossUnlocked + 1 end end

    contentRef = UI.ScrollView {
        width = "100%", flexGrow = 1,
        paddingLeft = 14, paddingRight = 14, paddingTop = 10, paddingBottom = 20,
    }
    contentRef:AddChild(buildContent())

    pageRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = C.bg,
        children = {
            -- 顶栏
            UI.Panel {
                width = "100%", height = 50,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 14, paddingRight = 14,
                borderBottomWidth = 1, borderColor = C.border,
                backgroundColor = {25, 30, 50, 255},
                children = {
                    UI.Button {
                        text = "←",
                        fontSize = 18,
                        width = 36, height = 36,
                        borderRadius = 18,
                        backgroundColor = {255, 255, 255, 10},
                        textColor = C.body,
                        onClick = function() M.hide() end,
                    },
                    UI.Label {
                        text = "图  鉴",
                        fontSize = 18, fontWeight = "bold",
                        fontColor = C.title,
                        marginLeft = 10, flexGrow = 1,
                        letterSpacing = 4,
                    },
                    UI.Label {
                        text = unitUnlocked .. "/" .. unitTotal .. " 角色  " ..
                               bossUnlocked .. "/" .. bossTotal .. " Boss",
                        fontSize = 11, fontColor = C.dim,
                    },
                },
            },
            -- Tab栏
            buildTabBar(),
            -- 内容滚动区
            contentRef,
        },
    }

    UI.SetRoot(pageRoot)
    print("[CodexUI] Shown")
end

function M.hide()
    if pageRoot then
        pageRoot:Destroy()
        pageRoot = nil
        contentRef = nil
        tabRefs = {}
    end
    local MainMenuUI = require("MainMenuUI")
    MainMenuUI.show()
    print("[CodexUI] Hidden")
end

return M
