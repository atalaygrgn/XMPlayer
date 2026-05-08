-- settings_view.lua
-- Renders the settings choice popup panel and manages its animation state.
-- Model data (options, groups, persistence) lives in settings.lua.

local theme    = require("theme")
local assets   = require("assets")
local utils    = require("utils")
local settings = require("settings")
local ui       = require("ui")

local settings_view = {}

-- Animation / interaction state
settings_view.active       = false  -- Is the popup open?
settings_view.alpha        = 0      -- Fade-in progress (0-1)
settings_view.scroll_y     = 0
settings_view.target_scroll_y = 0
settings_view.selected_option_idx = 1

-- Folder picker state (compact picker for path options)
settings_view.picker_active = false
settings_view.picker_alpha = 0
settings_view.picker_items = {}
settings_view.picker_selected_idx = 1
settings_view.picker_current_path = "/"
settings_view.picker_setting_idx = nil
settings_view.picker_scroll_y = 0
settings_view.picker_target_scroll_y = 0

function settings_view.ensure_picker_visible()
    if not settings_view.picker_items or #settings_view.picker_items == 0 then
        settings_view.picker_target_scroll_y = 0
        return
    end
    local screen_w, screen_h = love.graphics.getDimensions()
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
                local screen_h = love.graphics.getHeight()
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
    settings_view.picker_scroll_y = utils.lerp(settings_view.picker_scroll_y, settings_view.picker_target_scroll_y or 0, dt * 12)
end

function settings_view.draw_popup(setting_idx)
    local opt = settings.options[setting_idx]
    if not opt or opt.type ~= "choice" or settings_view.alpha <= 0 then return end

    local screen_w, screen_h = love.graphics.getDimensions()
    local panel_w = screen_w * 0.35
    local item_h  = 50
    local alpha   = settings_view.alpha
    local x       = screen_w - (panel_w * alpha)
    local y       = 0

    -- Panel background
    love.graphics.setColor(0.02, 0.02, 0.05, 0.92 * alpha)
    love.graphics.rectangle("fill", x, y, panel_w, screen_h)

    -- Left accent border
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.8 * alpha)
    love.graphics.rectangle("fill", x, y, 4, screen_h)

    local content_y_base = screen_h * 0.3
    local visible_area_h = screen_h * 0.6

    love.graphics.setScissor(x, content_y_base, panel_w, visible_area_h)
    love.graphics.push()
    love.graphics.translate(0, content_y_base + settings_view.scroll_y)

    love.graphics.setFont(assets.fonts.small)
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

        love.graphics.print(choice, x + 40, cy + 5)

        if is_current then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 1 * alpha)
            love.graphics.circle("fill", x + 25, cy + item_h / 2 - 6, 4)
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
                centerX,      content_y_base - 26)
        end
        if settings_view.scroll_y > -(#opt.choices * item_h) + visible_area_h then
            local targetY = content_y_base + visible_area_h + 14
            love.graphics.polygon("fill",
                centerX - 10, targetY,
                centerX + 10, targetY,
                centerX,      targetY + 12)
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
    local screen_w, screen_h = love.graphics.getDimensions()
    local panel_w = screen_w * 0.70
    local panel_h = math.min(screen_h * 0.8, 420)
    local x = math.floor(screen_w/2) - math.floor(panel_w/2)
    local y = math.floor(screen_h/2) - math.floor(panel_h/2)
    local alpha = settings_view.picker_alpha

    love.graphics.setColor(0.02, 0.02, 0.05, 0.96 * alpha)
    love.graphics.rectangle("fill", x, y, panel_w, panel_h, 12, 12)
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35 * alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, panel_w, panel_h, 12, 12)

    love.graphics.setFont(assets.fonts.main)
    ui.draw_glow_text("Select Folder", x + 20, y + 18, assets.fonts.main,
        { theme.text[1], theme.text[2], theme.text[3], alpha }, nil)

    love.graphics.setFont(assets.fonts.xs)
    love.graphics.setColor(1,1,1,0.6 * alpha)
    love.graphics.print(settings_view.picker_current_path, x + 20, y + 52)

    -- List area
    local list_x = x + 20
    local list_y = y + 92
    local list_h = panel_h - 140 -- reserve space for header + hints
    local item_h = 36

    love.graphics.setScissor(list_x, list_y, panel_w - 40, list_h)
    love.graphics.push()
    love.graphics.translate(0, list_y + settings_view.picker_scroll_y)

    for i, it in ipairs(settings_view.picker_items) do
        local cy = (i - 1) * item_h
        local focused = (i == settings_view.picker_selected_idx)
        if focused then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.24 * alpha)
            love.graphics.rectangle("fill", list_x - 6, cy - 6, panel_w - 28, item_h, 6, 6)
            love.graphics.setColor(1,1,1,1 * alpha)
        else
            love.graphics.setColor(1,1,1,0.8 * alpha)
        end
        love.graphics.setFont(assets.fonts.small)
        love.graphics.print(it.name, list_x, cy)
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- Button hints at bottom
    local hint_y = y + panel_h - 40
    love.graphics.setFont(assets.fonts.xs)
    love.graphics.setColor(1,1,1,0.85 * alpha)
    local hints = "A: Open    B: Back/Close    X: Set Folder"
    love.graphics.print(hints, x + 20, hint_y)
end

return settings_view
