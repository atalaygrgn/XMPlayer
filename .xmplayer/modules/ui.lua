local theme = require("theme")
local assets = require("assets")
local ui = {}

ui.active_toasts = {}

-- Marquee component state management and rendering
function ui.new_marquee(max_width, speed, pause_start, pause_end)
    return {
        offset = 0,
        timer = 0,
        phase = "pause_start",
        max_width = max_width or 200,
        speed = speed or 40,
        pause_start = pause_start or 3.0,
        pause_end = pause_end or 1.5
    }
end

function ui.update_marquee(m, dt, text_width)
    if text_width <= m.max_width then
        m.offset = 0
        m.timer = 0
        m.phase = "pause_start"
        return
    end

    local max_offset = text_width - m.max_width + 20
    m.timer = m.timer + dt

    if m.phase == "pause_start" then
        if m.timer > m.pause_start then
            m.phase = "scrolling"
            m.timer = 0
        end
    elseif m.phase == "scrolling" then
        m.offset = m.offset + dt * m.speed
        if m.offset >= max_offset then
            m.offset = max_offset
            m.phase = "pause_end"
            m.timer = 0
        end
    elseif m.phase == "pause_end" then
        if m.timer > m.pause_end then
            m.offset = 0
            m.phase = "pause_start"
            m.timer = 0
        end
    end
end

function ui.draw_marquee(m, text, x, y, font, color, abs_x, abs_y, glow_color)
    local text_w = font:getWidth(text)
    love.graphics.setFont(font)
    local alpha = color[4] or 1

    local function draw_text(ox, oy, c)
        love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
        if text_w > m.max_width then
            local sx = abs_x or x
            local sy = abs_y or y
            love.graphics.setScissor(sx, sy, m.max_width, font:getHeight())
            love.graphics.print(text, x - m.offset + (ox or 0), y + (oy or 0))
            love.graphics.setScissor()
        else
            love.graphics.print(text, x + (ox or 0), y + (oy or 0))
        end
    end
    -- Adaptive intensities
    local shadow_alpha = theme.shadow_intensity * alpha
    local glow_mult = (theme.current_mode == "Dark") and 1.5 or 1.3
    
    -- Draw Shadow
    draw_text(3, 3, {0, 0, 0, shadow_alpha})

    if glow_color then
        for i = 1, theme.glow_radius do
            local layer_alpha = (theme.glow_intensity * glow_mult / i) * alpha
            draw_text(-i, 0, {glow_color[1], glow_color[2], glow_color[3], layer_alpha})
            draw_text(i, 0, {glow_color[1], glow_color[2], glow_color[3], layer_alpha})
            draw_text(0, -i, {glow_color[1], glow_color[2], glow_color[3], layer_alpha})
            draw_text(0, i, {glow_color[1], glow_color[2], glow_color[3], layer_alpha})
        end
    end

    draw_text(0, 0, color)
end

-- Progress bar component
function ui.draw_progress_bar(x, y, w, h, progress, color, bg_color)
    -- Background
    love.graphics.setColor(bg_color[1], bg_color[2], bg_color[3], bg_color[4] or 0.1)
    love.graphics.rectangle("fill", x, y, w, h, 2, 2)

    -- Fill
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.9)
    love.graphics.rectangle("fill", x, y, w * progress, h, 2, 2)
end

-- Icon helper
function ui.draw_indexing_popup(progress_text)
    local screen_w, screen_h = love.graphics.getDimensions()
    local w, h = 400, 150
    local x, y = (screen_w - w) / 2, (screen_h - h) / 2
    
    -- Blurred background (dim)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    
    -- Popup box
    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 10)
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.8)
    love.graphics.rectangle("line", x, y, w, h, 10)
    
    -- Text
    love.graphics.setFont(assets.fonts.main)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Indexing Media Files...", x, y + 40, w, "center")
    
    love.graphics.setFont(assets.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf(progress_text or "Scanning...", x, y + 80, w, "center")
end

function ui.draw_icon(icon, x, y, size, color, alpha, thumbnail)
    if not icon and not thumbnail then return end
    
    if thumbnail and type(thumbnail) ~= "string" then
        local iw = thumbnail:getWidth()
        local ih = thumbnail:getHeight()
        local scale = size / math.max(iw, ih)
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(thumbnail, x, y, 0, scale, scale, iw/2, ih/2)
    elseif icon then
        local img_w = icon:getWidth()
        local img_h = icon:getHeight()
        local scale = size / math.max(img_w, img_h)
        love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
        love.graphics.draw(icon, x, y, 0, scale, scale, img_w/2, img_h/2)
    end
end

-- Draw text with a soft glow effect
function ui.draw_glow_text(text, x, y, font, color, glow_color, limit, align)
    local alpha = color[4] or 1
    
    -- Adaptive intensities
    local shadow_alpha = theme.shadow_intensity * alpha
    local glow_mult = (theme.current_mode == "Dark") and 1.5 or 1.3
    
    -- Draw Shadow
    love.graphics.setColor(0, 0, 0, shadow_alpha)
    if limit and align then
        love.graphics.printf(text, x + 3, y + 3, limit, align)
    else
        love.graphics.print(text, x + 3, y + 3)
    end
    
    -- Draw glow layers
    if glow_color then
        local gc = glow_color or theme.accent
        for i = 1, theme.glow_radius do
            local layer_alpha = (theme.glow_intensity * glow_mult / i) * alpha
            love.graphics.setColor(gc[1], gc[2], gc[3], layer_alpha)
            if limit and align then
                love.graphics.printf(text, x - i, y, limit, align)
                love.graphics.printf(text, x + i, y, limit, align)
                love.graphics.printf(text, x, y - i, limit, align)
                love.graphics.printf(text, x, y + i, limit, align)
            else
                love.graphics.print(text, x - i, y)
                love.graphics.print(text, x + i, y)
                love.graphics.print(text, x, y - i)
                love.graphics.print(text, x, y + i)
            end
        end
    end
    
    -- Main text
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    if limit and align then
        love.graphics.printf(text, x, y, limit, align)
    else
        love.graphics.print(text, x, y)
    end
end

-- Draw icon/thumbnail with a soft glow effect
function ui.draw_glow_icon(icon, x, y, size, color, alpha, glow_color, thumbnail)
    local img = (thumbnail and type(thumbnail) ~= "string") and thumbnail or icon
    if not img then return end
    
    local a = alpha or 1
    
    local img_w = img:getWidth()
    local img_h = img:getHeight()
    local base_scale = size / math.max(img_w, img_h)

    -- Adaptive intensities
    local shadow_alpha = theme.shadow_intensity * a
    local glow_base = (theme.current_mode == "Dark") and (theme.glow_intensity * 1.2) or (theme.glow_intensity * 1.1)
    -- Draw Shadow
    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.draw(img, x + 3, y + 3, 0, base_scale, base_scale, img_w/2, img_h/2)

    -- Draw glow layers
    if glow_color then
        local gc = glow_color or theme.accent
        local radius = size * 0.3 -- Base radius for the aura
        local time = love.timer.getTime()
        local pulse = 0.8 + 0.2 * math.sin(time * 3) -- Pulse between 0.6 and 1.0
        
        for i = 1, theme.glow_radius do
            -- Create a smoother, non-linear alpha decay for a softer look
            local layer_alpha = (glow_base * 0.8 / (i^1.2)) * a * pulse
            local scale = (1.0 + (i * 0.1)) * (0.95 + pulse * 0.05) -- Subtle scale pulse
            
            love.graphics.setColor(gc[1], gc[2], gc[3], layer_alpha)
            love.graphics.circle("fill", x, y, radius * scale)
        end
    end
    
    -- Main image
    if thumbnail then
        love.graphics.setColor(1, 1, 1, a)
    else
        love.graphics.setColor(color[1], color[2], color[3], a)
    end
    love.graphics.draw(img, x, y, 0, base_scale, base_scale, img_w/2, img_h/2)
end

-- Toast Notification System
function ui.show_toast(text, icon_name, position)
    local toast = {
        text = text,
        icon = icon_name and assets.get_image(icon_name) or nil,
        position = position or "top_center",
        timer = 3.0,
        fade_time = 0.3,
        alpha = 0
    }
    table.insert(ui.active_toasts, toast)
end

function ui.update_toasts(dt)
    for i = #ui.active_toasts, 1, -1 do
        local t = ui.active_toasts[i]
        t.timer = t.timer - dt
        
        -- Handle alpha for fade in/out
        if t.timer > 2.7 then
            t.alpha = (3.0 - t.timer) / 0.3
        elseif t.timer < 0.3 then
            t.alpha = t.timer / 0.3
        else
            t.alpha = 1
        end
        
        if t.timer <= 0 then
            table.remove(ui.active_toasts, i)
        end
    end
end

function ui.draw_toasts()
    local sw, sh = love.graphics.getDimensions()
    local font = assets.fonts.small
    local padding = 20
    local icon_size = 32
    
    for _, t in ipairs(ui.active_toasts) do
        local tw = font:getWidth(t.text)
        local th = font:getHeight()
        local box_w = tw + padding * 2
        if t.icon then box_w = box_w + icon_size + 10 end
        local box_h = math.max(th, icon_size) + padding
        
        local x, y
        if t.position == "top_center" then
            x = (sw - box_w) / 2
            y = 8 + (1 - t.alpha) * -20 -- Subtle float animation
        else -- bottom_right
            x = sw - box_w - 30
            y = sh - box_h - 30 + (1 - t.alpha) * 20
        end
        
        -- Background (Glassmorphism look)
        love.graphics.setColor(0.1, 0.1, 0.15, 0.85 * t.alpha)
        love.graphics.rectangle("fill", x, y, box_w, box_h, 12, 12)
        
        -- Border with accent color
        local ac = theme.accent
        love.graphics.setColor(ac[1], ac[2], ac[3], 0.5 * t.alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, box_w, box_h, 12, 12)
        
        -- Icon
        local cur_x = x + padding
        if t.icon then
            ui.draw_icon(t.icon, cur_x + icon_size/2, y + box_h/2, icon_size, {1, 1, 1}, t.alpha)
            cur_x = cur_x + icon_size + 10
        end
        
        -- Text
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, t.alpha)
        love.graphics.print(t.text, cur_x, y + (box_h - th) / 2)
    end
end

return ui
