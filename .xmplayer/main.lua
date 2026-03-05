package.path = package.path .. ";modules/?.lua"
local theme = require("theme")
local player = require("player")
local categories = require("categories")
local xmb = require("xmb")
local music = require("music_player")
local background = require("background")
local viewer = require("image_viewer")
local settings = require("settings")
local assets = require("assets")
local indexing = require("indexing")
local ui = require("ui")
local utils = require("utils")


-- Framebuffer refresh counter (flush all swap buffers after MPV)
local refresh_frames_remaining = 0
local scan_co = nil

-- Battery status caching
local battery_percentage = nil
local battery_timer = 0
local BATTERY_UPDATE_INTERVAL = 10 -- Update every 10 seconds

function love.load()
    -- Load assets
    assets.load(categories)
    
    -- Init subsystems
    music.init()
    background.init()
    viewer.init()
    
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
    battery_percentage = utils.get_battery_percentage()
    
    -- Screen setup
    love.graphics.setBackgroundColor(theme.colors.background)
end

function love.update(dt)
    -- Check if we need a hard refresh after returning from MPV
    if player.needs_refresh then
        player.needs_refresh = false
        refresh_frames_remaining = 10
    end
    
    -- Update music player if active, otherwise update XMB
    local is_paused = false
    if music.active then
        music.update(dt)
        is_paused = music.paused
    elseif viewer.active then
        viewer.update(dt)
        is_paused = true
    elseif indexing.is_scanning then
        if scan_co then
            local ok, err = coroutine.resume(scan_co)
            if not ok then
                print("Indexing error: " .. tostring(err))
                indexing.is_scanning = false
                scan_co = nil
                xmb.refresh_browser()
            elseif coroutine.status(scan_co) == "dead" then
                scan_co = nil
                xmb.refresh_browser()
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
        battery_percentage = utils.get_battery_percentage()
    end
    
    background.update(dt, is_paused)
end

function love.draw()
    local screen_w, screen_h = love.graphics.getDimensions()
    
    -- Force full clear every frame (essential for embedded devices)
    love.graphics.clear(theme.colors.background[1], theme.colors.background[2], theme.colors.background[3], 1)
    
    -- Draw animated background
    background.draw(music)
    
    -- During refresh period, just draw the solid background and return
    if refresh_frames_remaining > 0 then
        refresh_frames_remaining = refresh_frames_remaining - 1
        return
    end
    
    if music.active then
        music.draw()
    elseif viewer.active then
        viewer.draw()
    elseif indexing.is_scanning then
        ui.draw_indexing_popup(indexing.scan_progress)
    else
        xmb.draw()
        
        -- Clock and info
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.8)
        love.graphics.setFont(assets.fonts.small)
        
        -- Left: Clock
        love.graphics.print(os.date("%H:%M"), 20, 20)
        
        -- Right: Battery
        if battery_percentage then
            local batt_str = string.format("%d%%", battery_percentage)
            local batt_w = assets.fonts.small:getWidth(batt_str)
            -- Add an icon placeholder or just text for now
            love.graphics.print(batt_str, screen_w - batt_w - 20, 20)
        end
    end
end

function love.keypressed(key)
    if music.active then
        if key == "escape" then
            music.close()
        else
            music.keypressed(key)
        end
        return
    end

    if viewer.active then
        viewer.keypressed(key)
        return
    end
    
    if key == "escape" then
        love.event.quit()
    else
        xmb.keypressed(key, player, music, viewer)
    end
end
