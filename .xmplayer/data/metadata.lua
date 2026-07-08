local utils = require("utils")
local metadata = {}

local folder_cover_cache = {}

local function parse_syncsafe(b1, b2, b3, b4)
    return b1 * 2097152 + b2 * 16384 + b3 * 128 + b4
end

local function parse_int32(b1, b2, b3, b4)
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

local function parse_uint24(b1, b2, b3)
    return b1 * 65536 + b2 * 256 + b3
end

local function parse_le_int32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    if not b4 then return nil, pos end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216, pos + 4
end

local function parse_be_int32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    if not b4 then return nil, pos end
    return parse_int32(b1, b2, b3, b4), pos + 4
end

local function iso_to_utf8(str)
    local chars = {}
    for i = 1, #str do
        local b = str:byte(i)
        if b < 128 then
            table.insert(chars, string.char(b))
        else
            table.insert(chars, string.char(192 + math.floor(b / 64), 128 + (b % 64)))
        end
    end
    return table.concat(chars)
end

local function utf16_to_utf8(text, big_endian)
    local chars = {}
    local i = 1

    while i + 1 <= #text do
        local b1, b2 = text:byte(i), text:byte(i + 1)
        local codepoint

        if big_endian then
            codepoint = b1 * 256 + b2
        else
            codepoint = b2 * 256 + b1
        end

        if codepoint == 0 then break end

        if codepoint < 0x80 then
            table.insert(chars, string.char(codepoint))
        elseif codepoint < 0x800 then
            table.insert(chars, string.char(
                0xC0 + math.floor(codepoint / 0x40),
                0x80 + (codepoint % 0x40)
            ))
        else
            table.insert(chars, string.char(
                0xE0 + math.floor(codepoint / 0x1000),
                0x80 + (math.floor(codepoint / 0x40) % 0x40),
                0x80 + (codepoint % 0x40)
            ))
        end

        i = i + 2
    end

    return table.concat(chars)
end

local function decode_id3_text(frame_data)
    local encoding = frame_data:byte(1) or 0
    local text = frame_data:sub(2)

    if encoding == 1 then
        local big_endian = false
        if #text >= 2 then
            local bb1, bb2 = text:byte(1), text:byte(2)
            if bb1 == 0xFE and bb2 == 0xFF then
                big_endian = true
                text = text:sub(3)
            elseif bb1 == 0xFF and bb2 == 0xFE then
                text = text:sub(3)
            end
        end
        text = utf16_to_utf8(text, big_endian)
    elseif encoding == 2 then
        text = utf16_to_utf8(text, true)
    elseif encoding == 0 then
        text = iso_to_utf8(text:gsub("%z+$", ""))
    else
        text = text:gsub("%z+$", "")
    end

    text = utils.trim(text:gsub("%z", ""))
    if text ~= "" then
        return text
    end

    return nil
end

local function join_unique(values)
    local unique = {}
    local seen = {}

    for _, value in ipairs(values or {}) do
        local trimmed = utils.trim(value or "")
        if trimmed ~= "" and not seen[trimmed] then
            seen[trimmed] = true
            table.insert(unique, trimmed)
        end
    end

    return table.concat(unique, ", ")
end

local function detect_image_ext(mime, data)
    mime = (mime or ""):lower()
    if mime:find("png", 1, true) then return "png" end
    if mime:find("jpeg", 1, true) or mime:find("jpg", 1, true) then return "jpg" end
    if mime:find("bmp", 1, true) then return "bmp" end
    if data and data:sub(1, 4) == "\137PNG" then return "png" end
    if data and data:sub(1, 2) == "\255\216" then return "jpg" end
    return nil
end

local function parse_flac_vorbis_comments(block_data)
    local comments = {}
    local pos = 1

    local vendor_len
    vendor_len, pos = parse_le_int32(block_data, pos)
    if not vendor_len or pos + vendor_len - 1 > #block_data then return comments end
    pos = pos + vendor_len

    local comment_count
    comment_count, pos = parse_le_int32(block_data, pos)
    if not comment_count then return comments end

    for _ = 1, comment_count do
        local comment_len
        comment_len, pos = parse_le_int32(block_data, pos)
        if not comment_len or pos + comment_len - 1 > #block_data then break end

        local entry = block_data:sub(pos, pos + comment_len - 1)
        pos = pos + comment_len

        local key, value = entry:match("^([^=]+)=(.*)$")
        if key and value then
            key = key:upper()
            comments[key] = comments[key] or {}
            table.insert(comments[key], utils.trim(value))
        end
    end

    return comments
end

local function extract_flac_picture(block_data)
    local pos = 1
    local picture_type
    picture_type, pos = parse_be_int32(block_data, pos)
    if not picture_type then return nil end

    local mime_len
    mime_len, pos = parse_be_int32(block_data, pos)
    if not mime_len or pos + mime_len - 1 > #block_data then return nil end
    local mime = block_data:sub(pos, pos + mime_len - 1)
    pos = pos + mime_len

    local desc_len
    desc_len, pos = parse_be_int32(block_data, pos)
    if not desc_len or pos + desc_len - 1 > #block_data then return nil end
    pos = pos + desc_len

    for _ = 1, 4 do
        local skipped
        skipped, pos = parse_be_int32(block_data, pos)
        if not skipped then return nil end
    end

    local data_len
    data_len, pos = parse_be_int32(block_data, pos)
    if not data_len or pos + data_len - 1 > #block_data then return nil end

    local image_data = block_data:sub(pos, pos + data_len - 1)
    local image_ext = detect_image_ext(mime, image_data)
    if not image_ext then return nil end

    return image_data, image_ext, picture_type
end

local function extract_flac_metadata(data)
    if #data < 4 or data:sub(1, 4) ~= "fLaC" then return {} end

    local flac_tags = {}
    local comment_map = {}
    local pos = 5

    while pos + 3 <= #data do
        local header = data:byte(pos)
        local is_last = header >= 128
        local block_type = header % 128
        local block_length = parse_uint24(data:byte(pos + 1), data:byte(pos + 2), data:byte(pos + 3))
        local block_start = pos + 4
        local block_end = block_start + block_length - 1

        if block_end > #data then break end

        local block_data = data:sub(block_start, block_end)
        if block_type == 4 then
            comment_map = parse_flac_vorbis_comments(block_data)
        elseif block_type == 6 and not flac_tags.cover_data then
            local image_data, image_ext, picture_type = extract_flac_picture(block_data)
            if image_data and (picture_type == 3 or picture_type == 0) then
                flac_tags.cover_data = image_data
                flac_tags.cover_ext = image_ext
            end
        end

        pos = block_end + 1
        if is_last then break end
    end

    flac_tags.title = join_unique(comment_map.TITLE)
    flac_tags.artist = join_unique(comment_map.ARTIST)
    flac_tags.album = join_unique(comment_map.ALBUM)
    flac_tags.album_artist = join_unique(comment_map.ALBUMARTIST or comment_map["ALBUM ARTIST"])
    flac_tags.track_number = comment_map.TRACKNUMBER and comment_map.TRACKNUMBER[1] or nil
    flac_tags.disc_number = comment_map.DISCNUMBER and comment_map.DISCNUMBER[1] or nil

    return flac_tags
end

function metadata.extract_id3_text(data, frame_id)
    if #data < 10 or data:sub(1, 3) ~= "ID3" then return nil end

    local version = data:byte(4)
    local tag_size = parse_syncsafe(data:byte(7), data:byte(8), data:byte(9), data:byte(10))

    local pos = 11
    local end_pos = math.min(tag_size + 10, #data)

    while pos + 10 < end_pos do
        local id = data:sub(pos, pos + 3)
        if id:match("^%z+$") or id == "" then break end

        local b1, b2, b3, b4 = data:byte(pos + 4), data:byte(pos + 5), data:byte(pos + 6), data:byte(pos + 7)
        local frame_size
        if version == 4 then
            frame_size = parse_syncsafe(b1, b2, b3, b4)
        else
            frame_size = parse_int32(b1, b2, b3, b4)
        end

        if frame_size <= 0 or pos + 10 + frame_size > end_pos then break end

        if id == frame_id then
            local frame_data = data:sub(pos + 10, pos + 10 + frame_size - 1)
            local text = decode_id3_text(frame_data)
            if text then return text end
        end

        pos = pos + 10 + frame_size
    end

    return nil
end

function metadata.extract_cover_art(data)
    if #data < 10 then return nil end
    if data:sub(1, 3) ~= "ID3" then return nil end

    local apic_pos = data:find("APIC", 1, true)
    if not apic_pos then return nil end
    if apic_pos + 10 > #data then return nil end

    local b1 = data:byte(apic_pos + 4)
    local b2 = data:byte(apic_pos + 5)
    local b3 = data:byte(apic_pos + 6)
    local b4 = data:byte(apic_pos + 7)
    local frame_size = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    if frame_size <= 0 or frame_size > #data then return nil end

    local data_start = apic_pos + 10
    local frame_data = data:sub(data_start, data_start + frame_size - 1)

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

function metadata.find_folder_cover(track_path)
    local dir = utils.get_dirname(track_path)
    if dir == "" then return nil end

    if folder_cover_cache[dir] then
        local cached = folder_cover_cache[dir]
        if cached == "none" then
            return nil
        else
            return cached.data, cached.ext
        end
    end

    local folder_name = utils.get_filename(dir)
    local exts = { "jpg", "jpeg", "png", "bmp" }
    local candidates = {}

    if folder_name then
        for _, ext in ipairs(exts) do
            table.insert(candidates, folder_name .. "." .. ext)
        end
    end

    local standard = {
        "cover.jpg", "cover.png", "folder.jpg", "folder.png",
        "Cover.jpg", "Cover.png", "Folder.jpg", "Folder.png",
        "front.jpg", "front.png", "Front.jpg", "Front.png",
        "album.jpg", "album.png", "Album.jpg", "Album.png"
    }
    for _, name in ipairs(standard) do table.insert(candidates, name) end

    for _, name in ipairs(candidates) do
        local full_path = dir .. "/" .. name
        local f = io.open(full_path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data and #data > 0 then
                local extension = name:match("%.([^%.]+)$")
                folder_cover_cache[dir] = { data = data, ext = extension }
                return data, extension
            end
        end
    end

    local command = "find \"" .. dir .. "\" -maxdepth 1 -type f 2>/dev/null"
    local handle = io.popen(command)
    if handle then
        local valid_exts = { jpg = true, jpeg = true, png = true, bmp = true }
        for line in handle:lines() do
            local ext = utils.get_extension(line)
            if ext and valid_exts[ext:sub(2)] then
                local f = io.open(line, "rb")
                if f then
                    local data = f:read("*a")
                    f:close()
                    handle:close()
                    local extension = ext:sub(2)
                    folder_cover_cache[dir] = { data = data, ext = extension }
                    return data, extension
                end
            end
        end
        handle:close()
    end

    folder_cover_cache[dir] = "none"
    return nil
end

function metadata.get_tags(filepath)
    local tags = {}
    local f = io.open(filepath, "rb")
    if f then
        local raw_data = f:read(256 * 1024)
        f:close()
        if raw_data then
            if raw_data:sub(1, 4) == "fLaC" then
                tags = extract_flac_metadata(raw_data)
            else
                tags.title = metadata.extract_id3_text(raw_data, "TIT2")
                tags.artist = metadata.extract_id3_text(raw_data, "TPE1")
                tags.album = metadata.extract_id3_text(raw_data, "TALB")
                tags.album_artist = metadata.extract_id3_text(raw_data, "TPE2")
                tags.track_number = metadata.extract_id3_text(raw_data, "TRCK")
                tags.disc_number = metadata.extract_id3_text(raw_data, "TPOS")

                local img_data, img_ext = metadata.extract_cover_art(raw_data)
                if img_data then
                    tags.cover_data = img_data
                    tags.cover_ext = img_ext
                end
            end
        end
    end

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
