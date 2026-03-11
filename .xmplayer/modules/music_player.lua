local browser   = require("browser")
local assets    = require("assets")
local metadata  = require("metadata")
local ui        = require("ui")
local utils     = require("utils")

local music = {}

-- Player state
music.active = false      -- Is the music player view showing?
music.playing = false     -- Is audio currently playing?
music.paused = false
music.current_track = nil -- {name, path}
music.current_index = 0   -- Index in the playlist
music.playlist = {}       -- List of tracks from current folder
music.source = nil        -- love.audio Source object
music.elapsed = 0         -- Elapsed time in seconds
music.duration = 0        -- Total duration in seconds
music.cover_art = nil     -- love.graphics Image for album art
music.repeat_one = false
music.auto_sleep_minutes = 0
music.auto_sleep_remaining = nil
music.visualizer_mode = "wave" -- off, wave, bars

-- Metadata tags
music.tags = {}
music.next_tags = {}

-- Animation
music.fade_alpha = 0
music.marquees   = {}  -- Populated by music_view.init()

function music.init()
    -- marquees are initialised by music_view.init() after fonts are loaded
end

local function build_playlist()
    music.playlist = {}
    for i, item in ipairs(browser.files) do
        if item.type == "file" then
            table.insert(music.playlist, { name = item.name, path = item.path, index = i })
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

function music.play(filepath, custom_playlist)
    if custom_playlist then
        music.playlist = custom_playlist
    else
        build_playlist()
    end

    local track_info = nil
    for i, t in ipairs(music.playlist) do
        if t.path == filepath then
            music.current_index = i
            track_info = t
            break
        end
    end

    if not track_info then
        track_info = { name = utils.get_filename(filepath), path = filepath }
        music.current_index = 1
    end

    music.active = true
    music.fade_alpha = 0
    if music.auto_sleep_minutes > 0 then
        music.auto_sleep_remaining = music.auto_sleep_minutes * 60
    else
        music.auto_sleep_remaining = nil
    end
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
    music.auto_sleep_remaining = nil
end

function music.set_repeat_one(enabled)
    music.repeat_one = (enabled == true)
end

function music.set_auto_sleep_minutes(minutes)
    local mins = tonumber(minutes) or 0
    mins = math.max(0, math.min(30, math.floor(mins)))
    music.auto_sleep_minutes = mins

    if mins > 0 and music.active then
        music.auto_sleep_remaining = mins * 60
    else
        music.auto_sleep_remaining = nil
    end
end

function music.set_visualizer_mode(mode)
    if mode == "off" or mode == "wave" or mode == "bars" then
        music.visualizer_mode = mode
    end
end

function music.update(dt)
    if not music.active then return end

    -- Fade in
    if music.fade_alpha < 1 then
        music.fade_alpha = math.min(1, music.fade_alpha + dt * 4)
    end

    if music.auto_sleep_remaining then
        music.auto_sleep_remaining = music.auto_sleep_remaining - dt
        if music.auto_sleep_remaining <= 0 then
            music.auto_sleep_remaining = nil
            ui.show_toast("Auto Sleep: returning to XMB", "music", "bottom_right")
            music.close()
            return
        end
    end

    -- Update playback
    if music.source and music.playing and not music.paused then
        music.elapsed = music.source:tell()
        if not music.source:isPlaying() then
            if music.repeat_one and music.playlist[music.current_index] then
                music.load_track(music.playlist[music.current_index])
            else
                music.next_track()
            end
        end
    end

    -- Update marquees
    if music.current_track then
        local info_w = love.graphics.getWidth() * 0.65
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

return music
