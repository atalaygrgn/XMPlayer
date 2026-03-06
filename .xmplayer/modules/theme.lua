local theme = {}

-- Constant metrics
theme.font_size_main = 24
theme.font_size_small = 18
theme.icon_size = 64
theme.icon_spacing = 64

-- Color palettes
theme.accents = {
    Blue = {0.2, 0.4, 0.8},
    Red = {0.8, 0.2, 0.2},
    Green = {0.2, 0.7, 0.3},
    Teal = {0.2, 0.6, 0.6},
    Purple = {0.6, 0.3, 0.8},
    Yellow = {0.9, 0.8, 0.1},
    Orange = {0.9, 0.5, 0.1},
    Silver = {0.75, 0.75, 0.75},
    Black = {0.1, 0.1, 0.1},
    Beige = {0.96, 0.96, 0.86},
    Tan = {0.82, 0.71, 0.55}
}

theme.modes = {
    Light = {
        background = {0.92, 0.96, 1.0},
        text = {0.15, 0.15, 0.2},
        text_dim = {0.15, 0.15, 0.2, 0.6}
    },
    Dark = {
        background = {0.05, 0.05, 0.1},
        text = {0.95, 0.95, 1.0},
        text_dim = {0.95, 0.95, 1.0, 0.6}
    }
}

-- Current state (to be updated by settings)
theme.bg = {0.95, 0.95, 0.98, 1}
theme.text = {0.15, 0.15, 0.2, 1}
theme.text_dim = {0.15, 0.15, 0.2, 0.6}
theme.accent = {0.2, 0.4, 0.8, 1}
theme.colors = {
    background = {0.92, 0.96, 1.0},
    text = {0.15, 0.15, 0.2},
    shadow = {0, 0, 0, 0.15},
    highlight = {0, 0, 0, 0.1},
}

function theme.apply(mode, color_name)
    local m = theme.modes[mode] or theme.modes.Light
    local c = theme.accents[color_name] or theme.accents.Blue

    -- Blend accent color into background for a subtle tint
    local base = m.background
    local tint = (mode == "Dark") and 0.08 or 0.05
    local bg_tinted = {
        base[1] * (1 - tint) + c[1] * tint,
        base[2] * (1 - tint) + c[2] * tint,
        base[3] * (1 - tint) + c[3] * tint,
    }

    theme.colors.background = bg_tinted
    theme.colors.text = m.text
    theme.text = {m.text[1], m.text[2], m.text[3], 1}
    theme.text_dim = m.text_dim
    theme.accent = {c[1], c[2], c[3], 1}
    theme.bg = {bg_tinted[1], bg_tinted[2], bg_tinted[3], 1}
end

-- Initialize with defaults
theme.apply("Light", "Blue")

return theme
