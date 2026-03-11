-- settings_view.lua
-- Renders the settings choice popup panel and manages its animation state.
-- Model data (options, groups, persistence) lives in settings.lua.

local theme    = require("theme")
local assets   = require("assets")
local utils    = require("utils")
local settings = require("settings")

local settings_view = {}

-- Animation / interaction state
settings_view.active       = false  -- Is the popup open?
settings_view.alpha        = 0      -- Fade-in progress (0-1)
settings_view.scroll_y     = 0
settings_view.target_scroll_y = 0
settings_view.selected_option_idx = 1

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

return settings_view
