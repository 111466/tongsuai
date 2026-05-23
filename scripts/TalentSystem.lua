-- ============================================================================
-- TalentSystem.lua — 三路线天赋树 + 声望点数系统
-- ============================================================================

local TS = {}

local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG

-- ============================================================================
-- 本地缓存
-- ============================================================================
local state = {
    reputation = 0,         -- 可用声望点数
    -- 每条路线已解锁的节点数（0-5）
    paths = {
        commander = 0,
        warfare = 0,
        economy = 0,
    },
}
local loaded = false

-- ============================================================================
-- 云端存取
-- ============================================================================

function TS.loadFromCloud(callback)
    if clientCloud then
        clientCloud:BatchGet()
            :Key("talent_data")
            :Fetch({
                ok = function(values)
                    local jsonStr = values.talent_data
                    if jsonStr and jsonStr ~= "" then
                        local ok, data = pcall(function() return require("cjson").decode(jsonStr) end)
                        if ok and data then
                            state.reputation = data.reputation or 0
                            if data.paths then
                                state.paths.commander = data.paths.commander or 0
                                state.paths.warfare = data.paths.warfare or 0
                                state.paths.economy = data.paths.economy or 0
                            end
                        end
                    end
                    loaded = true
                    print("[TS] Talent data loaded: rep=" .. state.reputation)
                    if callback then callback() end
                end,
                error = function(code, reason)
                    print("[TS] Talent load error: " .. tostring(reason))
                    loaded = true
                    if callback then callback() end
                end,
            })
    else
        loaded = true
        if callback then callback() end
    end
end

function TS.saveToCloud()
    if clientCloud then
        local jsonStr = require("cjson").encode({
            reputation = state.reputation,
            paths = state.paths,
        })
        clientCloud:BatchSet()
            :Set("talent_data", jsonStr)
            :Save("天赋进度", {
                ok = function() print("[TS] Talent data saved") end,
                error = function(_, reason) print("[TS] Talent save error: " .. tostring(reason)) end,
            })
    end
end

-- ============================================================================
-- 天赋操作
-- ============================================================================

--- 解锁路线的下一个节点
--- @param pathId string "commander"|"warfare"|"economy"
--- @return boolean success
--- @return string|nil errorMsg
function TS.unlockNext(pathId)
    local pathConfig = CONFIG.TalentPaths[pathId]
    if not pathConfig then return false, "无效路线" end

    local currentLevel = state.paths[pathId] or 0
    if currentLevel >= #pathConfig.nodes then return false, "已满级" end

    local nextNode = pathConfig.nodes[currentLevel + 1]
    if state.reputation < nextNode.cost then
        return false, "声望不足（需要 " .. nextNode.cost .. "，当前 " .. state.reputation .. "）"
    end

    state.reputation = state.reputation - nextNode.cost
    state.paths[pathId] = currentLevel + 1
    TS.saveToCloud()
    return true
end

--- 重置所有天赋（免费洗点），返还声望
function TS.resetAll()
    local refund = 0
    for pathId, level in pairs(state.paths) do
        local pathConfig = CONFIG.TalentPaths[pathId]
        if pathConfig then
            for i = 1, level do
                refund = refund + pathConfig.nodes[i].cost
            end
        end
        state.paths[pathId] = 0
    end
    state.reputation = state.reputation + refund
    TS.saveToCloud()
    return refund
end

--- 添加声望点数（关卡首通/无尽结算时调用）
function TS.addReputation(amount)
    state.reputation = state.reputation + amount
    TS.saveToCloud()
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function TS.isLoaded() return loaded end
function TS.getReputation() return state.reputation end

--- 获取路线当前解锁等级
function TS.getPathLevel(pathId)
    return state.paths[pathId] or 0
end

--- 获取路线配置
function TS.getPathConfig(pathId)
    return CONFIG.TalentPaths[pathId]
end

--- 获取下一个可解锁节点信息（或 nil 表示满级）
function TS.getNextNode(pathId)
    local pathConfig = CONFIG.TalentPaths[pathId]
    if not pathConfig then return nil end
    local level = state.paths[pathId] or 0
    if level >= #pathConfig.nodes then return nil end
    return pathConfig.nodes[level + 1]
end

--- 收集所有已解锁天赋的累积效果
--- @return table effects 合并后的效果表
function TS.getActiveEffects()
    local effects = {
        formationBuffMul = 1.0,
        unitCapBonus = 0,
        formationCdReduce = 0,
        atkMul = 1.0,
        critChance = 0,
        specialSlotReduce = 0,
        critDamageMul = 1.0,
        startResourceMul = 1.0,
        codexExpMul = 1.0,
        shopDiscount = 1.0,
    }

    for pathId, level in pairs(state.paths) do
        local pathConfig = CONFIG.TalentPaths[pathId]
        if pathConfig then
            for i = 1, level do
                local eff = pathConfig.nodes[i].effect
                -- 乘法类效果：叠乘
                if eff.formationBuffMul then effects.formationBuffMul = effects.formationBuffMul * eff.formationBuffMul end
                if eff.atkMul then effects.atkMul = effects.atkMul * eff.atkMul end
                if eff.critDamageMul then effects.critDamageMul = effects.critDamageMul * eff.critDamageMul end
                if eff.startResourceMul then effects.startResourceMul = effects.startResourceMul * eff.startResourceMul end
                if eff.codexExpMul then effects.codexExpMul = effects.codexExpMul * eff.codexExpMul end
                if eff.shopDiscount then effects.shopDiscount = effects.shopDiscount * eff.shopDiscount end
                -- 加法类效果：累加
                if eff.unitCapBonus then effects.unitCapBonus = effects.unitCapBonus + eff.unitCapBonus end
                if eff.formationCdReduce then effects.formationCdReduce = effects.formationCdReduce + eff.formationCdReduce end
                if eff.critChance then effects.critChance = effects.critChance + eff.critChance end
                if eff.specialSlotReduce then effects.specialSlotReduce = effects.specialSlotReduce + eff.specialSlotReduce end
            end
        end
    end

    return effects
end

--- 获取旧版兼容接口（Combat 等模块查询用）
function TS.getActiveTalent()
    return nil  -- 旧版单选天赋已废弃，各系统改为查询 getActiveEffects()
end

--- 旧版结算接口（保持向后兼容）
function TS.settleGame(won, currentGameTime)
    -- 新版不再通过 settleGame 发放声望，声望由 CampaignState/EndlessMode 发放
    -- 保持返回 0 避免调用方出错
    return 0
end

function TS.init(config)
    -- 保持旧接口兼容，新版无需传入 CONFIG（直接 require）
end

return TS
