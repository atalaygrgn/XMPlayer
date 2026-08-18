local metadata = require("metadata")
local utils = require("utils")
local binser = require("binser")

local indexing = {}
local INDEX_VERSION = 2
local THUMB_VERSION = 2
local ALBUM_THUMB_VERSION = 2

local storage_path = love.filesystem.getSource()
indexing.file_path = storage_path .. "/index.cfg"
indexing.thumb_dir = storage_path .. "/thumbnails"
indexing.data = {
    version = INDEX_VERSION,
    music = {
        albums = {},  -- {name = "Album Name", artist = "Artist Name", tracks = {path, ...}, thumb_path, thumb_path_small, thumb_version}
        artists = {}, -- {name = "Artist Name", albums = {name, ...}, tracks = {path, ...}}
        files = {}    -- {path = {title, artist, album, ...}}
    },
    photo_count = 0,
    video_count = 0
}

indexing.compatible_extensions = {
    music = { ".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".opus", ".wma", ".alac", ".aif", ".aiff",
        -- VGM Files
        ".spc",  -- SNES
        ".nsf",  -- NES
        ".nsfe", -- Extended NES
        ".vgm",  -- Sega Genesis, Master System, Game Gear
        ".vgz",  -- Compressed VGM
        ".gbs",  -- GB/GBC
        ".hes",  -- TurboGrafx-16 / PC Engine
        ".kss",  -- MSX & SEGA Master System (Z80)
    },
    photo = { ".jpg", ".jpeg", ".png", ".bmp" },
    video = { ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".m4v", ".flv" }
}

indexing.is_scanning = false
indexing.scan_progress = ""
indexing.scan_result_message = nil

local function normalize_key(value)
    return utils.trim((value or ""):lower())
end

local function normalize_label(value, fallback)
    local text = utils.trim(value or "")
    if text == "" then
        return fallback
    end
    return text
end

local function update_album_artist(album_entry, album_artist, artist_str)
    if album_artist and album_artist ~= "" then
        album_entry.artist = album_artist
    elseif not album_entry.artist or album_entry.artist == "" then
        album_entry.artist = artist_str
    elseif album_entry.artist ~= artist_str and album_entry.artist ~= "Various Artists" then
        album_entry.artist = "Various Artists"
    end
end

local function parse_track_index(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end

    local number = value:match("^(%d+)") or value:match("(%d+)")
    return number and tonumber(number) or nil
end

local function split_artists(artist_str)
    if not artist_str or artist_str == "" then
        return { "Unknown Artist" }
    end

    -- Replace common character separators with commas
    local normalized = artist_str:gsub("%s*&%s*", ", ")
    normalized = normalized:gsub("%s*;%s*", ", ")

    -- Normalize featuring patterns case-insensitively with space boundaries
    local patterns = {
        "%s+[Ff][Ee][Aa][Tt]%.?%s+",
        "%s+[Ff][Ee][Aa][Tt][Uu][Rr][Ii][Nn][Gg]%s+",
        "%s+[Ff][Tt]%.?%s+"
    }
    for _, pat in ipairs(patterns) do
        normalized = normalized:gsub(pat, ", ")
    end

    local artists = {}
    local seen = {}

    for _, artist in ipairs(utils.split(normalized, ",")) do
        local trimmed = utils.trim(artist)
        if trimmed ~= "" and not seen[trimmed] then
            seen[trimmed] = true
            table.insert(artists, trimmed)
        end
    end

    if #artists == 0 then
        artists[1] = "Unknown Artist"
    end

    return artists
end

local function compare_track_paths(path_a, path_b)
    local info_a = indexing.data.music.files[path_a] or {}
    local info_b = indexing.data.music.files[path_b] or {}

    local disc_a = info_a.disc_number or 1
    local disc_b = info_b.disc_number or 1
    if disc_a ~= disc_b then return disc_a < disc_b end

    local track_a = info_a.track_number or math.huge
    local track_b = info_b.track_number or math.huge
    if track_a ~= track_b then return track_a < track_b end

    local title_a = (info_a.title or utils.get_track_name(path_a) or ""):lower()
    local title_b = (info_b.title or utils.get_track_name(path_b) or ""):lower()
    if title_a ~= title_b then return title_a < title_b end

    return path_a:lower() < path_b:lower()
end

local function compare_artist_track_paths(path_a, path_b)
    local info_a = indexing.data.music.files[path_a] or {}
    local info_b = indexing.data.music.files[path_b] or {}

    local album_a = (info_a.album or "Unknown Album"):lower()
    local album_b = (info_b.album or "Unknown Album"):lower()
    if album_a ~= album_b then return album_a < album_b end

    local disc_a = info_a.disc_number or 1
    local disc_b = info_b.disc_number or 1
    if disc_a ~= disc_b then return disc_a < disc_b end

    local track_a = info_a.track_number or math.huge
    local track_b = info_b.track_number or math.huge
    if track_a ~= track_b then return track_a < track_b end

    local title_a = (info_a.title or utils.get_track_name(path_a) or ""):lower()
    local title_b = (info_b.title or utils.get_track_name(path_b) or ""):lower()
    if title_a ~= title_b then return title_a < title_b end

    return path_a:lower() < path_b:lower()
end


local function add_artist_album(artist_entry, album)
    for _, existing_album in ipairs(artist_entry.albums) do
        if existing_album == album then
            return
        end
    end

    table.insert(artist_entry.albums, album)
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end


local function ensure_thumb_dir()
    if os.execute("test -d \"" .. indexing.thumb_dir .. "\"") ~= 0 then
        os.execute("mkdir -p \"" .. indexing.thumb_dir .. "\"")
    end
end

local function sort_music_collections()
    for _, album_entry in pairs(indexing.data.music.albums) do
        table.sort(album_entry.tracks, compare_track_paths)
    end

    for _, artist_entry in pairs(indexing.data.music.artists) do
        table.sort(artist_entry.tracks, compare_artist_track_paths)
        table.sort(artist_entry.albums, function(a, b)
            return a:lower() < b:lower()
        end)
    end
end

local function split_albums(album_str)
    local norm = (album_str or ""):gsub("%s*;%s*", ", "):gsub("%s*\\\\%s*", ", ")
    local albums = {}
    local seen = {}

    for _, album in ipairs(utils.split(norm, ",")) do
        local trimmed = utils.trim(album)
        if trimmed ~= "" and not seen[trimmed] then
            seen[trimmed] = true
            table.insert(albums, trimmed)
        end
    end

    if #albums == 0 then
        albums[1] = "Unknown Album"
    end

    return albums
end

local function add_music_file_with_tags(path, tags)
    if indexing.data.music.files[path] then
        return false
    end

    tags = tags or metadata.get_tags(path)
    local title = normalize_label(tags.title, utils.get_track_name(path))
    local artist_str = normalize_label(tags.artist, "Unknown Artist")
    local album_str = normalize_label(tags.album, "Unknown Album")
    local album_artist = utils.trim(tags.album_artist or "")
    local artists = split_artists(artist_str)
    local albums = split_albums(album_str)
    local track_number = parse_track_index(tags.track_number)
    local disc_number = parse_track_index(tags.disc_number)

    indexing.data.music.files[path] = {
        title = title,
        artist = artist_str,
        album = album_str,
        album_artist = album_artist ~= "" and album_artist or nil,
        track_number = track_number,
        disc_number = disc_number
    }

    if not utils.is_vgm_file(path) then
        for _, a in ipairs(artists) do
            if not indexing.data.music.artists[a] then
                indexing.data.music.artists[a] = { name = a, albums = {}, tracks = {} }
            end
            table.insert(indexing.data.music.artists[a].tracks, path)
            for _, alb in ipairs(albums) do
                add_artist_album(indexing.data.music.artists[a], alb)
            end
        end

        local album_group_key = album_artist ~= "" and album_artist or ""

        for _, alb in ipairs(albums) do
            local album_key = normalize_key(alb) .. "::" .. normalize_key(album_group_key)
            if not indexing.data.music.albums[album_key] then
                indexing.data.music.albums[album_key] = { name = alb, artist = "", tracks = {} }
            end
            update_album_artist(indexing.data.music.albums[album_key], album_artist, artist_str)
            table.insert(indexing.data.music.albums[album_key].tracks, path)
        end
    end

    return true
end

local function add_music_file(path)
    return add_music_file_with_tags(path, nil)
end

local function process_music_files_threaded(music_files, progress_prefix)
    if not music_files or #music_files == 0 then return 0 end

    -- Check if love.thread is available
    if not (love and love.thread and love.thread.newThread) then
        local count = 0
        for i, path in ipairs(music_files) do
            indexing.scan_progress = string.format("%s (%d/%d)", progress_prefix, i, #music_files)
            if i % 5 == 0 then coroutine.yield() end
            if add_music_file(path) then count = count + 1 end
        end
        return count
    end

    local in_chan_name = "idx_meta_in_" .. tostring(os.time())
    local out_chan_name = "idx_meta_out_" .. tostring(os.time())
    local in_chan = love.thread.getChannel(in_chan_name)
    local out_chan = love.thread.getChannel(out_chan_name)

    -- Filter out already indexed files
    local pending = {}
    for _, path in ipairs(music_files) do
        if not indexing.data.music.files[path] then
            table.insert(pending, path)
        end
    end

    if #pending == 0 then return 0 end

    -- Spawn 2 background worker threads for parallel extraction
    local num_workers = 2
    local threads = {}
    for w = 1, num_workers do
        local ok, t = pcall(love.thread.newThread, "workers/metadata_worker.lua")
        if not ok or not t then
            ok, t = pcall(love.thread.newThread, ".xmplayer/workers/metadata_worker.lua")
        end
        if not ok or not t then
            ok, t = pcall(love.thread.newThread, "metadata_worker.lua")
        end
        if not ok or not t then
            ok, t = pcall(love.thread.newThread, ".xmplayer/metadata_worker.lua")
        end
        if ok and t then
            t:start(in_chan_name, out_chan_name)
            table.insert(threads, t)
        end
    end

    if #threads == 0 then
        -- Fallback if thread creation failed
        local count = 0
        for i, path in ipairs(pending) do
            indexing.scan_progress = string.format("%s (%d/%d)", progress_prefix, i, #pending)
            if i % 5 == 0 then coroutine.yield() end
            if add_music_file(path) then count = count + 1 end
        end
        return count
    end

    -- Push pending files to thread queue (skip_cover = true for speed during track metadata scan)
    for i, path in ipairs(pending) do
        in_chan:push({ type = "extract_file", path = path, id = i, skip_cover = true })
    end

    local processed = 0
    local added_count = 0
    local total = #pending

    while processed < total do
        local res = out_chan:pop()
        if res and res.type == "file_tags" then
            processed = processed + 1
            indexing.scan_progress = string.format("%s (%d/%d)", progress_prefix, processed, total)
            if add_music_file_with_tags(res.path, res.tags) then
                added_count = added_count + 1
            end
        else
            coroutine.yield()
        end
    end

    -- Stop worker threads
    for w = 1, #threads do
        in_chan:push({ type = "stop" })
    end

    return added_count
end



local function rebuild_music_collections_from_files()
    local old_files = indexing.data.music.files or {}
    local old_albums = indexing.data.music.albums or {}
    indexing.data.music.albums = {}
    indexing.data.music.artists = {}

    for path, info in pairs(old_files) do
        if not utils.is_vgm_file(path) then
            local artist_str = normalize_label(info.artist, "Unknown Artist")
            local album_str = normalize_label(info.album, "Unknown Album")
            local album_artist = utils.trim(info.album_artist or "")
            local artists = split_artists(artist_str)
            local albums = split_albums(album_str)

            for _, a in ipairs(artists) do
                if not indexing.data.music.artists[a] then
                    indexing.data.music.artists[a] = { name = a, albums = {}, tracks = {} }
                end
                table.insert(indexing.data.music.artists[a].tracks, path)
                for _, alb in ipairs(albums) do
                    add_artist_album(indexing.data.music.artists[a], alb)
                end
            end

            local album_group_key = album_artist ~= "" and album_artist or ""

            for _, alb in ipairs(albums) do
                local album_key = normalize_key(alb) .. "::" .. normalize_key(album_group_key)
                if not indexing.data.music.albums[album_key] then
                    local preserved_album = old_albums[album_key] or {}
                    indexing.data.music.albums[album_key] = {
                        name = alb,
                        artist = "",
                        tracks = {},
                        thumb_path = preserved_album.thumb_path,
                        thumb_path_small = preserved_album.thumb_path_small,
                        thumb_version = preserved_album.thumb_version
                    }
                end
                update_album_artist(indexing.data.music.albums[album_key], album_artist, artist_str)
                table.insert(indexing.data.music.albums[album_key].tracks, path)
            end
        end
    end

    sort_music_collections()
end

function indexing.save()
    local ok, serialized_data = pcall(binser.s, indexing.data)
    if ok and serialized_data then
        local f = io.open(indexing.file_path, "wb")
        if f then
            f:write(serialized_data)
            f:close()
            return true
        end
    end
    return false
end

function indexing.load()
    local f = io.open(indexing.file_path, "rb")
    if not f then return false end
    local content = f:read("*a")
    f:close()

    if not content or #content == 0 then
        os.remove(indexing.file_path)
        return false
    end

    -- Strictly require binser binary deserialization
    local ok, results = pcall(binser.d, content)
    if ok and type(results) == "table" and type(results[1]) == "table" then
        local data = results[1]
        if data.version == INDEX_VERSION then
            indexing.data = data
            rebuild_music_collections_from_files()
            return true
        end
    end

    -- Delete legacy text index file or invalid binary file and force a new scan
    os.remove(indexing.file_path)
    return false
end

function indexing.generate_thumbnail(image_path)
    -- Skip thumbnail generation for large files (> 5MB)
    local f_chk = io.open(image_path, "rb")
    if f_chk then
        local sz = f_chk:seek("end")
        f_chk:close()
        if sz and sz > 5 * 1024 * 1024 then -- 5 MB
            return image_path, 1
        end
    end

    -- 1. Try to extract EXIF thumbnail and orientation first (for JPEGs)
    local ext = image_path:match("%.([^%.]+)$")
    local orientation = 1
    if ext and (ext:lower() == "jpg" or ext:lower() == "jpeg") then
        local parsed_orientation, thumb_bytes = utils.get_jpeg_metadata(image_path, true)
        orientation = parsed_orientation or 1
        if thumb_bytes and #thumb_bytes > 100 and thumb_bytes:byte(1) == 0xFF and thumb_bytes:byte(2) == 0xD8 then
            local safe_name = image_path:gsub("[^%w]", "_")
            local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. ".jpg"
            ensure_thumb_dir()
            local f = io.open(thumb_path, "wb")
            if f then
                f:write(thumb_bytes)
                f:close()
                return thumb_path, orientation
            end
        end
    end

    -- 2. Fallback path: load full image and resize
    local fallback_file_data = nil
    local ok, img_data = pcall(love.image.newImageData, image_path)
    if not ok or not img_data then
        local f = io.open(image_path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data then
                local file_data = love.filesystem.newFileData(data, "temp_img")
                fallback_file_data = file_data
                ok, img_data = pcall(love.image.newImageData, file_data)
            end
        end
    end

    if fallback_file_data then
        fallback_file_data:release()
        fallback_file_data = nil
    end

    if not ok or not img_data then return nil, orientation end

    local result_thumb_path = image_path
    local safe_name = image_path:gsub("[^%w]", "_")

    pcall(function()
        local w, h = img_data:getDimensions()
        local thumb_size = 240
        local scale = thumb_size / math.max(w, h)
        if scale < 1 then
            local tw, th = math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))
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

            local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. ".png"
            ensure_thumb_dir()

            local file_data = scaled_id:encode("png")
            if file_data then
                local f = io.open(thumb_path, "wb")
                if f then
                    f:write(file_data:getString())
                    f:close()
                    result_thumb_path = thumb_path
                end
                file_data:release()
            end
            scaled_id:release()
        end
    end)

    img_data:release()

    return result_thumb_path or image_path, orientation
end

local function generate_thumbnail_from_image_data(img_data, album_key, target_size)
    target_size = target_size or 240
    if not img_data then return nil end

    local w, h = img_data:getDimensions()
    if not w or not h or w <= 0 or h <= 0 then return nil end

    local scale = target_size / math.max(w, h)
    local tw, th = math.floor(w * scale), math.floor(h * scale)

    local thumb_data = img_data
    local is_scaled = false
    if scale < 1 then
        local canvas = love.graphics.newCanvas(tw, th)
        local prev_canvas = love.graphics.getCanvas()
        local prev_shader = love.graphics.getShader()
        local cr, cg, cb, ca = love.graphics.getColor()
        local blend_mode, blend_alpha_mode = love.graphics.getBlendMode()

        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setShader()
        love.graphics.setBlendMode("alpha", "alphamultiply")
        love.graphics.setColor(1, 1, 1, 1)
        local temp_img = love.graphics.newImage(img_data)
        love.graphics.draw(temp_img, 0, 0, 0, scale, scale)

        love.graphics.setColor(cr, cg, cb, ca)
        love.graphics.setBlendMode(blend_mode, blend_alpha_mode)
        love.graphics.setShader(prev_shader)
        love.graphics.setCanvas(prev_canvas)
        thumb_data = canvas:newImageData()
        temp_img:release()
        canvas:release()
        is_scaled = true
    end

    ensure_thumb_dir()
    local safe_name = ("album_" .. album_key):gsub("[^%w]", "_")
    local suffix = (target_size == 64) and "_64.png" or ".png"
    local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. suffix

    local png_data = thumb_data:encode("png")
    local f = io.open(thumb_path, "wb")
    local success = false
    if f then
        f:write(png_data:getString())
        f:close()
        success = true
    end

    png_data:release()
    if is_scaled then
        thumb_data:release()
    end

    if success then
        return thumb_path
    end
    return nil
end

local function generate_album_thumbnails()
    for album_key, album in pairs(indexing.data.music.albums or {}) do
        if album.name == "Unknown Album" then
            album.thumb_path = nil
            album.thumb_path_small = nil
            album.thumb_version = ALBUM_THUMB_VERSION
        else
            local has_240 = album.thumb_path and file_exists(album.thumb_path)
            local has_64 = album.thumb_path_small and file_exists(album.thumb_path_small)
            if not (has_240 and has_64 and album.thumb_version == ALBUM_THUMB_VERSION) then
                local img_bytes, img_ext = nil, nil
                if album.tracks and #album.tracks > 0 then
                    -- 1. Search for embedded cover art from tracks of the album
                    for _, track_path in ipairs(album.tracks) do
                        local tags = metadata.get_tags_native(track_path)
                        if tags and tags.cover_data then
                            img_bytes = tags.cover_data
                            img_ext = tags.cover_ext or "jpg"
                            break
                        end
                    end

                    -- 2. Fallback to folder cover image if no embedded track art
                    if not img_bytes and album.tracks[1] then
                        img_bytes, img_ext = metadata.find_folder_cover(album.tracks[1])
                    end
                end

                if img_bytes then
                    local file_data = love.filesystem.newFileData(img_bytes, "album_" .. album_key .. ".bin")
                    local ok, img_data = pcall(love.image.newImageData, file_data)
                    if ok and img_data then
                        album.thumb_path = generate_thumbnail_from_image_data(img_data, album_key, 240)
                        album.thumb_path_small = generate_thumbnail_from_image_data(img_data, album_key, 64)
                        img_data:release()
                    end
                    file_data:release()
                end

                album.thumb_version = ALBUM_THUMB_VERSION
            end
        end
    end
end

local function get_files_recursive(path, extensions)
    if not path or path == "" then return {} end
    local files = {}
    local norm_path = utils.normalize_path(path)

    local cmd = 'find "' .. norm_path .. '" -type f 2>/dev/null'
    local handle = io.popen(cmd)
    if handle then
        local ext_map = {}
        for _, allowed in ipairs(extensions) do
            ext_map[allowed:lower()] = true
        end

        for line in handle:lines() do
            local norm_file = utils.normalize_path(line)
            local ext = utils.get_extension(norm_file)
            if ext and ext_map[ext:lower()] then
                table.insert(files, norm_file)
            end
        end
        handle:close()
    end
    return files
end

function indexing.scan(photo_dir, music_dir, video_dir)
    indexing.is_scanning = true
    indexing.scan_result_message = nil

    local music_exts = indexing.compatible_extensions.music
    local photo_exts = indexing.compatible_extensions.photo
    local video_exts = indexing.compatible_extensions.video

    -- Reset data
    indexing.data = {
        version = INDEX_VERSION,
        music = { albums = {}, artists = {}, files = {} },
        photo_count = 0,
        video_count = 0
    }

    -- 1. Scan Music
    indexing.scan_progress = "Scanning Music..."
    coroutine.yield()
    local music_files = get_files_recursive(music_dir, music_exts)
    coroutine.yield()

    process_music_files_threaded(music_files, "Indexing Music")

    sort_music_collections()

    indexing.scan_progress = "Generating Album Thumbnails..."
    coroutine.yield()
    generate_album_thumbnails()

    indexing.scan_progress = "Counting Photos & Videos..."
    coroutine.yield(indexing.scan_progress)
    indexing.data.photo_count = indexing.count_photos(photo_dir)
    indexing.data.video_count = indexing.count_videos(video_dir)

    indexing.save()
    indexing.is_scanning = false
    indexing.scan_progress = "Done"
    indexing.scan_result_message = "Indexing completed"
end

function indexing.scan_for_new_media(photo_dir, music_dir, video_dir)
    indexing.is_scanning = true
    indexing.scan_result_message = nil

    local music_exts = indexing.compatible_extensions.music
    local video_exts = indexing.compatible_extensions.video

    local new_count = 0
    local removed_count = 0

    indexing.data.music = indexing.data.music or { albums = {}, artists = {}, files = {} }
    indexing.data.music.albums = indexing.data.music.albums or {}
    indexing.data.music.artists = indexing.data.music.artists or {}
    indexing.data.music.files = indexing.data.music.files or {}

    indexing.scan_progress = "Pruning removed music..."
    coroutine.yield(indexing.scan_progress)
    local kept_music_files = {}
    for path, info in pairs(indexing.data.music.files) do
        if file_exists(path) then
            kept_music_files[path] = info
        else
            removed_count = removed_count + 1
        end
    end
    indexing.data.music.files = kept_music_files
    rebuild_music_collections_from_files()

    indexing.scan_progress = "Checking for new music..."
    coroutine.yield(indexing.scan_progress)
    local music_files = get_files_recursive(music_dir, music_exts)
    local music_added = process_music_files_threaded(music_files, "Checking Music")
    if music_added > 0 then
        new_count = new_count + music_added
    end

    if music_added > 0 then
        sort_music_collections()
        indexing.scan_progress = "Updating Album Thumbnails..."
        coroutine.yield()
        generate_album_thumbnails()
    else
        local needs_album_thumbnail_refresh = false
        for _, album in pairs(indexing.data.music.albums or {}) do
            if not album.thumb_path or not file_exists(album.thumb_path)
               or not album.thumb_path_small or not file_exists(album.thumb_path_small)
               or album.thumb_version ~= ALBUM_THUMB_VERSION then
                needs_album_thumbnail_refresh = true
                break
            end
        end

        if needs_album_thumbnail_refresh then
            indexing.scan_progress = "Restoring Album Thumbnails..."
            coroutine.yield()
            generate_album_thumbnails()
        end
    end

    indexing.scan_progress = "Counting Photos & Videos..."
    coroutine.yield(indexing.scan_progress)
    indexing.data.photo_count = indexing.count_photos(photo_dir)
    indexing.data.video_count = indexing.count_videos(video_dir)

    if new_count > 0 or removed_count > 0 then
        indexing.save()
        indexing.scan_result_message = string.format("Index updated: +%d new, -%d removed", new_count, removed_count)
    end

    indexing.is_scanning = false
    indexing.scan_progress = "Done"
end

function indexing.get_album_thumb_path(album_name, album_artist)
    if not album_name or album_name == "" or album_name == "Unknown Album" then
        return nil
    end
    if not indexing.data or not indexing.data.music or not indexing.data.music.albums then
        return nil
    end

    local norm_name = normalize_key(album_name)
    local norm_artist = normalize_key(album_artist or "")

    local exact_key = norm_name .. "::" .. norm_artist
    local album = indexing.data.music.albums[exact_key]
    if album and album.thumb_path and file_exists(album.thumb_path) then
        return album.thumb_path
    end

    local fallback_key = norm_name .. "::"
    album = indexing.data.music.albums[fallback_key]
    if album and album.thumb_path and file_exists(album.thumb_path) then
        return album.thumb_path
    end

    for _, alb in pairs(indexing.data.music.albums) do
        if alb.name and normalize_key(alb.name) == norm_name and alb.thumb_path and file_exists(alb.thumb_path) then
            return alb.thumb_path
        end
    end

    return nil
end

function indexing.get_album_thumb_path_for_track(track_path)
    if not track_path or not indexing.data or not indexing.data.music then
        return nil
    end
    local file_info = indexing.data.music.files[track_path]
    if file_info and file_info.album then
        return indexing.get_album_thumb_path(file_info.album, file_info.album_artist)
    end
    return nil
end

function indexing.count_photos(photo_dir)
    if not photo_dir or photo_dir == "" then return 0 end
    local photo_exts = indexing.compatible_extensions.photo
    local files = get_files_recursive(photo_dir, photo_exts)
    return #files
end

function indexing.ensure_photo_count(photo_dir)
    if (indexing.data.photo_count == nil or indexing.data.photo_count == 0) and photo_dir and photo_dir ~= "" then
        indexing.data.photo_count = indexing.count_photos(photo_dir)
        indexing.save()
    end
    return indexing.data.photo_count or 0
end

function indexing.count_videos(video_dir)
    if not video_dir or video_dir == "" then return 0 end
    local video_exts = indexing.compatible_extensions.video
    local files = get_files_recursive(video_dir, video_exts)
    return #files
end

function indexing.ensure_video_count(video_dir)
    if (indexing.data.video_count == nil or indexing.data.video_count == 0) and video_dir and video_dir ~= "" then
        indexing.data.video_count = indexing.count_videos(video_dir)
        indexing.save()
    end
    return indexing.data.video_count or 0
end

return indexing
