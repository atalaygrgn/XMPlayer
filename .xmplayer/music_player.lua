local theme = require("theme")
local browser = require("browser")

local music = {}

-- Player state
music.active = false       -- Is the music player view showing?
music.playing = false      -- Is audio currently playing?
music.paused = false
music.current_track = nil  -- {name, path}
music.current_index = 0    -- Index in the playlist
music.playlist = {}        -- List of tracks from current folder
music.source = nil         -- love.audio Source object
music.elapsed = 0          -- Elapsed time in seconds
music.duration = 0         -- Total duration in seconds
music.volume = 0.8
music.cover_art = nil      -- love.graphics Image for album art
music.tag_title = nil      -- Embedded ID3 title
music.tag_artist = nil     -- Embedded ID3 artist

-- Scrubber state
music.scrubbing = false
music.scrub_position = 0

-- Animation
music.title_marquee_offset = 0
music.title_marquee_timer = 0
music.artist_marquee_offset = 0
music.artist_marquee_timer = 0
music.fade_alpha = 0       -- Fade-in animation

-- Fonts (set during init)
local title_font
local artist_font
local time_font
local small_font
local music_icon  -- fallback icon when no cover art

function music.init()
    title_font = love.graphics.newFont(24)
    artist_font = love.graphics.newFont(20)
    time_font = love.graphics.newFont(20)
    small_font = love.graphics.newFont(18)
    music_icon = love.graphics.newImage("assets/icons/music.png")
end

local function build_playlist()
    music.playlist = {}
    for i, item in ipairs(browser.files) do
        if item.type == "file" then
            table.insert(music.playlist, {name = item.name, path = item.path, index = i})
        end
    end
end

local function get_track_name(filename)
    -- Strip extension
    return filename:match("(.+)%.[^%.]+$") or filename
end

local function format_time(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

-- Extract a text frame (like TIT2, TPE1) from ID3v2 data
local function extract_id3_text_frame(raw_data, frame_id)
    if #raw_data < 10 then return nil end
    if raw_data:sub(1, 3) ~= "ID3" then return nil end

    local pos = raw_data:find(frame_id)
    if not pos then return nil end

    if pos + 10 > #raw_data then return nil end

    local b1 = raw_data:byte(pos + 4)
    local b2 = raw_data:byte(pos + 5)
    local b3 = raw_data:byte(pos + 6)
    local b4 = raw_data:byte(pos + 7)
    local frame_size = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    if frame_size <= 0 or frame_size > 10000 then return nil end

    local data_start = pos + 10  -- skip frame header
    if data_start + frame_size > #raw_data then return nil end

    local frame_data = raw_data:sub(data_start, data_start + frame_size - 1)

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
local function extract_id3_cover(raw_data)
    -- Check for ID3v2 header: "ID3"
    if #raw_data < 10 then return nil end
    if raw_data:sub(1, 3) ~= "ID3" then return nil end

    -- Search for APIC frame marker
    local apic_pos = raw_data:find("APIC")
    if not apic_pos then return nil end

    -- APIC frame: 4 bytes frame ID + 4 bytes size + 2 bytes flags
    if apic_pos + 10 > #raw_data then return nil end

    local b1 = raw_data:byte(apic_pos + 4)
    local b2 = raw_data:byte(apic_pos + 5)
    local b3 = raw_data:byte(apic_pos + 6)
    local b4 = raw_data:byte(apic_pos + 7)
    local frame_size = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    if frame_size <= 0 or frame_size > #raw_data then return nil end

    -- Skip past frame header (10 bytes from APIC start) into frame data
    local data_start = apic_pos + 10
    local frame_data = raw_data:sub(data_start, data_start + frame_size - 1)

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
    local ok, result = pcall(function()
        local fd = love.filesystem.newFileData(img_data, "cover." .. img_ext)
        local id = love.image.newImageData(fd)
        return love.graphics.newImage(id)
    end)

    if ok and result then
        return result
    end
    return nil
end

-- Try to find a cover image file in the same directory as the track
local function find_folder_cover(track_path)
    local dir = track_path:match("(.*)/[^/]+$")
    if not dir then return nil end

    local candidates = {
        "cover.jpg", "cover.png",
        "Cover.jpg", "Cover.png",
        "folder.jpg", "folder.png",
        "Folder.jpg", "Folder.png",
        "front.jpg", "front.png",
        "Front.jpg", "Front.png",
        "album.jpg", "album.png",
        "Album.jpg", "Album.png",
    }

    for _, name in ipairs(candidates) do
        local full_path = dir .. "/" .. name
        local f = io.open(full_path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data and #data > 0 then
                local ok, result = pcall(function()
                    local fd = love.filesystem.newFileData(data, name)
                    local id = love.image.newImageData(fd)
                    return love.graphics.newImage(id)
                end)
                if ok and result then
                    return result
                end
            end
        end
    end
    return nil
end

function music.load_track(track_info)
    -- Stop any current track
    if music.source then
        music.source:stop()
        music.source = nil
    end

    -- Clear previous metadata
    music.cover_art = nil
    music.tag_title = nil
    music.tag_artist = nil

    music.current_track = track_info
    music.elapsed = 0
    music.title_marquee_offset = 0
    music.title_marquee_timer = 0
    music.artist_marquee_offset = 0
    music.artist_marquee_timer = 0

    -- Use io.open to read the file into memory, then create Source from FileData
    local file_handle = io.open(track_info.path, "rb")
    if not file_handle then
        print("Failed to open file: " .. track_info.path)
        music.playing = false
        return false
    end

    local file_data_raw = file_handle:read("*a")
    file_handle:close()

    if not file_data_raw or #file_data_raw == 0 then
        print("Empty file: " .. track_info.path)
        music.playing = false
        return false
    end

    -- Try to extract embedded metadata from the raw file data
    music.tag_title = extract_id3_text_frame(file_data_raw, "TIT2")
    music.tag_artist = extract_id3_text_frame(file_data_raw, "TPE1")
    music.cover_art = extract_id3_cover(file_data_raw)

    -- If no embedded art, look for folder cover images
    if not music.cover_art then
        music.cover_art = find_folder_cover(track_info.path)
    end

    local ok, result = pcall(function()
        local fd = love.filesystem.newFileData(file_data_raw, track_info.name)
        local source = love.audio.newSource(fd, "stream")
        return source
    end)

    if ok and result then
        music.source = result
        music.source:setVolume(music.volume)
        music.duration = music.source:getDuration()
        if music.duration <= 0 then music.duration = 0 end
        music.source:play()
        music.playing = true
        music.paused = false
        return true
    else
        print("Failed to decode: " .. tostring(result))
        music.playing = false
        return false
    end
end

function music.play(filepath, files_list)
    -- Build playlist from current browser files
    build_playlist()

    -- Find the selected track in the playlist
    local track_info = nil
    for i, t in ipairs(music.playlist) do
        if t.path == filepath then
            music.current_index = i
            track_info = t
            break
        end
    end

    if not track_info then
        track_info = {name = filepath:match("([^/]+)$"), path = filepath}
        music.current_index = 1
    end

    music.active = true
    music.fade_alpha = 0
    music.load_track(track_info)
end

function music.stop()
    if music.source then
        music.source:stop()
        music.source = nil
    end
    music.playing = false
    music.paused = false
    music.elapsed = 0
end

function music.toggle_pause()
    if not music.source then return end
    if music.paused then
        music.source:play()
        music.paused = false
    else
        music.source:pause()
        music.paused = true
    end
end

function music.next_track()
    if #music.playlist == 0 then return end
    music.current_index = music.current_index + 1
    if music.current_index > #music.playlist then
        music.current_index = 1
    end
    music.load_track(music.playlist[music.current_index])
end

function music.prev_track()
    if #music.playlist == 0 then return end
    -- If we're more than 3 seconds in, restart the current track
    if music.elapsed > 3 then
        music.load_track(music.playlist[music.current_index])
    else
        music.current_index = music.current_index - 1
        if music.current_index < 1 then
            music.current_index = #music.playlist
        end
        music.load_track(music.playlist[music.current_index])
    end
end

function music.close()
    music.stop()
    music.active = false
    music.current_track = nil
    music.playlist = {}
end

function music.update(dt)
    if not music.active then return end

    -- Fade in
    if music.fade_alpha < 1 then
        music.fade_alpha = math.min(1, music.fade_alpha + dt * 4)
    end

    -- Update elapsed from source
    if music.source and music.playing and not music.paused then
        music.elapsed = music.source:tell()

        -- Check if track ended
        if not music.source:isPlaying() and not music.paused then
            music.next_track()
        end
    end

    -- Marquee for long titles and artist names
    if music.current_track then
        local w = love.graphics.getWidth()
        local info_w = w * 0.44

        -- Title marquee
        local track_name = music.tag_title or get_track_name(music.current_track.name)
        local title_text_w = title_font:getWidth(track_name)
        if title_text_w > info_w then
            music.title_marquee_timer = music.title_marquee_timer + dt
            if music.title_marquee_timer > 1.5 then
                music.title_marquee_offset = music.title_marquee_offset + dt * 40
                if music.title_marquee_offset > title_text_w + 50 then
                    music.title_marquee_offset = -info_w * 0.6
                    music.title_marquee_timer = 0
                end
            end
        else
            music.title_marquee_offset = 0
            music.title_marquee_timer = 0
        end

        -- Artist marquee
        local artist_name = music.tag_artist or music.current_track.path:match(".*/(.+)/[^/]+$") or "Unknown"
        local artist_text_w = artist_font:getWidth(artist_name)
        if artist_text_w > info_w then
            music.artist_marquee_timer = music.artist_marquee_timer + dt
            if music.artist_marquee_timer > 1.5 then
                music.artist_marquee_offset = music.artist_marquee_offset + dt * 40
                if music.artist_marquee_offset > artist_text_w + 50 then
                    music.artist_marquee_offset = -info_w * 0.6
                    music.artist_marquee_timer = 0
                end
            end
        else
            music.artist_marquee_offset = 0
            music.artist_marquee_timer = 0
        end
    end
end

function music.draw()
    if not music.active then return end

    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    -- Full-screen dark background
    love.graphics.setColor(0.06, 0.06, 0.12, music.fade_alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- iPod Classic layout
    -- Top: "Now Playing" header
    -- Center: Disc art + track info
    -- Bottom: Progress bar + controls hint

    local alpha = music.fade_alpha

    -- ─── Header ───
    love.graphics.setColor(1, 1, 1, 0.6 * alpha)
    love.graphics.setFont(small_font)
    love.graphics.printf("Now Playing", 0, 20, w, "center")

    -- Track counter
    if #music.playlist > 0 then
        love.graphics.printf(
            music.current_index .. " of " .. #music.playlist,
            0, 20, w - 16, "right"
        )
    end

    -- Thin separator line
    love.graphics.setColor(1, 1, 1, 0.15 * alpha)
    love.graphics.rectangle("fill", 20, 60, w - 40, 1)

    -- ─── Album Art Square ───
    local art_size = math.min(w, h) * 0.5
    local art_x = w * 0.1
    local art_y = h * 0.5 - art_size / 2

    if music.cover_art then
        -- Draw cover art scaled to fit the square
        local img_w = music.cover_art:getWidth()
        local img_h = music.cover_art:getHeight()
        local scale = art_size / math.max(img_w, img_h)
        local draw_w = img_w * scale
        local draw_h = img_h * scale
        local offset_x = (art_size - draw_w) / 2
        local offset_y = (art_size - draw_h) / 2

        -- Subtle shadow behind the art
        love.graphics.setColor(0, 0, 0, 0.4 * alpha)
        love.graphics.rectangle("fill", art_x + 3, art_y + 3, art_size, art_size, 6, 6)

        -- Art border
        love.graphics.setColor(0.2, 0.22, 0.3, 0.6 * alpha)
        love.graphics.rectangle("fill", art_x - 2, art_y - 2, art_size + 4, art_size + 4, 6, 6)

        -- The cover art image
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(music.cover_art, art_x + offset_x, art_y + offset_y, 0, scale, scale)
    else
        -- No cover art: dark square with music icon
        -- Shadow
        love.graphics.setColor(0, 0, 0, 0.3 * alpha)
        love.graphics.rectangle("fill", art_x + 3, art_y + 3, art_size, art_size, 6, 6)

        -- Square background
        love.graphics.setColor(0.1, 0.12, 0.18, 0.9 * alpha)
        love.graphics.rectangle("fill", art_x, art_y, art_size, art_size, 6, 6)

        -- Border
        love.graphics.setColor(0.25, 0.28, 0.38, 0.5 * alpha)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", art_x, art_y, art_size, art_size, 6, 6)

        -- Music icon centered in the square
        local icon_w = music_icon:getWidth()
        local icon_h = music_icon:getHeight()
        local icon_target = art_size * 0.4
        local icon_scale = icon_target / math.max(icon_w, icon_h)
        local icon_draw_x = art_x + (art_size - icon_w * icon_scale) / 2
        local icon_draw_y = art_y + (art_size - icon_h * icon_scale) / 2

        love.graphics.setColor(0.5, 0.55, 0.7, 0.5 * alpha)
        love.graphics.draw(music_icon, icon_draw_x, icon_draw_y, 0, icon_scale, icon_scale)
    end

    -- ─── Track Info (right side of disc) ───
    if music.current_track then
        local info_x = w * 0.52
        local info_y = h * 0.28
        local info_w = w * 0.44

        -- Track title (with marquee if needed)
        local track_name = music.tag_title or get_track_name(music.current_track.name)
        love.graphics.setFont(title_font)
        local title_text_w = title_font:getWidth(track_name)

        -- Clip region for title marquee
        love.graphics.setScissor(info_x, info_y, info_w, 30)
        love.graphics.setColor(1, 1, 1, alpha)
        if title_text_w > info_w then
            love.graphics.print(track_name, info_x - music.title_marquee_offset, info_y)
        else
            love.graphics.print(track_name, info_x, info_y)
        end
        love.graphics.setScissor()

        -- Artist name (with marquee if needed)
        local artist_name = music.tag_artist or music.current_track.path:match(".*/(.+)/[^/]+$") or "Unknown"
        love.graphics.setFont(artist_font)
        local artist_text_w = artist_font:getWidth(artist_name)

        love.graphics.setScissor(info_x, info_y + 30, info_w, 26)
        love.graphics.setColor(0.7, 0.7, 0.8, 0.7 * alpha)
        if artist_text_w > info_w then
            love.graphics.print(artist_name, info_x - music.artist_marquee_offset, info_y + 30)
        else
            love.graphics.print(artist_name, info_x, info_y + 30)
        end
        love.graphics.setScissor()

        -- Status indicator
        love.graphics.setFont(small_font)
        love.graphics.setColor(0.5, 0.6, 0.9, 0.6 * alpha)
        local status = music.paused and "❙❙ Paused" or (music.playing and "► Playing" or "■ Stopped")
        love.graphics.print(status, info_x, info_y + 50)

        -- Volume bar
        local vol_x = info_x
        local vol_y = info_y + 72
        local vol_w = info_w * 0.6
        local vol_h = 4

        love.graphics.setFont(small_font)
        love.graphics.setColor(0.6, 0.6, 0.7, 0.5 * alpha)
        love.graphics.print("Vol", vol_x, vol_y - 2)

        local bar_x = vol_x + 30
        love.graphics.setColor(1, 1, 1, 0.1 * alpha)
        love.graphics.rectangle("fill", bar_x, vol_y, vol_w, vol_h, 2, 2)
        love.graphics.setColor(0.5, 0.6, 0.9, 0.7 * alpha)
        love.graphics.rectangle("fill", bar_x, vol_y, vol_w * music.volume, vol_h, 2, 2)
    end

    -- ─── Progress Bar ───
    local bar_y = h - 60
    local bar_x = 30
    local bar_w = w - 60
    local bar_h = 4

    -- Time labels
    love.graphics.setFont(time_font)
    love.graphics.setColor(1, 1, 1, 0.8 * alpha)
    love.graphics.print(format_time(music.elapsed), bar_x, bar_y - 22)

    local dur_text = format_time(music.duration)
    love.graphics.printf(dur_text, 0, bar_y - 22, w - bar_x, "right")

    -- Bar background
    love.graphics.setColor(1, 1, 1, 0.12 * alpha)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 2, 2)

    -- Bar fill
    local progress = 0
    if music.duration > 0 then
        progress = music.elapsed / music.duration
    end
    love.graphics.setColor(0.55, 0.65, 1.0, 0.9 * alpha)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * progress, bar_h, 2, 2)

    -- Playhead dot
    local dot_x = bar_x + bar_w * progress
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.circle("fill", dot_x, bar_y + bar_h / 2, 6)
    love.graphics.setColor(0.55, 0.65, 1.0, alpha)
    love.graphics.circle("fill", dot_x, bar_y + bar_h / 2, 4)

    -- ─── Controls Hint ───
    love.graphics.setFont(small_font)
    love.graphics.setColor(1, 1, 1, 0.35 * alpha)
    love.graphics.printf("A Play/Pause  ◄► Prev/Next  ▲▼ Volume  B Back", 0, h - 22, w, "center")
end

function music.keypressed(key)
    if not music.active then return false end

    if key == "a" or key == "return" or key == "enter" then
        music.toggle_pause()
        return true
    elseif key == "right" then
        music.next_track()
        return true
    elseif key == "left" then
        music.prev_track()
        return true
    elseif key == "up" then
        music.volume = math.min(1.0, music.volume + 0.05)
        if music.source then music.source:setVolume(music.volume) end
        return true
    elseif key == "down" then
        music.volume = math.max(0.0, music.volume - 0.05)
        if music.source then music.source:setVolume(music.volume) end
        return true
    elseif key == "b" or key == "backspace" then
        music.close()
        return true
    end

    return false
end

return music
