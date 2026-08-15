local utils = {}

function utils.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function utils.ensure_utf8(str)
    if not str or type(str) ~= "string" then return "" end
    local clean = str:gsub("%z", "")
    local buf = {}
    local len = #clean
    local i = 1
    while i <= len do
        local c = str:byte(i)
        if c < 0x80 then
            table.insert(buf, string.char(c))
            i = i + 1
        elseif c >= 0xC0 and c <= 0xDF and i + 1 <= len then
            local c2 = str:byte(i + 1)
            if c2 >= 0x80 and c2 <= 0xBF then
                table.insert(buf, str:sub(i, i + 1))
                i = i + 2
            else
                table.insert(buf, string.char(0xC0 + math.floor(c / 64), 0x80 + (c % 64)))
                i = i + 1
            end
        elseif c >= 0xE0 and c <= 0xEF and i + 2 <= len then
            local c2, c3 = str:byte(i + 1), str:byte(i + 2)
            if c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then
                table.insert(buf, str:sub(i, i + 2))
                i = i + 3
            else
                table.insert(buf, string.char(0xC0 + math.floor(c / 64), 0x80 + (c % 64)))
                i = i + 1
            end
        elseif c >= 0xF0 and c <= 0xF7 and i + 3 <= len then
            local c2, c3, c4 = str:byte(i + 1), str:byte(i + 2), str:byte(i + 3)
            if c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF and c4 >= 0x80 and c4 <= 0xBF then
                table.insert(buf, str:sub(i, i + 3))
                i = i + 4
            else
                table.insert(buf, string.char(0xC0 + math.floor(c / 64), 0x80 + (c % 64)))
                i = i + 1
            end
        else
            table.insert(buf, string.char(0xC0 + math.floor(c / 64), 0x80 + (c % 64)))
            i = i + 1
        end
    end
    return table.concat(buf)
end

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

-- Smooth exponential interpolation that's frame-rate independent.
-- `speed` is roughly in 1/seconds; higher = snappier.
function utils.smooth(a, b, dt, speed)
    if a == b then return a end
    local t = 1 - math.exp(-speed * (dt or 0))
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
    -- If base is root, consider any absolute path a subpath
    if base == "/" then
        return current:sub(1,1) == "/"
    end
    return current:sub(1, #base + 1) == base .. "/"
end

function utils.get_track_name(filename)
    -- Strip extension
    local name = utils.get_filename(filename)
    local n = name:match("(.+)%.[^%.]+$")
    return n or name
end

function utils.is_vgm_file(filepath)
    if type(filepath) ~= "string" then return false end
    local ext = utils.get_extension(filepath)
    if not ext then return false end
    ext = ext:lower()
    local vgm_exts = {
        [".spc"] = true, [".nsf"] = true, [".nsfe"] = true, [".vgm"] = true,
        [".vgz"] = true, [".gym"] = true, [".gbs"] = true, [".hes"] = true,
        [".kss"] = true, [".sap"] = true, [".ay"] = true, [".mod"] = true,
        [".s3m"] = true, [".xm"] = true, [".it"] = true
    }
    return vgm_exts[ext] == true
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
                    local w, h = img_data:getDimensions()
                    local max_texture_size = 2048
                    if love.graphics and love.graphics.getSystemLimit then
                        local ok_limit, val = pcall(love.graphics.getSystemLimit, "texturesize")
                        if ok_limit and val then
                            max_texture_size = val
                        end
                    end
                    local limit = math.min(max_texture_size, 2048)
                    if w > limit or h > limit then
                        local scale = limit / math.max(w, h)
                        local tw, th = math.floor(w * scale), math.floor(h * scale)
                        local scaled_id = love.image.newImageData(tw, th)
                        for y = 0, th - 1 do
                            local sy = math.floor(y / scale)
                            if sy >= h then sy = h - 1 end
                            for x = 0, tw - 1 do
                                local sx = math.floor(x / scale)
                                if sx >= w then sx = w - 1 end
                                local r, g, b, a = img_data:getPixel(sx, sy)
                                scaled_id:setPixel(x, y, r, g, b, a)
                            end
                        end
                        img_data:release()
                        img_data = scaled_id
                    end

                    local ok3, img3 = pcall(love.graphics.newImage, img_data)
                    img_data:release()
                    file_data:release()
                    if ok3 then return img3 end
                else
                    file_data:release()
                end
            end
        end
    end
    return nil
end

function utils.shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

function utils.get_jpeg_metadata(filepath, need_thumb)
    local f = io.open(filepath, "rb")
    if not f then return nil end
    local data = f:read(128 * 1024) -- Read first 128KB
    f:close()
    if not data or #data < 4 then return nil end

    if data:byte(1) ~= 0xFF or data:byte(2) ~= 0xD8 then
        return nil -- Not a valid JPEG SOI
    end

    local pos = 3
    local len = #data
    local exif_data = nil
    local app1_pos = nil
    
    while pos < len - 4 do
        local b = data:byte(pos)
        if b == 0xFF then
            local marker = data:byte(pos + 1)
            -- Skip padding 0xFF bytes
            while marker == 0xFF and pos + 1 < len do
                pos = pos + 1
                marker = data:byte(pos + 1)
            end

            if marker and marker ~= 0x00 and marker ~= 0xFF then
                -- Valid marker found
                if marker == 0xD9 or marker == 0xDA then
                    -- SOS (Start of Scan) or EOI (End of Image)
                    break
                end

                local has_length = true
                if marker == 0xD8 or marker == 0xD9 or (marker >= 0xD0 and marker <= 0xD7) or marker == 0x01 then
                    has_length = false
                end

                if has_length then
                    local seg_len = data:byte(pos + 2) * 256 + data:byte(pos + 3)
                    if marker == 0xE1 then
                        -- APP1 marker (EXIF)
                        if pos + 4 + 5 < len and data:sub(pos + 4, pos + 9) == "Exif\0\0" then
                            exif_data = data:sub(pos + 10, pos + 2 + seg_len)
                            app1_pos = pos
                            break
                        end
                    end
                    pos = pos + 2 + seg_len
                else
                    pos = pos + 2
                end
            else
                pos = pos + 1
            end
        else
            pos = pos + 1
        end
    end

    if not exif_data or #exif_data < 8 then return nil end

    -- Now parse the TIFF header in exif_data
    local is_little = false
    local byte_order = exif_data:sub(1, 2)
    if byte_order == "II" then
        is_little = true
    elseif byte_order == "MM" then
        is_little = false
    else
        return nil
    end

    local function read_u16(s, p)
        local b1, b2 = s:byte(p), s:byte(p + 1)
        if not b2 then return 0 end
        if is_little then
            return b2 * 256 + b1
        else
            return b1 * 256 + b2
        end
    end

    local function read_u32(s, p)
        local b1, b2, b3, b4 = s:byte(p), s:byte(p + 1), s:byte(p + 2), s:byte(p + 3)
        if not b4 then return 0 end
        if is_little then
            return b4 * 16777216 + b3 * 65536 + b2 * 256 + b1
        else
            return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
        end
    end

    local magic = read_u16(exif_data, 3)
    if magic ~= 0x2A then return nil end

    local first_ifd_offset = read_u32(exif_data, 5)
    if first_ifd_offset == 0 or first_ifd_offset + 1 > #exif_data then return nil end

    local p = first_ifd_offset + 1
    local num_entries = read_u16(exif_data, p)
    p = p + 2

    local orientation = 1
    local ifd1_offset = 0

    for i = 1, num_entries do
        if p + 12 > #exif_data then break end
        local tag = read_u16(exif_data, p)
        local type_code = read_u16(exif_data, p + 2)
        if tag == 0x0112 then -- Orientation tag
            local val
            if type_code == 3 then
                val = read_u16(exif_data, p + 8)
            elseif type_code == 4 then
                val = read_u32(exif_data, p + 8)
            end
            if val then orientation = val end
        end
        p = p + 12
    end

    if p + 4 <= #exif_data then
        ifd1_offset = read_u32(exif_data, p)
    end

    local thumb_bytes = nil
    if need_thumb and ifd1_offset > 0 and ifd1_offset + 1 <= #exif_data then
        p = ifd1_offset + 1
        local num_entries1 = read_u16(exif_data, p)
        p = p + 2
        local thumb_offset = 0
        local thumb_length = 0
        for i = 1, num_entries1 do
            if p + 12 > #exif_data then break end
            local tag = read_u16(exif_data, p)
            if tag == 0x0201 then
                thumb_offset = read_u32(exif_data, p + 8)
            elseif tag == 0x0202 then
                thumb_length = read_u32(exif_data, p + 8)
            end
            p = p + 12
        end

        if thumb_offset > 0 and thumb_length > 0 then
            local f2 = io.open(filepath, "rb")
            if f2 then
                f2:seek("set", app1_pos - 1 + 10 + thumb_offset)
                thumb_bytes = f2:read(thumb_length)
                f2:close()
            end
        end
    end

    return orientation, thumb_bytes
end

function utils.get_jpeg_orientation(filepath)
    local orientation = utils.get_jpeg_metadata(filepath, false)
    return orientation or 1
end

function utils.load_image_bytes(bytes)
    local fd, id, img
    local ok = pcall(function()
        fd = love.filesystem.newFileData(bytes, "temp_img.jpg")
        id = love.image.newImageData(fd)
        img = love.graphics.newImage(id)
    end)
    if id then id:release() end
    if fd then fd:release() end
    if ok and img then
        return img
    end
    return nil
end

function utils.load_image_thumb(path)
    if not path or path == "" then return nil end
    local ext = path:match("%.([^%.]+)$")
    if ext and (ext:lower() == "jpg" or ext:lower() == "jpeg") then
        local _, thumb_bytes = utils.get_jpeg_metadata(path, true)
        if thumb_bytes then
            local img = utils.load_image_bytes(thumb_bytes)
            if img then return img end
        end
    end
    -- Fallback to loading full image
    return utils.load_image(path)
end

return utils
