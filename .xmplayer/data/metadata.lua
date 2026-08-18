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
    if not frame_data or #frame_data < 2 then return nil end
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
        text = iso_to_utf8(text)
    end

    if text ~= "" then
        return text
    end

    return nil
end

local function split_multi_values(text)
    if not text or text == "" then return {} end
    local values = {}
    local s = text:gsub("[%z\r\n\t]+", "\0"):gsub("%s*\\\\%s*", "\0")
    for val in (s .. "\0"):gmatch("(.-)%z") do
        local trimmed = utils.trim(val)
        trimmed = trimmed:gsub("^\xEF\xBB\xBF", ""):gsub("^\xFE\xFF", ""):gsub("^\xFF\xFE", "")
        trimmed = utils.trim(trimmed)
        if trimmed ~= "" then
            table.insert(values, trimmed)
        end
    end
    return values
end

local function join_unique(values)
    if not values or #values == 0 then return nil end
    local unique = {}
    local seen = {}

    for _, value in ipairs(values) do
        local sub_vals = split_multi_values(value)
        for _, sub in ipairs(sub_vals) do
            local trimmed = utils.trim(sub or "")
            if trimmed ~= "" and not seen[trimmed] then
                seen[trimmed] = true
                table.insert(unique, trimmed)
            end
        end
    end

    if #unique == 0 then return nil end
    return table.concat(unique, ", ")
end

local function detect_image_ext(mime, data)
    mime = (mime or ""):lower()
    if mime:find("png", 1, true) then return "png" end
    if mime:find("jpeg", 1, true) or mime:find("jpg", 1, true) then return "jpg" end
    if mime:find("bmp", 1, true) then return "bmp" end
    if data and data:sub(1, 4) == "\137PNG" then return "png" end
    if data and data:sub(1, 2) == "\255\216" then return "jpg" end
    if data and data:sub(1, 2) == "BM" then return "bmp" end
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

local function parse_id3_frames(data)
    local result = {
        text_frames = {},
        cover_data = nil,
        cover_ext = nil,
        cover_type = nil
    }

    if not data or #data < 10 or data:sub(1, 3) ~= "ID3" then
        return result
    end

    local version = data:byte(4)
    local flags = data:byte(6)
    local tag_size = parse_syncsafe(data:byte(7), data:byte(8), data:byte(9), data:byte(10))

    local pos = 11
    local end_pos = math.min(tag_size + 10, #data)

    -- Check for extended header (bit 6 of flags)
    if math.floor(flags / 64) % 2 == 1 then
        if version == 3 and pos + 4 <= end_pos then
            local ext_size = parse_int32(data:byte(pos), data:byte(pos + 1), data:byte(pos + 2), data:byte(pos + 3))
            if ext_size then pos = pos + 4 + ext_size end
        elseif version == 4 and pos + 4 <= end_pos then
            local ext_size = parse_syncsafe(data:byte(pos), data:byte(pos + 1), data:byte(pos + 2), data:byte(pos + 3))
            if ext_size then pos = pos + 4 + ext_size end
        end
    end

    local v22_map = {
        TT2 = "TIT2",
        TP1 = "TPE1",
        TAL = "TALB",
        TP2 = "TPE2",
        TRK = "TRCK",
        TPA = "TPOS",
        PIC = "APIC"
    }

    while pos < end_pos do
        local id, frame_size, header_len

        if version == 2 then
            if pos + 6 > end_pos then break end
            id = data:sub(pos, pos + 2)
            id = v22_map[id] or id
            frame_size = parse_uint24(data:byte(pos + 3), data:byte(pos + 4), data:byte(pos + 5))
            header_len = 6
        else
            if pos + 10 > end_pos then break end
            id = data:sub(pos, pos + 3)
            id = v22_map[id] or id
            local b1, b2, b3, b4 = data:byte(pos + 4), data:byte(pos + 5), data:byte(pos + 6), data:byte(pos + 7)
            if version == 4 then
                frame_size = parse_syncsafe(b1, b2, b3, b4)
            else
                frame_size = parse_int32(b1, b2, b3, b4)
            end
            header_len = 10
        end

        if not id or id:match("^%z+$") or id == "" or frame_size <= 0 then
            break
        end

        if pos + header_len + frame_size > end_pos + 1 then
            break
        end

        local frame_data = data:sub(pos + header_len, pos + header_len + frame_size - 1)

        if id:sub(1, 1) == "T" and id ~= "TXXX" then
            local text = decode_id3_text(frame_data)
            if text then
                result.text_frames[id] = result.text_frames[id] or {}
                local vals = split_multi_values(text)
                for _, val in ipairs(vals) do
                    table.insert(result.text_frames[id], val)
                end
            end
        elseif id == "APIC" then
            local pic_type = 0
            local mime = ""

            local mime_end = frame_data:find("\0", 2, true)
            if mime_end then
                mime = frame_data:sub(2, mime_end - 1)
                pic_type = frame_data:byte(mime_end + 1) or 0
            end

            local jpg_start = frame_data:find("\xFF\xD8", 1, true)
            local png_start = frame_data:find("\x89PNG", 1, true)
            local bmp_start = frame_data:find("BM", 1, true)

            local img_start = nil
            local img_ext = nil

            if jpg_start and (not png_start or jpg_start < png_start) and (not bmp_start or jpg_start < bmp_start) then
                img_start = jpg_start
                img_ext = "jpg"
            elseif png_start and (not bmp_start or png_start < bmp_start) then
                img_start = png_start
                img_ext = "png"
            elseif bmp_start then
                img_start = bmp_start
                img_ext = "bmp"
            else
                img_ext = detect_image_ext(mime, nil)
            end

            if img_start then
                local img_data = frame_data:sub(img_start)
                if not result.cover_data or pic_type == 3 then
                    result.cover_data = img_data
                    result.cover_ext = img_ext or detect_image_ext(mime, img_data) or "jpg"
                    result.cover_type = pic_type
                end
            end
        end

        pos = pos + header_len + frame_size
    end

    return result
end

function metadata.extract_id3_text(data, frame_id)
    local parsed = parse_id3_frames(data)
    local values = parsed.text_frames[frame_id]
    if values and #values > 0 then
        if frame_id == "TRCK" or frame_id == "TPOS" then
            return values[1]
        else
            return join_unique(values)
        end
    end
    return nil
end

function metadata.extract_cover_art(data)
    local parsed = parse_id3_frames(data)
    if parsed.cover_data then
        return parsed.cover_data, parsed.cover_ext
    end
    return nil
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

function metadata.get_tags_native(filepath, skip_cover)
    local tags = {}
    local f = io.open(filepath, "rb")
    if f then
        local header = f:read(10)
        if header and #header >= 10 and header:sub(1, 3) == "ID3" then
            local tag_size = parse_syncsafe(header:byte(7), header:byte(8), header:byte(9), header:byte(10))
            local total_size = math.min(10 + tag_size, 32 * 1024 * 1024)
            f:seek("set", 0)
            local raw_data = f:read(total_size)
            f:close()

            if raw_data then
                local parsed = parse_id3_frames(raw_data)
                tags.title = join_unique(parsed.text_frames.TIT2)
                tags.artist = join_unique(parsed.text_frames.TPE1)
                tags.album = join_unique(parsed.text_frames.TALB)
                tags.album_artist = join_unique(parsed.text_frames.TPE2)
                tags.track_number = parsed.text_frames.TRCK and parsed.text_frames.TRCK[1] or nil
                tags.disc_number = parsed.text_frames.TPOS and parsed.text_frames.TPOS[1] or nil

                if not skip_cover and parsed.cover_data then
                    tags.cover_data = parsed.cover_data
                    tags.cover_ext = parsed.cover_ext
                end
            end
        elseif header and #header >= 4 and header:sub(1, 4) == "fLaC" then
            f:seek("set", 0)
            local blocks = {}
            table.insert(blocks, f:read(4))
            local is_last = false
            while not is_last do
                local bh = f:read(4)
                if not bh or #bh < 4 then break end
                table.insert(blocks, bh)
                local b_header = bh:byte(1)
                is_last = b_header >= 128
                local b_len = parse_uint24(bh:byte(2), bh:byte(3), bh:byte(4))
                if b_len > 0 then
                    local b_data = f:read(b_len)
                    if not b_data or #b_data < b_len then break end
                    table.insert(blocks, b_data)
                end
            end
            f:close()
            local raw_data = table.concat(blocks)
            tags = extract_flac_metadata(raw_data)
            if skip_cover then
                tags.cover_data = nil
                tags.cover_ext = nil
            end
        else
            f:seek("set", 0)
            local raw_data = f:read(256 * 1024)
            f:close()
            if raw_data then
                tags.title = metadata.extract_id3_text(raw_data, "TIT2")
                tags.artist = metadata.extract_id3_text(raw_data, "TPE1")
                tags.album = metadata.extract_id3_text(raw_data, "TALB")
                tags.album_artist = metadata.extract_id3_text(raw_data, "TPE2")
                tags.track_number = metadata.extract_id3_text(raw_data, "TRCK")
                tags.disc_number = metadata.extract_id3_text(raw_data, "TPOS")

                if not skip_cover then
                    local img_data, img_ext = metadata.extract_cover_art(raw_data)
                    if img_data then
                        tags.cover_data = img_data
                        tags.cover_ext = img_ext
                    end
                end
            end
        end
    end
    return tags
end

function metadata.get_tags(filepath, skip_cover)
    local tags = metadata.get_tags_native(filepath, skip_cover)

    if not skip_cover and not tags.cover_data then
        local img_data, img_ext = metadata.find_folder_cover(filepath)
        if img_data then
            tags.cover_data = img_data
            tags.cover_ext = img_ext
        end
    end

    return tags
end

return metadata
