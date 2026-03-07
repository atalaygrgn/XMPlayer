local theme = require("theme")
local browser = require("browser")
local assets = require("assets")
local metadata = require("metadata")
local ui = require("ui")
local utils = require("utils")

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
music.cover_art = nil      -- love.graphics Image for album art

-- Metadata tags
music.tags = {}
music.next_tags = {}

-- Animation / UI
music.fade_alpha = 0       -- Fade-in animation
music.marquees = {}

function music.init()
    -- Subsystem init happens in assets.load() now
    -- We'll just pre-create marquees here
    local info_w = love.graphics.getWidth() * 0.6
    music.marquees.title = ui.new_marquee(info_w)
    music.marquees.artist = ui.new_marquee(info_w)
    music.marquees.album = ui.new_marquee(info_w)
end

local function build_playlist()
    music.playlist = {}
    for i, item in ipairs(browser.files) do
        if item.type == "file" then
            table.insert(music.playlist, {name = item.name, path = item.path, index = i})
        end
    end
end

function music.load_track(track_info)
    -- Stop any current track
    music.stop()

    music.current_track = track_info
    music.elapsed = 0
    
    -- Reset marquees
    for _, m in pairs(music.marquees) do
        m.offset = 0
        m.timer = 0
        m.phase = "pause_start"
    end

    -- Extract metadata
    music.tags = metadata.get_tags(track_info.path)
    
    -- Pre-load next track tags for display
    if #music.playlist > 1 then
        local next_idx = (music.current_index % #music.playlist) + 1
        music.next_tags = metadata.get_tags(music.playlist[next_idx].path)
    else
        music.next_tags = {}
    end

    -- Load cover art if available
    music.cover_art = nil
    if music.tags.cover_data then
        local ok, result = pcall(function()
            local fd = love.filesystem.newFileData(music.tags.cover_data, "cover." .. (music.tags.cover_ext or "jpg"))
            local id = love.image.newImageData(fd)
            return love.graphics.newImage(id)
        end)
        if ok then 
            music.cover_art = result 
        end
    end

    -- Load audio
    local file_handle = io.open(track_info.path, "rb")
    if not file_handle then
        music.playing = false
        return false
    end

    local file_data_raw = file_handle:read("*a")
    file_handle:close()

    if not file_data_raw or #file_data_raw == 0 then
        music.playing = false
        return false
    end

    local ok, result = pcall(function()
        local fd = love.filesystem.newFileData(file_data_raw, track_info.name)
        music.sound_data = love.sound.newSoundData(fd)
        return love.audio.newSource(music.sound_data)
    end)

    if ok and result then
        music.source = result
        music.duration = music.sound_data:getDuration()
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

function music.play(filepath)
    build_playlist()

    local track_info = nil
    for i, t in ipairs(music.playlist) do
        if t.path == filepath then
            music.current_index = i
            track_info = t
            break
        end
    end

    if not track_info then
        track_info = {name = utils.get_filename(filepath), path = filepath}
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
        music.sound_data = nil
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

    -- Update playback
    if music.source and music.playing and not music.paused then
        music.elapsed = music.source:tell()
        if not music.source:isPlaying() then
            music.next_track()
        end
    end

    -- Update marquees
    if music.current_track then
        local info_w = love.graphics.getWidth() * 0.6
        music.marquees.title.max_width = info_w
        music.marquees.artist.max_width = info_w
        music.marquees.album.max_width = info_w

        local track_name = music.tags.title or utils.get_track_name(music.current_track.name)
        ui.update_marquee(music.marquees.title, dt, assets.fonts.title:getWidth(track_name))

        local artist_name = music.tags.artist or "Unknown Artist"
        ui.update_marquee(music.marquees.artist, dt, assets.fonts.artist:getWidth(artist_name))

        local album_name = music.tags.album or "Unknown Album"
        ui.update_marquee(music.marquees.album, dt, assets.fonts.album:getWidth(album_name))
    end
end

function music.draw()
    if not music.active then return end

    local w, h = love.graphics.getDimensions()
    local alpha = music.fade_alpha

    -- Header
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha)
    love.graphics.setFont(assets.fonts.small)
    love.graphics.printf("XMPlayer", 20, 10, w, "left")

    if #music.playlist > 0 then
        love.graphics.printf(music.current_index .. " of " .. #music.playlist, 0, 10, w - 16, "right")
    end

    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
    love.graphics.rectangle("fill", 20, 40, w - 40, 1)

    -- Album Art
    local art_size = math.min(w, h) * 0.3
    local art_x, art_y = w * 0.05, 60

    if music.cover_art then
        local img_w, img_h = music.cover_art:getDimensions()
        local scale = art_size / math.max(img_w, img_h)
        local draw_w, draw_h = img_w * scale, img_h * scale
        local ox, oy = (art_size - draw_w) / 2, (art_size - draw_h) / 2

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", art_x - 4, art_y - 4, art_size + 8, art_size + 8, 6, 6)

        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(music.cover_art, art_x + ox, art_y + oy, 0, scale, scale)
    else
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", art_x - 4, art_y - 4, art_size + 8, art_size + 8, 6, 6)
        
        ui.draw_icon(assets.images.music, art_x + art_size/2, art_y + art_size/2, art_size * 0.4, theme.text, 0.2 * alpha)
    end

    -- Track Info
    if music.current_track then
        local info_x, info_y, info_w = w * 0.3, 60, w * 0.6

        -- Title
        local track_name = music.tags.title or utils.get_track_name(music.current_track.name)
        ui.draw_marquee(music.marquees.title, track_name, info_x, info_y, assets.fonts.title, {theme.text[1], theme.text[2], theme.text[3], alpha}, info_x, info_y)

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", info_x, info_y + 40, info_w, 1)

        -- Artist
        local artist_name = music.tags.artist or "Unknown Artist"
        ui.draw_marquee(music.marquees.artist, artist_name, info_x, info_y + 46, assets.fonts.artist, {theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha}, info_x, info_y + 46)

        -- Album
        local album_name = music.tags.album or "Unknown Album"
        ui.draw_marquee(music.marquees.album, album_name, info_x, info_y + 74, assets.fonts.album, {theme.text[1], theme.text[2], theme.text[3], 0.4 * alpha}, info_x, info_y + 74)

        -- Next Track Info
        local extra_y = info_y + 110
        if #music.playlist > 1 then
            local next_idx = (music.current_index % #music.playlist) + 1
            local next_track = music.playlist[next_idx]
            -- Display track name if possible
            local track_name = music.next_tags.title or utils.get_track_name(next_track.name)
            local next_name = "Next: " .. track_name
            local next_w_max = info_w * 0.7
            local display_next = utils.truncate_text(next_name, assets.fonts.small, next_w_max)
            
            love.graphics.setFont(assets.fonts.small)
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.4 * alpha)
            love.graphics.print(display_next, info_x, extra_y)
        end

        local ext = utils.get_extension(music.current_track.path)
        if ext then
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.3 * alpha)
            love.graphics.printf(ext:sub(2):upper(), info_x, extra_y, info_w, "right")
        end

        -- Player Status Icon
        local status_icon = music.paused and assets.images.pause or assets.images.play
        ui.draw_icon(status_icon, 48, h - 36, 48, theme.text, 0.8 * alpha)
    end

    -- Progress Bar
    local bar_w, bar_h = w * 0.4, 4
    local bar_x, bar_y = w - bar_w - 30, h - 30
    local progress = music.duration > 0 and (music.elapsed / music.duration) or 0

    love.graphics.setFont(assets.fonts.time_elapsed)
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.9 * alpha)
    love.graphics.print(utils.format_time(music.elapsed), bar_x + bar_w - 120, bar_y - 36)

    love.graphics.setFont(assets.fonts.time_dur)
    love.graphics.printf("/ " .. utils.format_time(music.duration), 0, bar_y - 30, bar_x + bar_w, "right")

    ui.draw_progress_bar(bar_x, bar_y, bar_w, bar_h, progress, {0.55, 0.65, 1.0, 0.9 * alpha}, {theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha})
end

function music.keypressed(key)
    if not music.active then return false end

    if key == "a" or key == "return" then
        music.toggle_pause()
        return true
    elseif key == "right" then
        music.next_track()
        return true
    elseif key == "left" then
        music.prev_track()
        return true
    elseif key == "b" or key == "backspace" then
        music.close()
        return true
    end

    return false
end

return music
