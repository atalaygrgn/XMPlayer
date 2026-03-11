-- music_view.lua
-- Renders the music player screen and handles its keypresses.
-- All playback state lives in music_player.lua.

local theme  = require("theme")
local assets  = require("assets")
local ui      = require("ui")
local utils   = require("utils")
local music   = require("music_player")

local music_view = {}

function music_view.init()
    local info_w = love.graphics.getWidth() * 0.6
    music.marquees.title  = ui.new_marquee(info_w)
    music.marquees.artist = ui.new_marquee(info_w)
    music.marquees.album  = ui.new_marquee(info_w)
end

function music_view.draw()
    if not music.active then return end

    local w, h  = love.graphics.getDimensions()
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
    local art_size   = math.min(w, h) * 0.3
    local art_x, art_y = w * 0.05, 60

    if music.cover_art then
        local img_w, img_h = music.cover_art:getDimensions()
        local scale        = art_size / math.max(img_w, img_h)
        local draw_w, draw_h = img_w * scale, img_h * scale
        local ox, oy       = (art_size - draw_w) / 2, (art_size - draw_h) / 2

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", art_x - 4, art_y - 4, art_size + 8, art_size + 8, 6, 6)

        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(music.cover_art, art_x + ox, art_y + oy, 0, scale, scale)
    else
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", art_x - 4, art_y - 4, art_size + 8, art_size + 8, 6, 6)

        ui.draw_icon(assets.images.music,
            art_x + art_size / 2, art_y + art_size / 2,
            art_size * 0.4, theme.text, 0.2 * alpha)
    end

    -- Track Info
    if music.current_track then
        local info_x, info_y, info_w = w * 0.3, 60, w * 0.6

        -- Title
        local track_name = music.tags.title or utils.get_track_name(music.current_track.name)
        ui.draw_marquee(music.marquees.title, track_name, info_x, info_y, assets.fonts.title,
            { theme.text[1], theme.text[2], theme.text[3], alpha }, info_x, info_y)

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", info_x, info_y + 40, info_w, 1)

        -- Artist
        local artist_name = music.tags.artist or "Unknown Artist"
        ui.draw_marquee(music.marquees.artist, artist_name, info_x, info_y + 46, assets.fonts.artist,
            { theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha }, info_x, info_y + 46)

        -- Album
        local album_name = music.tags.album or "Unknown Album"
        ui.draw_marquee(music.marquees.album, album_name, info_x, info_y + 74, assets.fonts.album,
            { theme.text[1], theme.text[2], theme.text[3], 0.4 * alpha }, info_x, info_y + 74)

        -- Next Track Info
        local extra_y = info_y + 110
        if #music.playlist > 1 then
            local next_idx   = (music.current_index % #music.playlist) + 1
            local next_track = music.playlist[next_idx]
            local next_name  = "Next: " .. (music.next_tags.title or utils.get_track_name(next_track.name))
            local display_next = utils.truncate_text(next_name, assets.fonts.small, info_w * 0.7)

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
        ui.draw_icon(status_icon, 48, h - 42, 48, theme.text, 0.8 * alpha)
    end

    -- Progress Bar
    local bar_w, bar_h = w * 0.4, 4
    local bar_x, bar_y = w - bar_w - 30, h - 30
    local progress     = music.duration > 0 and (music.elapsed / music.duration) or 0

    love.graphics.setFont(assets.fonts.time_elapsed)
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.9 * alpha)
    love.graphics.print(utils.format_time(music.elapsed), bar_x + bar_w - 140, bar_y - 34)

    love.graphics.setFont(assets.fonts.time_dur)
    love.graphics.printf("/ " .. utils.format_time(music.duration), 0, bar_y - 30, bar_x + bar_w, "right")

    ui.draw_progress_bar(bar_x, bar_y, bar_w, bar_h, progress,
        { 0.55, 0.65, 1.0, 0.9 * alpha },
        { theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha })
end

function music_view.keypressed(key)
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

return music_view
