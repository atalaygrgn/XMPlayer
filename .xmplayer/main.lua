local source_root = (love.filesystem and love.filesystem.getSource and love.filesystem.getSource()) or "."
source_root = source_root:gsub("\\", "/")
package.path = table.concat({
    package.path,
    source_root .. "/?.lua",
    source_root .. "/core/?.lua",
    source_root .. "/ui/?.lua",
    source_root .. "/media/?.lua",
    source_root .. "/players/?.lua",
    source_root .. "/systems/?.lua",
    source_root .. "/data/?.lua",
}, ";")
local viewport = require("viewport")
local simpleScalePath = source_root .. "/simpleScale.lua"
assert(loadfile(simpleScalePath))()
local simpleScale = simpleScale
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
local history = require("history")
local video_manager = require("video_manager")
local ui = require("ui")
local system = require("system")
local runtime_state = require("runtime_state")
local utils = require("utils")

local function build_valid_media_paths()
    local valid_paths = {}

    for path in pairs(indexing.data.music.files or {}) do
        valid_paths[path] = true
    end

    for path in pairs(indexing.data.photos or {}) do
        valid_paths[path] = true
    end

    for _, path in ipairs(indexing.data.videos or {}) do
        valid_paths[path] = true
    end

    return valid_paths
end

local function cleanup_stale_media_state()
    local valid_paths = build_valid_media_paths()
    video_manager.prune_stale_state(valid_paths)
    history.prune_missing(valid_paths)
end


function love.load()
    math.randomseed(os.time())

    viewport.update_from_window(love.graphics.getDimensions())

    simpleScale.setWindow(viewport.width, viewport.height, love.graphics.getWidth(), love.graphics.getHeight(), {
        vsync = true,
        resizable = false
    })

    -- Load assets
    assets.load(categories)

    -- Init subsystems
    background.init()
    music.init()
    music_view.init()
    image_viewer.init()

    -- Load and Apply settings
    settings.load()

    -- One-shot restart request from settings: force full media reindex on this launch
    local force_reindex = settings.consume_reindex_request()

    -- Initial scan / Indexing
    local has_existing_index = false
    if not force_reindex then
        has_existing_index = indexing.load()
    end

    local photo_dir = settings.get_option("photo_dir").value
    local music_dir = settings.get_option("music_dir").value
    local video_dir = settings.get_option("video_dir").value

    -- Trigger a full scan only when we have no usable index or the user requested one.
    -- Empty media categories are handled by the incremental scan path.
    if force_reindex or not has_existing_index then
        runtime_state.begin_scan(coroutine.create(function()
            indexing.scan(photo_dir, music_dir, video_dir)
        end))
        indexing.is_scanning = true
    else
        runtime_state.begin_scan(coroutine.create(function()
            indexing.scan_for_new_media(photo_dir, music_dir, video_dir)
        end))
        indexing.is_scanning = true
    end

    -- Initial battery check
    runtime_state.battery_percentage = system.get_battery_percentage()
    runtime_state.is_charging = system.is_charging()
    runtime_state.last_volume = system.get_volume()
    runtime_state.last_brightness = system.get_brightness()

    -- Screen setup
    love.graphics.setBackgroundColor(theme.colors.background)
end

function love.resize()
    viewport.update_from_window(love.graphics.getDimensions())
    simpleScale.resizeUpdate()
    if assets and assets.update_font_scales then
        assets.update_font_scales(simpleScale.scale)
    end
end

function love.update(dt)
    -- Check if we need a hard refresh after returning from MPV
    if player.needs_refresh then
        -- Force Love2D to re-init the display context
        -- This tears down the framebuffer connection and rebuilds it
        local width, height = love.graphics.getDimensions()
        viewport.update_from_window(width, height)
        simpleScale.updateWindow(width, height, {
            fullscreen = true,
            vsync = true,
            resizable = false
        })
        if assets and assets.update_font_scales then
            assets.update_font_scales(simpleScale.scale)
        end

        player.needs_refresh = false
    end

    -- Update music player if active, otherwise update XMB
    local is_paused = false
    local was_music_active = runtime_state.was_music_active

    if music.active then
        if not was_music_active then
            music_view.on_music_opened()
        end
        music.update(dt)
        if music.active then
            music_view.update(dt)
        end
        is_paused = music.paused
    elseif image_viewer.active then
        image_viewer.update(dt)
        is_paused = true
    elseif indexing.is_scanning then
        if runtime_state.scan_co then
            local ok, err = coroutine.resume(runtime_state.scan_co)
            if not ok then
                print("Indexing error: " .. tostring(err))
                indexing.is_scanning = false
                runtime_state.clear_scan()
                xmb.refresh_browser()
                runtime_state.set_launch_status("Indexing Error")
            elseif coroutine.status(runtime_state.scan_co) == "dead" then
                indexing.is_scanning = false
                runtime_state.clear_scan()
                cleanup_stale_media_state()
                xmb.refresh_browser()
                runtime_state.set_launch_status("Indexing Complete")
                -- Startup sound
                local opt_startup = settings.get_option("startup_sound")
                if (not opt_startup) or opt_startup.value == 1 then
                    if assets and assets.play_sfx then
                        assets.play_sfx("startup")
                    end
                end
            end
        end
        return
    elseif runtime_state.launch_status_timer > 0 then
        runtime_state.launch_status_timer = math.max(0, runtime_state.launch_status_timer - dt)
        if runtime_state.launch_status_timer == 0 then
            runtime_state.launch_status_message = nil
        end
        return
    else
        xmb.update(dt)
    end

    if was_music_active and not music.active then
        music_view.on_music_closed()
    end

    runtime_state.was_music_active = music.active

    -- Update battery status
    runtime_state.battery_timer = runtime_state.battery_timer + dt
    if runtime_state.battery_timer >= runtime_state.battery_update_interval then
        runtime_state.battery_timer = 0
        runtime_state.battery_percentage = system.get_battery_percentage()
        runtime_state.is_charging = system.is_charging()
    end

    -- Update volume & brightness status
    runtime_state.ui_timer = runtime_state.ui_timer + dt
    if runtime_state.ui_timer >= runtime_state.ui_check_interval then
        runtime_state.ui_timer = 0

        -- Volume
        local current_volume = system.get_volume()
        if settings.vol_bright_enabled and runtime_state.last_volume ~= nil and current_volume ~= nil and current_volume ~= runtime_state.last_volume then
            ui.show_volume_toast(current_volume)
        end
        runtime_state.last_volume = current_volume

        -- Brightness
        local current_brightness = system.get_brightness()
        if settings.vol_bright_enabled and runtime_state.last_brightness ~= nil and current_brightness ~= nil and current_brightness ~= runtime_state.last_brightness then
            ui.show_brightness_toast(current_brightness)
        end
        runtime_state.last_brightness = current_brightness
    end

    background.update(dt, is_paused)
    ui.update_toasts(dt)
end

function love.draw()
    simpleScale.set()
    local screen_w, screen_h = viewport.get()

    -- Force full clear every frame (essential for embedded devices)
    love.graphics.clear(theme.colors.background[1], theme.colors.background[2], theme.colors.background[3], 1)

    -- Draw animated background
    background.draw(music)

    if music.active then
        music_view.draw()
    elseif image_viewer.active then
        image_view.draw()
    elseif indexing.is_scanning or runtime_state.launch_status_timer > 0 then
        ui.draw_indexing_popup(runtime_state.launch_status_message or indexing.scan_progress,
            runtime_state.launch_status_timer > 0)
    else
        xmb_draw.draw(xmb)

        -- Clock and info
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.8)

        -- Left: Clock
        ui.print_text(os.date("%H:%M"), 20, 20, assets.fonts.small, { theme.text[1], theme.text[2], theme.text[3], 0.8 })

        -- Right: Battery
        if runtime_state.battery_percentage then
            local batt_str = string.format("%d%%", runtime_state.battery_percentage)
            local batt_w = ui.measure_text_width(assets.fonts.small, batt_str)
            local icon = runtime_state.is_charging and assets.images.battery_charge or assets.images.battery

            if icon then
                local icon_h = ui.measure_text_height(assets.fonts.small)
                local scale = icon_h / icon:getHeight()
                local icon_w = icon:getWidth() * scale

                local x = screen_w - batt_w - icon_w - 25
                local y = 20

                love.graphics.draw(icon, x, y, 0, scale, scale)
            end

            ui.print_text(batt_str, screen_w - batt_w - 20, 20, assets.fonts.small,
                { theme.text[1], theme.text[2], theme.text[3], 0.8 })
        end
    end

    -- Draw toasts on top of everything
    if not (music.active and music_view.is_display_sleeping()) then
        ui.draw_toasts()
    end

    simpleScale.unSet(theme.colors.background)
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
