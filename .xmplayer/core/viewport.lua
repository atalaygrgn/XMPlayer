local viewport = {}

viewport.width = 640
viewport.height = 480

local function get_scale_and_offset()
    local window_w, window_h = love.graphics.getDimensions()
    local scale = math.min(window_w / viewport.width, window_h / viewport.height)
    local offset_x = (window_w - viewport.width * scale) / 2
    local offset_y = (window_h - viewport.height * scale) / 2
    return scale, offset_x, offset_y
end

function viewport.get()
    return viewport.width, viewport.height
end

function viewport.update_from_window(window_w, window_h)
    window_w = window_w or love.graphics.getWidth()
    window_h = window_h or love.graphics.getHeight()

    if window_h <= 0 then
        window_h = 1
    end

    local aspect_ratio = window_w / window_h
    viewport.width = math.max(1, math.floor(viewport.height * aspect_ratio + 0.5))
    return viewport.width, viewport.height
end

function viewport.get_scale()
    local scale, offset_x, offset_y = get_scale_and_offset()
    return scale
end

function viewport.to_screen_rect(x, y, w, h)
    local scale, offset_x, offset_y = get_scale_and_offset()
    return
        math.floor(offset_x + x * scale + 0.5),
        math.floor(offset_y + y * scale + 0.5),
        math.ceil(w * scale),
        math.ceil(h * scale)
end

function viewport.set_scissor(x, y, w, h)
    love.graphics.setScissor(viewport.to_screen_rect(x, y, w, h))
end

return viewport
