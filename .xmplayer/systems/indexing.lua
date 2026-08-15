local metadata = require("metadata")
local utils = require("utils")

local indexing = {}
local INDEX_VERSION = 2
local THUMB_VERSION = 2
local ALBUM_THUMB_VERSION = 1

local storage_path = love.filesystem.getSource()
indexing.file_path = storage_path .. "/index.cfg"
indexing.thumb_dir = storage_path .. "/thumbnails"
indexing.data = {
    version = INDEX_VERSION,
    music = {
        albums = {},  -- {name = "Album Name", artist = "Artist Name", tracks = {path, ...}, thumb_path, thumb_version}
        artists = {}, -- {name = "Artist Name", albums = {name, ...}, tracks = {path, ...}}
        files = {}    -- {path = {title, artist, album, ...}}
    },
    photos = {},      -- {path = {thumb_path, ...}}
    videos = {}       -- {path, ...}
}

indexing.compatible_extensions = {
    music = { ".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".opus", ".wma", ".alac", ".aif", ".aiff",
        -- VGM Files
        ".spc",  -- SNES
        ".nsf",  -- NES
        ".nsfe", -- Extended NES
        ".vgm",  -- Sega Genesis, Master System, Game Gear
        ".vgz",  -- Compressed VGM
        ".gym",  -- Sega Genesis
        ".gbs",  -- GB/GBC
        ".hes",  -- TurboGrafx-16 / PC Engine
        ".kss",  -- MSX & SEGA Master System (Z80)
        ".sap",  -- Atari
        ".ay",   -- ZX Spectrum & Amstrad CPC
        ".mod",  -- Amiga Module
        ".s3m",  -- Scream Tracker 3
        ".xm",   -- FastTracker 2
        ".it"    -- Impulse Tracker
    },
    photo = { ".jpg", ".jpeg", ".png", ".bmp" },
    video = { ".mp4", ".mkv", ".avi", ".mov", ".wmv" }
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

local function get_album_display_artist(album_artist, artist_str, artists)
    if album_artist ~= "" then
        return album_artist
    end

    if #artists > 1 then
        return "Various Artists"
    end

    return artists[1] or artist_str
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
        table.sort(artist_entry.tracks, compare_track_paths)
        table.sort(artist_entry.albums, function(a, b)
            return a:lower() < b:lower()
        end)
    end
end

local function add_music_file_with_tags(path, tags)
    if indexing.data.music.files[path] then
        return false
    end

    tags = tags or metadata.get_tags(path)
    local title = normalize_label(tags.title, utils.get_track_name(path))
    local artist_str = normalize_label(tags.artist, "Unknown Artist")
    local album = normalize_label(tags.album, "Unknown Album")
    local album_artist = utils.trim(tags.album_artist or "")
    local artists = split_artists(artist_str)
    local primary_artist = artists[1]
    local track_number = parse_track_index(tags.track_number)
    local disc_number = parse_track_index(tags.disc_number)

    indexing.data.music.files[path] = {
        title = title,
        artist = artist_str,
        album = album,
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
            add_artist_album(indexing.data.music.artists[a], album)
        end

        local album_group_key = album_artist ~= "" and album_artist or ""
        local album_display_artist = get_album_display_artist(album_artist, artist_str, artists)
        local album_key = normalize_key(album) .. "::" .. normalize_key(album_group_key)
        if not indexing.data.music.albums[album_key] then
            indexing.data.music.albums[album_key] = { name = album, artist = album_display_artist, tracks = {} }
        elseif album_artist ~= "" then
            indexing.data.music.albums[album_key].artist = album_artist
        elseif indexing.data.music.albums[album_key].artist == nil or indexing.data.music.albums[album_key].artist == "" then
            indexing.data.music.albums[album_key].artist = album_display_artist
        end
        table.insert(indexing.data.music.albums[album_key].tracks, path)
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
        local ok, t = pcall(love.thread.newThread, "metadata_worker.lua")
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

    -- Push pending files to thread queue
    for i, path in ipairs(pending) do
        in_chan:push({ type = "extract_file", path = path, id = i })
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
            local album = normalize_label(info.album, "Unknown Album")
            local album_artist = utils.trim(info.album_artist or "")
            local artists = split_artists(artist_str)
            local primary_artist = artists[1]

            for _, a in ipairs(artists) do
                if not indexing.data.music.artists[a] then
                    indexing.data.music.artists[a] = { name = a, albums = {}, tracks = {} }
                end
                table.insert(indexing.data.music.artists[a].tracks, path)
                add_artist_album(indexing.data.music.artists[a], album)
            end

            local album_group_key = album_artist ~= "" and album_artist or ""
            local album_display_artist = get_album_display_artist(album_artist, artist_str, artists)
            local album_key = normalize_key(album) .. "::" .. normalize_key(album_group_key)
            if not indexing.data.music.albums[album_key] then
                local preserved_album = old_albums[album_key] or {}
                indexing.data.music.albums[album_key] = {
                    name = album,
                    artist = album_display_artist,
                    tracks = {},
                    thumb_path = preserved_album.thumb_path,
                    thumb_version = preserved_album.thumb_version
                }
            elseif album_artist ~= "" then
                indexing.data.music.albums[album_key].artist = album_artist
            elseif indexing.data.music.albums[album_key].artist == nil or indexing.data.music.albums[album_key].artist == "" then
                indexing.data.music.albums[album_key].artist = album_display_artist
            end
            table.insert(indexing.data.music.albums[album_key].tracks, path)
        end
    end

    sort_music_collections()
end

function indexing.save()
    local function serialize(o, indent)
        indent = indent or ""
        if type(o) == "number" or type(o) == "boolean" then
            return tostring(o)
        elseif type(o) == "string" then
            return string.format("%q", o)
        elseif type(o) == "table" then
            local s = "{\n"
            for k, v in pairs(o) do
                local key = type(k) == "string" and string.format("[%q]", k) or string.format("[%d]", k)
                s = s .. indent .. "  " .. key .. " = " .. serialize(v, indent .. "  ") .. ",\n"
            end
            return s .. indent .. "}"
        else
            return "nil"
        end
    end
    local data_str = "return " .. serialize(indexing.data)
    local f = io.open(indexing.file_path, "w")
    if f then
        f:write(data_str)
        f:close()
    end
end

function indexing.load()
    local f = io.open(indexing.file_path, "r")
    if f then
        f:close()
        local chunk, err = loadfile(indexing.file_path)
        if chunk then
            local ok, data = pcall(chunk)
            if ok and type(data) == "table" then
                if data.version ~= INDEX_VERSION then
                    return false
                end
                indexing.data = data
                return true
            end
        end
    end
    return false
end

function indexing.generate_thumbnail(image_path)
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
        -- Fallback: try reading via io if love.image.newImageData(path) failed (e.g. absolute path issue)
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
    end

    if not ok or not img_data then return nil, orientation end

    local w, h = img_data:getDimensions()
    local thumb_size = 120
    local scale = thumb_size / math.max(w, h)
    local tw, th = math.floor(w * scale), math.floor(h * scale)

    -- Optimization: Only resize if larger than thumb_size
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
        local thumb_data = canvas:newImageData()
        temp_img:release()
        canvas:release()
        img_data:release()

        local safe_name = image_path:gsub("[^%w]", "_")
        local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. ".png"

        ensure_thumb_dir()

        local file_data = thumb_data:encode("png")
        local f = io.open(thumb_path, "wb")
        if f then
            f:write(file_data:getString())
            f:close()
        end
        file_data:release()
        thumb_data:release()
        return thumb_path, orientation
    else
        img_data:release()
        return image_path, orientation
    end
end

local function generate_thumbnail_from_image_data(img_data, album_key)
    if not img_data then return nil end

    local w, h = img_data:getDimensions()
    if not w or not h or w <= 0 or h <= 0 then return nil end

    local thumb_size = 120
    local scale = thumb_size / math.max(w, h)
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
    local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. ".png"

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
            album.thumb_version = ALBUM_THUMB_VERSION
        else
            if not (album.thumb_path and album.thumb_version == ALBUM_THUMB_VERSION and file_exists(album.thumb_path)) then
                local cover_track = album.tracks and album.tracks[1]
                if cover_track then
                    -- Get folder cover image (cover.jpg, folder.png, etc.) - no metadata parsing
                    local img_bytes, img_ext = metadata.find_folder_cover(cover_track)
                    if img_bytes then
                        local file_data = love.filesystem.newFileData(img_bytes, "album_" .. album_key .. ".bin")
                        local ok, img_data = pcall(love.image.newImageData, file_data)
                        if ok and img_data then
                            album.thumb_path = generate_thumbnail_from_image_data(img_data, album_key)
                            img_data:release()
                        end
                        file_data:release()
                    end
                end
                album.thumb_version = ALBUM_THUMB_VERSION
            end
        end
    end
end

local function get_files_recursive(path, extensions)
    local files = {}
    local cmd = "find \"" .. path .. "\" -type f 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            local ext = utils.get_extension(line)
            if ext then
                for _, allowed in ipairs(extensions) do
                    if ext == allowed then
                        table.insert(files, line)
                        break
                    end
                end
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

    -- Reset data but keep existing photo thumbnails if any
    local old_photos = indexing.data.photos
    indexing.data = {
        version = INDEX_VERSION,
        music = { albums = {}, artists = {}, files = {} },
        photos = old_photos or {},
        videos = {}
    }

    -- 1. Scan Video
    indexing.scan_progress = "Scanning Videos..."
    coroutine.yield(indexing.scan_progress)
    indexing.data.videos = get_files_recursive(video_dir, video_exts)
    coroutine.yield()

    -- 2. Scan Music
    indexing.scan_progress = "Scanning Music..."
    coroutine.yield()
    local music_files = get_files_recursive(music_dir, music_exts)
    coroutine.yield()

    process_music_files_threaded(music_files, "Indexing Music")

    sort_music_collections()

    indexing.scan_progress = "Generating Album Thumbnails..."
    coroutine.yield()
    generate_album_thumbnails()

    -- 3. Scan Photos
    indexing.scan_progress = "Scanning Photos..."
    coroutine.yield(indexing.scan_progress)
    local photo_files = get_files_recursive(photo_dir, photo_exts)

    local new_photos = {}
    for i, path in ipairs(photo_files) do
        indexing.scan_progress = string.format("Indexing Photos (%d/%d)", i, #photo_files)
        coroutine.yield(indexing.scan_progress)

        local photo_info = indexing.data.photos[path] or { thumb_path = nil, orientation = nil }
        if not photo_info.thumb_path or not photo_info.orientation then
            local thumb_path, orientation = indexing.generate_thumbnail(path)
            photo_info.thumb_path = thumb_path
            photo_info.orientation = orientation or 1
        end
        new_photos[path] = photo_info
    end
    indexing.data.photos = new_photos

    indexing.save()
    indexing.is_scanning = false
    indexing.scan_progress = "Done"
    indexing.scan_result_message = "Indexing completed"
end

function indexing.scan_for_new_media(photo_dir, music_dir, video_dir)
    indexing.is_scanning = true
    indexing.scan_result_message = nil

    local music_exts = indexing.compatible_extensions.music
    local photo_exts = indexing.compatible_extensions.photo
    local video_exts = indexing.compatible_extensions.video

    local new_count = 0
    local removed_count = 0

    indexing.data.music = indexing.data.music or { albums = {}, artists = {}, files = {} }
    indexing.data.music.albums = indexing.data.music.albums or {}
    indexing.data.music.artists = indexing.data.music.artists or {}
    indexing.data.music.files = indexing.data.music.files or {}
    indexing.data.photos = indexing.data.photos or {}
    indexing.data.videos = indexing.data.videos or {}

    indexing.scan_progress = "Pruning removed videos..."
    coroutine.yield(indexing.scan_progress)
    local kept_videos = {}
    for _, path in ipairs(indexing.data.videos) do
        if file_exists(path) then
            table.insert(kept_videos, path)
        else
            removed_count = removed_count + 1
        end
    end
    indexing.data.videos = kept_videos

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

    indexing.scan_progress = "Pruning removed photos..."
    coroutine.yield(indexing.scan_progress)
    local kept_photos = {}
    for path, photo_info in pairs(indexing.data.photos) do
        if file_exists(path) then
            kept_photos[path] = photo_info
        else
            removed_count = removed_count + 1
        end
    end
    indexing.data.photos = kept_photos

    indexing.scan_progress = "Checking for new videos..."
    coroutine.yield(indexing.scan_progress)
    local video_files = get_files_recursive(video_dir, video_exts)
    local existing_videos = {}
    for _, path in ipairs(indexing.data.videos or {}) do
        existing_videos[path] = true
    end
    for _, path in ipairs(video_files) do
        if not existing_videos[path] then
            table.insert(indexing.data.videos, path)
            existing_videos[path] = true
            new_count = new_count + 1
        end
    end

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
            if not album.thumb_path or not file_exists(album.thumb_path) or album.thumb_version ~= ALBUM_THUMB_VERSION then
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

    indexing.scan_progress = "Checking for new photos..."
    coroutine.yield(indexing.scan_progress)
    local photo_files = get_files_recursive(photo_dir, photo_exts)
    for i, path in ipairs(photo_files) do
        indexing.scan_progress = string.format("Checking Photos (%d/%d)", i, #photo_files)
        coroutine.yield(indexing.scan_progress)
        local photo_info = indexing.data.photos[path]
        if not photo_info then
            local thumb_path, orientation = indexing.generate_thumbnail(path)
            indexing.data.photos[path] = {
                thumb_path = thumb_path,
                orientation = orientation or 1
            }
            new_count = new_count + 1
        elseif not photo_info.thumb_path or not photo_info.orientation then
            local thumb_path, orientation = indexing.generate_thumbnail(path)
            photo_info.thumb_path = thumb_path or photo_info.thumb_path
            photo_info.orientation = orientation or photo_info.orientation or 1
        end
    end

    if new_count > 0 or removed_count > 0 then
        indexing.save()
        indexing.scan_result_message = string.format("Index updated: +%d new, -%d removed", new_count, removed_count)
    end

    indexing.is_scanning = false
    indexing.scan_progress = "Done"
end

return indexing
