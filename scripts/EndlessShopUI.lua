-- scripts/EndlessShopUI.lua
-- 无尽模式波次间商店 Modal
local UI = require("urhox-libs/UI")
local GS = require("GameState")
local Shop = require("ShopSystem")
local EM = require("EndlessMode")
local T = require("MenuTheme")

local M = {}

---@type Widget|nil
local modal = nil
local onNextWaveCb = nil
local countdownTimer = 5.0
---@type Widget|nil
local countdownLabel = nil
---@type Widget|nil
local coinLabel = nil
---@type Widget[]
local itemButtons = {}

-- buff 图标映射
local buffIcons = {
    "S1", "S2", "S3", "S4", "S5", "S6",
    "S7", "S8", "S9", "S10",
}

local function refreshUI()
    -- 更新余额
    local info = EM.getWaveInfo()
    local coins = info and info.warCoins or 0
    if coinLabel then coinLabel:SetText("战争币: " .. coins) end

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
        countdownLabel:SetText("下一波 (" .. sec .. "s)")
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
        local canAfford = coins >= (item.cost or 0)
        local buyBtn = UI.Button {
            text = canAfford and "购买" or "不足",
            fontSize = 12,
            height = 28,
            width = "80%",
            alignSelf = "center",
            marginTop = 6,
            borderRadius = T.radius.sm,
            backgroundColor = canAfford and T.colors.primary or {150, 150, 150, 255},
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
                UI.Label { text = icon, fontSize = 24, textAlign = "center", fontColor = T.colors.primary },
                UI.Label { text = item.name or ("buff" .. i), fontSize = 12, fontColor = T.colors.textPrimary, textAlign = "center", marginTop = 4 },
                UI.Label { text = "x" .. (item.cost or 0), fontSize = 12, fontColor = T.colors.gold, textAlign = "center", marginTop = 2 },
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
        text = "下一波 (5s)",
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
        text = "战争币: " .. coins,
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
                text = "第 " .. waveNumber .. " 波 完成!",
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
