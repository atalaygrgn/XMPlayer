-- music_view.lua
-- Renders the music player screen and handles its keypresses.
-- All playback state lives in music_player.lua.

local theme  = require("theme")
local assets  = require("assets")
local ui      = require("ui")
local utils   = require("utils")
local music   = require("music_player")
local background = require("background")
local settings = require("settings")

local music_view = {}
music_view.buttons_locked = false
music_view.idle_seconds = 0
music_view.display_sleep_alpha = 0
music_view.display_sleeping = false

music_view.context_menu = {
    active = false,
    alpha = 0,
    selected_idx = 1,
    items = {
        "repeat_one",
        "auto_sleep",
        "visualizer"
    }
}

local function repeat_label()
    return music.repeat_one and "On" or "Off"
end

local function auto_sleep_label()
    if music.auto_sleep_minutes <= 0 then
        return "Off"
    end
    return string.format("%dm", music.auto_sleep_minutes)
end

local function visualizer_label()
    if music.visualizer_mode == "off" then
        return "Off"
    elseif music.visualizer_mode == "bars" then
        return "Bars"
    end
    return "Wave"
end

local function cycle_current_option(direction)
    local selected = music_view.context_menu.items[music_view.context_menu.selected_idx]
    if selected == "repeat_one" then
        music.set_repeat_one(not music.repeat_one)
    elseif selected == "auto_sleep" then
        local next_value = music.auto_sleep_minutes + direction
        if next_value > 30 then next_value = 0 end
        if next_value < 0 then next_value = 30 end
        music.set_auto_sleep_minutes(next_value)
    elseif selected == "visualizer" then
        local modes = { "off", "wave", "bars" }
        local idx = 1
        for i, mode in ipairs(modes) do
            if mode == music.visualizer_mode then
                idx = i
                break
            end
        end
        idx = idx + direction
        if idx > #modes then idx = 1 end
        if idx < 1 then idx = #modes end
        music.set_visualizer_mode(modes[idx])
    end
end

function music_view.init()
    local info_w = love.graphics.getWidth() * 0.65
    music.marquees.title  = ui.new_marquee(info_w)
    music.marquees.artist = ui.new_marquee(info_w)
    music.marquees.album  = ui.new_marquee(info_w)
    music_view.buttons_locked = false
end

function music_view.on_music_opened()
    music_view.idle_seconds = 0
    music_view.display_sleep_alpha = 0
    music_view.display_sleeping = false
end

function music_view.on_music_closed()
    music_view.idle_seconds = 0
    music_view.display_sleep_alpha = 0
    music_view.display_sleeping = false
end

function music_view.register_user_input()
    music_view.idle_seconds = 0
    music_view.display_sleeping = false
end

function music_view.is_display_sleeping()
    return music_view.display_sleep_alpha > 0.01
end

function music_view.update(dt)
    if not music.active then return end

    local sleep_seconds = settings.display_sleep_seconds or 0
    if sleep_seconds <= 0 then
        music_view.idle_seconds = 0
        music_view.display_sleeping = false
        music_view.display_sleep_alpha = math.max(0, music_view.display_sleep_alpha - dt * 6)
        return
    end

    music_view.idle_seconds = music_view.idle_seconds + dt
    if music_view.idle_seconds >= sleep_seconds then
        music_view.display_sleep_alpha = math.min(1, music_view.display_sleep_alpha + dt * 2)
    else
        music_view.display_sleep_alpha = math.max(0, music_view.display_sleep_alpha - dt * 6)
    end

    music_view.display_sleeping = (music_view.display_sleep_alpha >= 0.99)
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

    if music.current_track and background.has_custom_wallpaper() then
        local panel_x = w * 0.03
        local panel_y = art_y - 14
        local panel_w = w * 0.94
        local panel_h = art_size + 24

        love.graphics.setColor(0.04, 0.05, 0.07, 0.42 * alpha)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 14, 14)

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.08 * alpha)
        love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 14, 14)
    end

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
        local info_x, info_y, info_w = w * 0.3, 60, w * 0.65
        local extra_y = info_y + 120

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
        if #music.playlist > 1 then
            local next_idx   = (music.current_index % #music.playlist) + 1
            local next_track = music.playlist[next_idx]
            local next_name  = "Next: " .. (music.next_tags.title or utils.get_track_name(next_track.name))
            local display_next = utils.truncate_text(next_name, assets.fonts.small, info_w * 0.8)

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

        if music_view.buttons_locked and assets.images.lock then
            ui.draw_icon(assets.images.lock, 48, h - 100, 48, theme.text, 0.95 * alpha)
        end

        if music.repeat_one and assets.images.repeat_one then
            ui.draw_icon(assets.images.repeat_one, 100, h - 42, 36, theme.text, 0.8 * alpha)
        end
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

    local menu = music_view.context_menu
    if menu.active then
        menu.alpha = math.min(1, menu.alpha + 0.2)
    else
        menu.alpha = math.max(0, menu.alpha - 0.2)
    end

    if menu.alpha > 0 then
        local menu_w = 300
        local row_h = 44
        local menu_h = (#menu.items * row_h) + 28
        local menu_x = w - menu_w - 20
        local menu_y = bar_y - menu_h - 48

        love.graphics.setColor(0.05, 0.05, 0.08, 0.92 * menu.alpha)
        love.graphics.rectangle("fill", menu_x, menu_y, menu_w, menu_h, 14, 14)

        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.3 * menu.alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", menu_x, menu_y, menu_w, menu_h, 14, 14)

        for i, item_id in ipairs(menu.items) do
            local y = menu_y + 14 + (i - 1) * row_h
            local focused = (i == menu.selected_idx)
            local label = ""
            local value = ""

            if item_id == "repeat_one" then
                label = "Repeat One"
                value = repeat_label()
            elseif item_id == "auto_sleep" then
                label = "Auto Sleep"
                value = auto_sleep_label()
            elseif item_id == "visualizer" then
                label = "Visualizer"
                value = visualizer_label()
            end

            if focused then
                love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.25 * menu.alpha)
                love.graphics.rectangle("fill", menu_x + 10, y - 4, menu_w - 20, row_h - 4, 9, 9)
            end

            love.graphics.setFont(assets.fonts.small)
            if focused then
                ui.draw_glow_text(label, menu_x + 24, y + 2, assets.fonts.small,
                    { theme.text[1], theme.text[2], theme.text[3], menu.alpha }, nil)
            else
                love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.75 * menu.alpha)
                love.graphics.print(label, menu_x + 24, y + 2)
            end

            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.85 * menu.alpha)
            love.graphics.printf(value, menu_x + 20, y + 2, menu_w - 44, "right")
        end
    end

    if music_view.display_sleep_alpha > 0 then
        love.graphics.setColor(0, 0, 0, music_view.display_sleep_alpha)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
end

function music_view.keypressed(key)
    if not music.active then return false end

    local was_sleeping = music_view.display_sleeping

    local lock_combo_pressed = (key == "y" and love.keyboard.isDown("right"))
        or (key == "right" and love.keyboard.isDown("y"))

    music_view.register_user_input()

    if lock_combo_pressed then
        music_view.buttons_locked = not music_view.buttons_locked
        if music_view.buttons_locked then
            music_view.context_menu.active = false
        end
        return true
    end

    if was_sleeping then
        return true
    end

    if music_view.buttons_locked then
        return true
    end

    if music_view.context_menu.active then
        if key == "up" then
            music_view.context_menu.selected_idx = math.max(1, music_view.context_menu.selected_idx - 1)
            return true
        elseif key == "down" then
            music_view.context_menu.selected_idx = math.min(#music_view.context_menu.items,
                music_view.context_menu.selected_idx + 1)
            return true
        elseif key == "left" then
            cycle_current_option(-1)
            return true
        elseif key == "right" or key == "a" or key == "return" then
            cycle_current_option(1)
            return true
        elseif key == "b" or key == "backspace" or key == "x" then
            music_view.context_menu.active = false
            return true
        end
    end

    if key == "a" or key == "return" then
        music.toggle_pause()
        return true
    elseif key == "x" then
        music_view.context_menu.active = true
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
