-- ============================================================================
-- CodexState.lua — 图鉴解锁状态 + 云端存档
-- ============================================================================

local CS = {}

-- 已遭遇的Boss/怪物（key = id, value = true）
CS.encounteredEnemies = {}

-- 云端加载完成标记
CS.loaded = false

-- ============================================================================
-- 记录遭遇
-- ============================================================================

--- 记录遭遇过某个Boss/怪物（用于解锁图鉴条目）
---@param enemyId string
function CS.recordEnemyEncounter(enemyId)
    if not CS.encounteredEnemies[enemyId] then
        CS.encounteredEnemies[enemyId] = true
        CS._saveToCloud()
        print("[CODEX] Encountered: " .. enemyId)
    end
end

--- 查询某个条目是否已解锁
---@param id string
---@return boolean
function CS.isUnlocked(id)
    -- 5个兵种始终解锁
    local alwaysUnlocked = { peasant=true, soldier=true, archer=true, healer=true }
    if alwaysUnlocked[id] then return true end
    return CS.encounteredEnemies[id] == true
end

-- ============================================================================
-- 云端存档
-- ============================================================================

function CS._saveToCloud()
    if not clientCloud then return end
    local data = {}
    for id, _ in pairs(CS.encounteredEnemies) do
        data[#data + 1] = id
    end
    local value = table.concat(data, ",")
    clientCloud:BatchSet()
        :Set("codex_enemies", value)
        :Save("图鉴进度", {
            ok = function() print("[CODEX] Saved") end,
            error = function(_, reason) print("[CODEX] Save error: " .. tostring(reason)) end,
        })
end

---@param callback? function
function CS.loadFromCloud(callback)
    if not clientCloud then
        CS.loaded = true
        if callback then callback() end
        return
    end
    clientCloud:BatchGet()
        :Key("codex_enemies")
        :Fetch({
            ok = function(values)
                local value = values.codex_enemies
                if value and value ~= "" then
                    CS.encounteredEnemies = {}
                    for id in string.gmatch(value, "[^,]+") do
                        CS.encounteredEnemies[id] = true
                    end
                end
                CS.loaded = true
                print("[CODEX] Loaded")
                if callback then callback() end
            end,
            error = function(_, reason)
                print("[CODEX] Load error: " .. tostring(reason))
                CS.loaded = true
                if callback then callback() end
            end,
        })
end

return CS
