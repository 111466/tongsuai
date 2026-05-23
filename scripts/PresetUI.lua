-- ============================================================================
-- PresetUI.lua — 全屏编队预设界面（5 个槽位 + 编辑器）
-- ============================================================================

local UI = require("urhox-libs/UI")
local PM = require("PresetManager")
local GS = require("GameState")
local T = require("MenuTheme")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

local M = {}

local pageRoot = nil
local selectedSlot = 1

-- 动态更新引用
local slotCardRefs = {}          -- slot → card panel 引用
local detailScrollRef = nil      -- 右侧详情 ScrollView 引用

-- 编辑器状态
local editing = false            -- 是否处于编辑模式
local editUnits = {}             -- { unitType = count, ... } 编辑中的兵种数量

-- ============================================================================
-- 暗色主题
-- ============================================================================

local C = {
    bg         = {25, 30, 50, 240},
    panelBg    = {40, 45, 65, 255},
    cardBg     = {55, 60, 80, 255},
    cardActive = {70, 140, 255, 60},
    border     = {80, 90, 120, 120},
    textTitle  = {255, 255, 255, 255},
    textBody   = {200, 210, 230, 255},
    textDim    = {140, 150, 170, 255},
    empty      = {80, 85, 100, 180},
    filled     = {70, 200, 120, 255},
    danger     = {255, 90, 70, 255},
    accent     = {70, 160, 255, 255},
    success    = {70, 200, 120, 255},
    warn       = {240, 180, 50, 255},
    editorBg   = {35, 40, 60, 255},
    rowHover   = {60, 70, 100, 255},
}

-- 兵种中文名速查
local UNIT_NAMES = {
    peasant  = "平民",
    soldier  = "士兵",
    archer   = "弓手",
    healer   = "治愈师",
}

-- 兵种显示顺序（按分类分组）
local UNIT_GROUPS = {
    { label = "采集", units = { "peasant" } },
    { label = "近战", units = { "soldier" } },
    { label = "远程", units = { "archer" } },
    { label = "辅助", units = { "healer" } },
}

-- 每种兵种最大数量
local UNIT_MAX = 10

-- ============================================================================
-- 辅助
-- ============================================================================

--- 格式化兵种组成文字
local function formatUnits(units)
    if not units or next(units) == nil then return "空编队" end
    local parts = {}
    for uid, count in pairs(units) do
        local name = UNIT_NAMES[uid] or uid
        table.insert(parts, name .. "×" .. count)
    end
    return table.concat(parts, "  ")
end

--- 计算编辑中兵种总数
local function getTotalUnits()
    local total = 0
    for _, count in pairs(editUnits) do
        total = total + count
    end
    return total
end

--- 深拷贝 units 表（浅层即可，只有 string→number）
local function copyUnits(src)
    local t = {}
    if src then
        for k, v in pairs(src) do t[k] = v end
    end
    return t
end

--- 进入编辑模式
local function enterEdit(preset)
    editing = true
    if preset then
        editUnits = copyUnits(preset.units)
    else
        editUnits = {}
    end
    M._refreshDetail()
end

--- 退出编辑模式
local function exitEdit()
    editing = false
    editUnits = {}
    M._refreshDetail()
end

-- ============================================================================
-- 选中态切换（不重建列表）
-- ============================================================================

local function selectSlot(newSlot)
    local oldSlot = selectedSlot
    selectedSlot = newSlot
    editing = false  -- 切换槽位时退出编辑
    -- 切换卡片样式
    if oldSlot and slotCardRefs[oldSlot] then
        slotCardRefs[oldSlot]:SetStyle({
            backgroundColor = C.cardBg,
            borderWidth = 0,
        })
    end
    if newSlot and slotCardRefs[newSlot] then
        slotCardRefs[newSlot]:SetStyle({
            backgroundColor = C.cardActive,
            borderWidth = 1,
            borderColor = C.accent,
        })
    end
    -- 只更新右侧详情
    M._refreshDetail()
end

--- 只刷新右侧详情
function M._refreshDetail()
    if not detailScrollRef then return end
    detailScrollRef:RemoveAllChildren()
    detailScrollRef:AddChild(buildDetail())
end

-- ============================================================================
-- 编辑器：兵种选择器
-- ============================================================================

local function buildUnitPicker()
    local groupPanels = {}

    for _, group in ipairs(UNIT_GROUPS) do
        local rows = {}
        for _, uid in ipairs(group.units) do
            local name = UNIT_NAMES[uid] or uid
            local count = editUnits[uid] or 0
            local ringColor = CONFIG.UnitRingColors[uid] or {200,200,200}
            local stats = CONFIG.UnitStats[uid]

            -- 数据行
            table.insert(rows, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                width = "100%",
                paddingLeft = 6, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
                borderRadius = 6,
                backgroundColor = count > 0 and {ringColor[1], ringColor[2], ringColor[3], 25} or {0,0,0,0},
                children = {
                    -- 兵种色标
                    UI.Panel {
                        width = 22, height = 22, borderRadius = 11,
                        backgroundColor = {ringColor[1], ringColor[2], ringColor[3], 200},
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label {
                                text = string.sub(name, 1, 3),
                                fontSize = 8, fontWeight = "bold",
                                fontColor = {255,255,255,255},
                            },
                        },
                    },
                    -- 名称+属性
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1, gap = 1,
                        children = {
                            UI.Label { text = name, fontSize = 12, fontWeight = "bold", fontColor = C.textTitle },
                            UI.Label {
                                text = stats and ("HP:" .. stats.hp .. " ATK:" .. stats.atk) or "",
                                fontSize = 9, fontColor = C.textDim,
                            },
                        },
                    },
                    -- - 按钮
                    UI.Button {
                        text = "-",
                        fontSize = 14, fontWeight = "bold",
                        width = 28, height = 28,
                        paddingLeft = 0, paddingRight = 0, paddingTop = 0, paddingBottom = 0,
                        borderRadius = 6,
                        backgroundColor = count > 0 and {255, 90, 70, 60} or {60, 65, 85, 255},
                        textColor = count > 0 and C.danger or C.textDim,
                        onClick = function()
                            if (editUnits[uid] or 0) > 0 then
                                editUnits[uid] = editUnits[uid] - 1
                                if editUnits[uid] <= 0 then editUnits[uid] = nil end
                                M._refreshDetail()
                            end
                        end,
                    },
                    -- 数量
                    UI.Label {
                        text = tostring(count),
                        fontSize = 14, fontWeight = "bold",
                        fontColor = count > 0 and C.textTitle or C.textDim,
                        width = 24, textAlign = "center",
                    },
                    -- + 按钮
                    UI.Button {
                        text = "+",
                        fontSize = 14, fontWeight = "bold",
                        width = 28, height = 28,
                        paddingLeft = 0, paddingRight = 0, paddingTop = 0, paddingBottom = 0,
                        borderRadius = 6,
                        backgroundColor = count < UNIT_MAX and {70, 200, 120, 60} or {60, 65, 85, 255},
                        textColor = count < UNIT_MAX and C.success or C.textDim,
                        onClick = function()
                            local cur = editUnits[uid] or 0
                            if cur < UNIT_MAX then
                                editUnits[uid] = cur + 1
                                M._refreshDetail()
                            end
                        end,
                    },
                },
            })
        end

        table.insert(groupPanels, UI.Panel {
            width = "100%", gap = 2,
            children = {
                -- 分组标签
                UI.Label {
                    text = group.label,
                    fontSize = 11, fontWeight = "bold",
                    fontColor = C.accent,
                    paddingLeft = 4, paddingBottom = 2,
                },
                table.unpack(rows),
            },
        })
    end

    return UI.Panel {
        width = "100%", gap = 8,
        children = {
            UI.Label { text = "兵种编成", fontSize = 14, fontWeight = "bold", fontColor = C.textTitle },
            UI.Label {
                text = "总计：" .. getTotalUnits() .. " 人",
                fontSize = 11, fontColor = C.textBody,
            },
            table.unpack(groupPanels),
        },
    }
end

-- ============================================================================
-- 构建界面
-- ============================================================================

--- 单个槽位卡片
local function buildSlotCard(slot, data, isActive)
    local hasData = data and data.hasData
    local name = hasData and data.name or "空槽位"
    local preset = PM.load(slot)

    -- 兵种文字
    local unitsText = ""
    if hasData and preset then
        unitsText = formatUnits(preset.units)
    end

    local statusColor = hasData and C.filled or C.empty

    local card = UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center", gap = 10,
        padding = 12, borderRadius = 10,
        backgroundColor = isActive and C.cardActive or C.cardBg,
        borderWidth = isActive and 1 or 0,
        borderColor = C.accent,
        cursor = "pointer",
        onClick = function()
            selectSlot(slot)
        end,
        children = {
            -- 槽位编号
            UI.Panel {
                width = 36, height = 36, borderRadius = 18,
                backgroundColor = hasData
                    and {statusColor[1], statusColor[2], statusColor[3], 180}
                    or {60, 65, 85, 255},
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(slot),
                        fontSize = 15, fontWeight = "bold",
                        fontColor = hasData and {255,255,255,255} or C.textDim,
                    },
                },
            },
            -- 信息区
            UI.Panel {
                flexShrink = 1, flexGrow = 1, gap = 2,
                children = {
                    UI.Label { text = name, fontSize = 14, fontWeight = "bold", fontColor = C.textTitle },
                    UI.Label {
                        text = hasData and unitsText or "尚未保存",
                        fontSize = 11, fontColor = C.textDim,
                        numberOfLines = 1,
                    },
                },
            },
            -- 状态指示
            UI.Panel {
                width = 8, height = 8, borderRadius = 4,
                backgroundColor = hasData and C.filled or C.empty,
            },
        },
    }
    slotCardRefs[slot] = card
    return card
end

--- 详情面板（右侧）
function buildDetail()
    local preset = PM.load(selectedSlot)
    local hasData = preset ~= nil

    -- ==================== 编辑模式 ====================
    if editing then
        local totalUnits = getTotalUnits()
        local hasUnits = totalUnits > 0
        local canSave = hasUnits  -- 至少要有1个兵种才能保存

        return UI.Panel {
            width = "100%", padding = 12, gap = 10,
            children = {
                -- 编辑器标题栏
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                    children = {
                        UI.Label {
                            text = hasData and ("编辑 - 槽位 " .. selectedSlot) or ("新建 - 槽位 " .. selectedSlot),
                            fontSize = 15, fontWeight = "bold", fontColor = C.textTitle,
                            flexGrow = 1,
                        },
                        UI.Button {
                            text = "取消",
                            fontSize = 12,
                            paddingLeft = 12, paddingRight = 12, paddingTop = 5, paddingBottom = 5,
                            onClick = function() exitEdit() end,
                        },
                    },
                },

                UI.Panel { width = "100%", height = 1, backgroundColor = C.border },

                -- 兵种选择器
                buildUnitPicker(),

                UI.Panel { width = "100%", height = 1, backgroundColor = C.border },

                -- 保存按钮区
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 10, alignItems = "center",
                    paddingTop = 4,
                    children = {
                        UI.Button {
                            text = "保存预设",
                            variant = "primary",
                            fontSize = 14, fontWeight = "bold",
                            paddingLeft = 24, paddingRight = 24, paddingTop = 10, paddingBottom = 10,
                            backgroundColor = canSave and nil or {60, 65, 85, 255},
                            onClick = function()
                                if not canSave then
                                    UI.Toast.Show("请至少添加1个兵种", { variant = "warning", position = "top" })
                                    return
                                end
                                M._saveFromEditor(selectedSlot)
                            end,
                        },
                        UI.Label {
                            text = canSave and (totalUnits .. "人编队") or "请配置兵种",
                            fontSize = 12,
                            fontColor = canSave and C.success or C.warn,
                        },
                    },
                },
            },
        }
    end

    -- ==================== 空槽位（非编辑模式） ====================
    if not hasData then
        return UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center", gap = 16,
            children = {
                UI.Label { text = "槽位 " .. selectedSlot .. " 为空", fontSize = 16, fontColor = C.textDim },
                UI.Label { text = "创建新的编队预设", fontSize = 12, fontColor = C.textDim },
                UI.Button {
                    text = "新建预设",
                    variant = "primary",
                    fontSize = 14,
                    paddingLeft = 24, paddingRight = 24, paddingTop = 10, paddingBottom = 10,
                    onClick = function()
                        enterEdit(nil)
                    end,
                },
            },
        }
    end

    -- ==================== 有数据：显示详情 ====================
    local unitRows = {}
    if preset.units then
        for uid, count in pairs(preset.units) do
            local name = UNIT_NAMES[uid] or uid
            local ringColor = CONFIG.UnitRingColors[uid] or {200,200,200}
            table.insert(unitRows, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                children = {
                    UI.Panel {
                        width = 24, height = 24, borderRadius = 12,
                        backgroundColor = {ringColor[1], ringColor[2], ringColor[3], 180},
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = string.sub(name, 1, 3), fontSize = 9, fontWeight = "bold", fontColor = {255,255,255,255} },
                        },
                    },
                    UI.Label { text = name, fontSize = 13, fontColor = C.textBody, flexGrow = 1 },
                    UI.Label { text = "×" .. count, fontSize = 14, fontWeight = "bold", fontColor = C.textTitle },
                },
            })
        end
    end

    return UI.Panel {
        width = "100%", padding = 16, gap = 12,
        children = {
            -- 标题
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 10,
                children = {
                    UI.Panel {
                        width = 44, height = 44, borderRadius = 22,
                        backgroundColor = {C.filled[1], C.filled[2], C.filled[3], 180},
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = tostring(selectedSlot), fontSize = 18, fontWeight = "bold", fontColor = {255,255,255,255} },
                        },
                    },
                    UI.Panel {
                        gap = 2, flexShrink = 1,
                        children = {
                            UI.Label { text = preset.name, fontSize = 17, fontWeight = "bold", fontColor = C.textTitle },
                        },
                    },
                },
            },

            UI.Panel { width = "100%", height = 1, backgroundColor = C.border },

            -- 兵种组成
            UI.Label { text = "兵种编成", fontSize = 13, fontWeight = "bold", fontColor = C.textTitle },
            (#unitRows > 0)
                and UI.Panel { width = "100%", gap = 4, children = unitRows }
                or UI.Label { text = "无兵种数据", fontSize = 12, fontColor = C.textDim },

            UI.Panel { width = "100%", height = 1, backgroundColor = C.border },

            -- 操作按钮
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 10, flexWrap = "wrap",
                children = {
                    UI.Button {
                        text = "加载此预设",
                        variant = "primary",
                        fontSize = 13,
                        paddingLeft = 16, paddingRight = 16, paddingTop = 8, paddingBottom = 8,
                        onClick = function()
                            M._loadPreset(selectedSlot)
                        end,
                    },
                    UI.Button {
                        text = "编辑",
                        fontSize = 13,
                        paddingLeft = 16, paddingRight = 16, paddingTop = 8, paddingBottom = 8,
                        onClick = function()
                            enterEdit(preset)
                        end,
                    },
                    UI.Button {
                        text = "删除",
                        fontSize = 13,
                        paddingLeft = 16, paddingRight = 16, paddingTop = 8, paddingBottom = 8,
                        textColor = C.danger,
                        backgroundColor = {255, 90, 70, 20},
                        onClick = function()
                            PM.delete(selectedSlot)
                            UI.Toast.Show("预设 " .. selectedSlot .. " 已删除", { variant = "info", position = "top" })
                            M._fullRefresh()
                        end,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 预设操作
-- ============================================================================

--- 从编辑器保存到指定槽位
function M._saveFromEditor(slot)
    -- 清理空兵种
    local cleanUnits = {}
    for uid, count in pairs(editUnits) do
        if count > 0 then cleanUnits[uid] = count end
    end

    local preset = {
        name = "预设 " .. slot,
        units = cleanUnits,
    }
    PM.save(slot, preset)
    editing = false
    editUnits = {}
    UI.Toast.Show("已保存到预设 " .. slot, { variant = "success", position = "top" })
    M._fullRefresh()
end

--- 保存当前菜单阵型到指定槽位（保留兼容）
function M._saveCurrent(slot)
    M._saveFromEditor(slot)
end

--- 加载预设到菜单
function M._loadPreset(slot)
    local preset = PM.load(slot)
    if not preset then return end

    if preset.formation then
        GS.menuFormationId = preset.formation
    end

    UI.Toast.Show("已加载预设：" .. preset.name, { variant = "success", position = "top" })
end

-- ============================================================================
-- show / hide / refresh
-- ============================================================================

--- 全量刷新（保存/删除后需要更新左侧槽位状态）
function M._fullRefresh()
    if not pageRoot then return end
    pageRoot:Destroy()
    pageRoot = nil
    M.show()
end

function M.show()
    if pageRoot then return end

    -- 重置引用
    slotCardRefs = {}
    detailScrollRef = nil
    editing = false

    local allSlots = PM.listAll()

    -- 左侧槽位列表
    local slotCards = {}
    for i = 1, PM.getMaxSlots() do
        table.insert(slotCards, buildSlotCard(i, allSlots[i], selectedSlot == i))
    end

    -- 右侧详情
    local detailContent = buildDetail()

    -- 右侧详情 ScrollView（存引用）
    detailScrollRef = UI.ScrollView {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        paddingTop = 6, paddingBottom = 10,
        children = { detailContent },
    }

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
                    UI.Label { text = "编队预设", fontSize = 18, fontWeight = "bold", fontColor = C.textTitle },
                    UI.Panel { flexGrow = 1 },
                    UI.Label { text = "共 " .. PM.getMaxSlots() .. " 个槽位", fontSize = 12, fontColor = C.textDim },
                },
            },

            -- 主体：左右分栏
            UI.Panel {
                flexGrow = 1, flexShrink = 1, flexDirection = "row",
                width = "100%",
                overflow = "hidden",
                children = {
                    -- 左侧槽位列表
                    UI.ScrollView {
                        width = "28%",
                        flexShrink = 1,
                        paddingLeft = 10, paddingRight = 6, paddingTop = 10, paddingBottom = 10,
                        backgroundColor = C.panelBg,
                        contentContainerStyle = { gap = 8 },
                        children = slotCards,
                    },
                    -- 分隔线
                    UI.Panel { width = 1, alignSelf = "stretch", backgroundColor = C.border },
                    -- 右侧详情
                    detailScrollRef,
                },
            },
        },
    }

    UI.SetRoot(pageRoot)
    print("[PresetUI] Shown, slot=" .. selectedSlot)
end

---@param silent? boolean
function M.hide(silent)
    if pageRoot then
        pageRoot:Destroy()
        pageRoot = nil
    end
    slotCardRefs = {}
    detailScrollRef = nil
    editing = false
    editUnits = {}
    if not silent then
        local MainMenuUI = require("MainMenuUI")
        MainMenuUI.show()
    end
    print("[PresetUI] Hidden")
end

return M
