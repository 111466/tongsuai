-- ============================================================================
-- Utils.lua - 工具函数
-- ============================================================================

local GS = require("GameState")

local Utils = {}

function Utils.dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function Utils.clamp(v, minV, maxV)
    return math.max(minV, math.min(maxV, v))
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.randomRange(a, b)
    return a + math.random() * (b - a)
end

function Utils.worldToScreen(wx, wy)
    local sx = (wx - GS.cameraX) + GS.screenW / 2
    local sy = (wy - GS.cameraY) + GS.screenH / 2
    return sx, sy
end

function Utils.screenToWorld(sx, sy)
    local wx = sx + GS.cameraX - GS.screenW / 2
    local wy = sy + GS.cameraY - GS.screenH / 2
    return wx, wy
end

function Utils.normalize(x, y)
    local len = math.sqrt(x * x + y * y)
    if len < 0.001 then return 0, 0 end
    return x / len, y / len
end

function Utils.isOnScreen(wx, wy, margin)
    margin = margin or 50
    local sx, sy = Utils.worldToScreen(wx, wy)
    return sx > -margin and sx < GS.screenW + margin and sy > -margin and sy < GS.screenH + margin
end

return Utils
