local theme = require("theme")
local categories = require("categories")

local settings = {}

settings.keytone_enabled = true
settings.display_sleep_seconds = 0
settings.power_save_sleep_enabled = true
settings.video_player_mode = "mpv"
settings.ffplay_aspect_ratio = "Original"
settings.track_info_background_mode = 1
local storage_path = love.filesystem.getSource()
settings.file_path = storage_path .. "/settings.cfg"

-- Current submenu depth for settings category
settings.current_group = nil -- nil = top-level groups, string = group id

-- Grouped settings
settings.groups = {
    {
        id = "quit",
        name = "Quit XMPlayer",
        icon = "quit",
    },
    {
        id = "general",
        name = "General Settings",
        icon = "option",
    },
    {
        id = "music_settings",
        name = "Music Settings",
        icon = "music",
    },
    {
        id = "video_settings",
        name = "Video Settings",
        icon = "video",
    },
    {
        id = "theme_settings",
        name = "Theme Settings",
        icon = "theme",
    },
    {
        id = "media_dirs",
        name = "Media Directories",
        icon = "folder",
    },
    {
        id = "about",
        name = "About XMPlayer",
        icon = "info",
    },
    {
        id = "devtools",
        name = "Dev Tools",
        icon = "option",
    },
}

settings.options = {
    {
        id = "theme",
        name = "Theme",
        type = "choice",
        group = "theme_settings",
        choices = { "Light", "Dark" },
        value = 1
    },
    {
        id = "theme_color",
        name = "Theme Color",
        type = "choice",
        group = "theme_settings",
        choices = { "Dark Red", "Volcanic", "Golden", "Lime Green", "Apple Green", "Moss Green", "Undersea", "Electric Blue", "Midnight Blue", "Dark Purple", "Ice Cold", "Morning Blue", "Gray Light", "Gray Dark" },
        value = 5
    },
    {
        id = "particles",
        name = "Particle Effects",
        type = "choice",
        group = "theme_settings",
        choices = { "Show", "Hide" },
        value = 1
    },
    {
        id = "custom_bg",
        name = "Background",
        type = "choice",
        group = "theme_settings",
        choices = { "Waves", "Ribbon", "Wallpaper" },
        value = 1
    },
    {
        id = "custom_bg_path",
        name = "Wallpaper Path",
        type = "path",
        group = "internal",
        value = ""
    },
    {
        id = "wallpaper_type",
        name = "Wallpaper Type",
        type = "choice",
        group = "theme_settings",
        choices = { "Static", "Scrolling", "Seamless" },
        value = 1
    },
    {
        id = "blur_wallpaper",
        name = "Blur Wallpaper",
        type = "choice",
        group = "theme_settings",
        choices = { "No", "Yes" },
        value = 1
    },
    {
        id = "tint_wallpaper",
        name = "Tint Wallpaper to Theme Color",
        type = "choice",
        group = "theme_settings",
        choices = { "No", "Yes" },
        value = 1
    },
    {
        id = "wallpaper_brightness",
        name = "Wallpaper Brightness",
        type = "choice",
        group = "theme_settings",
        choices = { "No Change", "Darker", "Darkest", "Brighter", "Brightest" },
        value = 1
    },
    {
        id = "photo_dir",
        name = "Photo Directory",
        type = "path",
        group = "media_dirs",
        value = ""
    },
    {
        id = "music_dir",
        name = "Music Directory",
        type = "path",
        group = "media_dirs",
        value = ""
    },
    {
        id = "video_dir",
        name = "Video Directory",
        type = "path",
        group = "media_dirs",
        value = ""
    },
    {
        id = "reindex_media",
        name = "Reindex Media and Restart App",
        type = "action",
        group = "media_dirs",
        icon = "repeat",
    },
    {
        id = "keytone",
        name = "Key Tone",
        type = "choice",
        group = "general",
        choices = { "On", "Off" },
        value = 1
    },
    {
        id = "startup_sound",
        name = "Startup Sound",
        type = "choice",
        group = "general",
        choices = { "On", "Off" },
        value = 1
    },
    {
        id = "vol_bright_control",
        name = "Volume & Brightness Control",
        type = "choice",
        group = "general",
        choices = { "Show", "Hide" },
        value = 1
    },
    {
        id = "force_reindex_once",
        name = "Force Reindex Once",
        type = "flag",
        group = "internal",
        value = 0
    },
    {
        id = "display_sleep",
        name = "Auto Display Sleep (Music)",
        type = "choice",
        group = "music_settings",
        choices = { "Off", "5s", "10s", "15s", "30s", "1m", "3m" },
        value = 1
    },
    {
        id = "power_save_sleep",
        name = "Power-saving Display Sleep",
        type = "choice",
        group = "music_settings",
        choices = { "On", "Off" },
        value = 1
    },
    {
        id = "track_info_background",
        name = "Track Info Background",
        type = "choice",
        group = "music_settings",
        choices = { "Hide", "Clear", "Opaque" },
        value = 1
    },
    {
        id = "video_player",
        name = "Video Player",
        type = "choice",
        group = "video_settings",
        choices = { "mpv", "ffplay" },
        value = 1
    },
    {
        id = "ffplay_aspect_ratio",
        name = "ffplay Aspect Ratio",
        type = "choice",
        group = "video_settings",
        choices = { "Original", "4:3", "16:9", "3:2", "1:1" },
        value = 1
    },
    {
        id = "repeat_folder",
        name = "Loop Folder (mpv)",
        type = "choice",
        group = "video_settings",
        choices = { "No", "Yes" },
        value = 1
    },
    {
        id = "repeat_watchlist",
        name = "Loop Watchlist (mpv)",
        type = "choice",
        group = "video_settings",
        choices = { "No", "Yes" },
        value = 1
    },
    {
        id = "clear_history",
        name = "Clear Watch History",
        type = "action",
        group = "video_settings",
    },
    {
        id = "restore_default_wallpaper",
        name = "Restore Default Wallpaper",
        type = "action",
        group = "general",
    },
    {
        id = "version",
        name = "Version",
        type = "info",
        group = "about",
        value = "v0.2.1 Sage Symphony"
    },
    {
        id = "build_type",
        name = "Build Target",
        type = "info",
        group = "about",
        value = os.getenv("XM_BUILD_TYPE") or "muOS App"
    },
    {
        id = "website",
        name = "Website",
        type = "info",
        group = "about",
        value = "github.com/atalaygrgn/XMPlayer"
    },
    {
        id = "test_toast_top",
        name = "Test Top Center Toast",
        type = "action",
        group = "devtools",
    },
    {
        id = "test_toast_bottom",
        name = "Test Bottom Right Toast",
        type = "action",
        group = "devtools",
    },
}

-- Helper to find option by id
function settings.get_option(id)
    for _, opt in ipairs(settings.options) do
        if opt.id == id then return opt end
    end
    return nil
end

function settings.request_reindex_on_restart()
    local opt = settings.get_option("force_reindex_once")
    if opt then
        opt.value = 1
        settings.save()
    end
end

function settings.consume_reindex_request()
    local opt = settings.get_option("force_reindex_once")
    if opt and tonumber(opt.value) == 1 then
        opt.value = 0
        settings.save()
        return true
    end
    return false
end

function settings.save()
    local data_str = "return {\n"
    for _, opt in ipairs(settings.options) do
        if opt.value ~= nil and opt.type ~= "info" then
            if type(opt.value) == "string" then
                data_str = data_str .. string.format("  [\"%s\"] = %q,\n", opt.id, opt.value)
            else
                data_str = data_str .. string.format("  [\"%s\"] = %s,\n", opt.id, tostring(opt.value))
            end
        end
    end
    data_str = data_str .. "}\n"
    local f = io.open(settings.file_path, "w")
    if f then
        f:write(data_str)
        f:close()
    end
end

function settings.load()
    local f = io.open(settings.file_path, "r")
    if f then
        f:close()
        local chunk, err = loadfile(settings.file_path)
        if chunk then
            local ok, data = pcall(chunk)
            if ok and type(data) == "table" then
                for id, val in pairs(data) do
                    local opt = settings.get_option(id)
                    if opt and opt.type ~= "info" then
                        opt.value = val
                    end
                end
            end
        end
    end
    settings.apply()
end

function settings.apply()
    local opt_theme = settings.get_option("theme")
    local opt_color = settings.get_option("theme_color")
    if opt_theme and opt_color then
        theme.apply(opt_theme.choices[opt_theme.value], opt_color.choices[opt_color.value])
    end

    -- Update categories paths
    local opt_photo = settings.get_option("photo_dir")
    local opt_music = settings.get_option("music_dir")
    local opt_video = settings.get_option("video_dir")
    for _, cat in ipairs(categories) do
        if cat.id == "photo" and opt_photo then
            cat.path = opt_photo.value
        elseif cat.id == "music" and opt_music then
            cat.path = opt_music.value
        elseif cat.id == "video" and opt_video then
            cat.path = opt_video.value
        end
    end

    -- Update keytone
    local opt_keytone = settings.get_option("keytone")
    if opt_keytone then
        settings.keytone_enabled = (opt_keytone.value == 1)
    end

    -- Update volume & brightness control visibility
    local opt_vol_bright = settings.get_option("vol_bright_control")
    if opt_vol_bright then
        settings.vol_bright_enabled = (opt_vol_bright.value == 1)
    end

    local opt_display_sleep = settings.get_option("display_sleep")
    if opt_display_sleep then
        local display_sleep_choices = { 0, 5, 10, 15, 30, 60, 180 }
        settings.display_sleep_seconds = display_sleep_choices[opt_display_sleep.value] or 0
    else
        settings.display_sleep_seconds = 0
    end

    local opt_power_save_sleep = settings.get_option("power_save_sleep")
    if opt_power_save_sleep then
        settings.power_save_sleep_enabled = (opt_power_save_sleep.value == 1)
    else
        settings.power_save_sleep_enabled = true
    end

    local opt_video_player = settings.get_option("video_player")
    if opt_video_player then
        settings.video_player_mode = opt_video_player.choices[opt_video_player.value] or "mpv"
    else
        settings.video_player_mode = "mpv"
    end

    local opt_ffplay_aspect = settings.get_option("ffplay_aspect_ratio")
    if opt_ffplay_aspect then
        settings.ffplay_aspect_ratio = opt_ffplay_aspect.choices[opt_ffplay_aspect.value] or "Original"
    else
        settings.ffplay_aspect_ratio = "Original"
    end

    local opt_repeat_folder = settings.get_option("repeat_folder")
    if opt_repeat_folder then
        settings.repeat_folder = opt_repeat_folder.choices[opt_repeat_folder.value] or "No"
    else
        settings.repeat_folder = "No"
    end

    local opt_repeat_watchlist = settings.get_option("repeat_watchlist")
    if opt_repeat_watchlist then
        settings.repeat_watchlist = opt_repeat_watchlist.choices[opt_repeat_watchlist.value] or "No"
    else
        settings.repeat_watchlist = "No"
    end

    local opt_track_info_background = settings.get_option("track_info_background")
    if opt_track_info_background then
        settings.track_info_background_mode = math.max(1, math.min(3, math.floor(opt_track_info_background.value or 1)))
    else
        settings.track_info_background_mode = 1
    end

    -- Update particles visibility
    local opt_particles = settings.get_option("particles")
    if opt_particles then
        settings.show_particles = (opt_particles.value == 1)
    end

    -- Update background mode and wallpaper
    local opt_custom_bg = settings.get_option("custom_bg")
    local opt_custom_bg_path = settings.get_option("custom_bg_path")
    if opt_custom_bg then
        local background = require("background")
        background.set_custom_bg_path(opt_custom_bg_path and opt_custom_bg_path.value or nil)
        background.set_background_mode(opt_custom_bg.value)
    end

    -- Update wallpaper effects
    local background = require("background")

    local opt_blur_wallpaper = settings.get_option("blur_wallpaper")
    if opt_blur_wallpaper then
        background.set_wallpaper_blur(opt_blur_wallpaper.value == 2)
    end

    local opt_tint_wallpaper = settings.get_option("tint_wallpaper")
    if opt_tint_wallpaper then
        background.set_wallpaper_tint(opt_tint_wallpaper.value == 2)
    end

    local opt_wallpaper_brightness = settings.get_option("wallpaper_brightness")
    if opt_wallpaper_brightness then
        background.set_wallpaper_brightness(opt_wallpaper_brightness.value)
    end

    -- Update wallpaper type (Static, Scrolling, Seamless)
    local opt_wallpaper_type = settings.get_option("wallpaper_type")
    if opt_wallpaper_type then
        background.set_wallpaper_type(opt_wallpaper_type.value)
    end
end

function settings.get_browser_items()
    if settings.current_group then
        -- Show options within the selected group
        local items = {}
        for i, opt in ipairs(settings.options) do
            if opt.group == settings.current_group then
                local display_value = ""
                if opt.type == "choice" then
                    display_value = ": " .. opt.choices[opt.value]
                elseif opt.type == "path" or opt.type == "info" then
                    display_value = ": " .. tostring(opt.value)
                end

                local icon = "option"
                if opt.group == "about" then
                    icon = "info"
                elseif opt.group == "media_dirs" then
                    icon = "folder"
                end
                table.insert(items, {
                    name = opt.name .. display_value,
                    type = (opt.type == "info") and "info_text" or "setting",
                    setting_idx = i,
                    icon = icon
                })
            end
        end
        return items
    else
        -- Show top-level groups
        local items = {}
        for i, grp in ipairs(settings.groups) do
            table.insert(items, {
                name = grp.name,
                type = "settings_group",
                group_idx = i,
                group_id = grp.id,
                icon = grp.icon
            })
        end
        return items
    end
end

-- Check if we're inside a settings submenu
function settings.in_submenu()
    return settings.current_group ~= nil
end

-- Go back to top-level settings groups
function settings.go_back()
    settings.current_group = nil
end

-- Enter a group
function settings.enter_group(group_id)
    settings.current_group = group_id
end

return settings
