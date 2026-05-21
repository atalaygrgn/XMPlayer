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
    assets.images.sdcard = love.graphics.newImage("assets/icons/sdcard.png")
    assets.images.info = love.graphics.newImage("assets/icons/info.png")
    assets.images.option = love.graphics.newImage("assets/icons/option.png")
    assets.images.play = love.graphics.newImage("assets/icons/play.png")
    assets.images.pause = love.graphics.newImage("assets/icons/pause.png")
    assets.images.lock = love.graphics.newImage("assets/icons/lock.png")
    assets.images.repeat_one = love.graphics.newImage("assets/icons/repeat-one.png")
    assets.images.battery = love.graphics.newImage("assets/icons/battery.png")
    assets.images.battery_charge = love.graphics.newImage("assets/icons/batterycharge.png")
    assets.images.albums = love.graphics.newImage("assets/icons/albums.png")
    assets.images.album = love.graphics.newImage("assets/icons/album.png")
    assets.images.track = love.graphics.newImage("assets/icons/track.png")
    assets.images.mic = love.graphics.newImage("assets/icons/mic.png")
    assets.images.artist = love.graphics.newImage("assets/icons/artist.png")
    assets.images.folder_music = love.graphics.newImage("assets/icons/folder-music.png")
    assets.images.file_music = love.graphics.newImage("assets/icons/file-music.png")
    assets.images.folder_image = love.graphics.newImage("assets/icons/folder-image.png")
    assets.images.folder_video = love.graphics.newImage("assets/icons/folder-video.png")
    assets.images.file_video = love.graphics.newImage("assets/icons/file-video.png")
    assets.images.folders = love.graphics.newImage("assets/icons/folders.png")
    assets.images.file = love.graphics.newImage("assets/icons/file.png")
    assets.images.theme = love.graphics.newImage("assets/icons/theme.png")
    assets.images.history = love.graphics.newImage("assets/icons/history.png")
    assets.images.quit = love.graphics.newImage("assets/icons/quit.png")
    assets.images.shuffle = love.graphics.newImage("assets/icons/shuffle.png")
    assets.images.eye = love.graphics.newImage("assets/icons/eye.png")
    assets.images.playlist_music = love.graphics.newImage("assets/icons/playlist-music.png")
    assets.images.playlist_add = love.graphics.newImage("assets/icons/playlist-add.png")

    -- Load volume icons
    assets.images.volume_up = love.graphics.newImage("assets/icons/volume-up.png")
    assets.images.volume_down = love.graphics.newImage("assets/icons/volume-down.png")
    assets.images.volume_mute = love.graphics.newImage("assets/icons/volume-mute.png")
    assets.images.brightness = love.graphics.newImage("assets/icons/bulb.png")

    -- Load category icons (overwrites specifics if they share names)
    if categories then
        for _, cat in ipairs(categories) do
            assets.images["cat_" .. cat.id] = love.graphics.newImage(cat.icon)
        end
    end

    -- Load fonts
    local font_path = "assets/font/eurostile_bold.ttf"
    assets.fonts.main = love.graphics.newFont(font_path, 28)
    assets.fonts.small = love.graphics.newFont(font_path, 24)
    assets.fonts.title = love.graphics.newFont(font_path, 30)
    assets.fonts.artist = love.graphics.newFont(font_path, 24)
    assets.fonts.album = love.graphics.newFont(font_path, 22)
    assets.fonts.time_elapsed = love.graphics.newFont(font_path, 28)
    assets.fonts.time_dur = love.graphics.newFont(font_path, 24)
    assets.fonts.xs = love.graphics.newFont(font_path, 18)
    assets.fonts.large = love.graphics.newFont(font_path, 48)

    -- Load SFX
    assets.sfx.nav = love.audio.newSource("assets/sfx/keytone.wav", "static")
    assets.sfx.startup = love.audio.newSource("assets/sfx/startup.wav", "static")
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
