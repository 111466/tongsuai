-- ============================================================================
-- CampaignState.lua — 战役进度管理 + 云存档
-- ============================================================================

local CampaignData = require("CampaignData")

local CS = {}

-- 本地缓存
local state = {
    chapter = 1,
    cleared = {},           -- set: levelId -> true
    unlocked_units = {},    -- set: unitId -> true
    unlocked_formations = {},-- set: formationId -> true
}
local loaded = false

-- ============================================================================
-- 云端存取
-- ============================================================================

--- 序列化为 JSON 字符串存云端
local function serialize()
    local cleared_list = {}
    for id in pairs(state.cleared) do table.insert(cleared_list, id) end
    local units_list = {}
    for id in pairs(state.unlocked_units) do table.insert(units_list, id) end
    local formations_list = {}
    for id in pairs(state.unlocked_formations) do table.insert(formations_list, id) end

    return require("cjson").encode({
        chapter = state.chapter,
        cleared = cleared_list,
        unlocked_units = units_list,
        unlocked_formations = formations_list,
    })
end

--- 从 JSON 字符串反序列化
local function deserialize(jsonStr)
    if not jsonStr or jsonStr == "" then return end
    local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
    if not ok or not data then return end

    state.chapter = data.chapter or 1
    state.cleared = {}
    for _, id in ipairs(data.cleared or {}) do state.cleared[id] = true end
    state.unlocked_units = {}
    for _, id in ipairs(data.unlocked_units or {}) do state.unlocked_units[id] = true end
    state.unlocked_formations = {}
    for _, id in ipairs(data.unlocked_formations or {}) do state.unlocked_formations[id] = true end
end

function CS.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("campaign_data")
            :Fetch({
                ok = function(values)
                    deserialize(values.campaign_data)
                    loaded = true
                    print("[CS] Campaign data loaded: chapter=" .. state.chapter)
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[CS] Campaign load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function CS.saveToCloud()
    if clientCloud then
        clientCloud:BatchSet()
            :Set("campaign_data", serialize())
            :Save("战役进度", {
                ok = function() print("[CS] Campaign data saved") end,
                error = function(_, reason) print("[CS] Campaign save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

local function isDevMode()
    local ok, Settings = pcall(require, "SettingsUI")
    return ok and Settings.get and Settings.get("devMode") == true
end

function CS.isLoaded() return loaded end
function CS.getCurrentChapter() return state.chapter end
function CS.isCleared(levelId)
    if isDevMode() then return true end
    return state.cleared[levelId] == true
end
function CS.isUnitUnlocked(unitId)
    if isDevMode() then return true end
    return state.unlocked_units[unitId] == true
end
function CS.isFormationUnlocked(formId)
    if isDevMode() then return true end
    return state.unlocked_formations[formId] == true
end

function CS.isLevelAccessible(levelId)
    if isDevMode() then return true end
    local level = CampaignData.getLevel(levelId)
    if not level then return false end
    if not level.unlock_condition then return true end  -- 1-1 无条件

    if level.unlock_condition.mode == "any" then
        for _, reqId in ipairs(level.unlock_condition) do
            if type(reqId) == "string" and state.cleared[reqId] then return true end
        end
        return false
    else
        for _, reqId in ipairs(level.unlock_condition) do
            if type(reqId) == "string" and not state.cleared[reqId] then return false end
        end
    end

    -- 特殊条件
    if level.unlock_condition.special == "3-3_low_casualties" then
        -- 由通关 3-3 时记录的损失数判断（存在 state 中）
        return (state.casualties_3_3 or 999) <= 5
    end

    return true
end

-- ============================================================================
-- 状态更新
-- ============================================================================

--- 记录关卡通关，返回首通奖励（或 nil）
function CS.clearLevel(levelId, casualties)
    local isFirstClear = not state.cleared[levelId]
    state.cleared[levelId] = true

    -- 更新章节进度
    local level = CampaignData.getLevel(levelId)
    if level and level.chapter > state.chapter then
        state.chapter = level.chapter
    end

    -- 记录 3-3 损失数（用于隐藏关卡解锁）
    if levelId == "3-3" then
        state.casualties_3_3 = casualties
    end

    local reward = nil
    if isFirstClear and level and level.reward then
        reward = level.reward
        if reward.type == "unit" then
            state.unlocked_units[reward.id] = true
        elseif reward.type == "formation" then
            state.unlocked_formations[reward.id] = true
        end
    end

    CS.saveToCloud()
    return reward
end

--- 获取已通关关卡列表
function CS.getClearedLevels()
    local list = {}
    for id in pairs(state.cleared) do table.insert(list, id) end
    table.sort(list)
    return list
end

--- 获取已解锁兵种列表
function CS.getUnlockedUnits()
    local list = {}
    for id in pairs(state.unlocked_units) do table.insert(list, id) end
    return list
end

--- 获取已解锁阵型列表
function CS.getUnlockedFormations()
    local list = {}
    for id in pairs(state.unlocked_formations) do table.insert(list, id) end
    return list
end

return CS
