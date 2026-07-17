local assets = require("assets")
local theme = require("theme")
local ui = require("ui")
local utils = require("utils")
local viewport = require("viewport")

local keyboard = {
    active = false,
    closing = false,
    closed_at = 0,
    pending_callback = nil,
    pending_args = nil,
    title = "Enter Text",
    value = "",
    max_length = 40,
    caps_on = false,
    selected_row = 1,
    selected_col = 1,
    on_submit = nil,
    on_cancel = nil,
    opened_at = 0,
}

local rows = {
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
    { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
    { "a", "s", "d", "f", "g", "h", "j", "k", "l", "del" },
    { "z", "x", "c", "v", "b", "n", "m", ",", ".", "-" },
}

local caps_number_map = {
    ["1"] = "?",
    ["2"] = ":",
    ["3"] = "/",
    ["4"] = "@",
    ["5"] = "#",
    ["6"] = "$",
    ["7"] = "%",
    ["8"] = "=",
    ["9"] = "&",
    ["0"] = "*",
}

local function is_letter(key)
    return type(key) == "string" and key:match("^[a-z]$") ~= nil
end

local function key_label(key)
    if key == "del" then
        return "del"
    end
    if keyboard.caps_on and caps_number_map[key] then
        return caps_number_map[key]
    end
    if is_letter(key) and keyboard.caps_on then
        return key:upper()
    end
    return key
end

local function selected_key()
    local row = rows[keyboard.selected_row]
    if not row then return nil end
    return row[keyboard.selected_col]
end

local function clamp_selection()
    local row = rows[keyboard.selected_row]
    if not row then
        keyboard.selected_row = 1
        keyboard.selected_col = 1
        return
    end

    if keyboard.selected_col > #row then
        keyboard.selected_col = #row
    end
    if keyboard.selected_col < 1 then
        keyboard.selected_col = 1
    end
end

local function apply_key(key)
    if not key then return end

    if key == "SPACE" then
        if #keyboard.value < keyboard.max_length then
            keyboard.value = keyboard.value .. " "
        end
    elseif key == "del" then
        if #keyboard.value > 0 then
            keyboard.value = keyboard.value:sub(1, -2)
        end
    elseif key == "CAPS" then
        keyboard.caps_on = not keyboard.caps_on
    elseif key == "CANCEL" then
        local cb = keyboard.on_cancel
        keyboard.on_submit = nil
        keyboard.on_cancel = nil
        keyboard.closing = true
        keyboard.closed_at = love.timer.getTime()
        keyboard.pending_callback = cb
        keyboard.pending_args = nil
    elseif key == "DONE" then
        local cb = keyboard.on_submit
        local text = utils.trim(keyboard.value)
        keyboard.on_submit = nil
        keyboard.on_cancel = nil
        keyboard.closing = true
        keyboard.closed_at = love.timer.getTime()
        keyboard.pending_callback = cb
        keyboard.pending_args = text
    else
        if keyboard.caps_on and caps_number_map[key] then
            key = caps_number_map[key]
        end
        if is_letter(key) and keyboard.caps_on then
            key = key:upper()
        end
        if #keyboard.value < keyboard.max_length then
            keyboard.value = keyboard.value .. key
        end
    end
end

function keyboard.open(opts)
    opts = opts or {}
    keyboard.active = true
    keyboard.closing = false
    keyboard.closed_at = 0
    keyboard.pending_callback = nil
    keyboard.pending_args = nil
    keyboard.title = opts.title or "Enter Text"
    keyboard.value = opts.value or ""
    keyboard.max_length = opts.max_length or 40
    keyboard.caps_on = false
    keyboard.selected_row = 1
    keyboard.selected_col = 1
    keyboard.on_submit = opts.on_submit
    keyboard.on_cancel = opts.on_cancel
    keyboard.opened_at = love.timer.getTime()
end

function keyboard.is_active()
    return keyboard.active
end

function keyboard.update(dt)
    if not keyboard.active then return end

    if keyboard.closing then
        if love.timer.getTime() - keyboard.closed_at >= 0.18 then
            local cb = keyboard.pending_callback
            local args = keyboard.pending_args
            keyboard.active = false
            keyboard.closing = false
            keyboard.pending_callback = nil
            keyboard.pending_args = nil
            if cb then
                cb(args)
            end
        end
    end
end

function keyboard.keypressed(key)
    if not keyboard.active then return false end
    if keyboard.closing then return true end

    if key == "left" then
        keyboard.selected_col = keyboard.selected_col - 1
        if keyboard.selected_col < 1 then
            keyboard.selected_col = #rows[keyboard.selected_row]
        end
        clamp_selection()
        return true
    end

    if key == "right" then
        keyboard.selected_col = keyboard.selected_col + 1
        if keyboard.selected_col > #rows[keyboard.selected_row] then
            keyboard.selected_col = 1
        end
        clamp_selection()
        return true
    end

    if key == "up" then
        keyboard.selected_row = keyboard.selected_row - 1
        if keyboard.selected_row < 1 then
            keyboard.selected_row = #rows
        end
        clamp_selection()
        return true
    end

    if key == "down" then
        keyboard.selected_row = keyboard.selected_row + 1
        if keyboard.selected_row > #rows then
            keyboard.selected_row = 1
        end
        clamp_selection()
        return true
    end

    if key == "return" then -- A button
        apply_key(selected_key())
        return true
    end

    if key == "backspace" or key == "b" then -- B button
        apply_key("del")
        return true
    end

    if key == "x" then -- X button
        apply_key("CANCEL")
        return true
    end

    if key == "z" then -- Start button
        apply_key("DONE")
        return true
    end

    if key == "y" then -- Y button
        apply_key("SPACE")
        return true
    end

    if key == "pageup" or key == "pagedown" then -- L1/R1 buttons
        apply_key("CAPS")
        return true
    end

    return true
end

function keyboard.draw()
    if not keyboard.active then return end

    local screen_w, screen_h = viewport.get()
    local fade
    if keyboard.closing then
        local elapsed = love.timer.getTime() - keyboard.closed_at
        fade = math.max(0, math.min(1, 1 - (elapsed / 0.18)))
    else
        fade = math.max(0, math.min(1, (love.timer.getTime() - keyboard.opened_at) / 0.18))
    end
    local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4.5)
    local panel_alpha = 0.95 * fade
    local shadow_alpha = 0.22 * fade

    love.graphics.setColor(0, 0, 0, 0.55 * fade)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)

    local panel_w = screen_w * 0.9
    local panel_h = math.min(screen_h * 0.88, 400)
    local panel_x = (screen_w - panel_w) / 2
    local panel_y = (screen_h - panel_h) / 2

    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.rectangle("fill", panel_x + 4, panel_y + 5, panel_w, panel_h, 16, 16)

    love.graphics.setColor(0.66, 0.74, 0.78, panel_alpha)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 16, 16)

    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35 * fade)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 16, 16)

    local title_font = assets.fonts.main
    ui.draw_glow_text(keyboard.title, panel_x + 26, panel_y + 20, title_font,
        { theme.text[1], theme.text[2], theme.text[3], 0.95 * fade }, nil)

    local input_x = panel_x + 26
    local input_y = panel_y + 64
    local input_w = panel_w - 52
    local input_h = 58

    love.graphics.setColor(0, 0, 0, 0.18 * fade)
    love.graphics.rectangle("fill", input_x + 3, input_y + 4, input_w, input_h, 10, 10)

    love.graphics.setColor(0.1, 0.11, 0.16, 0.92 * fade)
    love.graphics.rectangle("fill", input_x, input_y, input_w, input_h, 10, 10)
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.25 * fade)
    love.graphics.rectangle("line", input_x, input_y, input_w, input_h, 10, 10)

    local shown_value = keyboard.value
    local placeholder = "(enter playlist name)"
    if keyboard.title and string.find(keyboard.title:lower(), "watchlist") then
        placeholder = "(enter watchlist name)"
    end

    if shown_value == "" then
        shown_value = placeholder
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.45 * fade)
    else
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.95 * fade)
    end
    ui.print_text(shown_value, input_x + 14, input_y + 15, assets.fonts.small,
        shown_value == placeholder and { theme.text[1], theme.text[2], theme.text[3], 0.45 * fade } or
        { theme.text[1], theme.text[2], theme.text[3], 0.95 * fade })

    -- Blinking cursor
    if not keyboard.closing and (love.timer.getTime() % 1.0) < 0.5 then
        local text_w = 0
        if keyboard.value ~= "" then
            text_w = ui.measure_text_width(assets.fonts.small, keyboard.value)
        end
        local cursor_x = input_x + 14 + text_w
        local cursor_y = input_y + 15
        local cursor_h = ui.measure_text_height(assets.fonts.small)
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.95 * fade)
        love.graphics.rectangle("fill", cursor_x, cursor_y + 2, 2, cursor_h - 4)
    end

    local start_y = input_y + input_h + 22
    local row_h = 56
    local key_h = 36

    for row_idx, row in ipairs(rows) do
        local y = start_y + (row_idx - 1) * row_h
        local key_gap = 8
        local key_w = math.floor((panel_w - 52 - ((#row - 1) * key_gap)) / #row)
        local x = panel_x + 26

        for col_idx, key_name in ipairs(row) do
            local focused = (keyboard.selected_row == row_idx and keyboard.selected_col == col_idx)
            local label = key_label(key_name)
            local key_shadow_alpha = (focused and (0.22 + 0.1 * pulse) or 0.14) * fade
            local key_fill_alpha = (focused and (0.96 + 0.02 * pulse) or 0.82) * fade
            local label_alpha = (focused and 1 or 0.85) * fade

            love.graphics.setColor(0, 0, 0, key_shadow_alpha)
            love.graphics.rectangle("fill", x + 2, y + 3, key_w, key_h, 3, 3)

            if focused then
                love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], (0.22 + 0.18 * pulse) * fade)
                love.graphics.rectangle("fill", x - 2, y - 2, key_w + 4, key_h + 4, 6, 6)
                local r = 0.83 - 0.10 * pulse
                local g = 0.84 - 0.10 * pulse
                local b = 0.85 - 0.10 * pulse
                love.graphics.setColor(r, g, b, key_fill_alpha)
                love.graphics.rectangle("fill", x, y, key_w, key_h, 3, 3)
            else
                love.graphics.setColor(0.93, 0.94, 0.95, key_fill_alpha)
                love.graphics.rectangle("fill", x, y, key_w, key_h, 3, 3)
            end

            if key_name == "CAPS" and keyboard.caps_on then
                love.graphics.setColor(0.83, 0.84, 0.85, 0.5 * fade)
                love.graphics.rectangle("fill", x + 2, y + 2, key_w - 4, key_h - 4, 8, 8)
            end

            love.graphics.setColor(0.19, 0.41, 0.58, label_alpha)
            ui.printf_text(label, x, y + 10, key_w, "center", assets.fonts.keyboardkey, { 0.19, 0.41, 0.58, label_alpha })

            x = x + key_w + key_gap
        end
    end

    -- Button hint bar
    local hints = {
        { btn = "(B)",   action = "Back" },
        { btn = "(Y)",   action = "Space" },
        { btn = "(X)",   action = "Cancel" },
        { btn = "L/R",   action = "Shift" },
        { btn = "Start", action = "Done" },
    }

    local hint_y = panel_y + panel_h - 28
    local hint_font = assets.fonts.xs
    local sep_y = hint_y - 10
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.12 * fade)
    love.graphics.setLineWidth(1)
    love.graphics.line(panel_x + 16, sep_y, panel_x + panel_w - 16, sep_y)

    local total_hints = #hints
    local hint_spacing = (panel_w - 52) / total_hints
    for i, h in ipairs(hints) do
        local hx = panel_x + 26 + (i - 1) * hint_spacing
        -- Button label (accent coloured)
        ui.print_text(h.btn, hx, hint_y, hint_font,
            { theme.accent[1], theme.accent[2], theme.accent[3], 0.85 * fade })
        local btn_w = ui.measure_text_width(hint_font, h.btn)
        -- Action label (muted white)
        ui.print_text(h.action, hx + btn_w + 4, hint_y, hint_font,
            { theme.text[1], theme.text[2], theme.text[3], 0.55 * fade })
    end
end

return keyboard
