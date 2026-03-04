local theme = require("theme")
local player = require("player")
local categories = require("categories")
local xmb = require("xmb")
local music = require("music_player")

-- Framebuffer refresh counter (flush all swap buffers after MPV)
local refresh_frames_remaining = 0

-- Assets
local images = {}
local bg_image
local fonts = {}

function love.load()
    -- Load assets
    bg_image = love.graphics.newImage("assets/bg.jpg")
    for _, cat in ipairs(categories) do
        images[cat.id] = love.graphics.newImage(cat.icon)
    end
    images.folder_icon = love.graphics.newImage("assets/icons/folder.png")
    images.video_icon = love.graphics.newImage("assets/icons/video.png")
    images.music_icon = love.graphics.newImage("assets/icons/music.png")
    images.photo_icon = love.graphics.newImage("assets/icons/photo.png")

    fonts.main = love.graphics.newFont(24)
    fonts.small = love.graphics.newFont(18)
    
    -- Init subsystems
    music.init()
    
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
    if music.active then
        music.update(dt)
    else
        xmb.update(dt)
    end
end

function love.draw()
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    
    -- Force full clear every frame (essential for embedded devices)
    love.graphics.clear(theme.colors.background[1], theme.colors.background[2], theme.colors.background[3], 1)
    
    -- Draw solid opaque background (covers any stale framebuffer)
    love.graphics.setColor(theme.colors.background[1], theme.colors.background[2], theme.colors.background[3], 1)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    
    -- During refresh period, just draw the solid background and return
    if refresh_frames_remaining > 0 then
        refresh_frames_remaining = refresh_frames_remaining - 1
        return
    end
    
    if music.active then
        -- Music player takes over the full screen
        music.draw()
    else
        -- Draw Background image on top
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.draw(bg_image, 0, 0, 0, screen_w / bg_image:getWidth(), screen_h / bg_image:getHeight())
        
        -- Draw XMB
        xmb.draw(images, fonts)
        
        -- Clock and info
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.setFont(fonts.small)
        love.graphics.print(os.date("%H:%M:%S"), 20, 20)
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
    
    if key == "escape" then
        love.event.quit()
    else
        xmb.keypressed(key, player, music)
    end
end
