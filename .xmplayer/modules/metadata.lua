local metadata = {}

-- Extract a text frame (like TIT2, TPE1) from ID3v2 data
function metadata.extract_id3_text(data, frame_id)
    if #data < 10 then return nil end
    if data:sub(1, 3) ~= "ID3" then return nil end

    local pos = data:find(frame_id, 1, true)
    if not pos then return nil end

    if pos + 10 > #data then return nil end

    local b1 = data:byte(pos + 4)
    local b2 = data:byte(pos + 5)
    local b3 = data:byte(pos + 6)
    local b4 = data:byte(pos + 7)
    local frame_size = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    if frame_size <= 0 or frame_size > 10000 then return nil end

    local data_start = pos + 10  -- skip frame header
    if data_start + frame_size > #data then return nil end

    local frame_data = data:sub(data_start, data_start + frame_size - 1)

    -- First byte is encoding: 0=ISO-8859-1, 1=UTF-16, 2=UTF-16BE, 3=UTF-8
    local encoding = frame_data:byte(1)
    local text = frame_data:sub(2)

    if encoding == 1 or encoding == 2 then
        -- UTF-16: strip BOM and null bytes, convert to simple ASCII-safe string
        -- Remove BOM (FF FE or FE FF)
        if #text >= 2 then
            local b1, b2 = text:byte(1), text:byte(2)
            if (b1 == 0xFF and b2 == 0xFE) or (b1 == 0xFE and b2 == 0xFF) then
                text = text:sub(3)
            end
        end
        -- Simple UTF-16LE to ASCII extraction (take every other byte)
        local chars = {}
        for i = 1, #text - 1, 2 do
            local c = text:byte(i)
            if c > 0 and c < 128 then
                table.insert(chars, string.char(c))
            elseif c == 0 then
                break  -- null terminator
            end
        end
        text = table.concat(chars)
    else
        -- UTF-8 or ISO-8859-1: strip trailing nulls
        text = text:gsub("%z+$", "")
    end

    -- Trim whitespace
    text = text:match("^%s*(.-)%s*$")
    if text and #text > 0 then
        return text
    end
    return nil
end

-- Try to extract embedded cover art from an MP3's ID3v2 APIC frame
function metadata.extract_cover_art(data)
    -- Check for ID3v2 header: "ID3"
    if #data < 10 then return nil end
    if data:sub(1, 3) ~= "ID3" then return nil end

    -- Search for APIC frame marker
    local apic_pos = data:find("APIC", 1, true)
    if not apic_pos then return nil end

    -- APIC frame: 4 bytes frame ID + 4 bytes size + 2 bytes flags
    if apic_pos + 10 > #data then return nil end

    local b1 = data:byte(apic_pos + 4)
    local b2 = data:byte(apic_pos + 5)
    local b3 = data:byte(apic_pos + 6)
    local b4 = data:byte(apic_pos + 7)
    local frame_size = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    if frame_size <= 0 or frame_size > #data then return nil end

    -- Skip past frame header (10 bytes from APIC start) into frame data
    local data_start = apic_pos + 10
    local frame_data = data:sub(data_start, data_start + frame_size - 1)

    -- Find the start of the image data (JPEG: FF D8, PNG: 89 50)
    local jpg_start = frame_data:find("\xFF\xD8")
    local png_start = frame_data:find("\x89PNG")

    local img_start = nil
    local img_ext = "jpg"
    if jpg_start and (not png_start or jpg_start < png_start) then
        img_start = jpg_start
        img_ext = "jpg"
    elseif png_start then
        img_start = png_start
        img_ext = "png"
    end

    if not img_start then return nil end

    local img_data = frame_data:sub(img_start)
    return img_data, img_ext
end

-- Try to find a cover image file in the same directory as the track
function metadata.find_folder_cover(track_path)
    local dir = track_path:match("(.*)/[^/]+$")
    if not dir then return nil end
    local folder_name = dir:match("([^/]+)$")

    local exts = {"jpg", "jpeg", "png", "bmp"}
    local candidates = {}
    
    -- 1. Priority: Folder named images
    if folder_name then
        for _, ext in ipairs(exts) do
            table.insert(candidates, folder_name .. "." .. ext)
        end
    end

    -- 2. Standard Candidates
    local standard = {
        "cover.jpg", "cover.png", "folder.jpg", "folder.png",
        "Cover.jpg", "Cover.png", "Folder.jpg", "Folder.png",
        "front.jpg", "front.png", "Front.jpg", "Front.png",
        "album.jpg", "album.png", "Album.jpg", "Album.png"
    }
    for _, name in ipairs(standard) do table.insert(candidates, name) end

    -- Search candidates first
    for _, name in ipairs(candidates) do
        local full_path = dir .. "/" .. name
        local f = io.open(full_path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data and #data > 0 then
                return data, name:match("%.([^%.]+)$")
            end
        end
    end

    -- 3. Fallback: First image in folder
    local command = "find \"" .. dir .. "\" -maxdepth 1 -type f 2>/dev/null"
    local handle = io.popen(command)
    if handle then
        local valid_exts = {jpg=true, jpeg=true, png=true, bmp=true}
        for line in handle:lines() do
            local ext = line:match("%.([^%.]+)$")
            if ext and valid_exts[ext:lower()] then
                local f = io.open(line, "rb")
                if f then
                    local data = f:read("*a")
                    f:close()
                    handle:close()
                    return data, ext
                end
            end
        end
        handle:close()
    end

    return nil
end

function metadata.get_tags(filepath)
    local tags = {}
    local f = io.open(filepath, "rb")
    if f then
        local raw_data = f:read(256 * 1024) -- Read first 256kb for tags
        f:close()
        if raw_data then
            tags.title = metadata.extract_id3_text(raw_data, "TIT2")
            tags.artist = metadata.extract_id3_text(raw_data, "TPE1")
            tags.album = metadata.extract_id3_text(raw_data, "TALB")
            
            local img_data, img_ext = metadata.extract_cover_art(raw_data)
            if img_data then
                tags.cover_data = img_data
                tags.cover_ext = img_ext
            end
        end
    end
    
    -- If no embedded cover, look for folder cover
    if not tags.cover_data then
        local img_data, img_ext = metadata.find_folder_cover(filepath)
        if img_data then
            tags.cover_data = img_data
            tags.cover_ext = img_ext
        end
    end
    
    return tags
end

return metadata
