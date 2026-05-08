local theme = require("theme")
local browser = require("browser")
local categories = require("categories")
local settings = require("settings")
local settings_view = require("settings_view")
local assets = require("assets")
local ui = require("ui")
local utils = require("utils")
local indexing = require("indexing")
local history = require("history")
local video_manager = require("video_manager")

local xmb = {}

xmb.current_category_idx = 3 -- Default to Music
xmb.current_item_idx = 1

-- Animation state
xmb.category_scroll_x = 0
xmb.target_category_scroll_x = 0
xmb.item_scroll_y = 0
xmb.target_item_scroll_y = 0

-- UI Components
xmb.item_marquee = ui.new_marquee(0, 50, 1.5, 1.0) -- width set in update

-- Slide transition state
xmb.list_slide_x = 0
xmb.list_slide_alpha = 1

-- Navigation history stack (stores focused item index in sub-menus)
-- Each entry: item_idx
xmb.nav_stack = {}
xmb.view_type = "browser" -- "category_root", "browser", "music_albums", "music_artists", "album_tracks", "artist_tracks"
xmb.view_data = nil

-- Continuous Repeat State
xmb.repeat_timer = 0
xmb.last_key = nil
local REPEAT_DELAY = 0.4
local REPEAT_INTERVAL = 0.08

-- Thumbnail cache
xmb.thumbs = {} -- {path = LoveImage}

xmb.context_menu = {
    active = false,
    alpha = 0,
    selected_idx = 1,
    title = "",
    items = {},
    target_path = nil
}

-- Helper to count media files in a directory (recursive)
local function count_media_in_dir(dir, media_type)
    if not dir or dir == "" then return 0 end
    local exts = indexing.compatible_extensions[media_type]
    if not exts then return 0 end
    -- Prefer counting from the indexing data when available (more portable
    -- and avoids shell/find differences). Fall back to a `find`-based count
    -- if the index is empty or unavailable.
    if indexing and indexing.data then
        -- Use indexed data when available for portability and speed
        if media_type == "music" and indexing.data.music and next(indexing.data.music.files) then
            local cnt = 0
            for path, _ in pairs(indexing.data.music.files) do
                if utils.is_subpath(dir, path) then
                    cnt = cnt + 1
                end
            end
            return cnt
        end

        if media_type == "photo" and indexing.data.photos and next(indexing.data.photos) then
            local cnt = 0
            for path, _ in pairs(indexing.data.photos) do
                if utils.is_subpath(dir, path) then
                    cnt = cnt + 1
                end
            end
            return cnt
        end

        if media_type == "video" and indexing.data.videos and #indexing.data.videos > 0 then
            local cnt = 0
            for _, path in ipairs(indexing.data.videos) do
                if utils.is_subpath(dir, path) then
                    cnt = cnt + 1
                end
            end
            return cnt
        end
    end

    local pattern_parts = {}
    for _, ext in ipairs(exts) do
        local e = ext:sub(2) -- remove leading dot
        table.insert(pattern_parts, "-name '*." .. e .. "' -o -name '*." .. e:upper() .. "'")
    end
    local pattern_str = table.concat(pattern_parts, " ")

    local cmd = [[find "]] .. dir .. [[" -type f \( ]] .. pattern_str .. [[ \) 2>/dev/null | wc -l]]
    local handle = io.popen(cmd)
    local count = 0
    if handle then
        local result = handle:read("*a")
        handle:close()
        count = tonumber(result:match("%d+")) or 0
    end
    return count
end

-- Media type helpers (placed before use in prep_files)
local function is_music_file(path)
    local ext = utils.get_extension(path)
    if not ext then return false end
    for _, e in ipairs(indexing.compatible_extensions.music) do
        if ext == e then return true end
    end
    return false
end

local function is_photo_file(path)
    local ext = utils.get_extension(path)
    if not ext then return false end
    for _, e in ipairs(indexing.compatible_extensions.photo) do
        if ext == e then return true end
    end
    return false
end

local function is_video_file(path)
    local ext = utils.get_extension(path)
    if not ext then return false end
    for _, e in ipairs(indexing.compatible_extensions.video) do
        if ext == e then return true end
    end
    return false
end

local function prep_files()
    local screen_w = love.graphics.getWidth()
    local cat_base_x = screen_w * 0.25
    local max_w = screen_w - cat_base_x - 40
    local font = assets.fonts.small

    for _, item in ipairs(browser.files) do
        item.name = utils.clean_utf8(item.name)
        item.display_name = utils.truncate_text(item.name, font, max_w)
        -- Assign sensible icons for files if not already provided
        if item.type == "file" and not item.icon then
            if is_photo_file(item.path) then
                item.icon = "photo"
            elseif (is_video_file and is_video_file(item.path)) then
                item.icon = "file_video"
            elseif is_music_file(item.path) then
                item.icon = "file_music"
            else
                item.icon = "file"
            end
        end
    end
end

local function current_filter()
    local cat = categories[xmb.current_category_idx]
    return cat and cat.filter or nil
end

local function refresh_settings_items(keep_idx)
    local old_idx = keep_idx and xmb.current_item_idx or nil
    browser.set_files(settings.get_browser_items())
    prep_files()
    if old_idx then
        xmb.current_item_idx = old_idx
    end
end


local function close_context_menu()
    xmb.context_menu.active = false
    xmb.context_menu.items = {}
    xmb.context_menu.selected_idx = 1
    xmb.context_menu.title = ""
    xmb.context_menu.target_path = nil
end

local function open_context_menu(title, items, path)
    if not path or not items or #items == 0 then return end
    xmb.context_menu.active = true
    xmb.context_menu.selected_idx = 1
    xmb.context_menu.title = title
    xmb.context_menu.items = items
    xmb.context_menu.target_path = path
end

local function open_photo_context_menu(path)
    open_context_menu("Photo Options", {
        { id = "set_wallpaper", label = "Set as Wallpaper" }
    }, path)
end

local function open_video_context_menu(path)
    local watched = video_manager.is_watched(path)
    open_context_menu("Video Options", {
        {
            id = "toggle_watched",
            label = watched and "Unmark as Watched" or "Mark as Watched"
        }
    }, path)
end

local function apply_context_action(action_id)
    if action_id == "set_wallpaper" and xmb.context_menu.target_path then
        local path = xmb.context_menu.target_path
        local opt_path = settings.get_option("custom_bg_path")
        local opt_enabled = settings.get_option("custom_bg")
        if opt_path then
            opt_path.value = path
        end
        if opt_enabled then
            opt_enabled.value = 1
        end
        settings.apply()
        settings.save()

        --ui.show_toast("Wallpaper set", "photo", "bottom_right")
    elseif action_id == "toggle_watched" and xmb.context_menu.target_path then
        local path = xmb.context_menu.target_path
        local watched = video_manager.toggle_watched(path)
        --ui.show_toast(watched and "Marked as watched" or "Marked as unwatched", "video", "bottom_right")
    end
end

function xmb.in_submenu()
    local cat = categories[xmb.current_category_idx]
    if cat.id == "settings" then
        return settings.in_submenu()
    end

    if (cat.id == "music" or cat.id == "video" or cat.id == "photo" or cat.id == "folder") and xmb.view_type ~= "category_root" then
        return true
    end

    if cat.path then
        return utils.normalize_path(browser.current_dir) ~= utils.normalize_path(browser.base_dir)
    end
    return false
end

-- Go back one level in the current submenu
function xmb.go_back()
    if xmb.context_menu.active then
        close_context_menu()
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
        return
    end

    -- Restore previous item index from stack
    local prev_idx = 1
    if #xmb.nav_stack > 0 then
        prev_idx = table.remove(xmb.nav_stack)
    end

    local cat = categories[xmb.current_category_idx]
    if cat.id == "settings" then
        settings.go_back()
        refresh_settings_items(false)
        xmb.current_item_idx = math.min(prev_idx, #browser.files)
    elseif cat.path then
        if xmb.view_type ~= "browser" then
            -- Handle categorical views
            if xmb.view_type == "album_tracks" or xmb.view_type == "artist_tracks" then
                if xmb.view_type == "album_tracks" then
                    xmb.view_type = "music_albums"
                else
                    xmb.view_type = "music_artists"
                end
                xmb.refresh_items()
            else
                xmb.view_type = "category_root"
                xmb.refresh_items()
            end
            xmb.current_item_idx = math.min(prev_idx, #browser.files)
            prep_files()
        else
            local current = utils.normalize_path(browser.current_dir)
            local base = utils.normalize_path(browser.base_dir)

            if (cat.id == "music" or cat.id == "video" or cat.id == "photo" or cat.id == "folder") and current == base then
                -- Return to categorical root
                xmb.view_type = "category_root"
                xmb.refresh_items()
                xmb.current_item_idx = math.min(prev_idx, #browser.files)
                prep_files()
            elseif current ~= base then
                local parent = utils.get_dirname(browser.current_dir)
                if parent ~= "" and utils.is_subpath(base, parent) then
                    browser.set_state(browser.base_dir, parent, current_filter())
                    xmb.refresh_items()
                    xmb.current_item_idx = math.min(prev_idx, #browser.files)
                    prep_files()
                else
                    browser.set_state(browser.base_dir, base, current_filter())
                    xmb.refresh_items()
                    xmb.current_item_idx = math.min(prev_idx, #browser.files)
                    prep_files()
                end
            end
        end
    end

    xmb.item_marquee.offset = 0
    xmb.item_marquee.timer = 0
    xmb.item_marquee.phase = "pause_start"

    -- Snap vertical scroll to new position instantly
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 75
    xmb.item_scroll_y = xmb.target_item_scroll_y
    -- Slide in from the left (going back)
    xmb.list_slide_x = -120
    xmb.list_slide_alpha = 0

    if settings.keytone_enabled then
        assets.play_sfx("nav")
    end
end

function xmb.refresh_items()
    local cat = categories[xmb.current_category_idx]
    browser.set_files({})

    -- Helper: check if a directory contains any non-hidden entries
    local function dir_has_entries(path)
        if not path or path == "" then return false end
        local cmd = "find \"" .. path .. "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' 2>/dev/null"
        local h = io.popen(cmd)
        if not h then return false end
        for _ in h:lines() do
            h:close()
            return true
        end
        h:close()
        return false
    end

    if (cat.id == "music" or cat.id == "video" or cat.id == "photo") and (not cat.path or cat.path == "") then
        browser.set_files({ { name = "Media directory not set. Please set directory from Settings.", type = "info_text" } })
        return
    end

    if cat.id == "music" then
        if xmb.view_type == "category_root" then
            table.insert(browser.files,
                { name = "Albums", type = "view_trigger", target_view = "music_albums", icon = "albums" })
            table.insert(browser.files,
                { name = "Artists", type = "view_trigger", target_view = "music_artists", icon = "mic" })

            local music_count = 0
            for _ in pairs(indexing.data.music.files) do music_count = music_count + 1 end
            table.insert(browser.files,
                {
                    name = "Music Files",
                    type = "directory_trigger",
                    path = cat.path,
                    icon = "folder_music",
                    description = music_count .. " tracks"
                })

            browser.set_state(cat.path, cat.path, cat.filter)
        elseif xmb.view_type == "music_albums" then
            for key, album in pairs(indexing.data.music.albums) do
                table.insert(browser.files, {
                    name = album.name,
                    type = "album",
                    data = album,
                    description = album.artist
                })
            end
            table.sort(browser.files, function(a, b)
                local name_a = a.name:lower()
                local name_b = b.name:lower()
                if name_a ~= name_b then
                    return name_a < name_b
                end

                return (a.description or ""):lower() < (b.description or ""):lower()
            end)
        elseif xmb.view_type == "music_artists" then
            for name, artist in pairs(indexing.data.music.artists) do
                table.insert(browser.files, { name = name, type = "artist", data = artist })
            end
            table.sort(browser.files, function(a, b) return a.name:lower() < b.name:lower() end)
        elseif xmb.view_type == "album_tracks" then
            table.insert(browser.files,
                { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle", tracks = xmb.view_data.tracks })
            for _, path in ipairs(xmb.view_data.tracks) do
                local info = indexing.data.music.files[path]
                table.insert(browser.files, { name = info.title or "Unknown", path = path, type = "file" })
            end
        elseif xmb.view_type == "artist_tracks" then
            table.insert(browser.files,
                { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle", tracks = xmb.view_data.tracks })
            for _, path in ipairs(xmb.view_data.tracks) do
                local info = indexing.data.music.files[path]
                table.insert(browser.files, { name = info.title or "Unknown", path = path, type = "file" })
            end
        elseif xmb.view_type == "browser" then
            browser.scan()
            -- Check if we have any music files in this folder
            local has_music = false
            for _, item in ipairs(browser.files) do
                if item.type == "file" and is_music_file(item.path) then
                    has_music = true
                elseif item.type == "directory" then
                    local count = count_media_in_dir(item.path, "music")
                    item.description = count .. " tracks"
                end
            end
            if has_music then
                table.insert(browser.files, 1, { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle" })
            end
        end
    elseif cat.id == "video" then
        if xmb.view_type == "category_root" then
            table.insert(browser.files,
                {
                    name = "Resume Watching",
                    type = "view_trigger",
                    target_view = "video_resume",
                    icon = "history",
                    description = "Pick up where you left off"
                })
            table.insert(browser.files,
                {
                    name = "Video Files",
                    type = "directory_trigger",
                    path = cat.path,
                    icon = "folder_video",
                    description = #indexing.data.videos .. " videos"
                })

            browser.set_state(cat.path, cat.path, cat.filter)
        elseif xmb.view_type == "video_resume" then
            local resume_list = video_manager.get_resume_list()
            for _, item in ipairs(resume_list) do
                table.insert(browser.files, { name = item.name, path = item.path, type = "file" })
            end
        elseif xmb.view_type == "browser" then
            browser.scan()
            -- Add Play All and Shuffle Play if there are video files
            local has_videos = false
            for _, item in ipairs(browser.files) do
                if item.type == "file" then
                    has_videos = true
                elseif item.type == "directory" then
                    local count = count_media_in_dir(item.path, "video")
                    item.description = count .. " videos"
                end
            end
            if has_videos then
                table.insert(browser.files, 1, { name = "Play All", type = "video_play_all", icon = "play" })
                table.insert(browser.files, 2, { name = "Shuffle Play", type = "video_shuffle_play", icon = "shuffle" })
            end
        end
    elseif cat.id == "photo" then
        if xmb.view_type == "category_root" then
            local photo_count = 0
            for _ in pairs(indexing.data.photos) do photo_count = photo_count + 1 end
            table.insert(browser.files,
                {
                    name = "Photo Files",
                    type = "directory_trigger",
                    path = cat.path,
                    icon = "folder_image",
                    description = photo_count .. " photos"
                })
            browser.set_state(cat.path, cat.path, cat.filter)
        elseif xmb.view_type == "browser" then
            browser.scan()
            for _, item in ipairs(browser.files) do
                if item.type == "directory" then
                    local count = count_media_in_dir(item.path, "photo")
                    item.description = count .. " photos"
                end
            end
        end
    elseif cat.id == "settings" then
        refresh_settings_items(false)
    elseif cat.id == "folder" then
        if xmb.view_type == "category_root" then
            -- Files tab: show storage roots instead of raw filesystem root
            table.insert(browser.files, {
                name = "Primary Storage",
                type = "directory_trigger",
                path = "/mnt/mmc",
                icon = "drive",
                description = "/mnt/mmc"
            })

            if dir_has_entries("/mnt/sdcard") then
                table.insert(browser.files, {
                    name = "Secondary Storage",
                    type = "directory_trigger",
                    path = "/mnt/sdcard",
                    icon = "sdcard",
                    description = "/mnt/sdcard"
                })
            end
        elseif xmb.view_type == "browser" then
            -- In browser view for Files category: list selected storage contents
            browser.scan()
        end
    elseif cat.path then
        local base_dir = cat.path or "/mnt/sdcard"
        -- Preserve current browser state if already inside this category's base
        if not browser.current_dir or not utils.is_subpath(base_dir, browser.current_dir) then
            browser.set_state(base_dir, base_dir, cat.filter)
        end
        if xmb.view_type == "browser" then
            browser.scan()
        end
    end
end

function xmb.refresh_browser(slide_dir)
    close_context_menu()

    local cat = categories[xmb.current_category_idx]
    if cat.id == "music" or cat.id == "video" or cat.id == "photo" or cat.id == "folder" then
        xmb.view_type = "category_root"
    else
        xmb.view_type = "browser"
    end

    xmb.view_data = nil

    -- Ensure browser state is clean for the new category
    -- If media category has no configured path, show an instructional info item
    if (cat.id == "music" or cat.id == "video" or cat.id == "photo") and (not cat.path or cat.path == "") then
        browser.set_files({ { name = "Media directory not set. Please set directory from Settings.", type = "info_text" } })
    else
        local base_dir = cat.path or "/mnt/sdcard"
        browser.set_state(base_dir, base_dir, cat.filter)
        xmb.refresh_items()
    end

    if cat.id == "settings" then
        xmb.current_item_idx = 2 -- General Settings, not quit
    else
        xmb.current_item_idx = 1 -- First item as usual otherwise
    end

    xmb.item_marquee.offset = 0
    xmb.item_marquee.timer = 0
    xmb.item_marquee.phase = "pause_start"

    xmb.nav_stack = {} -- Clear history on category switch
    -- Snap vertical scroll to top or focused item instantly
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 75
    xmb.item_scroll_y = xmb.target_item_scroll_y
    -- Slide direction based on navigation
    local slide = (slide_dir == "left") and -120 or 120
    xmb.list_slide_x = slide
    xmb.list_slide_alpha = 0

    prep_files()
end

-- Shared navigation logic for single press and continuous scroll
function xmb.navigate(dir)
    local moved = false
    if settings_view.active then
        if settings_view.picker_active then
            local old_idx = settings_view.picker_selected_idx
            if dir == "up" then
                settings_view.picker_selected_idx = math.max(1, settings_view.picker_selected_idx - 1)
                settings_view.ensure_picker_visible()
            elseif dir == "down" then
                settings_view.picker_selected_idx = math.min(#settings_view.picker_items, settings_view.picker_selected_idx + 1)
                settings_view.ensure_picker_visible()
            end
            moved = (old_idx ~= settings_view.picker_selected_idx)
            if moved and settings.keytone_enabled then
                assets.play_sfx("nav")
            end
            return moved
        end

        local old_idx = settings_view.selected_option_idx
        if dir == "up" then
            settings_view.selected_option_idx = math.max(1, settings_view.selected_option_idx - 1)
        elseif dir == "down" then
            local selected = browser.files[xmb.current_item_idx]
            if selected and selected.setting_idx then
                local opt = settings.options[selected.setting_idx]
                if opt and opt.choices then
                    settings_view.selected_option_idx = math.min(#opt.choices, settings_view.selected_option_idx + 1)
                end
            end
        end
        moved = (old_idx ~= settings_view.selected_option_idx)
    elseif dir == "left" then
        if xmb.in_submenu() then
            xmb.go_back()
            return true -- already played sfx in go_back
        else
            local old_cat = xmb.current_category_idx
            xmb.current_category_idx = math.max(1, xmb.current_category_idx - 1)
            if old_cat ~= xmb.current_category_idx then
                xmb.refresh_browser("left")
                moved = true
            end
        end
    elseif dir == "right" then
        if not xmb.in_submenu() then
            local old_cat = xmb.current_category_idx
            xmb.current_category_idx = math.min(#categories, xmb.current_category_idx + 1)
            if old_cat ~= xmb.current_category_idx then
                xmb.refresh_browser("right")
                moved = true
            end
        end
    elseif dir == "down" then
        local old_idx = xmb.current_item_idx
        xmb.current_item_idx = math.min(#browser.files, xmb.current_item_idx + 1)
        if old_idx ~= xmb.current_item_idx then
            xmb.item_marquee.offset = 0
            xmb.item_marquee.timer = 0
            xmb.item_marquee.phase = "pause_start"
            moved = true
        end
    elseif dir == "up" then
        local old_idx = xmb.current_item_idx
        xmb.current_item_idx = math.max(1, xmb.current_item_idx - 1)
        if old_idx ~= xmb.current_item_idx then
            xmb.item_marquee.offset = 0
            xmb.item_marquee.timer = 0
            xmb.item_marquee.phase = "pause_start"
            moved = true
        end
    end

    if moved and settings.keytone_enabled then
        assets.play_sfx("nav")
    end
    return moved
end

function xmb.update(dt)
    if xmb.context_menu.active then
        xmb.context_menu.alpha = math.min(1, xmb.context_menu.alpha + dt * 10)
    else
        xmb.context_menu.alpha = math.max(0, xmb.context_menu.alpha - dt * 10)
    end

    -- Smooth scroll (use exponential smoothing for consistent easing)
    xmb.category_scroll_x = utils.smooth(xmb.category_scroll_x, xmb.target_category_scroll_x, dt, 10)
    xmb.item_scroll_y = utils.smooth(xmb.item_scroll_y, xmb.target_item_scroll_y, dt, 10)

    -- Slide transition animation (snappier horizontal slide)
    xmb.list_slide_x = utils.smooth(xmb.list_slide_x, 0, dt, 14)
    xmb.list_slide_alpha = utils.smooth(xmb.list_slide_alpha, 1, dt, 10)
    if math.abs(xmb.list_slide_x) < 0.5 then xmb.list_slide_x = 0 end
    if xmb.list_slide_alpha > 0.99 then xmb.list_slide_alpha = 1 end

    local selected = browser.files[xmb.current_item_idx]
    settings_view.update(dt, selected and selected.setting_idx)

    -- Categories are centered at 1/4 of screen width
    xmb.target_category_scroll_x = -(xmb.current_category_idx - 1) * (theme.icon_size + theme.icon_spacing)

    -- Items are scrolled based on current selection
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 75

    local cat_base_x = love.graphics.getWidth() * 0.25
    xmb.item_marquee.max_width = love.graphics.getWidth() - cat_base_x - 40

    -- Update marquee
    if selected then
        ui.update_marquee(xmb.item_marquee, dt, assets.fonts.main:getWidth(selected.name))
    else
        xmb.item_marquee.offset = 0
        xmb.item_marquee.timer = 0
        xmb.item_marquee.phase = "pause_start"
    end

    -- Continuous scroll handling
    local up = love.keyboard.isDown("up")
    local down = love.keyboard.isDown("down")
    local left = love.keyboard.isDown("left")
    local right = love.keyboard.isDown("right")

    local current_key = nil
    if up then
        current_key = "up"
    elseif down then
        current_key = "down"
    elseif left then
        current_key = "left"
    elseif right then
        current_key = "right"
    end

    if current_key then
        if xmb.last_key == current_key then
            xmb.repeat_timer = xmb.repeat_timer - dt
            if xmb.repeat_timer <= 0 then
                xmb.navigate(current_key)
                xmb.repeat_timer = REPEAT_INTERVAL
            end
        else
            -- First frame of a hold (the keypressed already handled the first jump)
            xmb.last_key = current_key
            xmb.repeat_timer = REPEAT_DELAY
        end
    else
        xmb.last_key = nil
        xmb.repeat_timer = 0
    end
end

function xmb.keypressed(key, player, music, viewer)
    if settings_view.active then
        -- If folder picker is active, handle its navigation separately
        if settings_view.picker_active then
            if key == "up" then
                settings_view.picker_selected_idx = math.max(1, settings_view.picker_selected_idx - 1)
                settings_view.ensure_picker_visible()
                if settings.keytone_enabled then assets.play_sfx("nav") end
            elseif key == "down" then
                settings_view.picker_selected_idx = math.min(#settings_view.picker_items, settings_view.picker_selected_idx + 1)
                settings_view.ensure_picker_visible()
                if settings.keytone_enabled then assets.play_sfx("nav") end
            elseif key == "return" or key == "enter" or key == "a" or key == "space" then
                local pick = settings_view.picker_items[settings_view.picker_selected_idx]
                if pick then
                    -- If user selected a directory, either drill into it or pick it
                    -- If the chosen entry's path is a directory, open it (drill) by refreshing items
                    local chosen_path = pick.path
                    -- If user selected "..", just update current path and list
                    if chosen_path then
                        settings_view.picker_current_path = chosen_path
                        -- Refresh items for new folder
                        local parent = utils.get_dirname(settings_view.picker_current_path)
                        -- Rebuild items
                        settings_view.picker_items = {}
                        if parent and parent ~= "" then
                            table.insert(settings_view.picker_items, { name = "..", path = parent })
                        end
                        local dirs = (function()
                            local items = {}
                            local cmd = "find \"" .. settings_view.picker_current_path .. "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' -type d 2>/dev/null"
                            local h = io.popen(cmd)
                            if h then
                                local out = h:read("*a")
                                h:close()
                                for line in out:gmatch("[^\r\n]+") do
                                    table.insert(items, { name = utils.get_filename(line), path = line })
                                end
                            end
                            table.sort(items, function(a,b) return a.name:lower() < b.name:lower() end)
                            return items
                        end)()
                        for _, d in ipairs(dirs) do table.insert(settings_view.picker_items, d) end
                        settings_view.picker_selected_idx = 1
                        settings_view.ensure_picker_visible()
                        if settings.keytone_enabled then assets.play_sfx("nav") end
                    end
                end
            elseif key == "x" then
                -- Set the currently opened folder path as the value
                local sidx = settings_view.picker_setting_idx
                if sidx then
                    local opt = settings.get_option(settings.options[sidx].id)
                    if opt then
                        opt.value = settings_view.picker_current_path
                        settings.apply()
                        settings.save()
                        ui.show_toast("Media directory set", "folder", "bottom_right")
                        refresh_settings_items(false)
                    end
                end
                settings_view.close_folder_picker()
            elseif key == "backspace" or key == "b" or key == "escape" then
                -- Back to parent folder, or close if at root
                local parent = utils.get_dirname(settings_view.picker_current_path)
                if not parent or parent == "" then
                    settings_view.close_folder_picker()
                else
                    settings_view.picker_current_path = parent
                    -- Rebuild items
                    settings_view.picker_items = {}
                    local grand = utils.get_dirname(settings_view.picker_current_path)
                    if grand and grand ~= "" then
                        table.insert(settings_view.picker_items, { name = "..", path = grand })
                    end
                    local dirs = (function()
                        local items = {}
                        local cmd = "find \"" .. settings_view.picker_current_path .. "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' -type d 2>/dev/null"
                        local h = io.popen(cmd)
                        if h then
                            local out = h:read("*a")
                            h:close()
                            for line in out:gmatch("[^\r\n]+") do
                                table.insert(items, { name = utils.get_filename(line), path = line })
                            end
                        end
                        table.sort(items, function(a,b) return a.name:lower() < b.name:lower() end)
                        return items
                    end)()
                    for _, d in ipairs(dirs) do table.insert(settings_view.picker_items, d) end
                    settings_view.picker_selected_idx = 1
                    settings_view.ensure_picker_visible()
                    if settings.keytone_enabled then assets.play_sfx("nav") end
                end
            end
            return
        end

        if key == "up" or key == "down" then
            xmb.navigate(key)
        elseif key == "return" or key == "enter" or key == "a" or key == "space" then
            local selected = browser.files[xmb.current_item_idx]
            local opt = settings.options[selected.setting_idx]
            opt.value = settings_view.selected_option_idx
            settings.apply()
            settings.save()

            refresh_settings_items(true)
        elseif key == "backspace" or key == "b" or key == "escape" then
            settings_view.active = false
        end
        return
    end

    if xmb.context_menu.active then
        if key == "up" then
            xmb.context_menu.selected_idx = math.max(1, xmb.context_menu.selected_idx - 1)
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        elseif key == "down" then
            xmb.context_menu.selected_idx = math.min(#xmb.context_menu.items, xmb.context_menu.selected_idx + 1)
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        elseif key == "return" or key == "enter" or key == "a" or key == "space" then
            local selected_action = xmb.context_menu.items[xmb.context_menu.selected_idx]
            if selected_action then
                apply_context_action(selected_action.id)
            end
            close_context_menu()
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        elseif key == "backspace" or key == "b" or key == "escape" or key == "x" then
            close_context_menu()
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        end
        return
    end

    if key == "up" or key == "down" or key == "left" or key == "right" then
        xmb.navigate(key)
    elseif key == "return" or key == "enter" or key == "a" then
        local selected = browser.files[xmb.current_item_idx]
        if selected and selected.type ~= "info" and selected.type ~= "info_text" then
            if selected.type == "directory" then
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                browser.set_state(browser.base_dir, selected.path, current_filter())
                xmb.refresh_items()
                if browser.files[1] and browser.files[1].type == "shuffle_play" and #browser.files > 1 then
                    xmb.current_item_idx = 2
                elseif browser.files[1] and browser.files[1].type == "video_play_all" and #browser.files > 2 then
                    xmb.current_item_idx = 3
                else
                    xmb.current_item_idx = 1
                end
                prep_files()
                xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 75
                xmb.item_scroll_y = xmb.target_item_scroll_y
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
            elseif selected.type == "file" then
                local cat_id = categories[xmb.current_category_idx].id
                if cat_id == "video" then
                    local is_resume_view = (xmb.view_type == "video_resume")
                    player.play_video(selected.path, is_resume_view)
                elseif cat_id == "music" and music then
                    music.play(selected.path)
                elseif cat_id == "photo" and viewer then
                    viewer.open(selected.path, browser.files)
                elseif cat_id == "folder" then
                    -- Files tab: open recognized media types directly
                    if is_video_file(selected.path) then
                        player.play_video(selected.path)
                    elseif is_music_file(selected.path) and music then
                        music.play(selected.path)
                    elseif is_photo_file(selected.path) and viewer then
                        viewer.open(selected.path, browser.files)
                    end
                end
            elseif selected.type == "setting" then
                local opt = settings.options[selected.setting_idx]
                if opt.type == "choice" then
                    settings_view.active = true
                    settings_view.selected_option_idx = opt.value
                elseif opt.type == "path" then
                    -- Open compact folder picker starting from filesystem root or current value
                    local start_path = opt.value and opt.value ~= "" and opt.value or "/"
                    settings_view.open_folder_picker(start_path, selected.setting_idx)
                elseif opt.type == "action" then
                    if opt.id == "clear_history" then
                        history.clear()
                        video_manager.clear_history()
                        ui.show_toast("Watch history cleared", "history", "bottom_right")
                        -- Refresh browser items to show (maybe nothing changed visually but action happened)
                        refresh_settings_items(false)
                    elseif opt.id == "restore_default_wallpaper" then
                        local opt_custom_bg = settings.get_option("custom_bg")
                        local opt_custom_bg_path = settings.get_option("custom_bg_path")

                        if opt_custom_bg then
                            opt_custom_bg.value = 1
                        end
                        if opt_custom_bg_path then
                            opt_custom_bg_path.value = "assets/background/bg.jpg"
                        end

                        settings.apply()
                        settings.save()
                        ui.show_toast("Default wallpaper restored", "theme", "bottom_right")
                        refresh_settings_items(false)
                    elseif opt.id == "reindex_media" then
                        settings.request_reindex_on_restart()
                        love.event.quit("restart")
                    elseif opt.id == "test_toast_top" then
                        ui.show_toast("Dev: Top Center Toast", "info", "top_center")
                    elseif opt.id == "test_toast_bottom" then
                        ui.show_toast("Dev: Bottom Right Toast", "option", "bottom_right")
                    end
                end
                if settings.keytone_enabled then
                    assets.play_sfx("nav")
                end
            elseif selected.type == "settings_group" then
                if selected.group_id == "quit" then
                    love.event.quit()
                else
                    table.insert(xmb.nav_stack, xmb.current_item_idx)
                    settings.enter_group(selected.group_id)
                end
                refresh_settings_items(false)
                xmb.current_item_idx = 1
                xmb.item_marquee.offset = 0
                xmb.item_marquee.timer = 0
                xmb.item_marquee.phase = "pause_start"
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
                if settings.keytone_enabled then
                    assets.play_sfx("nav")
                end
            elseif selected.type == "view_trigger" then
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                xmb.view_type = selected.target_view
                xmb.refresh_items()
                xmb.current_item_idx = 1
                prep_files()
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
            elseif selected.type == "directory_trigger" then
                -- If the directory for this category is not configured, prompt user to set it
                if not selected.path or selected.path == "" then
                    ui.show_toast("Media directory not set. Please set directory from Settings.", "folder", "top_center")
                    if settings.keytone_enabled then
                        assets.play_sfx("nav")
                    end
                else
                    table.insert(xmb.nav_stack, xmb.current_item_idx)
                    local cat_id = categories[xmb.current_category_idx].id
                    if cat_id == "folder" then
                        -- For Files tab storage entries, set base_dir to the selected storage path
                        browser.set_state(selected.path, selected.path, current_filter())
                    else
                        browser.set_state(browser.base_dir, selected.path, current_filter())
                    end
                    xmb.view_type = "browser"
                    xmb.refresh_items()

                    if browser.files[1] and browser.files[1].type == "shuffle_play" and #browser.files > 1 then
                        xmb.current_item_idx = 2
                    elseif browser.files[1] and browser.files[1].type == "video_play_all" and #browser.files > 2 then
                        xmb.current_item_idx = 3
                    else
                        xmb.current_item_idx = 1
                    end
                    prep_files()
                    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 75
                    xmb.item_scroll_y = xmb.target_item_scroll_y
                    xmb.list_slide_x = 120
                    xmb.list_slide_alpha = 0
                end
            elseif selected.type == "album" or selected.type == "artist" then
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                xmb.view_type = (selected.type == "album") and "album_tracks" or "artist_tracks"
                xmb.view_data = selected.data
                xmb.refresh_items()
                if browser.files[1] and browser.files[1].type == "shuffle_play" and #browser.files > 1 then
                    xmb.current_item_idx = 2
                else
                    xmb.current_item_idx = 1
                end
                prep_files()
                xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 75
                xmb.item_scroll_y = xmb.target_item_scroll_y
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
            elseif selected.type == "shuffle_play" then
                local playlist = {}
                if selected.tracks then
                    -- From indexing data
                    for _, path in ipairs(selected.tracks) do
                        local info = indexing.data.music.files[path]
                        table.insert(playlist, { name = info.title or utils.get_filename(path), path = path })
                    end
                else
                    -- From current browser files
                    for _, item in ipairs(browser.files) do
                        if item.type == "file" and is_music_file(item.path) then
                            table.insert(playlist, { name = item.name, path = item.path })
                        end
                    end
                end

                if #playlist > 0 then
                    utils.shuffle(playlist)
                    music.play(playlist[1].path, playlist)
                end
            elseif selected.type == "video_play_all" then
                local playlist = {}
                for _, item in ipairs(browser.files) do
                    if item.type == "file" then
                        table.insert(playlist, item.path)
                    end
                end
                if #playlist > 0 then
                    player.play_video(playlist)
                end
            elseif selected.type == "video_shuffle_play" then
                local playlist = {}
                for _, item in ipairs(browser.files) do
                    if item.type == "file" then
                        table.insert(playlist, item.path)
                    end
                end
                if #playlist > 0 then
                    utils.shuffle(playlist)
                    player.play_video(playlist)
                end
            end
        end
    elseif key == "backspace" or key == "b" then
        if xmb.in_submenu() then
            xmb.go_back()
        end
    elseif key == "x" then
        local selected = browser.files[xmb.current_item_idx]
        local cat_id = categories[xmb.current_category_idx].id
        if selected and selected.type == "file" and (cat_id == "photo" or cat_id == "folder") and is_photo_file(selected.path) then
            open_photo_context_menu(selected.path)
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        elseif selected and selected.type == "file" and (cat_id == "video" or cat_id == "folder") then
            open_video_context_menu(selected.path)
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        end
    end
end

return xmb
