local theme = require("theme")
local assets = require("assets")
local ui = {}

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

function ui.draw_marquee(m, text, x, y, font, color, abs_x, abs_y)
    local text_w = font:getWidth(text)
    love.graphics.setFont(font)
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)

    if text_w > m.max_width then
        -- Use absolute coordinates for scissor if provided, otherwise fallback to x, y
        local sx = abs_x or x
        local sy = abs_y or y
        love.graphics.setScissor(sx, sy, m.max_width, font:getHeight())
        love.graphics.print(text, x - m.offset, y)
        love.graphics.setScissor()
    else
        love.graphics.print(text, x, y)
    end
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
    
    -- Spinner or dots
    local dots = math.floor(love.timer.getTime() * 2) % 4
    local dot_str = string.rep(".", dots)
    love.graphics.print(dot_str, x + w/2 + 80, y + 40)
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

return ui
