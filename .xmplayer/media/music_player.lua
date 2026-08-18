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
music.cover_art_path       = nil   -- Associated album thumbnail path if active
music.repeat_one           = false
music.shuffle              = false
music.original_playlist    = {}
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

local function ensure_meta_worker()
    if not music.meta_in_chan then
        music.meta_in_chan = love.thread.getChannel("music_metadata_in")
        music.meta_out_chan = love.thread.getChannel("music_metadata_out")
    end
    if not music.meta_thread or not music.meta_thread:isRunning() then
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
            t:start("music_metadata_in", "music_metadata_out")
            music.meta_thread = t
        end
    end
end

function music.update_next_tags()
    if #music.playlist > 1 and music.current_index > 0 and music.playlist[music.current_index] then
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
end

function music.init()
    -- Initialize FFmpeg audio backend
    ffmpeg_audio.init()
    ensure_meta_worker()
    -- marquees are initialised by music_view.init() after fonts are loaded
end

local function build_playlist()
    music.original_playlist = {}
    for i, item in ipairs(browser.files) do
        if item.type == "file" and utils.is_music_file(item.path) then
            table.insert(music.original_playlist, { name = item.name, path = item.path, index = i })
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

    -- Instant initial metadata setup from index for instant UI responsiveness
    local indexed_track = (indexing and indexing.data and indexing.data.music and indexing.data.music.files) and
        indexing.data.music.files[track_info.path]

    if indexed_track then
        music.tags = {
            title = indexed_track.title,
            artist = indexed_track.artist,
            album = indexed_track.album,
            album_artist = indexed_track.album_artist,
            track_number = indexed_track.track_number,
            disc_number = indexed_track.disc_number
        }
    else
        music.tags = {
            title = utils.get_track_name(track_info.name)
        }
    end

    -- Pre-load next track tags for display
    music.update_next_tags()

    -- Associated album art thumbnail handling
    local album_thumb_path = indexing.get_album_thumb_path_for_track(track_info.path)
    if not album_thumb_path and music.tags and music.tags.album then
        album_thumb_path = indexing.get_album_thumb_path(music.tags.album, music.tags.album_artist)
    end

    if album_thumb_path then
        if music.cover_art_path == album_thumb_path and music.cover_art then
            -- Same album thumbnail already loaded; preserve it without resetting/reloading
        else
            local fd, id, img
            local ok = pcall(function()
                local f = io.open(album_thumb_path, "rb")
                if f then
                    local data = f:read("*a")
                    f:close()
                    if data and #data > 0 then
                        fd = love.filesystem.newFileData(data, "album_cover.png")
                        id = love.image.newImageData(fd)
                        img = love.graphics.newImage(id)
                    end
                end
            end)
            if ok and img then
                if music.cover_art then music.cover_art:release() end
                music.cover_art = img
                music.cover_art_path = album_thumb_path
            else
                if music.cover_art then music.cover_art:release() end
                music.cover_art = nil
                music.cover_art_path = nil
            end
            if id then id:release() end
            if fd then fd:release() end
        end
    else
        if music.cover_art_path then
            if music.cover_art then
                music.cover_art:release()
                music.cover_art = nil
            end
            music.cover_art_path = nil
        end
    end

    -- Trigger background metadata & cover art extraction
    music.meta_generation = (music.meta_generation or 0) + 1
    ensure_meta_worker()
    if music.meta_in_chan then
        music.meta_in_chan:push({ type = "extract_file", path = track_info.path, id = music.meta_generation })
    end

    -- Load audio via FFmpeg backend
    local ok = ffmpeg_audio.load(track_info.path)
    if ok then
        music.source = true -- Placeholder for compatibility
        music.sound_data = ffmpeg_audio.getSoundDataCompat()
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

function music.play(filepath, custom_playlist, options)
    if custom_playlist then
        local filtered = {}
        for _, t in ipairs(custom_playlist) do
            local p = (type(t) == "table" and t.path) or t
            if p and utils.is_music_file(p) then
                if type(t) == "table" then
                    table.insert(filtered, t)
                else
                    table.insert(filtered, { name = utils.get_filename(p), path = p })
                end
            end
        end
        music.original_playlist = filtered
    else
        build_playlist()
    end

    local is_shuffle = (options and options.shuffle == true)
    music.shuffle = is_shuffle

    local track_info = nil
    local start_index = 1
    for i, t in ipairs(music.original_playlist) do
        if t.path == filepath then
            start_index = i
            track_info = t
            break
        end
    end

    if not track_info then
        track_info = { name = utils.get_filename(filepath), path = filepath }
        start_index = 1
    end

    if is_shuffle and #music.original_playlist > 1 then
        local others = {}
        for _, t in ipairs(music.original_playlist) do
            if t.path ~= track_info.path then
                table.insert(others, t)
            end
        end
        utils.shuffle(others)
        local new_playlist = { track_info }
        for _, t in ipairs(others) do
            table.insert(new_playlist, t)
        end
        music.playlist = new_playlist
        music.current_index = 1
    else
        music.playlist = {}
        for _, t in ipairs(music.original_playlist) do
            table.insert(music.playlist, t)
        end
        music.current_index = start_index
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
    music.pending_slide_dir = 20
    music.load_track(music.playlist[music.current_index])
end

function music.prev_track()
    if #music.playlist == 0 then return end
    if music.elapsed > 3 then
        music.pending_slide_dir = -20
        music.load_track(music.playlist[music.current_index])
    else
        music.current_index = music.current_index - 1
        if music.current_index < 1 then
            music.current_index = #music.playlist
        end
        music.pending_slide_dir = -20
        music.load_track(music.playlist[music.current_index])
    end
end

function music.close()
    music.stop()
    music.active = false
    music.current_track = nil
    music.playlist = {}
    music.original_playlist = {}
    music.shuffle = false
    music.slide_x = 0
    music.auto_sleep_remaining = nil
    music.duration = 0
    music.cover_art_path = nil
    if music.cover_art then
        music.cover_art:release()
        music.cover_art = nil
    end
end

function music.set_repeat_one(enabled)
    music.repeat_one = (enabled == true)
end

function music.set_shuffle(enabled)
    local new_shuffle = (enabled == true)
    if music.shuffle == new_shuffle then return end
    music.shuffle = new_shuffle

    if #music.original_playlist > 0 then
        local current_track = music.current_track or music.playlist[music.current_index]
        if music.shuffle then
            local others = {}
            for _, t in ipairs(music.original_playlist) do
                if not current_track or t.path ~= current_track.path then
                    table.insert(others, t)
                end
            end
            utils.shuffle(others)

            local new_playlist = {}
            local curr_idx = (music.current_index > 0 and music.current_index <= #music.original_playlist) and music.current_index or 1
            curr_idx = math.min(curr_idx, #others + 1)

            local other_ptr = 1
            for i = 1, #others + 1 do
                if i == curr_idx and current_track then
                    table.insert(new_playlist, current_track)
                else
                    if others[other_ptr] then
                        table.insert(new_playlist, others[other_ptr])
                        other_ptr = other_ptr + 1
                    end
                end
            end
            music.playlist = new_playlist
            music.current_index = curr_idx
        else
            local new_playlist = {}
            for _, t in ipairs(music.original_playlist) do
                table.insert(new_playlist, t)
            end
            music.playlist = new_playlist

            if current_track then
                for i, t in ipairs(music.playlist) do
                    if t.path == current_track.path then
                        music.current_index = i
                        break
                    end
                end
            end
        end
    end

    music.update_next_tags()
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
    local dur = ffmpeg_audio.getDuration()
    if dur and dur > 0 then
        music.duration = dur
    end

    -- Process background metadata extraction results
    if music.meta_out_chan then
        while true do
            local res = music.meta_out_chan:pop()
            if not res then break end
            if res.type == "file_tags" and res.id == music.meta_generation then
                if res.tags then
                    if res.tags.title then music.tags.title = res.tags.title end
                    if res.tags.artist then music.tags.artist = res.tags.artist end
                    if res.tags.album then music.tags.album = res.tags.album end
                    if res.tags.album_artist then music.tags.album_artist = res.tags.album_artist end
                    if res.tags.track_number then music.tags.track_number = res.tags.track_number end
                    if res.tags.disc_number then music.tags.disc_number = res.tags.disc_number end

                    if res.tags.cover_data then
                        if not music.cover_art_path then
                            -- Check if track now has an associated album thumbnail
                            local album_thumb_path = indexing.get_album_thumb_path(res.tags.album or music.tags.album, res.tags.album_artist or music.tags.album_artist)
                            if album_thumb_path then
                                local fd, id, img
                                local ok = pcall(function()
                                    local f = io.open(album_thumb_path, "rb")
                                    if f then
                                        local data = f:read("*a")
                                        f:close()
                                        if data and #data > 0 then
                                            fd = love.filesystem.newFileData(data, "album_cover.png")
                                            id = love.image.newImageData(fd)
                                            img = love.graphics.newImage(id)
                                        end
                                    end
                                end)
                                if ok and img then
                                    if music.cover_art then music.cover_art:release() end
                                    music.cover_art = img
                                    music.cover_art_path = album_thumb_path
                                end
                                if id then id:release() end
                                if fd then fd:release() end
                            end
                        end

                        if not music.cover_art_path then
                            local fd, id, img
                            local ok = pcall(function()
                                fd = love.filesystem.newFileData(res.tags.cover_data, "cover." .. (res.tags.cover_ext or "jpg"))
                                id = love.image.newImageData(fd)
                                img = love.graphics.newImage(id)
                            end)
                            if ok and img then
                                if music.cover_art then music.cover_art:release() end
                                music.cover_art = img
                            end
                            if id then id:release() end
                            if fd then fd:release() end
                        end
                    else
                        if not music.cover_art_path then
                            -- Track has no cover art and no album thumb: release previous cover art
                            if music.cover_art then
                                music.cover_art:release()
                                music.cover_art = nil
                            end
                        end
                    end
                end
            end
        end
    end

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
                music.pending_slide_dir = 20
                music.load_track(music.playlist[music.current_index])
            else
                music.next_track()
            end
        end
    end

    -- Update marquees
    if music.current_track then
        local w, h = viewport.get()
        local art_size = math.min(w, h) * 0.3
        local art_x = w * 0.05
        local info_x = math.max(w * 0.3, art_x + art_size + 12)
        local info_w = (w * 0.95) - info_x
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
