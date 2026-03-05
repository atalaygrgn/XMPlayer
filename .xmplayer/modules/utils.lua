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

function utils.clean_utf8(str)
    if not str then return "" end
    -- Replace invalid UTF-8 bytes with '?'
    local clean = {}
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        if b < 128 then
            table.insert(clean, string.char(b))
            i = i + 1
        elseif b >= 192 and b <= 223 then
            local b2 = str:byte(i + 1)
            if b2 and b2 >= 128 and b2 <= 191 then
                table.insert(clean, str:sub(i, i + 1))
                i = i + 2
            else
                table.insert(clean, "?")
                i = i + 1
            end
        elseif b >= 224 and b <= 239 then
            local b2 = str:byte(i + 1)
            local b3 = str:byte(i + 2)
            if b2 and b3 and b2 >= 128 and b2 <= 191 and b3 >= 128 and b3 <= 191 then
                table.insert(clean, str:sub(i, i + 2))
                i = i + 3
            else
                table.insert(clean, "?")
                i = i + 1
            end
        elseif b >= 240 and b <= 247 then
            local b2 = str:byte(i + 1)
            local b3 = str:byte(i + 2)
            local b4 = str:byte(i + 3)
            if b2 and b3 and b4 and b2 >= 128 and b2 <= 191 and b3 >= 128 and b3 <= 191 and b4 >= 128 and b4 <= 191 then
                table.insert(clean, str:sub(i, i + 4))
                i = i + 4
            else
                table.insert(clean, "?")
                i = i + 1
            end
        else
            table.insert(clean, "?")
            i = i + 1
        end
    end
    return table.concat(clean)
end

function utils.truncate_text(text, font, max_w)
    text = utils.clean_utf8(text or "")
    if font:getWidth(text) <= max_w then return text end
    
    local utf8 = require("utf8")
    local last_pos = 0
    for i, _ in utf8.codes(text) do
        -- Get the byte position where the NEXT character starts
        local next_pos = utf8.offset(text, 2, i) or (#text + 1)
        local part = text:sub(1, next_pos - 1)
        
        if font:getWidth(part .. "...") > max_w then
            if last_pos == 0 then return "..." end
            return text:sub(1, last_pos) .. "..."
        end
        last_pos = next_pos - 1
    end
    return "..."
end

return utils

