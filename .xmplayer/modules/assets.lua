local theme = require("theme")
local assets = {}

assets.images = {}
assets.fonts = {}
assets.sfx = {}

function assets.load(categories)
    -- Load generic icons
    assets.images.folder = love.graphics.newImage("assets/icons/folder.png")
    assets.images.video = love.graphics.newImage("assets/icons/video.png")
    assets.images.music = love.graphics.newImage("assets/icons/music.png")
    assets.images.photo = love.graphics.newImage("assets/icons/photo.png")
    assets.images.drive = love.graphics.newImage("assets/icons/drive.png")
    assets.images.info = love.graphics.newImage("assets/icons/info.png")
    assets.images.option = love.graphics.newImage("assets/icons/option.png")
    assets.images.play = love.graphics.newImage("assets/icons/play.png")
    assets.images.pause = love.graphics.newImage("assets/icons/pause.png")

    -- Load category icons (overwrites specifics if they share names)
    if categories then
        for _, cat in ipairs(categories) do
            assets.images["cat_" .. cat.id] = love.graphics.newImage(cat.icon)
        end
    end

    -- Load fonts
    assets.fonts.main = love.graphics.newFont(24)
    assets.fonts.small = love.graphics.newFont(20)
    assets.fonts.title = love.graphics.newFont(26)
    assets.fonts.artist = love.graphics.newFont(20)
    assets.fonts.album = love.graphics.newFont(18)
    assets.fonts.time_elapsed = love.graphics.newFont(24)
    assets.fonts.time_dur = love.graphics.newFont(20)
    assets.fonts.xs = love.graphics.newFont(16)

    -- Load SFX
    assets.sfx.nav = love.audio.newSource("assets/sfx/keytone.wav", "static")
end

function assets.get_image(name)
    return assets.images[name]
end

function assets.play_sfx(name)
    local sfx = assets.sfx[name]
    if sfx then
        sfx:stop()
        sfx:play()
    end
end

return assets
