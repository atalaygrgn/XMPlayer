local assets = require("assets")
local theme = require("theme")
local ui = require("ui")
local utils = require("utils")

local keyboard = {
    active = false,
    title = "Enter Text",
    value = "",
    max_length = 40,
    caps_on = false,
    selected_row = 1,
    selected_col = 1,
    on_submit = nil,
    on_cancel = nil,
}

local rows = {
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
    { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
    { "a", "s", "d", "f", "g", "h", "j", "k", "l", "<-" },
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
    if key == "<-" then
        return "<-"
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
    elseif key == "<-" then
        if #keyboard.value > 0 then
            keyboard.value = keyboard.value:sub(1, -2)
        end
    elseif key == "CAPS" then
        keyboard.caps_on = not keyboard.caps_on
    elseif key == "CANCEL" then
        local cb = keyboard.on_cancel
        keyboard.active = false
        keyboard.on_submit = nil
        keyboard.on_cancel = nil
        if cb then cb() end
    elseif key == "DONE" then
        local cb = keyboard.on_submit
        local text = utils.trim(keyboard.value)
        keyboard.active = false
        keyboard.on_submit = nil
        keyboard.on_cancel = nil
        if cb then cb(text) end
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
    keyboard.title = opts.title or "Enter Text"
    keyboard.value = opts.value or ""
    keyboard.max_length = opts.max_length or 40
    keyboard.caps_on = false
    keyboard.selected_row = 1
    keyboard.selected_col = 1
    keyboard.on_submit = opts.on_submit
    keyboard.on_cancel = opts.on_cancel
end

function keyboard.is_active()
    return keyboard.active
end

function keyboard.keypressed(key)
    if not keyboard.active then return false end

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
        apply_key("<-")
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

    local screen_w, screen_h = love.graphics.getDimensions()

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)

    local panel_w = screen_w * 0.9
    local panel_h = screen_h * 0.8
    local panel_x = (screen_w - panel_w) / 2
    local panel_y = (screen_h - panel_h) / 2

    love.graphics.setColor(0.06, 0.07, 0.1, 0.95)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 16, 16)

    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 16, 16)

    local title_font = assets.fonts.main
    ui.draw_glow_text(keyboard.title, panel_x + 26, panel_y + 20, title_font,
        { theme.text[1], theme.text[2], theme.text[3], 0.95 }, nil)

    local input_x = panel_x + 26
    local input_y = panel_y + 74
    local input_w = panel_w - 52
    local input_h = 58

    love.graphics.setColor(0.1, 0.11, 0.16, 0.92)
    love.graphics.rectangle("fill", input_x, input_y, input_w, input_h, 10, 10)
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.25)
    love.graphics.rectangle("line", input_x, input_y, input_w, input_h, 10, 10)

    local shown_value = keyboard.value
    if shown_value == "" then
        shown_value = "(enter playlist name)"
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.45)
    else
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.95)
    end
    love.graphics.setFont(assets.fonts.small)
    love.graphics.print(shown_value, input_x + 14, input_y + 15)

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

            if focused then
                love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35)
                love.graphics.rectangle("fill", x, y, key_w, key_h, 9, 9)
            else
                love.graphics.setColor(0.15, 0.16, 0.22, 0.8)
                love.graphics.rectangle("fill", x, y, key_w, key_h, 9, 9)
            end

            if key_name == "CAPS" and keyboard.caps_on then
                love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.22)
                love.graphics.rectangle("fill", x + 2, y + 2, key_w - 4, key_h - 4, 8, 8)
            end

            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], focused and 1 or 0.85)
            love.graphics.setFont(assets.fonts.xs)
            love.graphics.printf(label, x, y + 10, key_w, "center")

            x = x + key_w + key_gap
        end
    end
end

return keyboard