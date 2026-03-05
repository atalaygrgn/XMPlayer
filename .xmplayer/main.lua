package.path = package.path .. ";modules/?.lua"
local theme = require("theme")
local player = require("player")
local categories = require("categories")
local xmb = require("xmb")
local music = require("music_player")
local background = require("background")
local viewer = require("image_viewer")
local settings = require("settings")

-- Framebuffer refresh counter (flush all swap buffers after MPV)
local refresh_frames_remaining = 0

-- Assets
local images = {}
local bg_image
local fonts = {}
local sfx = {}

function love.load()
    -- Load assets

    for _, cat in ipairs(categories) do
        images[cat.id] = love.graphics.newImage(cat.icon)
    end
    images.folder_icon = love.graphics.newImage("assets/icons/folder.png")
    images.video_icon = love.graphics.newImage("assets/icons/video.png")
    images.music_icon = love.graphics.newImage("assets/icons/music.png")
    images.photo_icon = love.graphics.newImage("assets/icons/photo.png")

    fonts.main = love.graphics.newFont(24)
    fonts.small = love.graphics.newFont(20)
    
    -- Load SFX
    sfx.nav = love.audio.newSource("assets/sfx/keytone.wav", "static")
    
    -- Init subsystems
    music.init()
    background.init()
    viewer.init()
    
    -- Apply initial settings
    settings.apply()
    
    -- Initial scan
    xmb.refresh_browser()
    
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
    local is_paused = true
    if music.active then
        music.update(dt)
        is_paused = music.paused
    elseif viewer.active then
        viewer.update(dt)
        is_paused = true
    else
        xmb.update(dt, fonts, sfx)
    end
    background.update(dt, is_paused)
end

function love.draw()
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    
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
        -- Music player takes over the full screen
        music.draw()
    elseif viewer.active then
        -- Image viewer takes over the full screen
        viewer.draw()
    else

        
        -- Draw XMB
        xmb.draw(images, fonts)
        
        -- Clock and info
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.8)
        love.graphics.setFont(fonts.small)
        love.graphics.print(os.date("%H:%M"), 20, 20)
        love.graphics.print("XMPlayer v0.1", screen_w - 160, 20)
    end
end

function love.keypressed(key)
    -- Music player intercepts input when active
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
        xmb.keypressed(key, player, music, viewer, fonts, sfx)
    end
end
