-- ============================================================================
-- TalentUI.lua — 全屏天赋树界面（三路线 × 5节点 + 声望系统）
-- ============================================================================

local UI = require("urhox-libs/UI")
local TS = require("TalentSystem")
local T = require("MenuTheme")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

local M = {}

local pageRoot = nil

-- ============================================================================
-- 暗色主题
-- ============================================================================

local C = {
    bg         = {25, 30, 50, 240},
    panelBg    = {40, 45, 65, 255},
    cardBg     = {55, 60, 80, 255},
    cardHover  = {70, 80, 110, 255},
    border     = {80, 90, 120, 120},
    textTitle  = {255, 255, 255, 255},
    textBody   = {200, 210, 230, 255},
    textDim    = {140, 150, 170, 255},
    locked     = {80, 85, 100, 255},
    unlocked   = {70, 200, 120, 255},
    available  = {70, 160, 255, 255},
    maxed      = {255, 210, 60, 255},
}

-- 三路线主题色
local PATH_COLORS = {
    commander = {70, 160, 255},   -- 蓝
    warfare   = {255, 90, 70},    -- 红
    economy   = {80, 200, 100},   -- 绿
}

local PATH_ICONS = {
    commander = "帅",
    warfare   = "战",
    economy   = "经",
}

local PATH_ORDER = { "commander", "warfare", "economy" }

-- ============================================================================
-- 构建界面
-- ============================================================================

--- 单个天赋节点
local function buildNode(pathId, index, node, currentLevel, reputation)
    local isUnlocked = index <= currentLevel
    local isNext     = index == currentLevel + 1
    local canAfford  = reputation >= node.cost
    local isAvailable = isNext and canAfford

    -- 状态颜色
    local bgColor, textColor, borderColor
    if isUnlocked then
        bgColor = {PATH_COLORS[pathId][1], PATH_COLORS[pathId][2], PATH_COLORS[pathId][3], 50}
        textColor = {PATH_COLORS[pathId][1], PATH_COLORS[pathId][2], PATH_COLORS[pathId][3], 255}
        borderColor = {PATH_COLORS[pathId][1], PATH_COLORS[pathId][2], PATH_COLORS[pathId][3], 160}
    elseif isAvailable then
        bgColor = {70, 160, 255, 25}
        textColor = C.available
        borderColor = C.available
    else
        bgColor = C.cardBg
        textColor = C.textDim
        borderColor = C.border
    end

    -- 状态标记
    local statusText, statusColor
    if isUnlocked then
        statusText = "已解锁"
        statusColor = C.unlocked
    elseif isNext then
        statusText = canAfford and ("解锁 (-" .. node.cost .. ")") or ("需要 " .. node.cost .. " 声望")
        statusColor = canAfford and C.available or C.textDim
    else
        statusText = "需前置 " .. node.cost .. " 声望"
        statusColor = C.textDim
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center", gap = 10,
        padding = 10, borderRadius = 10,
        backgroundColor = bgColor,
        borderWidth = 1,
        borderColor = borderColor,
        cursor = isAvailable and "pointer" or "default",
        onClick = isAvailable and function()
            local ok, err = TS.unlockNext(pathId)
            if ok then
                M._refresh()
                UI.Toast.Show(node.name .. " 已解锁!", { variant = "success", position = "top" })
            else
                UI.Toast.Show(err or "解锁失败", { variant = "error", position = "top" })
            end
        end or nil,
        children = {
            -- 序号圆
            UI.Panel {
                width = 32, height = 32, borderRadius = 16,
                backgroundColor = isUnlocked
                    and {PATH_COLORS[pathId][1], PATH_COLORS[pathId][2], PATH_COLORS[pathId][3], 180}
                    or {60, 65, 85, 255},
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(index),
                        fontSize = 14, fontWeight = "bold",
                        fontColor = isUnlocked and {255,255,255,255} or C.textDim,
                    },
                },
            },
            -- 文字区
            UI.Panel {
                flexShrink = 1, flexGrow = 1, gap = 2,
                children = {
                    UI.Label { text = node.name, fontSize = 13, fontWeight = "bold", fontColor = textColor },
                    UI.Label { text = node.desc, fontSize = 11, fontColor = C.textBody },
                },
            },
            -- 状态
            UI.Panel {
                paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
                backgroundColor = {statusColor[1], statusColor[2], statusColor[3], 30},
                borderRadius = 4,
                children = {
                    UI.Label { text = statusText, fontSize = 10, fontColor = statusColor },
                },
            },
        },
    }
end

--- 单条路线面板
local function buildPath(pathId)
    local pathConfig = CONFIG.TalentPaths[pathId]
    if not pathConfig then return UI.Panel {} end
    local currentLevel = TS.getPathLevel(pathId)
    local reputation = TS.getReputation()
    local pc = PATH_COLORS[pathId]
    local isMaxed = currentLevel >= #pathConfig.nodes

    -- 进度文字
    local progressText = currentLevel .. " / " .. #pathConfig.nodes
    local progressColor = isMaxed and C.maxed or C.textBody

    -- 节点列表
    local nodeChildren = {}
    for i, node in ipairs(pathConfig.nodes) do
        -- 连接线（节点间）
        if i > 1 then
            local lineColor = (i <= currentLevel)
                and {pc[1], pc[2], pc[3], 120}
                or {60, 65, 85, 255}
            table.insert(nodeChildren, UI.Panel {
                width = 2, height = 10, alignSelf = "center",
                backgroundColor = lineColor,
            })
        end
        table.insert(nodeChildren, buildNode(pathId, i, node, currentLevel, reputation))
    end

    return UI.Panel {
        width = "100%", maxWidth = 500,
        backgroundColor = C.panelBg,
        borderRadius = 12,
        paddingLeft = 12, paddingRight = 12, paddingTop = 12, paddingBottom = 14,
        gap = 4,
        children = {
            -- 路线头部
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8, marginBottom = 6,
                children = {
                    UI.Panel {
                        width = 36, height = 36, borderRadius = 18,
                        backgroundColor = {pc[1], pc[2], pc[3], 180},
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = PATH_ICONS[pathId], fontSize = 16, fontWeight = "bold", fontColor = {255,255,255,255} },
                        },
                    },
                    UI.Panel {
                        gap = 1, flexShrink = 1,
                        children = {
                            UI.Label { text = pathConfig.name, fontSize = 15, fontWeight = "bold", fontColor = {pc[1], pc[2], pc[3], 255} },
                            UI.Label { text = pathConfig.desc, fontSize = 11, fontColor = C.textDim },
                        },
                    },
                    UI.Panel { flexGrow = 1 },
                    -- 进度标记
                    UI.Panel {
                        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                        backgroundColor = isMaxed and {255, 210, 60, 30} or {pc[1], pc[2], pc[3], 25},
                        borderRadius = 6,
                        children = {
                            UI.Label {
                                text = isMaxed and "已满级" or progressText,
                                fontSize = 12, fontWeight = "bold",
                                fontColor = progressColor,
                            },
                        },
                    },
                },
            },
            -- 节点列表
            table.unpack(nodeChildren),
        },
    }
end

-- ============================================================================
-- show / hide / refresh
-- ============================================================================

function M._refresh()
    if not pageRoot then return end
    M.hide(true)  -- silent hide, don't go back to menu
    M.show()
end

function M.show()
    if pageRoot then return end

    local reputation = TS.getReputation()

    -- 三条路线面板
    local pathPanels = {}
    for _, pid in ipairs(PATH_ORDER) do
        table.insert(pathPanels, buildPath(pid))
    end

    pageRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = C.bg,
        children = {
            -- 顶栏
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                paddingLeft = 16, paddingRight = 16, paddingTop = 10, paddingBottom = 10,
                gap = 12,
                backgroundColor = {30, 35, 55, 255},
                children = {
                    UI.Button {
                        text = "< 返回",
                        fontSize = 13,
                        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
                        onClick = function() M.hide() end,
                    },
                    UI.Label { text = "天赋", fontSize = 18, fontWeight = "bold", fontColor = C.textTitle },
                    UI.Panel { flexGrow = 1 },
                    -- 声望显示
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
                        backgroundColor = {255, 210, 60, 25},
                        borderRadius = 8,
                        children = {
                            UI.Label { text = "声望", fontSize = 12, fontColor = C.maxed },
                            UI.Label { text = tostring(reputation), fontSize = 15, fontWeight = "bold", fontColor = C.maxed },
                        },
                    },
                    -- 重置按钮
                    UI.Button {
                        text = "重置天赋",
                        fontSize = 12,
                        variant = "ghost",
                        paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
                        textColor = {255, 120, 100, 255},
                        onClick = function()
                            local refund = TS.resetAll()
                            M._refresh()
                            UI.Toast.Show("天赋已重置，返还 " .. refund .. " 声望", { variant = "info", position = "top" })
                        end,
                    },
                },
            },

            -- 内容区：纵向滚动（移动端友好）
            UI.ScrollView {
                flexGrow = 1, width = "100%",
                paddingLeft = 12, paddingRight = 12, paddingTop = 10, paddingBottom = 24,
                contentContainerStyle = {
                    gap = 12,
                    alignItems = "center",
                },
                children = pathPanels,
            },
        },
    }

    UI.SetRoot(pageRoot)
    print("[TalentUI] Shown, rep=" .. reputation)
end

---@param silent? boolean  静默关闭（刷新用，不回主菜单）
function M.hide(silent)
    if pageRoot then
        pageRoot:Destroy()
        pageRoot = nil
    end
    if not silent then
        local MainMenuUI = require("MainMenuUI")
        MainMenuUI.show()
    end
    print("[TalentUI] Hidden")
end

return M
