local metadata = require("metadata")
local utils = require("utils")

local indexing = {}

local storage_path = love.filesystem.getSource()
indexing.file_path = storage_path .. "/index.cfg"
indexing.thumb_dir = storage_path .. "/thumbnails"
indexing.data = {
    music = {
        albums = {}, -- {name = "Album Name", artist = "Artist Name", tracks = {path, ...}}
        artists = {}, -- {name = "Artist Name", albums = {name, ...}, tracks = {path, ...}}
        files = {} -- {path = {title, artist, album, ...}}
    },
    photos = {}, -- {path = {thumb_path, ...}}
    videos = {} -- {path, ...}
}

indexing.is_scanning = false
indexing.scan_progress = ""

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
        local thumb_data = love.image.newImageData(tw, th)
        -- Linear interpolation is slow in Lua, but Love2D doesn't have a built-in resize ImageData in 11.x without Canvas
        -- However, we can use a Canvas to scale and then get ImageData back
        local canvas = love.graphics.newCanvas(tw, th)
        love.graphics.setCanvas(canvas)
        local temp_img = love.graphics.newImage(img_data)
        love.graphics.draw(temp_img, 0, 0, 0, scale, scale)
        love.graphics.setCanvas()
        thumb_data = canvas:newImageData()
        temp_img:release()
        
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
    return nil
end

local function get_files_recursive(path, extensions)
    local files = {}
    local cmd = "find \"" .. path .. "\" -type f 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            local ext = line:match("%.([^%.]+)$")
            if ext then
                ext = "." .. ext:lower()
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
    
    local music_exts = {".mp3", ".wav", ".flac", ".ogg", ".m4a"}
    local photo_exts = {".jpg", ".jpeg", ".png", ".gif", ".bmp"}
    local video_exts = {".mp4", ".mkv", ".avi", ".mov", ".wmv"}

    -- Reset data but keep existing photo thumbnails if any
    local old_photos = indexing.data.photos
    indexing.data = {
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
        
        local tags = metadata.get_tags(path)
        local title = tags.title or utils.get_track_name(path)
        local artist = tags.artist or "Unknown Artist"
        local album = tags.album or "Unknown Album"
        
        indexing.data.music.files[path] = {
            title = title,
            artist = artist,
            album = album
        }

        -- Group by Artist
        if not indexing.data.music.artists[artist] then
            indexing.data.music.artists[artist] = {name = artist, albums = {}, tracks = {}}
        end
        table.insert(indexing.data.music.artists[artist].tracks, path)

        -- Group by Album
        local album_key = artist .. " - " .. album
        if not indexing.data.music.albums[album_key] then
            indexing.data.music.albums[album_key] = {name = album, artist = artist, tracks = {}}
            table.insert(indexing.data.music.artists[artist].albums, album)
        end
        table.insert(indexing.data.music.albums[album_key].tracks, path)
    end

    -- 3. Scan Photos
    indexing.scan_progress = "Scanning Photos..."
    coroutine.yield(indexing.scan_progress)
    local photo_files = get_files_recursive(photo_dir, photo_exts)
    
    local new_photos = {}
    for i, path in ipairs(photo_files) do
        indexing.scan_progress = string.format("Indexing Photos (%d/%d)", i, #photo_files)
        coroutine.yield(indexing.scan_progress)
        
        local photo_info = indexing.data.photos[path] or {thumb_path = nil}
        if not photo_info.thumb_path then
            photo_info.thumb_path = indexing.generate_thumbnail(path)
        end
        new_photos[path] = photo_info
    end
    indexing.data.photos = new_photos

    indexing.save()
    indexing.is_scanning = false
    indexing.scan_progress = "Done"
end

return indexing
