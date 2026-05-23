-- ============================================================================
-- CampaignData.lua — 战役关卡配置数据
-- ============================================================================

local CD = {}

--- 章节信息
CD.Chapters = {
    { id = 1, name = "边境烽烟", levelCount = 6 },
    { id = 2, name = "深入腹地", levelCount = 6 },
    { id = 3, name = "王都之战", levelCount = 5 },
}

--- 所有关卡配置
--- enemies: { { units = {type=count,...}, formation = id|nil, aiLevel = 1-3 }, ... }
--- player_start: { type = count, ... }
--- reward: { type = "unit"|"formation", id = string }
CD.Levels = {
    ["1-1"] = {
        name = "初战告捷", chapter = 1,
        map_size = { w = 2000, h = 2000 },
        player_start = { peasant = 5, soldier = 3 },
        resources = 40,
        enemies = {
            { units = { peasant = 3, soldier = 5 }, formation = nil, aiLevel = 1 },
        },
        reward = nil,  -- 教学关无特殊奖励
        next = { "1-2" },
        unlock_condition = nil,
    },
    ["1-2"] = {
        name = "资源争夺", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 4 },
        resources = 50,
        enemies = {
            { units = { peasant = 4, soldier = 6, archer = 2 }, formation = nil, aiLevel = 1 },
        },
        reward = nil,
        next = { "1-3" },
        unlock_condition = { "1-1" },
    },
    ["1-3"] = {
        name = "骑兵突袭", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 5, knight = 2 },
        resources = 50,
        enemies = {
            { units = { peasant = 3, soldier = 5, knight = 3 }, formation = nil, aiLevel = 1 },
        },
        reward = { type = "formation", id = "cone" },
        next = { "1-4A", "1-4B" },
        unlock_condition = { "1-2" },
    },
    ["1-4A"] = {
        name = "山贼巢穴", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 4, knight = 2 },
        resources = 45,
        enemies = {
            { units = { peasant = 2, soldier = 8, archer = 3 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "unit", id = "archer" },
        next = { "1-5" },
        unlock_condition = { "1-3" },
    },
    ["1-4B"] = {
        name = "兽群侵袭", chapter = 1,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 4, knight = 2 },
        resources = 45,
        enemies = {
            { units = { peasant = 2, soldier = 6, knight = 4 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "unit", id = "mounted_archer" },
        next = { "1-5" },
        unlock_condition = { "1-3" },
    },
    ["1-5"] = {
        name = "边境要塞", chapter = 1,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 5, soldier = 5, knight = 3, archer = 2 },
        resources = 60,
        enemies = {
            { units = { peasant = 3, soldier = 7, knight = 3, archer = 3 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "formation", id = "phalanx" },
        next = { "2-1" },
        unlock_condition = { "1-4A", "1-4B", mode = "any" },
    },

    -- 第二章
    ["2-1"] = {
        name = "密林遭遇", chapter = 2,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 5, knight = 2, archer = 2 },
        resources = 50,
        enemies = {
            { units = { soldier = 6, knight = 2, archer = 4 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "unit", id = "mage" },
        next = { "2-2" },
        unlock_condition = { "1-5" },
    },
    ["2-2"] = {
        name = "伏击战", chapter = 2,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 4, soldier = 5, knight = 2, archer = 3 },
        resources = 50,
        enemies = {
            { units = { soldier = 5, archer = 5, mounted_archer = 2 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "formation", id = "arc" },
        next = { "2-3" },
        unlock_condition = { "2-1" },
    },
    ["2-3"] = {
        name = "副将来投", chapter = 2,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 5, knight = 3, archer = 3 },
        resources = 55,
        enemies = {
            { units = { soldier = 9, knight = 3 }, formation = "phalanx", aiLevel = 2 },
        },
        reward = { type = "unit", id = "vice_general" },
        next = { "2-4A", "2-4B" },
        unlock_condition = { "2-2" },
    },
    ["2-4A"] = {
        name = "平原决战", chapter = 2,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 7, knight = 3, archer = 3 },
        resources = 55,
        enemies = {
            { units = { soldier = 5, knight = 4, mounted_archer = 3 }, formation = "cone", aiLevel = 2 },
            { units = { soldier = 4, archer = 4 }, formation = nil, aiLevel = 2 },
        },
        reward = { type = "formation", id = "crane_wing" },
        next = { "2-5" },
        unlock_condition = { "2-3" },
    },
    ["2-4B"] = {
        name = "河谷阻击", chapter = 2,
        map_size = { w = 2500, h = 3000 },
        player_start = { peasant = 4, soldier = 7, knight = 2, archer = 3 },
        resources = 55,
        enemies = {
            { units = { soldier = 10, archer = 3 }, formation = "phalanx", aiLevel = 2 },
        },
        reward = { type = "unit", id = "drummer" },
        next = { "2-5" },
        unlock_condition = { "2-3" },
    },
    ["2-5"] = {
        name = "攻城战", chapter = 2,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 5, soldier = 8, knight = 3, archer = 3 },
        resources = 60,
        enemies = {
            { units = { soldier = 10, knight = 3, archer = 4 }, formation = "phalanx", aiLevel = 3 },
        },
        reward = { type = "unit", id = "advisor" },
        next = { "3-1" },
        unlock_condition = { "2-4A", "2-4B", mode = "any" },
    },

    -- 第三章
    ["3-1"] = {
        name = "王都外围", chapter = 3,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 9, knight = 3, archer = 3, mage = 1 },
        resources = 55,
        enemies = {
            { units = { soldier = 6, knight = 4, archer = 3, mage = 2 }, formation = "cone", aiLevel = 3 },
            { units = { soldier = 9 }, formation = "phalanx", aiLevel = 2 },
        },
        reward = nil,
        next = { "3-2" },
        unlock_condition = { "2-5" },
    },
    ["3-2"] = {
        name = "内城突破", chapter = 3,
        map_size = { w = 3000, h = 3000 },
        player_start = { peasant = 4, soldier = 9, knight = 3, archer = 3, mage = 2 },
        resources = 55,
        enemies = {
            { units = { soldier = 7, knight = 4, archer = 4, paladin = 1 }, formation = "crane_wing", aiLevel = 3 },
            { units = { soldier = 8, mage = 3 }, formation = nil, aiLevel = 3 },
        },
        reward = { type = "unit", id = "paladin" },
        next = { "3-3" },
        unlock_condition = { "3-1" },
    },
    ["3-3"] = {
        name = "王宫之战", chapter = 3,
        map_size = { w = 3500, h = 3500 },
        player_start = { peasant = 5, soldier = 10, knight = 4, archer = 4, mage = 2 },
        resources = 60,
        enemies = {
            { units = { soldier = 11, knight = 5, archer = 4, mage = 2 }, formation = "crane_wing", aiLevel = 3 },
            { units = { soldier = 5, knight = 3, mage = 2, drummer = 1 }, formation = "cone", aiLevel = 3 },
        },
        reward = { type = "formation", id = "chaos" },
        next = { "3-4", "3-S" },
        unlock_condition = { "3-2" },
    },
    ["3-4"] = {
        name = "正面决战", chapter = 3,
        map_size = { w = 3500, h = 3500 },
        player_start = { peasant = 5, soldier = 11, knight = 4, archer = 4, mage = 3 },
        resources = 65,
        enemies = {
            { units = { soldier = 12, knight = 5, archer = 5, mage = 3, paladin = 1 }, formation = "chaos", aiLevel = 3 },
            { units = { soldier = 6, knight = 4, mounted_archer = 3 }, formation = "crane_wing", aiLevel = 3 },
            { units = { soldier = 5, mage = 3, advisor = 1 }, formation = "celestial", aiLevel = 3 },
        },
        reward = { type = "formation", id = "celestial" },
        next = nil,  -- 终章
        unlock_condition = { "3-3" },
    },
    ["3-S"] = {
        name = "暗影小径", chapter = 3,
        map_size = { w = 2500, h = 2500 },
        player_start = { peasant = 3, soldier = 8, knight = 3, archer = 3, mage = 2 },
        resources = 40,
        enemies = {
            { units = { soldier = 10, knight = 4, assassin = 2 }, formation = nil, aiLevel = 3 },
        },
        reward = { type = "unit", id = "assassin" },
        next = nil,
        unlock_condition = { "3-3", special = "3-3_low_casualties" },  -- 通关 3-3 损失 <= 5 单位
    },
}

--- 获取章节所有关卡 ID
function CD.getLevelsByChapter(chapter)
    local result = {}
    for id, level in pairs(CD.Levels) do
        if level.chapter == chapter then
            table.insert(result, id)
        end
    end
    table.sort(result)
    return result
end

--- 获取关卡配置
function CD.getLevel(levelId)
    return CD.Levels[levelId]
end

return CD
