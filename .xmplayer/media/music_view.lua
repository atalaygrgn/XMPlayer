-- music_view.lua
-- Renders the music player screen and handles its keypresses.
-- All playback state lives in music_player.lua.

local theme                    = require("theme")
local assets                   = require("assets")
local ui                       = require("ui")
local utils                    = require("utils")
local music                    = require("music_player")
local settings                 = require("settings")
local viewport                 = require("viewport")
local system                   = require("system")

local music_view               = {}
music_view.buttons_locked      = false
music_view.idle_seconds        = 0
music_view.display_sleep_alpha = 0
music_view.display_sleeping    = false
music_view.lid_closed          = false

music_view.context_menu        = {
    active = false,
    alpha = 0,
    selected_idx = 1,
    items = {
        "display_sleep",
        "auto_sleep",
        "visualizer"
    }
}

local hold_wake_blocked_keys   = {
    pageup = true,
    pagedown = true,
    l = true,
    e = true,
}

local silent_playback_keys     = {
    pageup = true,
    pagedown = true,
    l = true,
    e = true,
    insert = true,
    delete = true
}

local function auto_sleep_label()
    local mins = music.auto_sleep_minutes
    if mins <= 0 then
        return "Off"
    elseif mins == 60 then
        return "1h"
    elseif mins == 120 then
        return "2h"
    elseif mins >= 60 then
        return string.format("%dh", math.floor(mins / 60))
    else
        return string.format("%dm", mins)
    end
end

local function display_sleep_label()
    local opt = settings.get_option("display_sleep")
    if not opt or not opt.choices or not opt.choices[opt.value] then
        return "Off"
    end
    return opt.choices[opt.value]
end

local function visualizer_label()
    if music.visualizer_mode == "off" then
        return "Off"
    elseif music.visualizer_mode == "bars" then
        return "Bars"
    elseif music.visualizer_mode == "walk" then
        return "Jumper"
    end
    return "Wave"
end

local function cycle_current_option(direction)
    local selected = music_view.context_menu.items[music_view.context_menu.selected_idx]
    if selected == "display_sleep" then
        local opt = settings.get_option("display_sleep")
        if opt and opt.choices and #opt.choices > 0 then
            local next_value = opt.value + direction
            if next_value > #opt.choices then next_value = 1 end
            if next_value < 1 then next_value = #opt.choices end
            opt.value = next_value
            settings.apply()
            settings.save()
        end
    elseif selected == "auto_sleep" then
        local choices = { 0, 1, 2, 3, 5, 10, 20, 30, 60, 120 }
        local idx = 1
        for i, val in ipairs(choices) do
            if val == music.auto_sleep_minutes then
                idx = i
                break
            end
        end
        local next_idx = idx + direction
        if next_idx > #choices then next_idx = 1 end
        if next_idx < 1 then next_idx = #choices end
        music.set_auto_sleep_minutes(choices[next_idx])
    elseif selected == "visualizer" then
        local modes = { "off", "wave", "bars", "walk" }
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
    local w, h                = viewport.get()
    local art_size            = math.min(w, h) * 0.3
    local art_x               = w * 0.05
    local info_x              = math.max(w * 0.3, art_x + art_size + 12)
    local info_w              = (w * 0.95) - info_x
    music.marquees.title      = ui.new_marquee(info_w)
    music.marquees.artist     = ui.new_marquee(info_w)
    music.marquees.album      = ui.new_marquee(info_w)
    music_view.buttons_locked = false
    music_view.y_hold_timer   = 0
    music_view.popup_active   = false
    music_view.popup_alpha    = 0
end

function music_view.on_music_opened()
    music_view.idle_seconds = 0
    music_view.display_sleep_alpha = 0
    music_view.display_sleeping = false
    music_view.y_hold_timer = 0
    music_view.popup_active = false
    music_view.popup_alpha = 0
end

function music_view.on_music_closed()
    music_view.idle_seconds = 0
    music_view.display_sleep_alpha = 0
    music_view.display_sleeping = false
    music_view.lid_closed = false
    music_view.y_hold_timer = 0
    music_view.popup_active = false
    music_view.popup_alpha = 0
    if music_view.saved_brightness then
        system.set_brightness(music_view.saved_brightness)
        music_view.saved_brightness = nil
    end
end

function music_view.register_user_input()
    music_view.idle_seconds = 0
    if music_view.display_sleeping then
        music_view.display_sleep_alpha = 0
        music_view.display_sleeping = false
        if settings.power_save_sleep_enabled then
            if music_view.saved_brightness and music_view.saved_brightness > 0 then
                system.set_brightness(music_view.saved_brightness)
                music_view.saved_brightness = nil
            else
                system.set_brightness(200)
            end
        end
    end
end

function music_view.is_display_sleeping()
    return music_view.display_sleep_alpha > 0.01
end

function music_view.update(dt)
    if not music.active then return end

    -- Update Y button hold detection and fade animation
    if love.keyboard.isDown("y") and not music_view.context_menu.active then
        music_view.y_hold_timer = (music_view.y_hold_timer or 0) + dt
        if music_view.y_hold_timer >= 0.2 then
            music_view.popup_active = true
        end
    else
        music_view.y_hold_timer = 0
        music_view.popup_active = false
    end

    if music_view.popup_active then
        music_view.popup_alpha = math.min(1, (music_view.popup_alpha or 0) + dt * 6)
    else
        music_view.popup_alpha = math.max(0, (music_view.popup_alpha or 0) - dt * 6)
    end

    if music_view.lid_closed then
        if not music_view.display_sleeping then
            music_view.display_sleeping = true
            music_view.display_sleep_alpha = 1
            if settings.power_save_sleep_enabled then
                music_view.saved_brightness = system.get_brightness() or 50
                system.set_brightness(0)
            end
        end
        return
    end

    local sleep_seconds = settings.display_sleep_seconds or 0
    if sleep_seconds <= 0 then
        music_view.idle_seconds = 0
        if music_view.display_sleeping then
            music_view.display_sleeping = false
            if settings.power_save_sleep_enabled then
                if music_view.saved_brightness and music_view.saved_brightness > 0 then
                    system.set_brightness(music_view.saved_brightness)
                    music_view.saved_brightness = nil
                else
                    system.set_brightness(200)
                end
            end
        end
        music_view.display_sleep_alpha = math.max(0, music_view.display_sleep_alpha - dt * 6)
        return
    end

    music_view.idle_seconds = music_view.idle_seconds + dt
    if music_view.idle_seconds >= sleep_seconds then
        music_view.display_sleep_alpha = math.min(1, music_view.display_sleep_alpha + dt * 2)
    else
        music_view.display_sleep_alpha = math.max(0, music_view.display_sleep_alpha - dt * 6)
    end

    local was_sleeping = music_view.display_sleeping
    music_view.display_sleeping = (music_view.display_sleep_alpha >= 0.99)

    if music_view.display_sleeping and not was_sleeping then
        if settings.power_save_sleep_enabled then
            local current = system.get_brightness() or 50
            if current > 0 then
                music_view.saved_brightness = current
            end
            system.set_brightness(0)
        end
    elseif not music_view.display_sleeping and was_sleeping then
        if settings.power_save_sleep_enabled then
            if music_view.saved_brightness and music_view.saved_brightness > 0 then
                system.set_brightness(music_view.saved_brightness)
                music_view.saved_brightness = nil
            else
                system.set_brightness(200)
            end
        end
    end
end

function music_view.draw()
    if not music.active then return end

    local w, h  = viewport.get()
    local alpha = music.fade_alpha

    -- Header
    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha)
    ui.printf_text("XMPlayer", 20, 10, w, "left", assets.fonts.small,
        { theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha })

    if #music.playlist > 0 then
        ui.printf_text(music.current_index .. " of " .. #music.playlist, 0, 10, w - 16, "right", assets.fonts.small,
            { theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha })
    end

    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
    love.graphics.rectangle("fill", 20, 40, w - 40, 1)

    -- Album Art
    local art_size     = math.min(w, h) * 0.3
    local art_x, art_y = w * 0.05, 60

    if music.current_track and (settings.track_info_background_mode or 1) > 1 then
        local panel_x = w * 0.03
        local panel_y = art_y - 12
        local panel_w = w * 0.94
        local panel_h = art_size + 24
        local panel_mode = settings.track_info_background_mode or 1
        local panel_fill_alpha = (panel_mode == 3) and 0.95 or 0.42
        local panel_border_alpha = (panel_mode == 3) and 0.16 or 0.08

        love.graphics.setColor(0.04, 0.05, 0.07, panel_fill_alpha * alpha)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 14, 14)

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], panel_border_alpha * alpha)
        love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 14, 14)
    end

    if music.cover_art then
        local img_w, img_h   = music.cover_art:getDimensions()
        local scale          = art_size / math.max(img_w, img_h)
        local draw_w, draw_h = img_w * scale, img_h * scale
        local ox, oy         = (art_size - draw_w) / 2, (art_size - draw_h) / 2

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
        local info_x = math.max(w * 0.3, art_x + art_size + 12)
        local info_y = 60
        local info_w = (w * 0.95) - info_x
        local is_vgm = utils.is_vgm_file(music.current_track.path)
        local extra_y = info_y + (is_vgm and 50 or 118)

        local function set_clip()
            viewport.set_scissor(info_x, 50, info_w, h - 50)
        end

        -- Title
        set_clip()
        local track_name = music.tags.title or utils.get_track_name(music.current_track.name)
        ui.draw_marquee(music.marquees.title, track_name, info_x + music.slide_x, info_y, assets.fonts.title,
            { theme.text[1], theme.text[2], theme.text[3], alpha }, info_x, info_y)

        love.graphics.setScissor()
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.1 * alpha)
        love.graphics.rectangle("fill", info_x, info_y + 40, info_w, 1)

        if not is_vgm then
            -- Artist
            set_clip()
            local artist_name = music.tags.artist or "Unknown Artist"
            ui.draw_marquee(music.marquees.artist, artist_name, info_x + music.slide_x, info_y + 46, assets.fonts.artist,
                { theme.text[1], theme.text[2], theme.text[3], 0.7 * alpha }, info_x, info_y + 46)

            -- Album
            set_clip()
            local album_name = music.tags.album or "Unknown Album"
            ui.draw_marquee(music.marquees.album, album_name, info_x + music.slide_x, info_y + 74, assets.fonts.album,
                { theme.text[1], theme.text[2], theme.text[3], 0.4 * alpha }, info_x, info_y + 74)
        end

        -- Next Track Info
        set_clip()
        if #music.playlist > 1 then
            local next_idx     = (music.current_index % #music.playlist) + 1
            local next_track   = music.playlist[next_idx]
            local next_name    = "Next: " .. (music.next_tags.title or utils.get_track_name(next_track.name))
            local display_next = utils.truncate_text(next_name, assets.fonts.small, info_w * 0.8)

            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.4 * alpha)
            ui.print_text(display_next, info_x + music.slide_x, extra_y, assets.fonts.small,
                { theme.text[1], theme.text[2], theme.text[3], 0.4 * alpha })
        end

        local ext = utils.get_extension(music.current_track.path)
        if ext then
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.3 * alpha)
            ui.printf_text(ext:sub(2):upper(), info_x + music.slide_x, extra_y, info_w, "right", assets.fonts.small,
                { theme.text[1], theme.text[2], theme.text[3], 0.3 * alpha })
        end
        love.graphics.setScissor()

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
    local bar_w, bar_h               = w * 0.4, 6
    local bar_x, bar_y               = w - bar_w - 30, h - 30
    local progress                   = music.duration > 0 and (music.elapsed / music.duration) or 0
    local track_info_background_mode = settings.track_info_background_mode or 1

    if track_info_background_mode > 1 then
        local panel_x = bar_x + bar_w - 152
        local panel_y = bar_y - 46
        local panel_w = 160
        local panel_h = 40
        local panel_fill_alpha = (track_info_background_mode == 3) and 0.95 or 0.42
        local panel_border_alpha = (track_info_background_mode == 3) and 0.16 or 0.08

        love.graphics.setColor(0.04, 0.05, 0.07, panel_fill_alpha * alpha)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 14, 14)

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], panel_border_alpha * alpha)
        love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 14, 14)
    end

    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.9 * alpha)
    ui.print_text(utils.format_time(music.elapsed), bar_x + bar_w - 140, bar_y - 40, assets.fonts.time_elapsed,
        { theme.text[1], theme.text[2], theme.text[3], 0.9 * alpha })

    ui.printf_text("/ " .. utils.format_time(music.duration), 0, bar_y - 38, bar_x + bar_w, "right",
        assets.fonts.time_dur, { theme.text[1], theme.text[2], theme.text[3], 0.9 * alpha })

    ui.draw_progress_bar(bar_x, bar_y, bar_w, bar_h, progress,
        { 0, 0.35, 0.65, 0.9 * alpha },
        { 0.8, 0.8, 0.8, 0.75 })

    local menu = music_view.context_menu
    if menu.active then
        menu.alpha = math.min(1, menu.alpha + 0.2)
    else
        menu.alpha = math.max(0, menu.alpha - 0.2)
    end

    if menu.alpha > 0 then
        local menu_w = 300
        local row_h = 44
        local menu_h = (#menu.items * row_h) + 20
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

            if item_id == "display_sleep" then
                label = "Display Sleep"
                value = display_sleep_label()
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

            local text_color = focused and { theme.text[1], theme.text[2], theme.text[3], menu.alpha } or
                { theme.text[1], theme.text[2], theme.text[3], 0.75 * menu.alpha }
            ui.print_text(label, menu_x + 24, y + 2, assets.fonts.small, text_color)

            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.85 * menu.alpha)
            ui.printf_text(value, menu_x + 20, y + 2, menu_w - 44, "right", assets.fonts.small,
                { theme.text[1], theme.text[2], theme.text[3], 0.85 * menu.alpha })
        end
    end

    -- Y Button Shortcuts Popup
    if music_view.popup_alpha and music_view.popup_alpha > 0 then
        local popup_alpha = music_view.popup_alpha
        local pw, ph = 200, 200
        local cx, cy = w / 2, h / 2
        local px, py = cx - pw / 2, cy - ph / 2

        -- Background panel (glassmorphic glass finish)
        love.graphics.setColor(0.04, 0.05, 0.07, 0.94 * popup_alpha * alpha)
        love.graphics.rectangle("fill", px, py, pw, ph, 16, 16)

        -- Border with theme accent color
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35 * popup_alpha * alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px, py, pw, ph, 16, 16)

        -- D-pad Center
        local dpad_x = cx
        local dpad_y = cy
        local dpad_size = 72

        -- Draw D-pad icon
        if assets.images.dpad then
            ui.draw_icon(assets.images.dpad, dpad_x, dpad_y, dpad_size, theme.text, popup_alpha * alpha)
        end

        -- Color definitions
        local color_unassigned = { theme.text[1], theme.text[2], theme.text[3], 0.35 * popup_alpha * alpha }
        local color_assigned = { theme.accent[1], theme.accent[2], theme.accent[3], 0.9 * popup_alpha * alpha }

        -- Up Icon (Lock/Unlock)
        local up_held = love.keyboard.isDown("up")
        local up_color = up_held and { theme.accent[1], theme.accent[2], theme.accent[3], 1.0 * popup_alpha * alpha } or
            (music_view.buttons_locked and color_assigned or color_unassigned)
        local ux, uy = cx, dpad_y - 65
        if assets.images.lock then
            ui.draw_icon(assets.images.lock, ux, uy, 36, up_color, popup_alpha * alpha)
            if not music_view.buttons_locked then
                love.graphics.setColor(up_color[1], up_color[2], up_color[3], (up_color[4] or 1) * 0.8)
                love.graphics.setLineWidth(2.5)
                love.graphics.line(ux - 12, uy + 12, ux + 12, uy - 12)
                love.graphics.setLineWidth(1)
            end
        end

        -- Right Icon (Repeat One)
        local right_held = love.keyboard.isDown("right")
        local right_icon = music.repeat_one and assets.images.repeat_one or assets.images.repeat_all
        local right_color = right_held and
            { theme.accent[1], theme.accent[2], theme.accent[3], 1.0 * popup_alpha * alpha } or
            (music.repeat_one and color_assigned or color_unassigned)
        if right_icon then
            ui.draw_icon(right_icon, cx + 65, dpad_y, 36, right_color, popup_alpha * alpha)
        end
    end

    if music_view.display_sleep_alpha > 0 then
        love.graphics.setColor(0, 0, 0, music_view.display_sleep_alpha)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
end

function music_view.keypressed(key)
    if not music.active then return false end

    if key == "insert" then
        music_view.lid_closed = true
        local was_sleeping = music_view.display_sleeping
        music_view.display_sleep_alpha = 1
        music_view.display_sleeping = true
        if not was_sleeping then
            if settings.power_save_sleep_enabled then
                music_view.saved_brightness = system.get_brightness() or 50
                system.set_brightness(0)
            end
        end
        return true
    elseif key == "delete" then
        music_view.lid_closed = false
        local was_sleeping = music_view.display_sleeping
        music_view.display_sleep_alpha = 0
        music_view.display_sleeping = false
        music_view.idle_seconds = 0
        if was_sleeping then
            if settings.power_save_sleep_enabled and music_view.saved_brightness then
                system.set_brightness(music_view.saved_brightness)
                music_view.saved_brightness = nil
            end
        end
        return true
    end

    local was_sleeping = music_view.display_sleeping
    local should_ignore_wake = music_view.buttons_locked and hold_wake_blocked_keys[key]
    local is_silent_key = silent_playback_keys[key]

    local lock_combo_pressed = not music_view.context_menu.active and (
        (key == "y" and love.keyboard.isDown("up"))
        or (key == "up" and love.keyboard.isDown("y"))
    )

    if not should_ignore_wake and not is_silent_key and not music_view.lid_closed then
        music_view.register_user_input()
    end

    if lock_combo_pressed then
        music_view.buttons_locked = not music_view.buttons_locked
        if music_view.buttons_locked then
            music_view.context_menu.active = false
        end
        return true
    end

    if was_sleeping and not is_silent_key then
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

    local repeat_combo_pressed = not music_view.context_menu.active and (
        (key == "y" and love.keyboard.isDown("right"))
        or (key == "right" and love.keyboard.isDown("y"))
    )

    if repeat_combo_pressed then
        music.set_repeat_one(not music.repeat_one)
        return true
    end

    if key == "a" or key == "return" then
        music.toggle_pause()
        return true
    elseif key == "x" then
        music_view.context_menu.active = true
        return true
    elseif key == "right" or key == "pagedown" then
        music.next_track()
        return true
    elseif key == "left" or key == "pageup" then
        music.prev_track()
        return true
    elseif key == "l" then
        music.seek(-10)
        return true
    elseif key == "e" then
        music.seek(10)
        return true
    elseif key == "b" or key == "backspace" then
        music.close()
        return true
    end

    return false
end

return music_view
