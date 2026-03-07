local theme = {}

-- Constant metrics
theme.font_size_main = 24
theme.font_size_small = 18
theme.icon_size = 64
theme.icon_spacing = 64
theme.glow_intensity = 0.2  -- Higher = brighter glow
theme.glow_radius = 10        -- Higher = wider, softer glow
theme.shadow_intensity = 0.3 -- Shadow visibility
theme.current_mode = "Light" -- Track current mode

-- Color palettes
theme.accents = {
    Blue = {0.2, 0.4, 0.8},
    Red = {0.8, 0.2, 0.2},
    Green = {0.2, 0.7, 0.3},
    Teal = {0.2, 0.6, 0.6},
    Purple = {0.6, 0.3, 0.8},
    Yellow = {0.9, 0.8, 0.1},
    Orange = {0.9, 0.5, 0.1}
}

theme.modes = {
    Light = {
        background = {0.15, 0.15, 0.2}, -- Base intensity parameters
        text = {0.95, 0.95, 1.0},
        text_dim = {0.95, 0.95, 1.0, 0.6}
    },
    Dark = {
        background = {0.02, 0.02, 0.04},
        text = {0.95, 0.95, 1.0},
        text_dim = {0.95, 0.95, 1.0, 0.6}
    }
}

-- Current state (to be updated by settings)
theme.bg = {0.05, 0.05, 0.08, 1}
theme.text = {0.95, 0.95, 1.0, 1}
theme.text_dim = {0.95, 0.95, 1.0, 0.6}
theme.accent = {0.2, 0.4, 0.8, 1}
theme.colors = {
    background = {0.05, 0.05, 0.08},
    text = {0.95, 0.95, 1.0},
    shadow = {0, 0, 0, 0.15},
    highlight = {0, 0, 0, 0.1},
}

function theme.apply(mode, color_name)
    theme.current_mode = mode
    local m = theme.modes[mode] or theme.modes.Light
    local c = theme.accents[color_name] or theme.accents.Blue

    -- Calculate a background tint that resembles the color but stays dark
    local bg_tinted
    if mode == "Light" then
        -- Richer color background, vibrant but dark enough for white icons
        local color_weight = 0.25
        local base_weight = 0.1
        bg_tinted = {
            c[1] * color_weight + m.background[1] * base_weight,
            c[2] * color_weight + m.background[2] * base_weight,
            c[3] * color_weight + m.background[3] * base_weight,
        }
    else
        -- Deep, dark tinted background
        local color_weight = 0.06
        bg_tinted = {
            m.background[1] + c[1] * color_weight,
            m.background[2] + c[2] * color_weight,
            m.background[3] + c[3] * color_weight,
        }
    end

    theme.colors.background = bg_tinted
    theme.colors.text = m.text
    theme.text = {m.text[1], m.text[2], m.text[3], 1}
    theme.text_dim = m.text_dim
    theme.accent = {c[1], c[2], c[3], 1}
    theme.bg = {bg_tinted[1], bg_tinted[2], bg_tinted[3], 1}
end

return theme
