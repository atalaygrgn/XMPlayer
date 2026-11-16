local theme = {}

-- Constant metrics
theme.font_size_main = 24
theme.font_size_small = 18
theme.icon_size = 64
theme.icon_spacing = 64
theme.glow_intensity = 0.3   -- Higher = brighter glow
theme.glow_radius = 3        -- Higher = wider, softer glow
theme.shadow_intensity = 0.5 -- Shadow visibility
theme.current_mode = "Light" -- Track current mode
theme.current_fg = "Light"   -- Track current foreground color ("Light" or "Dark")

-- Color palettes
theme.accents = {
    ["Electric Blue"] = { 0.0, 0.6, 1.0 },
    ["Apple Green"] = { 0.5, 0.9, 0.1 },
    ["Undersea"] = { 0.0, 0.4, 0.5 },
    ["Volcanic"] = { 0.9, 0.3, 0.1 },
    ["Dark Red"] = { 0.6, 0.0, 0.0 },
    ["Dark Purple"] = { 0.4, 0.1, 0.6 },
    ["Moss Green"] = { 0.4, 0.5, 0.2 },
    ["Golden"] = { 1.0, 0.8, 0.2 },
    ["Midnight Blue"] = { 0.1, 0.2, 0.4 },
    ["Morning Blue"] = { 0.6, 0.8, 0.9 },
    ["Lime Green"] = { 0.8, 1.0, 0.0 },
    ["Ice Cold"] = { 0.7, 0.9, 1.0 },
    ["Gray Dark"] = { 0.3, 0.3, 0.3 },
    ["Gray Light"] = { 0.7, 0.7, 0.7 }
}

theme.modes = {
    Light = {
        background = { 0.5, 0.5, 0.6 }, -- Base intensity parameters
        text = { 0.95, 0.95, 1.0 },
        text_dim = { 0.95, 0.95, 1.0, 0.6 }
    },
    Dark = {
        background = { 0.02, 0.02, 0.04 },
        text = { 0.95, 0.95, 1.0 },
        text_dim = { 0.95, 0.95, 1.0, 0.6 }
    }
}

theme.foregrounds = {
    Light = {
        text = { 0.95, 0.95, 1.0 },
        text_dim = { 0.95, 0.95, 1.0, 0.6 }
    },
    Dark = {
        text = { 0.0, 0.0, 0.0 },
        text_dim = { 0.0, 0.0, 0.0, 0.6 }
    }
}

-- Current state (to be updated by settings)
theme.bg = { 0.05, 0.05, 0.08, 1 }
theme.light_text = { 0.95, 0.95, 1.0, 1 }
theme.text = { 0.95, 0.95, 1.0, 1 }
theme.text_dim = { 0.95, 0.95, 1.0, 0.6 }
theme.accent = { 0.2, 0.4, 0.8, 1 }
theme.colors = {
    background = { 0.05, 0.05, 0.08 },
    text = { 0.95, 0.95, 1.0 },
    shadow = { 0, 0, 0, 0.15 },
    highlight = { 0, 0, 0, 0.1 },
}

function theme.apply(mode, color_name, fg_mode)
    theme.current_mode = mode
    fg_mode = fg_mode or theme.current_fg or "Light"
    theme.current_fg = fg_mode

    local m = theme.modes[mode] or theme.modes.Light
    local c = theme.accents[color_name] or theme.accents["Golden"]
    local fg = theme.foregrounds[fg_mode] or theme.foregrounds.Light

    -- Calculate a background tint that is much more vivid in Light mode
    local bg_tinted
    if mode == "Light" then
        -- High color weight for vividness, kept dark enough for white icons/text
        local color_weight = 0.5
        bg_tinted = {
            c[1] * color_weight,
            c[2] * color_weight,
            c[3] * color_weight,
        }
    else
        -- Deep, dark tinted background for Dark mode
        local color_weight = 0.12
        bg_tinted = {
            m.background[1] + c[1] * color_weight,
            m.background[2] + c[2] * color_weight,
            m.background[3] + c[3] * color_weight,
        }
    end

    theme.colors.background = bg_tinted
    theme.colors.text = fg.text
    theme.light_text = { 0.95, 0.95, 1.0, 1 }
    theme.text = { fg.text[1], fg.text[2], fg.text[3], 1 }
    theme.text_dim = { fg.text_dim[1], fg.text_dim[2], fg.text_dim[3], fg.text_dim[4] }
    theme.accent = { c[1], c[2], c[3], 1 }
    theme.bg = { bg_tinted[1], bg_tinted[2], bg_tinted[3], 1 }
end

return theme
