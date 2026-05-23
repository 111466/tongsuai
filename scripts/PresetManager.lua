-- ============================================================================
-- PresetManager.lua — 编队预设保存/加载/管理（5 个槽位）
-- ============================================================================

local PM = {}

local MAX_PRESETS = 5

-- 本地缓存
local presets = {}  -- [1..5] = { name, units, formation, squad } or nil
local loaded = false

-- ============================================================================
-- 云端存取
-- ============================================================================

function PM.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("presets_data")
            :Fetch({
                ok = function(values)
                    local jsonStr = values.presets_data
                    if jsonStr and jsonStr ~= "" then
                        local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
                        if ok and data then
                            -- cjson 可能把数组 key 1..5 序列化为字符串 key
                            for i = 1, MAX_PRESETS do
                                presets[i] = data[tostring(i)] or data[i] or nil
                            end
                        end
                    end
                    loaded = true
                    print("[PM] Presets loaded")
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[PM] Presets load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function PM.saveToCloud()
    if clientCloud then
        local jsonStr = require("cjson").encode(presets)
        clientCloud:BatchSet()
            :Set("presets_data", jsonStr)
            :Save("编队预设", {
                ok = function() print("[PM] Presets saved") end,
                error = function(_, reason) print("[PM] Presets save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 预设操作
-- ============================================================================

--- 保存预设到指定槽位
--- @param slot number 1-5
--- @param preset table { name=string, units={type=count,...}, formation=string|nil, squad={formation=string|nil, units={type=count,...}}|nil }
function PM.save(slot, preset)
    if slot < 1 or slot > MAX_PRESETS then return false end
    presets[slot] = {
        name = preset.name or ("预设" .. slot),
        units = preset.units or {},
        formation = preset.formation,
        squad = preset.squad,
    }
    PM.saveToCloud()
    return true
end

--- 加载指定槽位的预设
--- @param slot number 1-5
--- @return table|nil preset
function PM.load(slot)
    return presets[slot]
end

--- 删除指定槽位
function PM.delete(slot)
    if slot < 1 or slot > MAX_PRESETS then return end
    presets[slot] = nil
    PM.saveToCloud()
end

--- 重命名指定槽位
function PM.rename(slot, newName)
    if presets[slot] then
        presets[slot].name = newName
        PM.saveToCloud()
    end
end

--- 获取所有槽位概要
function PM.listAll()
    local result = {}
    for i = 1, MAX_PRESETS do
        if presets[i] then
            result[i] = { name = presets[i].name, hasData = true }
        else
            result[i] = { name = "空槽位", hasData = false }
        end
    end
    return result
end

function PM.isLoaded() return loaded end
function PM.getMaxSlots() return MAX_PRESETS end

return PM
