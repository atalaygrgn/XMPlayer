local utils = {}

function utils.lerp(a, b, t)
    return a + (b - a) * t
end

function utils.format_time(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

function utils.get_track_name(filename)
    -- Strip extension
    local name = filename:match("([^/]+)$") or filename
    return name:match("(.+)%.[^%.]+$") or name
end

function utils.truncate_text(text, font, max_w)
    if font:getWidth(text) <= max_w then return text end
    for i = #text, 1, -1 do
        local sub = text:sub(1, i) .. "..."
        if font:getWidth(sub) <= max_w then
            return sub
        end
    end
    return "..."
end

return utils

