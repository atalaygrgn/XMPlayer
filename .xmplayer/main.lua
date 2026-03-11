package.path = package.path .. ";modules/?.lua"
local theme = require("theme")
local player = require("player")
local categories = require("categories")
local xmb = require("xmb")
local xmb_draw = require("xmb_draw")
local music = require("music_player")
local music_view = require("music_view")
local background = require("background")
local image_viewer = require("image_viewer")
local image_view = require("image_view")
local settings = require("settings")
local assets = require("assets")
local indexing = require("indexing")
local ui = require("ui")
local system = require("system")


local scan_co = nil

-- Battery status caching
local battery_percentage = nil
local is_charging = false
local battery_timer = 0
local BATTERY_UPDATE_INTERVAL = 10 -- Update every 10 seconds

-- Volume status caching
local last_volume = nil
local last_brightness = nil
local ui_timer = 0
local UI_CHECK_INTERVAL = 0.1 -- Update every 0.1 seconds

function love.load()
    math.randomseed(os.time())
    -- Load assets
    assets.load(categories)

    -- Init subsystems
    background.init()
    music.init()
    music_view.init()
    image_viewer.init()

    -- Load and Apply settings
    settings.load()

    -- Initial scan / Indexing
    indexing.load()

    -- Trigger indexing if no data or requested
    if not next(indexing.data.music.files) or not next(indexing.data.photos) then
        local photo_dir = settings.get_option("photo_dir").value
        local music_dir = settings.get_option("music_dir").value
        local video_dir = settings.get_option("video_dir").value

        scan_co = coroutine.create(function()
            indexing.scan(photo_dir, music_dir, video_dir)
        end)
        indexing.is_scanning = true
    else
        xmb.refresh_browser()
    end

    -- Initial battery check
    battery_percentage = system.get_battery_percentage()
    is_charging = system.is_charging()
    last_volume = system.get_volume()
    last_brightness = system.get_brightness()

    -- Screen setup
    love.graphics.setBackgroundColor(theme.colors.background)
end

function love.update(dt)
    -- Check if we need a hard refresh after returning from MPV
    if player.needs_refresh then
        -- Force Love2D to re-init the display context
        -- This tears down the framebuffer connection and rebuilds it
        local width, height = love.graphics.getDimensions()
        love.window.setMode(width, height, {
            fullscreen = true,
            vsync = true,
            resizable = false
        })

        player.needs_refresh = false
    end

    -- Update music player if active, otherwise update XMB
    local is_paused = false
    if music.active then
        music.update(dt)
        is_paused = music.paused
    elseif image_viewer.active then
        image_viewer.update(dt)
        is_paused = true
    elseif indexing.is_scanning then
        if scan_co then
            local ok, err = coroutine.resume(scan_co)
            if not ok then
                print("Indexing error: " .. tostring(err))
                indexing.is_scanning = false
                scan_co = nil
                xmb.refresh_browser()
                ui.show_toast("Indexing error, see log.txt for details", "info", "top_center")
            elseif coroutine.status(scan_co) == "dead" then
                indexing.is_scanning = false
                scan_co = nil
                xmb.refresh_browser()
                ui.show_toast("Indexing completed", "info", "top_center")
            end
        end
        return
    else
        xmb.update(dt)
    end

    -- Update battery status
    battery_timer = battery_timer + dt
    if battery_timer >= BATTERY_UPDATE_INTERVAL then
        battery_timer = 0
        battery_percentage = system.get_battery_percentage()
        is_charging = system.is_charging()
    end

    -- Update volume & brightness status
    ui_timer = ui_timer + dt
    if ui_timer >= UI_CHECK_INTERVAL then
        ui_timer = 0

        -- Volume
        local current_volume = system.get_volume()
        if settings.vol_bright_enabled and last_volume ~= nil and current_volume ~= nil and current_volume ~= last_volume then
            ui.show_volume_toast(current_volume)
        end
        last_volume = current_volume

        -- Brightness
        local current_brightness = system.get_brightness()
        if settings.vol_bright_enabled and last_brightness ~= nil and current_brightness ~= nil and current_brightness ~= last_brightness then
            ui.show_brightness_toast(current_brightness)
        end
        last_brightness = current_brightness
    end

    background.update(dt, is_paused)
    ui.update_toasts(dt)
end

function love.draw()
    local screen_w, screen_h = love.graphics.getDimensions()

    -- Force full clear every frame (essential for embedded devices)
    love.graphics.clear(theme.colors.background[1], theme.colors.background[2], theme.colors.background[3], 1)

    -- Draw animated background
    background.draw(music)

    if music.active then
        music_view.draw()
    elseif image_viewer.active then
        image_view.draw()
    elseif indexing.is_scanning then
        ui.draw_indexing_popup(indexing.scan_progress)
    else
        xmb_draw.draw()

        -- Clock and info
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.8)
        love.graphics.setFont(assets.fonts.small)

        -- Left: Clock
        love.graphics.print(os.date("%H:%M"), 20, 20)

        -- Right: Battery
        if battery_percentage then
            local batt_str = string.format("%d%%", battery_percentage)
            local batt_w = assets.fonts.small:getWidth(batt_str)
            local icon = is_charging and assets.images.battery_charge or assets.images.battery

            if icon then
                local icon_h = assets.fonts.small:getHeight()
                local scale = icon_h / icon:getHeight()
                local icon_w = icon:getWidth() * scale

                local x = screen_w - batt_w - icon_w - 25
                local y = 20

                love.graphics.draw(icon, x, y, 0, scale, scale)
            end

            love.graphics.print(batt_str, screen_w - batt_w - 20, 20)
        end
    end

    -- Draw toasts on top of everything
    ui.draw_toasts()
end

function love.keypressed(key)
    if music.active then
        music_view.keypressed(key)
        return
    end

    if image_viewer.active then
        image_view.keypressed(key)
        return
    end

    xmb.keypressed(key, player, music, image_viewer)
end
