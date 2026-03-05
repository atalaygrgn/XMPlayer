local theme = require("theme")
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
function ui.draw_icon(icon, x, y, size, color, alpha)
    if not icon then return end
    local img_w = icon:getWidth()
    local img_h = icon:getHeight()
    local scale = size / math.max(img_w, img_h)
    
    love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
    love.graphics.draw(icon, x, y, 0, scale, scale, img_w/2, img_h/2)
end

return ui
