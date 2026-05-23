-- ============================================================================
-- GameUI.lua - 天赋选择界面 + 游戏HUD
-- ============================================================================

local UI = require("urhox-libs/UI")
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local FACTION_COLORS = ConfigModule.FACTION_COLORS
local TS = require("TalentSystem")
local Entities = require("Entities")
local SkillSystem = require("SkillSystem")
local SettingsUI = require("SettingsUI")

local M = {}

--- 退出到主菜单的回调（由 main.lua 设置）
M.onQuitToMenu = nil

-- 技能图标与颜色
local SKILL_ICONS = {
    dash = "冲",
    focusFire = "火",
    barricade = "拒",
    repel = "斥",
    bloodSacrifice = "祭",
    bounty = "赏",
}
local SKILL_COLORS = {
    dash = {80, 160, 255},
    focusFire = {255, 100, 50},
    barricade = {139, 90, 43},
    repel = {180, 220, 255},
    bloodSacrifice = {200, 30, 30},
    bounty = {255, 200, 0},
}

-- ============================================================================
-- 天赋选择界面
-- ============================================================================
local talentSelectUI_ = nil

function M.ShowTalentSelectUI(initGameFn)
    local function startGameFromTalentSelect()
        GS.gameState = "playing"
        initGameFn()
        -- 天赋效果通过 TS.getActiveEffects() 在各系统实时查询，无需手动 apply
        M.CreateGameUI()
    end

    GS.gameState = "talent_select"
    GS.uiRoot_ = nil  -- 清除游戏UI引用

    -- 新版天赋为三路线天赋树，暂时跳过天赋选择界面直接开局
    startGameFromTalentSelect()
end

-- ============================================================================
-- 游戏 HUD
-- ============================================================================

function M.CreateGameUI()
    GS.uiRoot_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 左上角资源面板 + 退出按钮
            UI.Panel {
                position = "absolute",
                top = 10,
                left = 10,
                gap = 6,
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        id = "resourcePanel",
                        padding = 10,
                        gap = 4,
                        backgroundColor = {0, 0, 0, 160},
                        borderRadius = 8,
                        pointerEvents = "none",
                        children = {
                            UI.Label {
                                id = "woodLabel",
                                text = "木材: 50",
                                fontSize = 14,
                                fontColor = {180, 220, 120, 255},
                            },
                            UI.Label {
                                id = "stoneLabel",
                                text = "石料: 0",
                                fontSize = 14,
                                fontColor = {180, 180, 220, 255},
                            },
                            UI.Label {
                                id = "armyLabel",
                                text = "军队: 0/3",
                                fontSize = 14,
                                fontColor = {220, 180, 120, 255},
                            },
                            UI.Label {
                                id = "timeLabel",
                                text = "时间: 0秒",
                                fontSize = 12,
                                fontColor = {180, 180, 180, 255},
                            },
                        },
                    },
                    UI.Panel {
                        backgroundColor = {0, 0, 0, 140},
                        borderRadius = 6,
                        paddingLeft = 10, paddingRight = 10,
                        paddingTop = 5, paddingBottom = 5,
                        cursor = "pointer",
                        onClick = function()
                            -- 显示退出确认弹窗
                            local dlg = GS.uiRoot_ and GS.uiRoot_:FindById("quitConfirmOverlay")
                            if dlg then dlg:SetVisible(true) end
                        end,
                        children = {
                            UI.Label {
                                text = "退出",
                                fontSize = 12,
                                fontColor = {200, 200, 200, 255},
                            },
                        },
                    },
                },
            },

            -- 右上角：AI状态指示
            UI.Panel {
                id = "factionPanel",
                position = "absolute",
                top = 10,
                right = 140,
                padding = 8,
                gap = 3,
                backgroundColor = {0, 0, 0, 120},
                borderRadius = 6,
                pointerEvents = "none",
                children = {
                    UI.Label {
                        id = "factionLabel",
                        text = "存活: 4",
                        fontSize = 12,
                        fontColor = {200, 200, 200, 255},
                    },
                },
            },

            -- 技能按钮栏
            UI.Panel {
                id = "skillPanel",
                position = "absolute",
                bottom = 70,
                left = 0,
                right = 0,
                flexDirection = "row",
                justifyContent = "center",
                gap = 6,
                pointerEvents = "box-none",
                children = (function()
                    local btns = {}
                    local skillOrder = SkillSystem.getSkillOrder()
                    for idx, skillId in ipairs(skillOrder) do
                        local sc = SKILL_COLORS[skillId] or {200, 200, 200}
                        local icon = SKILL_ICONS[skillId] or "?"
                        local skillName = SkillSystem.getSkillName(skillId)
                        table.insert(btns, UI.Panel {
                            id = "skillBtn_" .. skillId,
                            width = 48, height = 48,
                            backgroundColor = {sc[1], sc[2], sc[3], 180},
                            borderRadius = 8,
                            borderWidth = 1,
                            borderColor = {255, 255, 255, 80},
                            justifyContent = "center",
                            alignItems = "center",
                            cursor = "pointer",
                            onClick = function()
                                SkillSystem.activate(skillId)
                            end,
                            children = {
                                UI.Label {
                                    text = icon,
                                    fontSize = 18,
                                    fontWeight = "bold",
                                    fontColor = {255, 255, 255, 255},
                                    textAlign = "center",
                                },
                                UI.Label {
                                    id = "skillKey_" .. skillId,
                                    text = tostring(idx),
                                    fontSize = 9,
                                    fontColor = {255, 255, 255, 150},
                                    textAlign = "center",
                                },
                                -- 冷却覆盖层
                                UI.Panel {
                                    id = "skillCD_" .. skillId,
                                    position = "absolute",
                                    top = 0, left = 0, right = 0, bottom = 0,
                                    backgroundColor = {0, 0, 0, 0},
                                    borderRadius = 8,
                                    justifyContent = "center",
                                    alignItems = "center",
                                    pointerEvents = "none",
                                    children = {
                                        UI.Label {
                                            id = "skillCDText_" .. skillId,
                                            text = "",
                                            fontSize = 14,
                                            fontWeight = "bold",
                                            fontColor = {255, 255, 255, 255},
                                            textAlign = "center",
                                        },
                                    },
                                },
                            },
                        })
                    end
                    return btns
                end)(),
            },

            -- 底部操作按钮
            UI.Panel {
                id = "actionPanel",
                position = "absolute",
                bottom = 20,
                left = 0,
                right = 0,
                flexDirection = "row",
                justifyContent = "center",
                gap = 12,
                pointerEvents = "box-none",
                children = {
                    UI.Button {
                        id = "btnBuyPeasant",
                        text = "招募平民(10木材)",
                        fontSize = 13,
                        paddingLeft = 14,
                        paddingRight = 14,
                        paddingTop = 10,
                        paddingBottom = 10,
                        onClick = function()
                            local lord = GS.lords[1]
                            if lord and lord.alive and lord.wood >= CONFIG.PeasantCost then
                                lord.wood = lord.wood - CONFIG.PeasantCost
                                Entities.createFollower(lord, "peasant")
                                Entities.spawnParticle(lord.x, lord.y, 100, 200, 255, 3)
                            end
                        end,
                    },
                    UI.Button {
                        id = "btnBuySoldier",
                        text = "转化士兵(20木材)",
                        fontSize = 13,
                        paddingLeft = 14,
                        paddingRight = 14,
                        paddingTop = 10,
                        paddingBottom = 10,
                        onClick = function()
                            local lord = GS.lords[1]
                            if lord and lord.alive and lord.wood >= CONFIG.SoldierCost then
                                -- 找一个平民转化
                                local converted = false
                                for _, f in ipairs(GS.followers) do
                                    if f.lordId == lord.id and f.alive and f.fType == "peasant" and f.state == "following" then
                                        f.fType = "soldier"
                                        lord.wood = lord.wood - CONFIG.SoldierCost
                                        Entities.spawnParticle(f.x, f.y, 255, 200, 50, 5)
                                        Entities.spawnDamageNumber(f.x, f.y, "升级!", 255, 220, 50)
                                        converted = true
                                        break
                                    end
                                end
                                if not converted then
                                    -- 没有平民可转化
                                    print("没有可转化的平民!")
                                end
                            end
                        end,
                    },
                    UI.Button {
                        id = "btnUpgradeArcher",
                        text = "弓手(10石+10木)",
                        fontSize = 13,
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 10, paddingBottom = 10,
                        onClick = function()
                            local lord = GS.lords[1]
                            local archerStone = CONFIG.ArcherCostStone
                            local archerWood = CONFIG.ArcherCostWood
                            if lord and lord.alive and lord.stone >= archerStone and lord.wood >= archerWood then
                                for _, f in ipairs(GS.followers) do
                                    if f.lordId == lord.id and f.alive and f.fType == "soldier" and f.state == "following" then
                                        f.fType = "archer"
                                        f.fireTimer = 0
                                        lord.stone = lord.stone - archerStone
                                        lord.wood = lord.wood - archerWood
                                        Entities.spawnParticle(f.x, f.y, 100, 200, 255, 5)
                                        Entities.spawnDamageNumber(f.x, f.y, "弓手!", 100, 220, 255)
                                        break
                                    end
                                end
                            end
                        end,
                    },
                    UI.Button {
                        id = "btnRecruitHealer",
                        text = "治愈师(20石+20木)",
                        fontSize = 13,
                        paddingLeft = 12, paddingRight = 12,
                        paddingTop = 10, paddingBottom = 10,
                        onClick = function()
                            local lord = GS.lords[1]
                            local cost = CONFIG.HealerCost
                            if lord and lord.alive and lord.stone >= cost.stone and lord.wood >= cost.wood then
                                lord.stone = lord.stone - cost.stone
                                lord.wood  = lord.wood  - cost.wood
                                local healer = Entities.createFollower(lord, "healer")
                                if healer then
                                    Entities.spawnParticle(lord.x, lord.y, 80, 220, 160, 6)
                                    Entities.spawnDamageNumber(lord.x, lord.y, "治愈师!", 80, 220, 160)
                                end
                            end
                        end,
                    },


                },
            },

            -- 调试面板（开发者模式）
            UI.Panel {
                id = "devDebugPanel",
                position = "absolute",
                top = 10,
                right = 10,
                padding = 8,
                gap = 6,
                backgroundColor = {180, 40, 40, 200},
                borderRadius = 8,
                borderWidth = 1,
                borderColor = {255, 80, 80, 180},
                display = "none",
                children = {
                    UI.Label {
                        text = "DEV",
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = {255, 255, 100, 255},
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 4,
                        children = {
                            UI.Button {
                                text = "+50木",
                                fontSize = 11,
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 4, paddingBottom = 4,
                                onClick = function()
                                    local lord = GS.lords[1]
                                    if lord then lord.wood = lord.wood + 50 end
                                end,
                            },
                            UI.Button {
                                text = "+200木",
                                fontSize = 11,
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 4, paddingBottom = 4,
                                onClick = function()
                                    local lord = GS.lords[1]
                                    if lord then lord.wood = lord.wood + 200 end
                                end,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 4,
                        children = {
                            UI.Button {
                                text = "+50石",
                                fontSize = 11,
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 4, paddingBottom = 4,
                                onClick = function()
                                    local lord = GS.lords[1]
                                    if lord then lord.stone = lord.stone + 50 end
                                end,
                            },
                            UI.Button {
                                text = "+200石",
                                fontSize = 11,
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 4, paddingBottom = 4,
                                onClick = function()
                                    local lord = GS.lords[1]
                                    if lord then lord.stone = lord.stone + 200 end
                                end,
                            },
                        },
                    },
                    UI.Button {
                        text = "满血",
                        fontSize = 11,
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 4, paddingBottom = 4,
                        onClick = function()
                            local lord = GS.lords[1]
                            if lord then lord.hp = lord.maxHp or CONFIG.LordHP end
                        end,
                    },
                },
            },

            -- 退出确认弹窗（默认隐藏）
            UI.Panel {
                id = "quitConfirmOverlay",
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = {0, 0, 0, 160},
                justifyContent = "center",
                alignItems = "center",
                visible = false,
                children = {
                    UI.Panel {
                        width = 260,
                        backgroundColor = {40, 45, 65, 245},
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = {80, 90, 120, 150},
                        padding = 20,
                        gap = 16,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "确认退出？",
                                fontSize = 18,
                                fontWeight = "bold",
                                fontColor = {255, 255, 255, 255},
                            },
                            UI.Label {
                                text = "当前对局进度不会保存",
                                fontSize = 13,
                                fontColor = {180, 180, 200, 255},
                            },
                            UI.Panel {
                                flexDirection = "row",
                                gap = 16,
                                children = {
                                    UI.Button {
                                        text = "取消",
                                        fontSize = 14,
                                        paddingLeft = 24, paddingRight = 24,
                                        paddingTop = 8, paddingBottom = 8,
                                        onClick = function()
                                            local dlg = GS.uiRoot_ and GS.uiRoot_:FindById("quitConfirmOverlay")
                                            if dlg then dlg:SetVisible(false) end
                                        end,
                                    },
                                    UI.Button {
                                        text = "确认退出",
                                        fontSize = 14,
                                        variant = "primary",
                                        paddingLeft = 24, paddingRight = 24,
                                        paddingTop = 8, paddingBottom = 8,
                                        onClick = function()
                                            if M.onQuitToMenu then
                                                M.onQuitToMenu()
                                            end
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
            },

            -- 虚拟摇杆区域(通过NanoVG绘制，这里只是占位)
        },
    }

    UI.SetRoot(GS.uiRoot_)
end

-- ============================================================================
-- HUD 每帧更新
-- ============================================================================

function M.UpdateGameUI()
    if not GS.uiRoot_ then return end
    local lord = GS.lords[1]
    if not lord then return end

    local woodLabel = GS.uiRoot_:FindById("woodLabel")
    if woodLabel then woodLabel:SetText("木材: " .. lord.wood) end

    local stoneLabel = GS.uiRoot_:FindById("stoneLabel")
    if stoneLabel then stoneLabel:SetText("石料: " .. lord.stone) end

    local peasantCount = Entities.countFollowers(lord.id, "peasant")
    local soldierCount = Entities.countFollowers(lord.id, "soldier")
    local archerCount = Entities.countFollowers(lord.id, "archer")
    local armyLabel = GS.uiRoot_:FindById("armyLabel")
    if armyLabel then
        local parts = {"平民:" .. peasantCount, "兵:" .. soldierCount}
        if archerCount > 0 then table.insert(parts, "弓:" .. archerCount) end
        armyLabel:SetText(table.concat(parts, " "))
    end

    local timeLabel = GS.uiRoot_:FindById("timeLabel")
    if timeLabel then
        timeLabel:SetText(string.format("时间: %.0f秒", GS.gameTime))
    end

    -- 阵营数量
    local aliveCount = 0
    for _, l in ipairs(GS.lords) do
        if l.alive then aliveCount = aliveCount + 1 end
    end
    local factionLabel = GS.uiRoot_:FindById("factionLabel")
    if factionLabel then
        factionLabel:SetText("存活: " .. aliveCount .. "/" .. (CONFIG.AILordCount + 1))
    end



    -- 更新升级按钮文本（固定费用）
    local btnArcher = GS.uiRoot_:FindById("btnUpgradeArcher")
    if btnArcher then
        btnArcher:SetText("弓手(" .. CONFIG.ArcherCostStone .. "石+" .. CONFIG.ArcherCostWood .. "木)")
    end

    -- 开发者调试面板显隐
    local devPanel = GS.uiRoot_:FindById("devDebugPanel")
    if devPanel then
        local devOn = SettingsUI.get("devMode") == true
        devPanel:SetVisible(devOn)
    end

    -- 技能按钮冷却更新
    local skillOrder = SkillSystem.getSkillOrder()
    for _, skillId in ipairs(skillOrder) do
        local cdOverlay = GS.uiRoot_:FindById("skillCD_" .. skillId)
        local cdText = GS.uiRoot_:FindById("skillCDText_" .. skillId)
        local btnPanel = GS.uiRoot_:FindById("skillBtn_" .. skillId)
        if cdOverlay and cdText and btnPanel then
            local cd = SkillSystem.getCooldown(skillId)
            local isActive = SkillSystem.isActive(skillId)
            if cd > 0 then
                -- 冷却中：灰色遮罩 + 倒计时数字
                cdOverlay:SetStyle({ backgroundColor = {0, 0, 0, 150} })
                cdText:SetText(string.format("%.0f", math.ceil(cd)))
                btnPanel:SetStyle({ borderColor = {100, 100, 100, 150} })
            elseif isActive then
                -- 激活中：高亮边框
                cdOverlay:SetStyle({ backgroundColor = {0, 0, 0, 0} })
                cdText:SetText("")
                local sc = SKILL_COLORS[skillId] or {200, 200, 200}
                btnPanel:SetStyle({ borderColor = {255, 255, 255, 255}, borderWidth = 2 })
            else
                -- 可用
                cdOverlay:SetStyle({ backgroundColor = {0, 0, 0, 0} })
                cdText:SetText("")
                btnPanel:SetStyle({ borderColor = {255, 255, 255, 80}, borderWidth = 1 })
            end
        end
    end
end

return M
