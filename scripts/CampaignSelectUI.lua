-- scripts/CampaignSelectUI.lua
-- 战役关卡选择全屏页面：章节标签 + 关卡列表 + 底部详情出战
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
-- 检查章节是否解锁
------------------------------------------------------------

local function isChapterUnlocked(chapterIndex)
    if chapterIndex <= 1 then return true end
    local prevLevels = CD.getLevelsByChapter(chapterIndex - 1)
    if not prevLevels then return false end
    for _, levelId in ipairs(prevLevels) do
        if not CS.isCleared(levelId) then return false end
    end
    return true
end

------------------------------------------------------------
-- 详情面板更新
------------------------------------------------------------

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
-- 主界面
------------------------------------------------------------

function M.show(onStartLevel, initialLevelId)
    if pageRoot then return end

    onStartLevelCb = onStartLevel
    selectedLevelId = initialLevelId or nil
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
                text = "<- 返回",
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
            label = ch.name .. (unlocked and "" or " [锁]"),
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
            enemySummary = total .. " 敌"
        end

        local card = UI.Panel {
            width = "92%", height = 72,
            alignSelf = "center", marginBottom = 8,
            flexDirection = "row", alignItems = "center",
            backgroundColor = (selectedLevelId == levelId) and {70, 160, 255, 30} or T.colors.cardBg,
            borderRadius = T.radius.md,
            boxShadow = T.shadow,
            opacity = accessible and 1.0 or 0.4,
            pointerEvents = accessible and "auto" or "none",
            onClick = function(self)
                if accessible then
                    -- 重建以更新选中态，传入选中的关卡ID
                    M.hide()
                    M.show(onStartLevelCb, levelId)
                end
            end,
            children = {
                -- 左侧色条
                UI.Panel {
                    width = 4, height = "100%",
                    backgroundColor = (selectedLevelId == levelId) and T.colors.primary or (cleared and T.colors.success or T.colors.textSecondary),
                    borderRadiusTopLeft = T.radius.md, borderRadiusBottomLeft = T.radius.md,
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
                                UI.Label { text = levelId .. " " .. (level.name or ""), fontSize = 14, fontColor = T.colors.textPrimary, flexShrink = 1 },
                                UI.Label {
                                    text = cleared and "已通关" or (not accessible and "[锁]" or ""),
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
        text = "出战",
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
                GS.selectedLevelId = selectedLevelId
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

    -- 进场动画：内容区域淡入上滑
    scrollView:Animate({
        keyframes = {
            [0] = { opacity = 0, translateY = 20 },
            [1] = { opacity = 1, translateY = 0 },
        },
        duration = 0.3,
        easing = "easeOut",
    })

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
