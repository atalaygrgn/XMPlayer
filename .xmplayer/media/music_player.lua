local browser              = require("browser")
local assets               = require("assets")
local metadata             = require("metadata")
local ui                   = require("ui")
local utils                = require("utils")
local ffmpeg_audio         = require("ffmpeg_audio")
local viewport             = require("viewport")
local indexing             = require("indexing")

local music                = {}

-- Player state
music.active               = false -- Is the music player view showing?
music.playing              = false -- Is audio currently playing?
music.paused               = false
music.current_track        = nil   -- {name, path}
music.current_index        = 0     -- Index in the playlist
music.playlist             = {}    -- List of tracks from current folder
music.source               = nil   -- FFmpeg audio backend (for compatibility)
music.sound_data           = nil   -- Compatibility wrapper for visualizers
music.elapsed              = 0     -- Elapsed time in seconds
music.duration             = 0     -- Total duration in seconds
music.cover_art            = nil   -- love.graphics Image for album art
music.repeat_one           = false
music.auto_sleep_minutes   = 0
music.auto_sleep_remaining = nil
music.visualizer_mode      = "wave" -- off, wave, bars

-- Metadata tags
music.tags                 = {}
music.next_tags            = {}

-- Animation
music.fade_alpha           = 0
music.slide_x              = 0
music.pending_slide_dir    = nil
music.marquees             = {} -- Populated by music_view.init()

function music.init()
    -- Initialize FFmpeg audio backend
    ffmpeg_audio.init()
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
        local next_path = music.playlist[next_idx].path
        local indexed = (indexing and indexing.data and indexing.data.music and indexing.data.music.files) and
            indexing.data.music.files[next_path]
        if indexed then
            music.next_tags = { title = indexed.title }
        else
            music.next_tags = { title = utils.get_track_name(music.playlist[next_idx].name) }
        end
    else
        music.next_tags = {}
    end

    -- Load cover art if available
    if music.cover_art then
        music.cover_art:release()
    end
    music.cover_art = nil

    if music.tags.cover_data then
        local fd, id, img
        local ok = pcall(function()
            fd = love.filesystem.newFileData(music.tags.cover_data, "cover." .. (music.tags.cover_ext or "jpg"))
            id = love.image.newImageData(fd)
            img = love.graphics.newImage(id)
        end)
        if ok and img then
            music.cover_art = img
        end
        if id then id:release() end
        if fd then fd:release() end
    end

    -- Load audio via FFmpeg backend
    local ok = ffmpeg_audio.load(track_info.path)
    if ok then
        music.source = true -- Placeholder for compatibility
        music.sound_data = ffmpeg_audio.getSoundDataCompat()
        music.duration = ffmpeg_audio.getDuration()
        ffmpeg_audio.play()
        music.playing = true
        music.paused = false
        if music.pending_slide_dir then
            music.slide_x = music.pending_slide_dir
            music.pending_slide_dir = nil
        else
            music.slide_x = 0
        end
        return true
    else
        print("Failed to load with FFmpeg: " .. track_info.path)
        music.playing = false
        music.source = nil
        music.sound_data = nil
        music.pending_slide_dir = nil
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
    music.slide_x = 0
    if music.auto_sleep_minutes > 0 then
        music.auto_sleep_remaining = music.auto_sleep_minutes * 60
    else
        music.auto_sleep_remaining = nil
    end
    music.load_track(track_info)
end

function music.stop()
    ffmpeg_audio.stop()
    music.source = nil
    music.sound_data = nil
    music.playing = false
    music.paused = false
    music.elapsed = 0
end

function music.toggle_pause()
    if not music.source then return end
    if music.paused then
        ffmpeg_audio.play()
        music.paused = false
    else
        ffmpeg_audio.pause()
        music.paused = true
    end
end

function music.next_track()
    if #music.playlist == 0 then return end
    music.current_index = music.current_index + 1
    if music.current_index > #music.playlist then
        music.current_index = 1
    end
    music.pending_slide_dir = 120
    music.load_track(music.playlist[music.current_index])
end

function music.prev_track()
    if #music.playlist == 0 then return end
    if music.elapsed > 3 then
        music.pending_slide_dir = -120
        music.load_track(music.playlist[music.current_index])
    else
        music.current_index = music.current_index - 1
        if music.current_index < 1 then
            music.current_index = #music.playlist
        end
        music.pending_slide_dir = -120
        music.load_track(music.playlist[music.current_index])
    end
end

function music.close()
    music.stop()
    music.active = false
    music.current_track = nil
    music.playlist = {}
    music.slide_x = 0
    music.auto_sleep_remaining = nil
end

function music.set_repeat_one(enabled)
    music.repeat_one = (enabled == true)
end

function music.set_auto_sleep_minutes(minutes)
    local mins = tonumber(minutes) or 0
    mins = math.max(0, math.min(120, math.floor(mins)))
    music.auto_sleep_minutes = mins

    if mins > 0 and music.active then
        music.auto_sleep_remaining = mins * 60
    else
        music.auto_sleep_remaining = nil
    end
end

function music.set_visualizer_mode(mode)
    if mode == "off" or mode == "wave" or mode == "bars" or mode == "walk" then
        music.visualizer_mode = mode
    end
end

function music.update(dt)
    if not music.active then return end

    -- Update FFmpeg audio backend
    ffmpeg_audio.update()

    -- Fade in
    if music.fade_alpha < 1 then
        music.fade_alpha = math.min(1, music.fade_alpha + dt * 4)
    end

    -- Update slide_x
    if music.slide_x and music.slide_x ~= 0 then
        music.slide_x = utils.smooth(music.slide_x, 0, dt, 14)
        if math.abs(music.slide_x) < 0.5 then
            music.slide_x = 0
        end
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

    -- Update playback state
    if music.playing and not music.paused then
        music.elapsed = ffmpeg_audio.getElapsedTime()

        -- Determine track end robustly: only advance when elapsed is at (or very near)
        -- the known duration. This prevents auto-advancing while FFmpeg is buffering
        -- or before playback actually begins (causing 'roulette' skipping).
        local dur = music.duration or 0
        local near_end = (dur > 0) and (music.elapsed >= math.max(0, dur - 0.5))

        if near_end then
            if music.repeat_one and music.playlist[music.current_index] then
                music.pending_slide_dir = 120
                music.load_track(music.playlist[music.current_index])
            else
                music.next_track()
            end
        end
    end

    -- Update marquees
    if music.current_track then
        local info_w = viewport.get() * 0.65
        music.marquees.title.max_width = info_w
        music.marquees.artist.max_width = info_w
        music.marquees.album.max_width = info_w

        local track_name = music.tags.title or utils.get_track_name(music.current_track.name)
        ui.update_marquee(music.marquees.title, dt, ui.measure_text_width(assets.fonts.title, track_name))

        local artist_name = music.tags.artist or "Unknown Artist"
        ui.update_marquee(music.marquees.artist, dt, ui.measure_text_width(assets.fonts.artist, artist_name))

        local album_name = music.tags.album or "Unknown Album"
        ui.update_marquee(music.marquees.album, dt, ui.measure_text_width(assets.fonts.album, album_name))
    end
end

function music.seek(seconds)
    if not music.active or not music.source then return end

    if music.current_track and utils.is_vgm_file(music.current_track.path) then return end

    local target = music.elapsed + seconds
    ffmpeg_audio.seek(target)

    -- Update state immediately for visual responsiveness
    music.elapsed = math.max(0, math.min(target, music.duration))
end

return music
