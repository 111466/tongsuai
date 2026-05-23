-- scripts/MenuTheme.lua
-- 共享视觉主题常量，供所有菜单界面引用

local T = {}

T.colors = {
    primary       = {70, 160, 255, 255},
    accent        = {255, 150, 30, 255},
    accentDark    = {235, 120, 10, 255},
    success       = {80, 200, 100, 255},
    danger        = {255, 90, 70, 255},
    gold          = {255, 210, 60, 255},
    cardBg        = {255, 252, 245, 230},
    overlay       = {30, 35, 60, 200},
    textPrimary   = {50, 50, 60, 255},
    textSecondary = {130, 135, 150, 255},
    textOnDark    = {255, 255, 255, 255},
}

T.radius = { lg = 16, md = 12, sm = 8, pill = 24 }

T.shadow = {{ x=0, y=4, blur=12, spread=0, color={0,0,0,30} }}

T.fontSize = { title = 22, subtitle = 16, body = 13, small = 11, cta = 18 }

return T
