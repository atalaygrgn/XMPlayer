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
    music = { ".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".opus", ".wma"},
    photo = { ".jpg", ".jpeg", ".png", ".gif", ".bmp" },
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
    local artists = {}
    local seen = {}

    for _, artist in ipairs(utils.split(artist_str or "", ",")) do
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

local function add_music_file(path)
    if indexing.data.music.files[path] then
        return false
    end

    local tags = metadata.get_tags(path)
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

    return true
end

local function rebuild_music_collections_from_files()
    local old_files = indexing.data.music.files or {}
    local old_albums = indexing.data.music.albums or {}
    indexing.data.music.albums = {}
    indexing.data.music.artists = {}

    for path, info in pairs(old_files) do
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
    local ok, img_data = pcall(love.image.newImageData, image_path)
    if not ok or not img_data then
        -- Fallback: try reading via io if love.image.newImageData(path) failed (e.g. absolute path issue)
        local f = io.open(image_path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data then
                local file_data = love.filesystem.newFileData(data, "temp_img")
                ok, img_data = pcall(love.image.newImageData, file_data)
            end
        end
    end

    if not ok or not img_data then return nil end

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

        local safe_name = image_path:gsub("[^%w]", "_")
        local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. ".png"

        -- Create thumb dir if not exists
        if os.execute("test -d \"" .. indexing.thumb_dir .. "\"") ~= 0 then
            os.execute("mkdir -p \"" .. indexing.thumb_dir .. "\"")
        end

        local file_data = thumb_data:encode("png")
        local f = io.open(thumb_path, "wb")
        if f then
            f:write(file_data:getString())
            f:close()
        end
        return thumb_path
    end
    return image_path
end

local function generate_thumbnail_from_image_data(img_data, album_key)
    if not img_data then return nil end
    
    local w, h = img_data:getDimensions()
    if not w or not h or w <= 0 or h <= 0 then return nil end
    
    local thumb_size = 120
    local scale = thumb_size / math.max(w, h)
    local tw, th = math.floor(w * scale), math.floor(h * scale)
    
    local thumb_data = img_data
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
    end
    
    ensure_thumb_dir()
    local safe_name = ("album_" .. album_key):gsub("[^%w]", "_")
    local thumb_path = indexing.thumb_dir .. "/" .. safe_name .. ".png"
    
    local png_data = thumb_data:encode("png")
    local f = io.open(thumb_path, "wb")
    if f then
        f:write(png_data:getString())
        f:close()
        return thumb_path
    end
    
    return nil
end

local function generate_album_thumbnails()
    for album_key, album in pairs(indexing.data.music.albums or {}) do
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
                    end
                end
            end
            album.thumb_version = ALBUM_THUMB_VERSION
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

    for i, path in ipairs(music_files) do
        indexing.scan_progress = string.format("Indexing Music (%d/%d)", i, #music_files)
        if i % 5 == 0 then coroutine.yield() end -- Yield every 5 files to speed up but keep UI responsive
        add_music_file(path)
    end

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
        if i % 10 == 0 then coroutine.yield(indexing.scan_progress) end

        local photo_info = indexing.data.photos[path] or { thumb_path = nil }
        if not photo_info.thumb_path then
            photo_info.thumb_path = indexing.generate_thumbnail(path)
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
    local music_added = 0
    for i, path in ipairs(music_files) do
        if i % 10 == 0 then
            indexing.scan_progress = string.format("Checking Music (%d/%d)", i, #music_files)
            coroutine.yield(indexing.scan_progress)
        end
        if add_music_file(path) then
            new_count = new_count + 1
            music_added = music_added + 1
        end
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
        if i % 10 == 0 then
            indexing.scan_progress = string.format("Checking Photos (%d/%d)", i, #photo_files)
            coroutine.yield(indexing.scan_progress)
        end
        local photo_info = indexing.data.photos[path]
        if not photo_info then
            indexing.data.photos[path] = {
                thumb_path = indexing.generate_thumbnail(path)
            }
            new_count = new_count + 1
        elseif not photo_info.thumb_path then
            photo_info.thumb_path = indexing.generate_thumbnail(path)
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
