local theme = require("theme")
local assets = require("assets")
local utils = require("utils")
local categories = require("categories")

local settings = {}

settings.active = false
settings.alpha = 0
settings.selected_option_idx = 1
settings.scroll_y = 0
settings.target_scroll_y = 0
settings.keytone_enabled = true
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
        value = 2
    },
    {
        id = "theme_color",
        name = "Theme Color",
        type = "choice",
        group = "theme_settings",
        choices = { "Blue", "Red", "Green", "Teal", "Purple", "Yellow", "Orange" },
        value = 1
    },
    {
        id = "particles",
        name = "Particle Effects",
        type = "choice",
        group = "theme_settings",
        choices = { "Show", "Hide" },
        value = 2
    },
    {
        id = "photo_dir",
        name = "Photo Directory",
        type = "path",
        group = "media_dirs",
        value = "/mnt/sdcard/PICTURES"
    },
    {
        id = "music_dir",
        name = "Music Directory",
        type = "path",
        group = "media_dirs",
        value = "/mnt/sdcard/MUSIC"
    },
    {
        id = "video_dir",
        name = "Video Directory",
        type = "path",
        group = "media_dirs",
        value = "/mnt/sdcard/ROMS/Video"
    },
    {
        id = "keytone",
        name = "Keytone",
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
        id = "clear_history",
        name = "Clear Watch History",
        type = "action",
        group = "general",
    },
    {
        id = "version",
        name = "Version",
        type = "info",
        group = "about",
        value = "v0.1"
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

function settings.save()
    local data_str = "return {\n"
    for _, opt in ipairs(settings.options) do
        if opt.value ~= nil then
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
                    if opt then
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
    theme.apply(opt_theme.choices[opt_theme.value], opt_color.choices[opt_color.value])

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
    settings.keytone_enabled = (opt_keytone.value == 1)

    -- Update volume & brightness control visibility
    local opt_vol_bright = settings.get_option("vol_bright_control")
    settings.vol_bright_enabled = (opt_vol_bright.value == 1)

    -- Update particles visibility
    local opt_particles = settings.get_option("particles")
    settings.show_particles = (opt_particles.value == 1)
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

                local icon = "folder"
                if opt.group == "about" then
                    icon = "info"
                elseif opt.group == "general" or opt.group == "theme_settings" or opt.group == "devtools" then
                    icon = "option"
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

function settings.update(dt, setting_idx)
    if settings.active then
        settings.alpha = math.min(1, settings.alpha + dt * 10)

        -- Update scroll
        if setting_idx then
            local opt = settings.options[setting_idx]
            if opt and opt.choices then
                local item_h = 50
                local screen_h = love.graphics.getHeight()
                local visible_area_h = screen_h * 0.6

                -- Target scroll to keep selected item near the middle of visible area
                settings.target_scroll_y = -(settings.selected_option_idx - 1) * item_h + (visible_area_h / 2) -
                    (item_h / 2)

                -- Clamp scroll
                local max_scroll = 0
                local min_scroll = math.min(0, -(#opt.choices * item_h) + visible_area_h)
                settings.target_scroll_y = math.max(min_scroll, math.min(max_scroll, settings.target_scroll_y))
            end
        end
    else
        settings.alpha = math.max(0, settings.alpha - dt * 10)
    end

    settings.scroll_y = utils.lerp(settings.scroll_y, settings.target_scroll_y or 0, dt * 10)
end

function settings.draw_popup(setting_idx)
    local opt = settings.options[setting_idx]
    if not opt or opt.type ~= "choice" or settings.alpha <= 0 then return end

    local screen_w, screen_h = love.graphics.getDimensions()
    local panel_w = screen_w * 0.25
    local item_h = 50
    local alpha = settings.alpha
    local x = screen_w - (panel_w * alpha)
    local y = 0

    -- Panel Background
    love.graphics.setColor(0.02, 0.02, 0.05, 0.92 * alpha)
    love.graphics.rectangle("fill", x, y, panel_w, screen_h)

    -- Left accent border
    love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.8 * alpha)
    love.graphics.rectangle("fill", x, y, 4, screen_h)

    -- Content Container
    local content_y_base = screen_h * 0.3
    local visible_area_h = screen_h * 0.6

    love.graphics.setScissor(x, content_y_base, panel_w, visible_area_h)
    love.graphics.push()
    love.graphics.translate(0, content_y_base + settings.scroll_y)

    -- Choices
    love.graphics.setFont(assets.fonts.small)
    for i, choice in ipairs(opt.choices) do
        local cy = (i - 1) * item_h
        local is_selected = (i == settings.selected_option_idx)
        local is_current = (i == opt.value)

        if is_selected then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.3 * alpha)
            love.graphics.rectangle("fill", x + 4, cy - 5, panel_w - 4, item_h)

            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 1 * alpha)
            love.graphics.rectangle("fill", x + 4, cy - 5, 4, item_h)

            love.graphics.setColor(1, 1, 1, 1 * alpha)
        else
            love.graphics.setColor(1, 1, 1, 0.6 * alpha)
        end

        love.graphics.print(choice, x + 40, cy + 5)

        if is_current then
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 1 * alpha)
            love.graphics.circle("fill", x + 25, cy + item_h / 2 - 6, 4)
        end
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- Scroll indicators
    if #opt.choices * item_h > visible_area_h then
        love.graphics.setColor(1, 1, 1, 0.3 * alpha)
        local centerX = x + panel_w / 2
        if settings.scroll_y < 0 then
            love.graphics.polygon("fill", centerX - 10, content_y_base - 14, centerX + 10, content_y_base - 14, centerX,
                content_y_base - 26)
        end
        if settings.scroll_y > -(#opt.choices * item_h) + visible_area_h then
            local targetY = content_y_base + visible_area_h + 14
            love.graphics.polygon("fill", centerX - 10, targetY, centerX + 10, targetY, centerX, targetY + 12)
        end
    end
end

return settings
