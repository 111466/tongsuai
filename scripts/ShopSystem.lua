-- ============================================================================
-- ShopSystem.lua — 无尽模式商店（商品池、刷新、购买）
-- ============================================================================
local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Entities = require("Entities")
local EndlessMode -- lazy-loaded to break circular dep

local Shop = {}

-- =========================================================================
-- 商品池定义
-- =========================================================================

-- 每个商品: { id, name, desc, cost, tier, apply(playerLord) }
-- tier: "normal" | "rare" | "legendary"

local ALL_ITEMS = {
    -- ===== 普通 (每波可出) =====
    {
        id = "recruit_soldiers_3", name = "补充 3 个士兵",
        desc = "立即招募 3 个士兵", cost = 15, tier = "normal",
        apply = function(lord)
            for i = 1, 3 do Entities.createFollower(lord, "soldier") end
        end,
    },
    {
        id = "heal_all_20", name = "全军回复 20%",
        desc = "所有随从回复 20% 生命", cost = 10, tier = "normal",
        apply = function(lord)
            for _, f in ipairs(GS.followers) do
                if f.lordId == lord.id and f.alive then
                    f.hp = math.min(f.maxHp, f.hp + math.floor(f.maxHp * 0.2))
                end
            end
        end,
    },
    {
        id = "temp_atk_10", name = "攻击 +10%（3 波）",
        desc = "全军攻击临时提升 10%", cost = 12, tier = "normal",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "atkMul", value = 1.1, remaining = 3, permanent = false,
            })
        end,
    },
    {
        id = "recruit_archers_2", name = "补充 2 个弓箭手",
        desc = "立即招募 2 个弓箭手", cost = 18, tier = "normal",
        apply = function(lord)
            for i = 1, 2 do Entities.createFollower(lord, "archer") end
        end,
    },
    {
        id = "recruit_knights_2", name = "补充 2 个骑士",
        desc = "立即招募 2 个骑士", cost = 20, tier = "normal",
        apply = function(lord)
            for i = 1, 2 do Entities.createFollower(lord, "knight") end
        end,
    },
    {
        id = "lord_heal_full", name = "领主满血恢复",
        desc = "领主生命值完全回满", cost = 8, tier = "normal",
        apply = function(lord)
            lord.hp = lord.maxHp
        end,
    },
    -- ===== 稀有 (每 5 波新增) =====
    {
        id = "recruit_special_1", name = "招募 1 个特殊兵种",
        desc = "随机招募一个圣骑/刺客/鼓手", cost = 30, tier = "rare",
        apply = function(lord)
            local specials = { "paladin", "assassin", "drummer" }
            local pick = specials[math.random(1, #specials)]
            Entities.createFollower(lord, pick)
        end,
    },
    {
        id = "armor_20_perm", name = "全军护甲 +20%（永久）",
        desc = "本局剩余所有波次生效", cost = 35, tier = "rare",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "armorMul", value = 0.8, remaining = 999, permanent = true,
            })
        end,
    },

    {
        id = "heal_all_50", name = "全军回复 50%",
        desc = "所有随从回复 50% 生命", cost = 28, tier = "rare",
        apply = function(lord)
            for _, f in ipairs(GS.followers) do
                if f.lordId == lord.id and f.alive then
                    f.hp = math.min(f.maxHp, f.hp + math.floor(f.maxHp * 0.5))
                end
            end
        end,
    },
    -- ===== 传说 (每 10 波新增) =====
    {
        id = "capacity_5", name = "编制上限 +5",
        desc = "永久增加可带兵数量", cost = 50, tier = "legendary",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "unitCapBonus", value = 5, remaining = 999, permanent = true,
            })
        end,
    },
    {
        id = "formation_double_5", name = "阵型加成翻倍（5 波）",
        desc = "所有阵型效果翻倍", cost = 45, tier = "legendary",
        apply = function(lord)
            table.insert(GS.endlessBuffs, {
                type = "formationBuffMul", value = 2.0, remaining = 5, permanent = false,
            })
        end,
    },
    {
        id = "skill_cd_reset", name = "技能冷却清零",
        desc = "所有领主技能立即可用", cost = 40, tier = "legendary",
        apply = function(lord)
            for k, _ in pairs(GS.skillCooldowns) do
                GS.skillCooldowns[k] = 0
            end
        end,
    },
}

-- =========================================================================
-- 状态
-- =========================================================================
local currentItems = {}   -- 当前展示的 4 件商品

-- =========================================================================
-- 刷新
-- =========================================================================

--- 按波次刷新商店（每波 4 件）
function Shop.refresh(wave)
    local pool = {}
    for _, item in ipairs(ALL_ITEMS) do
        if item.tier == "normal" then
            table.insert(pool, item)
        elseif item.tier == "rare" and wave >= 5 then
            table.insert(pool, item)
        elseif item.tier == "legendary" and wave >= 10 then
            table.insert(pool, item)
        end
    end

    -- 天赋折扣（shopDiscount 为乘数：0.90 表示打九折，即付原价的 90%）
    local talentEffects = require("TalentSystem").getActiveEffects()
    local discountMul = talentEffects.shopDiscount or 1.0

    -- 随机抽取 4 件（不重复）
    currentItems = {}
    local poolCopy = {}
    for i, v in ipairs(pool) do poolCopy[i] = v end

    local pickCount = math.min(4, #poolCopy)
    for i = 1, pickCount do
        local idx = math.random(1, #poolCopy)
        local item = poolCopy[idx]
        -- 应用折扣（直接乘以折扣乘数）
        local finalCost = math.max(1, math.floor(item.cost * discountMul))
        table.insert(currentItems, {
            id = item.id,
            name = item.name,
            desc = item.desc,
            cost = finalCost,
            tier = item.tier,
            apply = item.apply,
        })
        table.remove(poolCopy, idx)
    end
end

-- =========================================================================
-- 购买
-- =========================================================================

--- 购买商品（index: 1-4）
function Shop.buy(index)
    EndlessMode = EndlessMode or require("EndlessMode")
    local item = currentItems[index]
    if not item then
        print("[SHOP] Invalid item index: " .. tostring(index))
        return false
    end
    if not EndlessMode.spendCoins(item.cost) then
        print("[SHOP] Not enough war coins (" .. GS.endlessWarCoins .. " < " .. item.cost .. ")")
        return false
    end

    -- 找到玩家领主
    local playerLord = GS.lords[1]
    if playerLord and playerLord.alive then
        item.apply(playerLord)
    end

    -- 移除已购买商品
    table.remove(currentItems, index)
    print("[SHOP] Bought: " .. item.name)
    return true
end

-- =========================================================================
-- 查询
-- =========================================================================

--- 获取当前商店商品列表（UI 用）
function Shop.getItems()
    local result = {}
    for i, item in ipairs(currentItems) do
        result[i] = {
            id = item.id,
            name = item.name,
            desc = item.desc,
            cost = item.cost,
            tier = item.tier,
        }
    end
    return result
end

--- 获取无尽模式 buff 的攻击倍率（Combat.lua 调用）
function Shop.getEndlessAtkMul()
    local mul = 1.0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "atkMul" and buff.remaining > 0 then
            mul = mul * buff.value
        end
    end
    return mul
end

--- 获取无尽模式 buff 的护甲倍率（Combat.lua 调用）
function Shop.getEndlessArmorMul()
    local mul = 1.0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "armorMul" and buff.remaining > 0 then
            mul = mul * buff.value
        end
    end
    return mul
end

--- 获取阵型加成倍率（FormationSystem 调用）
function Shop.getEndlessFormationMul()
    local mul = 1.0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "formationBuffMul" and buff.remaining > 0 then
            mul = mul * buff.value
        end
    end
    return mul
end

--- 获取编制上限加成（Entities/UI 调用）
function Shop.getEndlessCapBonus()
    local bonus = 0
    for _, buff in ipairs(GS.endlessBuffs) do
        if buff.type == "unitCapBonus" and buff.remaining > 0 then
            bonus = bonus + buff.value
        end
    end
    return bonus
end

--- 波次结束时递减临时 buff 计数器
function Shop.tickBuffs()
    for i = #GS.endlessBuffs, 1, -1 do
        local buff = GS.endlessBuffs[i]
        if not buff.permanent then
            buff.remaining = buff.remaining - 1
            if buff.remaining <= 0 then
                table.remove(GS.endlessBuffs, i)
            end
        end
    end
end

return Shop
