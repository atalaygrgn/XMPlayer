local utils = {}

function utils.split(str, sep)
    local result = {}
    for part in str:gmatch("([^" .. sep .. "]+)") do
        table.insert(result, part:match("^%s*(.-)%s*$"))
    end
    return result
end

function utils.lerp(a, b, t)
    return a + (b - a) * t
end

function utils.format_time(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

function utils.get_filename(path)
    if type(path) ~= "string" then return nil end
    return path:match("([^/]+)$") or path
end

function utils.get_extension(path)
    if type(path) ~= "string" then return nil end
    local ext = path:match("%.([^%.]+)$")
    if ext then return "." .. ext:lower() end
    return nil
end

function utils.get_dirname(path)
    if type(path) ~= "string" then return "" end
    local dir = path:match("(.*)/[^/]+$")
    return dir or ""
end

function utils.normalize_path(p)
    if not p then return "" end
    p = p:gsub("\\", "/"):gsub("/+", "/")
    if p:sub(-1) == "/" and #p > 1 then p = p:sub(1, -2) end
    return p
end

function utils.is_subpath(base, current)
    base = utils.normalize_path(base)
    current = utils.normalize_path(current)
    if base == current then return true end
    return current:sub(1, #base + 1) == base .. "/"
end

function utils.get_track_name(filename)
    -- Strip extension
    local name = utils.get_filename(filename)
    local n = name:match("(.+)%.[^%.]+$")
    return n or name
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

function utils.load_image(path)
    if not path or path == "" then return nil end
    -- Try direct load first (works if path is relative to source or save, or valid absolute in some environments)
    local ok, img = pcall(love.graphics.newImage, path)
    if ok then return img end

    -- Try reading via io if newImage failed (common issue for absolute paths in Love2D)
    local f = io.open(path, "rb")
    if f then
        local data = f:read("*a")
        f:close()
        if data and #data > 0 then
            local success, file_data = pcall(love.filesystem.newFileData, data, "temp_img")
            if success then
                local ok2, img_data = pcall(love.image.newImageData, file_data)
                if ok2 then
                    local ok3, img3 = pcall(love.graphics.newImage, img_data)
                    if ok3 then return img3 end
                end
            end
        end
    end
    return nil
end

function utils.get_battery_percentage()
    local path = "/sys/class/power_supply/axp2202-battery/capacity"
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content then
        return tonumber(content:match("(%d+)"))
    end
    return nil
end

function utils.is_charging()
    local path = "/sys/class/power_supply/axp2202-usb/online"
    local f = io.open(path, "r")
    if not f then return false end
    local content = f:read("*a")
    f:close()
    if content then
        return (tonumber(content:match("(%d+)")) or 0) == 1
    end
    return false
end

function utils.get_volume()
    local path = "/opt/muos/config/settings/general/volume"
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content then
        return tonumber(content:match("(%d+)"))
    end
    return nil
end

function utils.get_brightness()
    local path = "/opt/muos/config/settings/general/brightness"
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content then
        return tonumber(content:match("(%d+)"))
    end
    return nil
end

return utils
