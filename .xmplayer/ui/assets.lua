local theme = require("theme")
local assets = {}

assets.images = {}
assets.fonts = {}
assets.sfx = {}

local path_figtree = "assets/font/Figtree-SemiBold.otf"
local path_oswald = "assets/font/Oswald-SemiBold.ttf"
local path_cjk = "assets/font/DroidSansFallbackFull.ttf"
local path_kr = "assets/font/NanumGothic-Regular.ttf"

local font_sizes = {
    main         = 28,
    small        = 24,
    title        = 28,
    artist       = 24,
    album        = 24,
    time_elapsed = 28,
    time_dur     = 24,
    xs           = 20,
    large        = 52,
    keyboardkey  = 20,
}

-- Fonts that only render ASCII/digits/UI labels and do not need a CJK fallback atlas
local NO_CJK_FONTS = {
    time_elapsed = true,
    time_dur     = true,
    keyboardkey  = true,
    large        = true,
}

local font_file_data = {}
local last_font_scale = nil
local cached_fallbacks = {
    oswald = {},
    cjk = {},
    kr = {},
    system = {},
}

local function get_font_data(path)
    if font_file_data[path] ~= nil then
        return font_file_data[path] or nil
    end
    if love.filesystem.getInfo(path) then
        local ok, data = pcall(love.filesystem.newFileData, path)
        if ok and data then
            font_file_data[path] = data
            return data
        end
    end
    font_file_data[path] = false
    return nil
end

local function release_font_table(tbl)
    for k, f in pairs(tbl) do
        if f and f.release then
            pcall(function() f:release() end)
        end
        tbl[k] = nil
    end
end

-- Override setFont to unwrap our scaled font object
local orig_setFont = love.graphics.setFont
function love.graphics.setFont(font)
    if type(font) == "table" and font._raw then
        orig_setFont(font._raw)
    else
        orig_setFont(font)
    end
end

local FontWrapper = {}

function FontWrapper:getWidth(text)
    return self._raw:getWidth(text or "") / self._scale
end

function FontWrapper:getHeight()
    return self._raw:getHeight() / self._scale
end

function FontWrapper:getWrap(text, width)
    local width_limit = (width or 0) * self._scale
    local w, lines = self._raw:getWrap(text or "", width_limit)
    return w / self._scale, lines
end

function FontWrapper:getAscent()
    return self._raw:getAscent() / self._scale
end

function FontWrapper:getDescent()
    return self._raw:getDescent() / self._scale
end

function FontWrapper:getBaseline()
    return self._raw:getBaseline() / self._scale
end

FontWrapper.__index = function(self, key)
    local method = FontWrapper[key]
    if method ~= nil then
        return method
    end
    local val = self._raw[key]
    if type(val) == "function" then
        return function(_, ...)
            return val(self._raw, ...)
        end
    end
    return val
end

local function wrap_font(raw_font, scale)
    return setmetatable({
        _raw = raw_font,
        _scale = scale or 1
    }, FontWrapper)
end

function assets.update_font_scales(scale)
    scale = scale or 1
    if last_font_scale == scale and assets.fonts.main then
        return
    end
    last_font_scale = scale

    for k, wrapped in pairs(assets.fonts) do
        if wrapped and wrapped._raw and wrapped._raw.release then
            pcall(function() wrapped._raw:release() end)
        end
        assets.fonts[k] = nil
    end
    release_font_table(cached_fallbacks.oswald)
    release_font_table(cached_fallbacks.cjk)
    release_font_table(cached_fallbacks.kr)
    release_font_table(cached_fallbacks.system)

    local figtree_data = get_font_data(path_figtree)
    local oswald_data = get_font_data(path_oswald)
    local cjk_data = get_font_data(path_cjk)
    local kr_data = get_font_data(path_kr)

    for font_key, original_size in pairs(font_sizes) do
        local scaled_size = math.max(1, math.floor(original_size * scale + 0.5))
        local main_font = love.graphics.newFont(figtree_data or path_figtree, scaled_size)

        local oswald_fallback = cached_fallbacks.oswald[scaled_size]
        if not oswald_fallback then
            oswald_fallback = love.graphics.newFont(oswald_data or path_oswald, scaled_size)
            cached_fallbacks.oswald[scaled_size] = oswald_fallback
        end

        local system_fallback = cached_fallbacks.system[scaled_size]
        if not system_fallback then
            system_fallback = love.graphics.newFont(scaled_size)
            cached_fallbacks.system[scaled_size] = system_fallback
        end

        local fallbacks = { oswald_fallback }

        if not NO_CJK_FONTS[font_key] then
            if cjk_data then
                local cjk_fallback = cached_fallbacks.cjk[scaled_size]
                if not cjk_fallback then
                    cjk_fallback = love.graphics.newFont(cjk_data, scaled_size)
                    cached_fallbacks.cjk[scaled_size] = cjk_fallback
                end
                table.insert(fallbacks, cjk_fallback)
            end

            if kr_data then
                local kr_fallback = cached_fallbacks.kr[scaled_size]
                if not kr_fallback then
                    kr_fallback = love.graphics.newFont(kr_data, scaled_size)
                    cached_fallbacks.kr[scaled_size] = kr_fallback
                end
                table.insert(fallbacks, kr_fallback)
            end
        end

        table.insert(fallbacks, system_fallback)
        main_font:setFallbacks(unpack(fallbacks))
        assets.fonts[font_key] = wrap_font(main_font, scale)
    end
end

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
    assets.images.dpad = love.graphics.newImage("assets/icons/dpad.png")
    assets.images.repeat_one = love.graphics.newImage("assets/icons/repeat-one.png")
    assets.images.repeat_all = love.graphics.newImage("assets/icons/repeat.png")
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
    assets.images.screenshot = love.graphics.newImage("assets/icons/screenshot.png")
    assets.images.folder_video = love.graphics.newImage("assets/icons/folder-video.png")
    assets.images.file_video = love.graphics.newImage("assets/icons/file-video.png")
    assets.images.folders = love.graphics.newImage("assets/icons/folders.png")
    assets.images.file = love.graphics.newImage("assets/icons/file.png")
    assets.images.theme = love.graphics.newImage("assets/icons/theme.png")
    assets.images.history = love.graphics.newImage("assets/icons/history.png")
    assets.images.quit = love.graphics.newImage("assets/icons/quit.png")
    assets.images.shuffle = love.graphics.newImage("assets/icons/shuffle.png")
    assets.images.order_down = love.graphics.newImage("assets/icons/order-down.png")
    assets.images.slideshow = love.graphics.newImage("assets/icons/slideshow.png")
    assets.images.eye = love.graphics.newImage("assets/icons/eye.png")
    assets.images.playlist_music = love.graphics.newImage("assets/icons/playlist-music.png")
    assets.images.playlist_video = love.graphics.newImage("assets/icons/playlist-video.png")
    assets.images.playlist_add = love.graphics.newImage("assets/icons/playlist-add.png")
    assets.images.walker = love.graphics.newImage("assets/icons/walker.png")
    assets.images.muos = love.graphics.newImage("assets/icons/muos.png")


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

    local current_scale = (simpleScale and simpleScale.scale) or 1
    assets.update_font_scales(current_scale)

    -- Load SFX
    assets.sfx.nav = love.audio.newSource("assets/sfx/keytone.wav", "static")
    assets.sfx.nav:setVolume(0.5)
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
