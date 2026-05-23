-- ============================================================================
-- EventSystem.lua - 随机事件系统
-- ============================================================================

local GS = require("GameState")
local ConfigModule = require("Config")
local CONFIG = ConfigModule.CONFIG
local Utils = require("Utils")
local Entities = require("Entities")

local EventSystem = {}

local EVENT_DEFS = {
    {
        type = "resource_tide", name = "资源潮汐",
        desc = "地图中心出现大量资源！",
        duration = 0,  -- 一次性效果
        activate = function()
            local cx, cy = CONFIG.MapWidth / 2, CONFIG.MapHeight / 2
            local count = math.random(8, 12)
            for i = 1, count do
                local rx = cx + (math.random() - 0.5) * 400
                local ry = cy + (math.random() - 0.5) * 400
                rx = Utils.clamp(rx, 80, CONFIG.MapWidth - 80)
                ry = Utils.clamp(ry, 80, CONFIG.MapHeight - 80)
                if math.random() < 0.6 then
                    Entities.createResourceAt(rx, ry, "tree")
                else
                    Entities.createResourceAt(rx, ry, "mine")
                end
            end
        end,
    },
    {
        type = "blood_moon", name = "血月",
        desc = "所有战斗单位伤害+50%！",
        duration = 15,
        activate = function() GS.bloodMoonActive = true end,
        deactivate = function() GS.bloodMoonActive = false end,
    },
    {
        type = "fog", name = "迷雾",
        desc = "所有领主光环缩小30%！",
        duration = 20,
        activate = function() GS.fogActive = true end,
        deactivate = function() GS.fogActive = false end,
    },
}

function EventSystem.init()
    GS.eventTimer = 0
    GS.nextEventTime = math.random(60, 90)
    GS.activeEvent = nil
    GS.eventNotification = nil
    GS.bloodMoonActive = false
    GS.fogActive = false
end

function EventSystem.update(dt)
    -- 更新活跃事件倒计时
    if GS.activeEvent and GS.activeEvent.remaining > 0 then
        GS.activeEvent.remaining = GS.activeEvent.remaining - dt
        if GS.activeEvent.remaining <= 0 then
            if GS.activeEvent.deactivate then GS.activeEvent.deactivate() end
            GS.activeEvent = nil
        end
    end

    -- 通知淡出倒计时
    if GS.eventNotification then
        GS.eventNotification.timer = GS.eventNotification.timer - dt
        if GS.eventNotification.timer <= 0 then GS.eventNotification = nil end
    end

    -- 触发新事件
    GS.eventTimer = GS.eventTimer + dt
    if GS.eventTimer >= GS.nextEventTime then
        GS.eventTimer = 0
        GS.nextEventTime = math.random(60, 90)
        local def = EVENT_DEFS[math.random(1, #EVENT_DEFS)]
        def.activate()
        if def.duration > 0 then
            GS.activeEvent = {
                name = def.name, remaining = def.duration,
                deactivate = def.deactivate, type = def.type,
            }
        end
        GS.eventNotification = { text = def.name .. " — " .. def.desc, timer = 3.0 }
        print("[EVENT] " .. def.name .. " triggered!")
    end
end

return EventSystem
