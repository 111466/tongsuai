-- ============================================================================
-- SettingsUI.lua — 全屏设置界面（音效/音量/游戏设定）
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("MenuTheme")

local M = {}

local pageRoot = nil

-- ============================================================================
-- 本地设置缓存 (运行时生效，不做云同步)
-- ============================================================================

local settings = {
    masterVolume = 80,      -- 主音量 0-100
    sfxVolume    = 100,     -- 音效音量 0-100
    musicVolume  = 70,      -- 音乐音量 0-100
    cameraSens   = 50,      -- 镜头灵敏度 0-100
    showDmgNum   = true,    -- 显示伤害数字
    showMinimap  = true,    -- 显示小地图
    autoCollect  = true,    -- 自动采集资源
    screenShake  = true,    -- 屏幕震动
    devMode      = false,   -- 开发者模式
}

--- 外部读取设置值
function M.get(key) return settings[key] end

-- ============================================================================
-- 暗色主题
-- ============================================================================

local C = {
    bg         = {25, 30, 50, 240},
    panelBg    = {40, 45, 65, 255},
    cardBg     = {55, 60, 80, 255},
    border     = {80, 90, 120, 120},
    textTitle  = {255, 255, 255, 255},
    textBody   = {200, 210, 230, 255},
    textDim    = {140, 150, 170, 255},
    accent     = {70, 160, 255, 255},
}

-- ============================================================================
-- 辅助构件
-- ============================================================================

--- 设置分组标题
local function sectionTitle(text)
    return UI.Panel {
        width = "100%", marginTop = 6, marginBottom = 4,
        children = {
            UI.Label { text = text, fontSize = 14, fontWeight = "bold", fontColor = C.textTitle },
        },
    }
end

--- 带文字标签的滑块行
local function sliderRow(label, value, onChange)
    ---@type Label
    local valLabel
    valLabel = UI.Label { text = value .. "%", fontSize = 13, fontColor = C.accent, width = 38, textAlign = "right" }
    return UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center", gap = 10,
        paddingLeft = 4, paddingRight = 4, paddingTop = 6, paddingBottom = 6,
        children = {
            UI.Label { text = label, fontSize = 13, fontColor = C.textBody, width = 90 },
            UI.Slider {
                flexGrow = 1,
                value = value, min = 0, max = 100, step = 5,
                trackHeight = 4, thumbSize = 18,
                onChange = function(self, v)
                    valLabel:SetText(math.floor(v) .. "%")
                    if onChange then onChange(v) end
                end,
            },
            valLabel,
        },
    }
end

--- 带开关的行
local function toggleRow(label, checked, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
        paddingLeft = 4, paddingRight = 4, paddingTop = 6, paddingBottom = 6,
        children = {
            UI.Label { text = label, fontSize = 13, fontColor = C.textBody },
            UI.Toggle {
                checked = checked,
                onChange = function(self, v)
                    if onChange then onChange(v) end
                end,
            },
        },
    }
end

-- ============================================================================
-- show / hide
-- ============================================================================

function M.show()
    if pageRoot then return end

    local contentChildren = {
        -- ==================== 音频设置 ====================
        sectionTitle("音频设置"),
        sliderRow("主音量", settings.masterVolume, function(v)
            settings.masterVolume = math.floor(v)
        end),
        sliderRow("音效音量", settings.sfxVolume, function(v)
            settings.sfxVolume = math.floor(v)
        end),
        sliderRow("音乐音量", settings.musicVolume, function(v)
            settings.musicVolume = math.floor(v)
        end),

        UI.Panel { width = "100%", height = 1, backgroundColor = C.border, marginTop = 6, marginBottom = 6 },

        -- ==================== 操控设置 ====================
        sectionTitle("操控设置"),
        sliderRow("镜头灵敏度", settings.cameraSens, function(v)
            settings.cameraSens = math.floor(v)
        end),

        UI.Panel { width = "100%", height = 1, backgroundColor = C.border, marginTop = 6, marginBottom = 6 },

        -- ==================== 显示设置 ====================
        sectionTitle("显示设置"),
        toggleRow("显示伤害数字", settings.showDmgNum, function(v)
            settings.showDmgNum = v
        end),
        toggleRow("显示小地图", settings.showMinimap, function(v)
            settings.showMinimap = v
        end),
        toggleRow("屏幕震动", settings.screenShake, function(v)
            settings.screenShake = v
        end),

        UI.Panel { width = "100%", height = 1, backgroundColor = C.border, marginTop = 6, marginBottom = 6 },

        -- ==================== 游戏设置 ====================
        sectionTitle("游戏设置"),
        toggleRow("自动采集资源", settings.autoCollect, function(v)
            settings.autoCollect = v
        end),

        UI.Panel { width = "100%", height = 1, backgroundColor = C.border, marginTop = 6, marginBottom = 6 },

        -- ==================== 开发者选项 ====================
        sectionTitle("开发者选项"),
        toggleRow("开发者模式", settings.devMode, function(v)
            settings.devMode = v
            print("[Settings] DevMode = " .. tostring(v))
        end),
        UI.Label {
            text = "开启后：全资源解锁 + 游戏内显示调试面板",
            fontSize = 11, fontColor = C.textDim,
            paddingLeft = 4,
        },
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
                    UI.Label { text = "设置", fontSize = 18, fontWeight = "bold", fontColor = C.textTitle },
                },
            },

            -- 内容区（居中、限宽）
            UI.Panel {
                flexGrow = 1, width = "100%",
                alignItems = "center", paddingTop = 10, paddingBottom = 10,
                children = {
                    UI.ScrollView {
                        width = "90%",
                        maxWidth = 480,
                        flexGrow = 1,
                        paddingLeft = 16, paddingRight = 16, paddingTop = 12, paddingBottom = 20,
                        backgroundColor = C.panelBg,
                        borderRadius = 12,
                        contentContainerStyle = { gap = 2 },
                        children = contentChildren,
                    },
                },
            },
        },
    }

    UI.SetRoot(pageRoot)
    print("[SettingsUI] Shown")
end

function M.hide()
    if pageRoot then
        pageRoot:Destroy()
        pageRoot = nil
    end
    local MainMenuUI = require("MainMenuUI")
    MainMenuUI.show()
    print("[SettingsUI] Hidden")
end

return M
