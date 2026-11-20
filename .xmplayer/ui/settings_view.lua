-- settings_view.lua
-- Renders the settings choice popup panel and manages its animation state.
-- Model data (options, groups, persistence) lives in settings.lua.

local theme                          = require("theme")
local assets                         = require("assets")
local utils                          = require("utils")
local settings                       = require("settings")
local ui                             = require("ui")
local viewport                       = require("viewport")

local settings_view                  = {}

-- Animation / interaction state
settings_view.active                 = false -- Is the popup open?
settings_view.alpha                  = 0     -- Fade-in progress (0-1)
settings_view.scroll_y               = 0
settings_view.target_scroll_y        = 0
settings_view.selected_option_idx    = 1

-- Folder picker state (compact picker for path options)
settings_view.picker_active          = false
settings_view.picker_alpha           = 0
settings_view.picker_items           = {}
settings_view.picker_selected_idx    = 1
settings_view.picker_current_path    = "/"
settings_view.picker_setting_idx     = nil
settings_view.picker_scroll_y        = 0
settings_view.picker_target_scroll_y = 0

-- Custom equalizer popup state
settings_view.eq_active              = false
settings_view.eq_alpha               = 0
settings_view.eq_selected_idx        = 1

local EQ_SLIDERS = {
    { id = "custom_eq_bass",   label = "Bass (Low Shelf)" },
    { id = "custom_eq_mid",    label = "Mid (Peaking/Bell)" },
    { id = "custom_eq_treble", label = "Treble (High Shelf)" },
    { id = "custom_eq_preamp", label = "Preamp / Master Output Gain" },
}

function settings_view.ensure_picker_visible()
    if not settings_view.picker_items or #settings_view.picker_items == 0 then
        settings_view.picker_target_scroll_y = 0
        return
    end
    local screen_w, screen_h = viewport.get()
    local panel_h = math.min(screen_h * 0.6, 420)
    local list_h = panel_h - 140 -- leave room for header + hints
    local item_h = 36
    local sel = settings_view.picker_selected_idx or 1
    local selected_y = (sel - 1) * item_h
    local desired_top = selected_y - (list_h / 2 - item_h / 2)
    local max_scroll = 0
    local min_scroll = math.min(0, -(#settings_view.picker_items * item_h) + list_h)
    local target = -desired_top
    if target > max_scroll then target = max_scroll end
    if target < min_scroll then target = min_scroll end
    settings_view.picker_target_scroll_y = target
end

function settings_view.update(dt, setting_idx)
    if settings_view.active then
        settings_view.alpha = math.min(1, settings_view.alpha + dt * 10)

        if setting_idx then
            local opt = settings.options[setting_idx]
            if opt and opt.choices then
                local item_h = 50
                local _, screen_h = viewport.get()
                local visible_area_h = screen_h * 0.6

                settings_view.target_scroll_y =
                    -(settings_view.selected_option_idx - 1) * item_h
                    + (visible_area_h / 2) - (item_h / 2)

                local max_scroll = 0
                local min_scroll = math.min(0, -(#opt.choices * item_h) + visible_area_h)
                settings_view.target_scroll_y =
                    math.max(min_scroll, math.min(max_scroll, settings_view.target_scroll_y))
            end
        end
    else
        settings_view.alpha = math.max(0, settings_view.alpha - dt * 10)
    end

    settings_view.scroll_y = utils.lerp(
        settings_view.scroll_y,
        settings_view.target_scroll_y or 0,
        dt * 10
    )

    -- Picker alpha / scroll smoothing
    if settings_view.picker_active then
        settings_view.picker_alpha = math.min(1, settings_view.picker_alpha + dt * 12)
    else
        settings_view.picker_alpha = math.max(0, settings_view.picker_alpha - dt * 12)
    end
    settings_view.picker_scroll_y = utils.lerp(settings_view.picker_scroll_y, settings_view.picker_target_scroll_y or 0,
        dt * 12)

    -- Equalizer popup alpha smoothing
    if settings_view.eq_active then
        settings_view.eq_alpha = math.min(1, settings_view.eq_alpha + dt * 12)
    else
        settings_view.eq_alpha = math.max(0, settings_view.eq_alpha - dt * 12)
    end
end

function settings_view.draw_popup(setting_idx)
    local opt = settings.options[setting_idx]
    if not opt or opt.type ~= "choice" or settings_view.alpha <= 0 then return end

    local screen_w, screen_h = viewport.get()
    local panel_w            = math.max(screen_w * 0.35, 220)
    local item_h             = 50
    local alpha              = settings_view.alpha
    local x                  = screen_w - (panel_w * alpha)
    local y                  = 0

    -- Panel background
    love.graphics.setColor(0.02, 0.02, 0.05, 0.92 * alpha)
    love.graphics.rectangle("fill", x, y, panel_w, screen_h)

    -- Left accent border
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.8 * alpha)
    love.graphics.rectangle("fill", x, y, 4, screen_h)

    local content_y_base = screen_h * 0.3
    local visible_area_h = screen_h * 0.6

    viewport.set_scissor(x, content_y_base, panel_w, visible_area_h)
    love.graphics.push()
    love.graphics.translate(0, content_y_base + settings_view.scroll_y)

    for i, choice in ipairs(opt.choices) do
        local cy          = (i - 1) * item_h
        local is_selected = (i == settings_view.selected_option_idx)
        local is_current  = (i == opt.value)

        if is_selected then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.3 * alpha)
            love.graphics.rectangle("fill", x + 4, cy - 5, panel_w - 4, item_h)

            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 1 * alpha)
            love.graphics.rectangle("fill", x + 4, cy - 5, 4, item_h)

            love.graphics.setColor(1, 1, 1, 1 * alpha)
        else
            love.graphics.setColor(1, 1, 1, 0.6 * alpha)
        end

        ui.print_text(choice, x + 40, cy + 5, assets.fonts.small, { 1, 1, 1, is_selected and 1 * alpha or 0.6 * alpha })

        if is_current then
            ui.draw_smooth_circle(x + 25, cy + item_h / 2 - 6, 4.25,
                { theme.accent[1], theme.accent[2], theme.accent[3], 1 * alpha })
        end
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- Scroll indicators
    if #opt.choices * item_h > visible_area_h then
        love.graphics.setColor(1, 1, 1, 0.3 * alpha)
        local centerX = x + panel_w / 2
        if settings_view.scroll_y < 0 then
            love.graphics.polygon("fill",
                centerX - 10, content_y_base - 14,
                centerX + 10, content_y_base - 14,
                centerX, content_y_base - 26)
        end
        if settings_view.scroll_y > -(#opt.choices * item_h) + visible_area_h then
            local targetY = content_y_base + visible_area_h + 14
            love.graphics.polygon("fill",
                centerX - 10, targetY,
                centerX + 10, targetY,
                centerX, targetY + 12)
        end
    end
end

-- Folder picker helpers
local function list_directories(path)
    local items = {}
    if not path or path == "" then path = "/" end
    local cmd = "find \"" .. path .. "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' -type d 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
        local out = handle:read("*a")
        handle:close()
        for line in out:gmatch("[^\r\n]+") do
            table.insert(items, { name = utils.get_filename(line), path = line })
        end
    end
    table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
    return items
end

function settings_view.open_folder_picker(initial_path, setting_idx)
    settings_view.picker_active = true
    settings_view.picker_setting_idx = setting_idx
    settings_view.picker_current_path = initial_path and initial_path ~= "" and initial_path or "/"
    settings_view.picker_items = {}
    -- Parent entry
    local parent = utils.get_dirname(settings_view.picker_current_path)
    if parent and parent ~= "" then
        table.insert(settings_view.picker_items, { name = "..", path = parent })
    end
    local dirs = list_directories(settings_view.picker_current_path)
    for _, d in ipairs(dirs) do table.insert(settings_view.picker_items, d) end
    settings_view.picker_selected_idx = 1
    settings_view.picker_target_scroll_y = 0
    settings_view.active = true -- ensure popup state is active so input is routed
    settings_view.ensure_picker_visible()
end

function settings_view.close_folder_picker()
    settings_view.picker_active = false
    settings_view.picker_items = {}
    settings_view.picker_selected_idx = 1
    settings_view.picker_setting_idx = nil
    settings_view.picker_current_path = "/"
    settings_view.picker_target_scroll_y = 0
    settings_view.active = false
end

function settings_view.draw_folder_picker()
    if settings_view.picker_alpha <= 0 then return end
    local screen_w, screen_h = viewport.get()
    local panel_w = screen_w * 0.75
    local panel_h = math.min(screen_h * 0.8, 420)
    local x = math.floor(screen_w / 2) - math.floor(panel_w / 2)
    local y = math.floor(screen_h / 2) - math.floor(panel_h / 2)
    local alpha = settings_view.picker_alpha

    love.graphics.setColor(0.02, 0.02, 0.05, 0.96 * alpha)
    love.graphics.rectangle("fill", x, y, panel_w, panel_h, 12, 12)
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35 * alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, panel_w, panel_h, 12, 12)

    ui.draw_glow_text("Select Folder", x + 20, y + 18, assets.fonts.main,
        { theme.light_text[1], theme.light_text[2], theme.light_text[3], alpha }, nil)

    ui.print_text(settings_view.picker_current_path, x + 20, y + 52, assets.fonts.xs, { 1, 1, 1, 0.6 * alpha })

    -- List area
    local list_x = x + 20
    local list_y = y + 92
    local list_h = panel_h - 140 -- reserve space for header + hints
    local item_h = 36

    viewport.set_scissor(list_x, list_y, panel_w - 40, list_h)
    love.graphics.push()
    love.graphics.translate(0, list_y + settings_view.picker_scroll_y)

    for i, it in ipairs(settings_view.picker_items) do
        local cy = (i - 1) * item_h
        local focused = (i == settings_view.picker_selected_idx)
        if focused then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.24 * alpha)
            love.graphics.rectangle("fill", list_x - 6, cy - 6, panel_w - 28, item_h, 6, 6)
            love.graphics.setColor(1, 1, 1, 1 * alpha)
        else
            love.graphics.setColor(1, 1, 1, 0.8 * alpha)
        end
        ui.print_text(it.name, list_x, cy, assets.fonts.small, { 1, 1, 1, focused and 1 * alpha or 0.8 * alpha })
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- Button hints at bottom
    local hint_y = y + panel_h - 40
    local hints = "A: Open    B: Back/Close    X: Set Current Folder"
    ui.print_text(hints, x + 20, hint_y, assets.fonts.xs, { 1, 1, 1, 0.85 * alpha })
end

function settings_view.open_equalizer_popup()
    settings_view.eq_active = true
    settings_view.eq_selected_idx = 1
    settings_view.active = true
end

function settings_view.close_equalizer_popup()
    settings_view.eq_active = false
    settings_view.eq_selected_idx = 1
    settings_view.active = false
end

function settings_view.reset_custom_equalizer()
    local changed = false
    for _, slider in ipairs(EQ_SLIDERS) do
        local opt = settings.get_option(slider.id)
        if opt and (tonumber(opt.value) or 0) ~= 0 then
            opt.value = 0
            changed = true
        end
    end
    if changed then
        settings.apply()
        settings.save()
    end
    return changed
end

function settings_view.navigate_equalizer(dir)
    if dir == "up" then
        local old_idx = settings_view.eq_selected_idx
        settings_view.eq_selected_idx = math.max(1, settings_view.eq_selected_idx - 1)
        return settings_view.eq_selected_idx ~= old_idx
    elseif dir == "down" then
        local old_idx = settings_view.eq_selected_idx
        settings_view.eq_selected_idx = math.min(#EQ_SLIDERS + 1, settings_view.eq_selected_idx + 1)
        return settings_view.eq_selected_idx ~= old_idx
    elseif dir == "left" or dir == "right" then
        local slider = EQ_SLIDERS[settings_view.eq_selected_idx]
        if not slider then return false end
        local opt = settings.get_option(slider.id)
        if not opt then return false end
        local cur = tonumber(opt.value) or 0
        local step = (dir == "right") and 0.5 or -0.5
        local next_val = math.max(-12, math.min(12, math.floor((cur + step) * 2 + 0.5) / 2))
        if next_val ~= cur then
            opt.value = next_val
            settings.apply()
            settings.save()
            return true
        end
    end
    return false
end

function settings_view.draw_equalizer_popup()
    if settings_view.eq_alpha <= 0 then return end
    local screen_w, screen_h = viewport.get()
    local panel_w = math.min(screen_w * 0.82, 540)
    local panel_h = math.min(screen_h * 0.84, 400)
    local x = math.floor((screen_w - panel_w) / 2)
    local y = math.floor((screen_h - panel_h) / 2)
    local alpha = settings_view.eq_alpha

    love.graphics.setColor(0.02, 0.02, 0.05, 0.96 * alpha)
    love.graphics.rectangle("fill", x, y, panel_w, panel_h, 12, 12)
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35 * alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, panel_w, panel_h, 12, 12)

    ui.draw_glow_text("Custom Equalizer", x + 22, y + 16, assets.fonts.main,
        { theme.light_text[1], theme.light_text[2], theme.light_text[3], alpha }, nil)

    love.graphics.setColor(1, 1, 1, 0.14 * alpha)
    love.graphics.rectangle("fill", x + 20, y + 54, panel_w - 40, 1)

    local row_h = 54
    local row_step = 58
    for i, slider in ipairs(EQ_SLIDERS) do
        local row_y = y + 64 + (i - 1) * row_step
        local focused = (settings_view.eq_selected_idx == i)
        local opt = settings.get_option(slider.id)
        local val = math.max(-12, math.min(12, tonumber(opt and opt.value) or 0))

        if focused then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.24 * alpha)
            love.graphics.rectangle("fill", x + 14, row_y, panel_w - 28, row_h, 8, 8)
        end

        local text_alpha = (focused and 1.0 or 0.8) * alpha
        ui.print_text(slider.label, x + 26, row_y + 4, assets.fonts.xs, { 1, 1, 1, text_alpha })

        local val_str = (math.abs(val) < 0.01) and "0.0 dB" or string.format("%+.1f dB", val)
        ui.printf_text(val_str, x + 26, row_y + 4, panel_w - 52, "right", assets.fonts.xs,
            { 1, 1, 1, (focused and 1.0 or 0.85) * alpha })

        local bar_x = x + 26
        local bar_y = row_y + 34
        local bar_w = panel_w - 52
        local bar_h = 8
        local center_x = bar_x + bar_w / 2

        -- Slider track
        love.graphics.setColor(1, 1, 1, 0.16 * alpha)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 4, 4)

        -- Active fill from 0 dB center
        local norm = val / 12
        local knob_x = center_x + norm * (bar_w / 2)
        if math.abs(norm) > 0.001 then
            local fill_x = math.min(center_x, knob_x)
            local fill_w = math.abs(knob_x - center_x)
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.9 * alpha)
            love.graphics.rectangle("fill", fill_x, bar_y, fill_w, bar_h, 3, 3)
        end

        -- 0 dB center tick mark
        love.graphics.setColor(1, 1, 1, 0.45 * alpha)
        love.graphics.rectangle("fill", center_x - 1, bar_y - 3, 2, bar_h + 6)

        -- Slider knob
        ui.draw_smooth_circle(knob_x, bar_y + bar_h / 2, focused and 6.5 or 5,
            { 1, 1, 1, (focused and 1.0 or 0.85) * alpha })
    end

    -- Reset Button
    local reset_focused = (settings_view.eq_selected_idx == #EQ_SLIDERS + 1)
    local btn_w, btn_h = 160, 36
    local btn_x = x + math.floor((panel_w - btn_w) / 2)
    local btn_y = y + 304

    if reset_focused then
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.42 * alpha)
        love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 8, 8)
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.95 * alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", btn_x, btn_y, btn_w, btn_h, 8, 8)
    else
        love.graphics.setColor(1, 1, 1, 0.10 * alpha)
        love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 8, 8)
        love.graphics.setColor(1, 1, 1, 0.25 * alpha)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", btn_x, btn_y, btn_w, btn_h, 8, 8)
    end
    love.graphics.setLineWidth(1)

    ui.printf_text("Reset", btn_x, btn_y + 4, btn_w, "center", assets.fonts.small,
        { 1, 1, 1, (reset_focused and 1.0 or 0.8) * alpha })

    -- Footer hints
    local hint_y = y + panel_h - 36
    local hints = reset_focused and "A: Reset Parameters   B: Close" or "Left/Right: Adjust    B: Close"
    ui.print_text(hints, x + 22, hint_y, assets.fonts.xs, { 1, 1, 1, 0.85 * alpha })
end

return settings_view
