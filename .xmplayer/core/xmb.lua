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
local keyboard = require("onscreen_keyboard")
local viewport = require("viewport")
local xmb_state = require("xmb_state")
local xmb_actions = require("xmb_actions")
local system = require("system")
local runtime_state = require("runtime_state")
local m3u = require("m3u")

local xmb = xmb_state.new()
xmb.item_marquee = ui.new_marquee(0, 50, 1.5, 1.0)
xmb.desc_marquee = ui.new_marquee(0, 50, 1.5, 1.0)

local REPEAT_DELAY = 0.4
local REPEAT_INTERVAL = 0.08

xmb.cached_dir_counts = {}
xmb.pending_dir_counts = {}

function xmb.ensure_dir_count_worker()
    if not xmb.dir_count_in_chan then
        xmb.dir_count_in_chan = love.thread.getChannel("dir_count_in")
        xmb.dir_count_out_chan = love.thread.getChannel("dir_count_out")
        xmb.dir_count_thread = utils.new_worker_thread("dir_count_worker.lua")
        if xmb.dir_count_thread then
            xmb.dir_count_thread:start("dir_count_in", "dir_count_out")
        end
    end
end

-- Helper to precompute media counts for directories recursively (threaded, non-blocking)
local function precompute_dir_counts(current_dir, media_type)
    if not current_dir or current_dir == "" then return {} end
    local norm_current = utils.normalize_path(current_dir)
    local key = media_type .. ":" .. norm_current

    if xmb.cached_dir_counts and xmb.cached_dir_counts[key] then
        return xmb.cached_dir_counts[key]
    end

    xmb.ensure_dir_count_worker()

    if not xmb.pending_dir_counts then xmb.pending_dir_counts = {} end
    if not xmb.cached_dir_counts then xmb.cached_dir_counts = {} end

    if not xmb.pending_dir_counts[key] then
        xmb.pending_dir_counts[key] = true
        local files_list = nil
        if media_type == "music" and indexing and indexing.data and indexing.data.music and next(indexing.data.music.files) then
            files_list = {}
            for path in pairs(indexing.data.music.files) do
                table.insert(files_list, utils.normalize_path(path))
            end
        end
        xmb.dir_count_in_chan:push({
            type = "compute_counts",
            current_dir = current_dir,
            media_type = media_type,
            exts = indexing.compatible_extensions[media_type],
            files_list = files_list,
            key = key
        })
    end

    return {}
end

-- Media type helpers (fast O(1) set lookups via utils)
local is_music_file = utils.is_music_file
local is_photo_file = utils.is_photo_file
local is_video_file = utils.is_video_file

local function prep_files()
    local screen_w = viewport.get()
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
                -- Use track icon when listing album/artist tracks, otherwise use file music icon
                if xmb.view_type == "album_tracks" or xmb.view_type == "artist_tracks" then
                    item.icon = "track"
                else
                    item.icon = "file_music"
                end
            else
                item.icon = "file"
            end
        end
    end
end

local PLAYLISTS_DIR = "playlists"
local WATCHLISTS_DIR = "watchlists"

local function shell_quote(path)
    return m3u.shell_quote(path)
end

local function sanitize_playlist_name(name)
    return m3u.sanitize_name(name)
end

local function ensure_watchlists_dir()
    m3u.ensure_dir(WATCHLISTS_DIR)
end

local function watchlist_path_for_name(name)
    return m3u.path_for_name(WATCHLISTS_DIR, name)
end

local function list_watchlists()
    return m3u.list(WATCHLISTS_DIR, "watchlist", "playlist_video")
end

local function create_watchlist(name)
    return m3u.create(WATCHLISTS_DIR, name)
end

local function rename_watchlist(old_path, new_name)
    return m3u.rename(WATCHLISTS_DIR, old_path, new_name)
end

local function remove_watchlist(path)
    return m3u.remove(path)
end

local function parse_m3u_watchlist(watchlist_path)
    return m3u.parse(watchlist_path, is_video_file)
end

local function add_video_to_watchlist(watchlist_path, video_path)
    return m3u.add_entry(watchlist_path, video_path)
end

local function remove_video_from_watchlist_file(watchlist_path, video_idx)
    return m3u.remove_entry(watchlist_path, video_idx, is_video_file)
end

local function ensure_playlists_dir()
    m3u.ensure_dir(PLAYLISTS_DIR)
end

local function playlist_path_for_name(name)
    return m3u.path_for_name(PLAYLISTS_DIR, name)
end

local function list_playlists()
    return m3u.list(PLAYLISTS_DIR, "playlist", "playlist_music")
end

local function create_playlist(name)
    return m3u.create(PLAYLISTS_DIR, name)
end

local function rename_playlist(old_path, new_name)
    return m3u.rename(PLAYLISTS_DIR, old_path, new_name)
end

local function remove_playlist(path)
    return m3u.remove(path)
end

local function parse_m3u_playlist(playlist_path)
    return m3u.parse(playlist_path, is_music_file)
end

local function current_filter()
    local cat = categories[xmb.current_category_idx]
    return cat and cat.filter or nil
end

local function first_media_item_index()
    for i, item in ipairs(browser.files) do
        if item.type == "directory" or item.type == "file" then
            return i
        end
    end
    return 1
end

local function first_playlist_track_index()
    for i, item in ipairs(browser.files) do
        if item.type == "file" then
            return i
        end
    end
    return 1
end

local function reset_marquee()
    xmb.item_marquee.offset = 0
    xmb.item_marquee.timer = 0
    xmb.item_marquee.phase = "pause_start"
    xmb.desc_marquee.offset = 0
    xmb.desc_marquee.timer = 0
    xmb.desc_marquee.phase = "pause_start"
end

local function clear_context_menu()
    xmb.context_menu.active = false
    xmb.context_menu.items = {}
    xmb.context_menu.selected_idx = 1
    xmb.context_menu.title = ""
    xmb.context_menu.target_path = nil
end

local function play_nav_sfx()
    xmb_actions.play_nav_sfx(settings, assets)
end

local function reset_focus_position()
    xmb.current_item_idx = math.max(1, math.min(xmb.current_item_idx, math.max(1, #browser.files)))
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 65
    xmb.item_scroll_y = xmb.target_item_scroll_y
end

local function set_item_focus(index, options)
    local count = math.max(1, #browser.files)
    local target = math.max(1, math.min(index or 1, count))
    xmb.current_item_idx = target

    if not options or options.reset_marquee ~= false then
        reset_marquee()
    end

    xmb.target_item_scroll_y = -(target - 1) * 65
    xmb.item_scroll_y = xmb.target_item_scroll_y

    if options then
        if options.slide_x ~= nil then
            xmb.list_slide_x = options.slide_x
        end
        if options.slide_alpha ~= nil then
            xmb.list_slide_alpha = options.slide_alpha
        end
    end
end

local function enter_list_view(index, slide_x)
    table.insert(xmb.nav_stack, xmb.current_item_idx)
    xmb.current_item_idx = index or 1
    prep_files()
    set_item_focus(xmb.current_item_idx, {
        slide_x = slide_x or 120,
        slide_alpha = 0,
    })
end

local function refresh_settings_items(keep_idx)
    local old_idx = keep_idx and xmb.current_item_idx or nil
    browser.set_files(settings.get_browser_items())
    prep_files()
    if old_idx then
        xmb.current_item_idx = old_idx
    end
end

local function refresh_playlist_items(target_path, fallback_idx)
    local idx = fallback_idx or 1
    xmb.refresh_items()

    if target_path then
        for i, item in ipairs(browser.files) do
            if item.path == target_path then
                idx = i
                break
            end
        end
    end

    xmb.current_item_idx = math.min(idx, math.max(1, #browser.files))
    prep_files()
    reset_focus_position()
end


local function close_context_menu()
    clear_context_menu()
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
        },
        { id = "add_to_watchlist", label = "Add to Watchlist..." },
    }, path)
end

local function open_watchlist_context_menu(path)
    open_context_menu("Watchlist Options", {
        { id = "rename_watchlist", label = "Rename Watchlist" },
        { id = "remove_watchlist", label = "Remove Watchlist" },
    }, path)
end

local function open_watchlist_video_context_menu(path, video_idx)
    local watched = video_manager.is_watched(path)
    open_context_menu("Video Options", {
        {
            id = "toggle_watched",
            label = watched and "Unmark as Watched" or "Mark as Watched"
        },
        { id = "add_to_watchlist",      label = "Add to Watchlist..." },
        { id = "remove_from_watchlist", label = "Remove from list" },
    }, path)
    xmb.context_menu.target_index = video_idx
end

local function open_playlist_context_menu(path)
    open_context_menu("Playlist Options", {
        { id = "rename_playlist", label = "Rename Playlist" },
        { id = "remove_playlist", label = "Remove Playlist" },
    }, path)
end

local function open_playlist_track_context_menu(path, track_idx)
    open_context_menu("Track Options", {
        { id = "add_to_playlist",      label = "Add to Playlist..." },
        { id = "remove_from_playlist", label = "Remove from list" },
    }, path)
    xmb.context_menu.target_index = track_idx
end

local function remove_track_from_playlist_file(playlist_path, track_idx)
    return m3u.remove_entry(playlist_path, track_idx, is_music_file)
end

local function open_music_context_menu(path)
    open_context_menu("Track Options", {
        { id = "add_to_playlist", label = "Add to Playlist..." },
    }, path)
end

local function open_playlist_sidebar(track_path)
    xmb.playlist_sidebar_items = list_playlists()
    if not xmb.playlist_sidebar_items or #xmb.playlist_sidebar_items == 0 then
        ui.show_toast("No playlists created", "playlist_music", "top_center")
        return false
    end
    xmb.playlist_sidebar_selected_idx = 1
    xmb.playlist_sidebar_scroll_y = 0
    xmb.playlist_sidebar_target_scroll_y = 0
    xmb.playlist_sidebar_track_to_add = track_path
    xmb.playlist_sidebar_title = "Add to Playlist"
    xmb.playlist_sidebar_active = true
    return true
end

local function open_video_watchlist_sidebar(video_path)
    xmb.playlist_sidebar_items = list_watchlists()
    if not xmb.playlist_sidebar_items or #xmb.playlist_sidebar_items == 0 then
        ui.show_toast("No watchlists created", "playlist_video", "top_center")
        return false
    end
    xmb.playlist_sidebar_selected_idx = 1
    xmb.playlist_sidebar_scroll_y = 0
    xmb.playlist_sidebar_target_scroll_y = 0
    xmb.playlist_sidebar_track_to_add = video_path
    xmb.playlist_sidebar_title = "Add to Watchlist"
    xmb.playlist_sidebar_active = true
    return true
end

local function close_playlist_sidebar()
    xmb.playlist_sidebar_active = false
    xmb.playlist_sidebar_items = {}
    xmb.playlist_sidebar_selected_idx = 1
    xmb.playlist_sidebar_track_to_add = nil
    xmb.playlist_sidebar_target_scroll_y = 0
end

local function ensure_playlist_sidebar_visible()
    if not xmb.playlist_sidebar_items or #xmb.playlist_sidebar_items == 0 then
        xmb.playlist_sidebar_target_scroll_y = 0
        return
    end
    local screen_w, screen_h = viewport.get()
    local panel_h = math.min(screen_h * 0.6, 420)
    local list_h = panel_h - 140
    local item_h = 36
    local sel = xmb.playlist_sidebar_selected_idx or 1
    local selected_y = (sel - 1) * item_h
    local desired_top = selected_y - (list_h / 2 - item_h / 2)
    local max_scroll = 0
    local min_scroll = math.min(0, -(#xmb.playlist_sidebar_items * item_h) + list_h)
    local target = -desired_top
    if target > max_scroll then target = max_scroll end
    if target < min_scroll then target = min_scroll end
    xmb.playlist_sidebar_target_scroll_y = target
end

local function add_track_to_playlist(playlist_path, track_path)
    return m3u.add_entry(playlist_path, track_path)
end

local function build_playlist_from_items(items)
    local playlist = {}
    for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.name and item.path then
            table.insert(playlist, { name = item.name, path = item.path })
        elseif type(item) == "string" then
            local info = indexing.data.music.files[item]
            if info then
                table.insert(playlist, { name = info.title or utils.get_filename(item), path = item })
            else
                table.insert(playlist, { name = utils.get_filename(item), path = item })
            end
        end
    end
    return playlist
end

local function build_media_playlist_from_browser()
    local playlist = {}
    for _, item in ipairs(browser.files) do
        if item.type == "file" then
            table.insert(playlist, item.path)
        end
    end
    return playlist
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
            opt_enabled.value = 3 -- 3 = Wallpaper mode
        end
        settings.apply()
        settings.save()

        --ui.show_toast("Wallpaper set", "photo", "bottom_right")
    elseif action_id == "toggle_watched" and xmb.context_menu.target_path then
        local path = xmb.context_menu.target_path
        local watched = video_manager.toggle_watched(path)
        --ui.show_toast(watched and "Marked as watched" or "Marked as unwatched", "video", "bottom_right")
    elseif action_id == "rename_playlist" and xmb.context_menu.target_path then
        local old_path = xmb.context_menu.target_path
        local old_name = utils.get_filename(old_path) or old_path
        old_name = old_name:gsub("%.m3u8?$", "")

        keyboard.open({
            title = "Rename Playlist",
            value = old_name,
            max_length = 50,
            on_submit = function(name)
                local new_path, err, replaced_invalid = rename_playlist(old_path, name)
                if not new_path then
                    if err == "invalid_name" then
                        ui.show_toast("Enter a valid playlist name", "playlist_add", "top_center")
                    elseif err == "exists" then
                        ui.show_toast("Playlist already exists", "playlist_music", "top_center")
                    else
                        ui.show_toast("Could not rename playlist", "info", "top_center")
                    end
                    return
                end

                refresh_playlist_items(new_path, xmb.current_item_idx)
                if replaced_invalid then
                    ui.show_toast("Invalid filename characters", "info", "top_center")
                end
                ui.show_toast("Playlist renamed", "playlist_music", "bottom_right")
            end,
        })
    elseif action_id == "remove_playlist" and xmb.context_menu.target_path then
        local path = xmb.context_menu.target_path
        local ok, err = remove_playlist(path)
        if not ok then
            ui.show_toast("Could not remove playlist", "info", "top_center")
            return
        end

        refresh_playlist_items(nil, xmb.current_item_idx)
        ui.show_toast("Playlist removed", "playlist_music", "bottom_right")
    elseif action_id == "add_to_playlist" and xmb.context_menu.target_path then
        open_playlist_sidebar(xmb.context_menu.target_path)
    elseif action_id == "remove_from_playlist" and xmb.context_menu.target_path then
        local playlist_path = xmb.view_data and xmb.view_data.path
        local track_idx = xmb.context_menu.target_index
        if playlist_path and track_idx then
            local ok, err = remove_track_from_playlist_file(playlist_path, track_idx)
            if not ok then
                ui.show_toast("Could not remove track", "info", "top_center")
                return
            end

            -- Update in-memory tracks
            table.remove(xmb.view_data.tracks, track_idx)

            -- Refresh vertical UI items list
            xmb.refresh_items()
            prep_files()

            -- Adjust current item focus/selection index if needed
            if xmb.current_item_idx > #browser.files then
                xmb.current_item_idx = math.max(1, #browser.files)
            end
            reset_focus_position()

            ui.show_toast("Track removed from list", "playlist_music", "bottom_right")
        end
    elseif action_id == "add_to_watchlist" and xmb.context_menu.target_path then
        open_video_watchlist_sidebar(xmb.context_menu.target_path)
    elseif action_id == "remove_from_watchlist" and xmb.context_menu.target_path then
        local watchlist_path = xmb.view_data and xmb.view_data.path
        local video_idx = xmb.context_menu.target_index
        if watchlist_path and video_idx then
            local ok, err = remove_video_from_watchlist_file(watchlist_path, video_idx)
            if not ok then
                ui.show_toast("Could not remove video", "info", "top_center")
                return
            end

            -- Update in-memory tracks
            table.remove(xmb.view_data.tracks, video_idx)

            -- Refresh vertical UI items list
            xmb.refresh_items()
            prep_files()

            -- Adjust current item focus/selection index if needed
            if xmb.current_item_idx > #browser.files then
                xmb.current_item_idx = math.max(1, #browser.files)
            end
            reset_focus_position()

            ui.show_toast("Video removed from watchlist", "playlist_video", "bottom_right")
        end
    elseif action_id == "rename_watchlist" and xmb.context_menu.target_path then
        local old_path = xmb.context_menu.target_path
        local old_name = utils.get_filename(old_path) or old_path
        old_name = old_name:gsub("%.m3u8?$", "")

        keyboard.open({
            title = "Rename Watchlist",
            value = old_name,
            max_length = 50,
            on_submit = function(name)
                local new_path, err, replaced_invalid = rename_watchlist(old_path, name)
                if not new_path then
                    if err == "invalid_name" then
                        ui.show_toast("Enter a valid watchlist name", "playlist_add", "top_center")
                    elseif err == "exists" then
                        ui.show_toast("Watchlist already exists", "playlist_video", "top_center")
                    else
                        ui.show_toast("Could not rename watchlist", "info", "top_center")
                    end
                    return
                end

                refresh_playlist_items(new_path, xmb.current_item_idx)
                if replaced_invalid then
                    ui.show_toast("Invalid filename characters", "info", "top_center")
                end
                ui.show_toast("Watchlist renamed", "playlist_video", "bottom_right")
            end,
        })
    elseif action_id == "remove_watchlist" and xmb.context_menu.target_path then
        local path = xmb.context_menu.target_path
        local ok, err = remove_watchlist(path)
        if not ok then
            ui.show_toast("Could not remove watchlist", "info", "top_center")
            return
        end

        refresh_playlist_items(nil, xmb.current_item_idx)
        ui.show_toast("Watchlist removed", "playlist_video", "bottom_right")
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
            elseif xmb.view_type == "playlist_tracks" then
                xmb.view_type = "music_playlists"
                xmb.refresh_items()
            elseif xmb.view_type == "watchlist_videos" then
                xmb.view_type = "video_watchlists"
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

    set_item_focus(xmb.current_item_idx, {
        slide_x = -120,
        slide_alpha = 0,
    })

    play_nav_sfx()
end

local function build_music_view_items(cat)
    if xmb.view_type == "category_root" then
        table.insert(browser.files,
            { name = "Albums", type = "view_trigger", target_view = "music_albums", icon = "albums" })
        table.insert(browser.files,
            { name = "Artists", type = "view_trigger", target_view = "music_artists", icon = "mic" })
        table.insert(browser.files,
            { name = "Playlists", type = "view_trigger", target_view = "music_playlists", icon = "playlist_music" })

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
        for _, album in pairs(indexing.data.music.albums) do
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
    elseif xmb.view_type == "music_playlists" then
        table.insert(browser.files, {
            name = "Create Playlist",
            type = "playlist_create",
            icon = "playlist_add",
        })

        local playlists = list_playlists()
        for _, item in ipairs(playlists) do
            local tracks = parse_m3u_playlist(item.path)
            local track_count = #tracks
            item.description = (track_count == 0) and "Empty" or (track_count .. " tracks")
            table.insert(browser.files, item)
        end
    elseif xmb.view_type == "album_tracks" then
        table.insert(browser.files,
            { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle", tracks = xmb.view_data.tracks })
        for _, path in ipairs(xmb.view_data.tracks) do
            local info = indexing.data.music.files[path]
            table.insert(browser.files, { name = (info and info.title) or "Unknown", path = path, type = "file" })
        end
    elseif xmb.view_type == "artist_tracks" then
        table.insert(browser.files,
            { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle", tracks = xmb.view_data.tracks })
        for _, path in ipairs(xmb.view_data.tracks) do
            local info = indexing.data.music.files[path]
            local title = (info and info.title) or utils.get_track_name(path) or "Unknown"
            local album = (info and info.album) or "Unknown Album"
            table.insert(browser.files, {
                name = title,
                path = path,
                type = "file",
                description = album
            })
        end
    elseif xmb.view_type == "playlist_tracks" then
        if xmb.view_data and xmb.view_data.tracks and #xmb.view_data.tracks > 0 then
            table.insert(browser.files,
                { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle", tracks = xmb.view_data.tracks })
            for i = 1, #xmb.view_data.tracks do
                local track = xmb.view_data.tracks[i]
                local info = indexing.data.music.files[track.path]
                local track_name = (info and info.title) or track.name or "Unknown"
                table.insert(browser.files, { name = track_name, path = track.path, type = "file" })
            end
        else
            table.insert(browser.files,
                { name = "Empty Playlist", path = "", type = "info", icon = "playlist_music" })
        end
    elseif xmb.view_type == "browser" then
        browser.scan()
        local counts = precompute_dir_counts(browser.current_dir, "music")
        local has_music = false
        for _, item in ipairs(browser.files) do
            if item.type == "file" and is_music_file(item.path) then
                has_music = true
            elseif item.type == "directory" then
                local count = counts[utils.normalize_path(item.path)] or counts[item.path] or 0
                item.description = count .. " tracks"
            end
        end
        if has_music then
            table.insert(browser.files, 1, { name = "Shuffle Play", type = "shuffle_play", icon = "shuffle" })
        end
    end
end

local function build_video_view_items(cat)
    if xmb.view_type == "category_root" then
        table.insert(browser.files,
            {
                name = "Resume Watching",
                type = "view_trigger",
                target_view = "video_resume",
                icon = "history",
            })
        table.insert(browser.files,
            {
                name = "Watchlists",
                type = "view_trigger",
                target_view = "video_watchlists",
                icon = "playlist_video",
            })
        local video_count = (indexing and indexing.ensure_video_count) and indexing.ensure_video_count(cat.path) or 0
        table.insert(browser.files,
            {
                name = "Video Files",
                type = "directory_trigger",
                path = cat.path,
                icon = "folder_video",
                description = video_count .. " videos"
            })

        browser.set_state(cat.path, cat.path, cat.filter)
    elseif xmb.view_type == "video_resume" then
        local resume_list = video_manager.get_resume_list()
        for _, item in ipairs(resume_list) do
            table.insert(browser.files, { name = item.name, path = item.path, type = "file" })
        end
    elseif xmb.view_type == "video_watchlists" then
        table.insert(browser.files, {
            name = "Create Watchlist",
            type = "watchlist_create",
            icon = "playlist_add",
        })

        local watchlists = list_watchlists()
        for _, item in ipairs(watchlists) do
            local tracks = parse_m3u_watchlist(item.path)
            local track_count = #tracks
            item.description = (track_count == 0) and "Empty" or (track_count .. " videos")
            table.insert(browser.files, item)
        end
    elseif xmb.view_type == "watchlist_videos" then
        if xmb.view_data and xmb.view_data.tracks and #xmb.view_data.tracks > 0 then
            table.insert(browser.files,
                {
                    name = "Shuffle Play",
                    type = "video_shuffle_play",
                    icon = "shuffle",
                    tracks = xmb.view_data.tracks
                })
            table.insert(browser.files,
                { name = "Play All", type = "video_play_all", icon = "play", tracks = xmb.view_data.tracks })
            for i = 1, #xmb.view_data.tracks do
                local track = xmb.view_data.tracks[i]
                local track_name = utils.get_track_name(track.path)
                table.insert(browser.files, { name = track_name, path = track.path, type = "file" })
            end
        else
            table.insert(browser.files,
                { name = "Empty Watchlist", path = "", type = "info", icon = "playlist_video" })
        end
    elseif xmb.view_type == "browser" then
        browser.scan()
        local counts = precompute_dir_counts(browser.current_dir, "video")
        local has_videos = false
        for _, item in ipairs(browser.files) do
            if item.type == "file" then
                has_videos = true
            elseif item.type == "directory" then
                local count = counts[utils.normalize_path(item.path)] or counts[item.path] or 0
                item.description = count .. " videos"
            end
        end
        if has_videos then
            table.insert(browser.files, 1, { name = "Shuffle Play", type = "video_shuffle_play", icon = "shuffle" })
            table.insert(browser.files, 2, { name = "Play All", type = "video_play_all", icon = "play" })
        end
    end
end

local function build_photo_view_items(cat)
    if xmb.view_type == "category_root" then
        local photo_count = (indexing and indexing.ensure_photo_count) and indexing.ensure_photo_count(cat.path) or 0
        table.insert(browser.files,
            {
                name = "Photo Files",
                type = "directory_trigger",
                path = cat.path,
                icon = "folder_image",
                description = photo_count .. " photos"
            })
        table.insert(browser.files,
            {
                name = "Screenshots",
                type = "directory_trigger",
                path = system.get_screenshot_dir(),
                icon = "screenshot",
                is_screenshots = true
            })
        browser.set_state(cat.path, cat.path, cat.filter)
    elseif xmb.view_type == "browser" then
        browser.scan()
        local counts = precompute_dir_counts(browser.current_dir, "photo")
        local has_photos = false
        for _, item in ipairs(browser.files) do
            if item.type == "file" and is_photo_file(item.path) then
                has_photos = true
            elseif item.type == "directory" then
                local count = counts[utils.normalize_path(item.path)] or counts[item.path] or 0
                item.description = count .. " photos"
            end
        end
        if has_photos then
            table.insert(browser.files, 1, { name = "Slideshow", type = "photo_slideshow", icon = "slideshow" })
        end
    end
end

local function build_folder_view_items(cat, dir_has_entries)
    if xmb.view_type == "category_root" then
        local paths = {}
        if system.get_cfw_name() == "muOS" then
            table.insert(paths, {
                name = "Primary Storage",
                type = "directory_trigger",
                path = "/mnt/mmc",
                icon = "muos",
                description = "/mnt/mmc"
            })
            if dir_has_entries("/mnt/sdcard") then
                table.insert(paths, {
                    name = "Secondary Storage",
                    type = "directory_trigger",
                    path = "/mnt/sdcard",
                    icon = "sdcard",
                    description = "/mnt/sdcard"
                })
            end
            if dir_has_entries("/mnt/usb") then
                table.insert(paths, {
                    name = "External Storage",
                    type = "directory_trigger",
                    path = "/mnt/usb",
                    icon = "drive",
                    description = "/mnt/usb"
                })
            end
        else
            if dir_has_entries("/userdata") then
                table.insert(paths, {
                    name = "Userdata Storage",
                    type = "directory_trigger",
                    path = "/userdata",
                    icon = "drive",
                    description = "/userdata"
                })
            end
            if dir_has_entries("/storage") then
                table.insert(paths, {
                    name = "System Storage",
                    type = "directory_trigger",
                    path = "/storage",
                    icon = "drive",
                    description = "/storage"
                })
            end
            if dir_has_entries("/roms") then
                table.insert(paths, {
                    name = "Roms Storage",
                    type = "directory_trigger",
                    path = "/roms",
                    icon = "drive",
                    description = "/roms"
                })
            end
            if dir_has_entries("/mnt/sdcard") then
                table.insert(paths, {
                    name = "SD Card Storage",
                    type = "directory_trigger",
                    path = "/mnt/sdcard",
                    icon = "sdcard",
                    description = "/mnt/sdcard"
                })
            end
        end

        if #paths == 0 then
            table.insert(paths, {
                name = "Root Directory",
                type = "directory_trigger",
                path = "/",
                icon = "drive",
                description = "/"
            })
        end

        for _, p in ipairs(paths) do
            table.insert(browser.files, p)
        end
    elseif xmb.view_type == "browser" then
        browser.scan()
    end
end

function xmb.refresh_items()
    xmb.clear_thumb_cache()
    local cat = categories[xmb.current_category_idx]
    browser.set_files({})

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
        build_music_view_items(cat)
    elseif cat.id == "video" then
        build_video_view_items(cat)
    elseif cat.id == "photo" then
        build_photo_view_items(cat)
    elseif cat.id == "settings" then
        refresh_settings_items(false)
    elseif cat.id == "folder" then
        build_folder_view_items(cat, dir_has_entries)
    elseif cat.path then
        local base_dir = cat.path or system.get_default_base_dir()
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
        local base_dir = cat.path or system.get_default_base_dir()
        browser.set_state(base_dir, base_dir, cat.filter)
        xmb.refresh_items()
    end

    if cat.id == "settings" then
        xmb.current_item_idx = 2 -- General Settings, not quit
    else
        xmb.current_item_idx = 1 -- First item as usual otherwise
    end

    xmb.nav_stack = {} -- Clear history on category switch
    -- Slide direction based on navigation
    local slide = (slide_dir == "left") and -120 or 120
    set_item_focus(xmb.current_item_idx, {
        slide_x = slide,
        slide_alpha = 0,
    })

    prep_files()
end

-- Shared navigation logic for single press and continuous scroll
function xmb.navigate(dir, no_wrap)
    local moved = false
    if settings_view.active then
        if settings_view.picker_active then
            local old_idx = settings_view.picker_selected_idx
            if dir == "up" then
                settings_view.picker_selected_idx = math.max(1, settings_view.picker_selected_idx - 1)
                settings_view.ensure_picker_visible()
            elseif dir == "down" then
                settings_view.picker_selected_idx = math.min(#settings_view.picker_items,
                    settings_view.picker_selected_idx + 1)
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
        local is_settings = (categories[xmb.current_category_idx].id == "settings")
        if is_settings or no_wrap then
            xmb.current_item_idx = math.min(#browser.files, xmb.current_item_idx + 1)
        else
            xmb.current_item_idx = xmb.current_item_idx + 1
            if xmb.current_item_idx > #browser.files then
                xmb.current_item_idx = 1
            end
        end
        if old_idx ~= xmb.current_item_idx then
            reset_marquee()
            moved = true
        end
    elseif dir == "up" then
        local old_idx = xmb.current_item_idx
        local is_settings = (categories[xmb.current_category_idx].id == "settings")
        if is_settings or no_wrap then
            xmb.current_item_idx = math.max(1, xmb.current_item_idx - 1)
        else
            xmb.current_item_idx = xmb.current_item_idx - 1
            if xmb.current_item_idx < 1 then
                xmb.current_item_idx = #browser.files
            end
        end
        if old_idx ~= xmb.current_item_idx then
            reset_marquee()
            moved = true
        end
    end

    if moved and settings.keytone_enabled then
        assets.play_sfx("nav")
    end
    return moved
end

function xmb.update(dt)
    keyboard.update(dt)

    if xmb.context_menu.active then
        xmb.context_menu.alpha = math.min(1, xmb.context_menu.alpha + dt * 10)
    else
        xmb.context_menu.alpha = math.max(0, xmb.context_menu.alpha - dt * 10)
    end

    if xmb.playlist_sidebar_active then
        xmb.playlist_sidebar_alpha = math.min(1, xmb.playlist_sidebar_alpha + dt * 12)
    else
        xmb.playlist_sidebar_alpha = math.max(0, xmb.playlist_sidebar_alpha - dt * 12)
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

    xmb.playlist_sidebar_scroll_y = utils.lerp(xmb.playlist_sidebar_scroll_y, xmb.playlist_sidebar_target_scroll_y or 0,
        dt * 12)

    -- Categories are centered at 1/4 of screen width
    xmb.target_category_scroll_x = -(xmb.current_category_idx - 1) * (theme.icon_size + theme.icon_spacing)

    -- Items are scrolled based on current selection
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 65

    local screen_w = viewport.get()
    local cat_base_x = screen_w * 0.25
    xmb.item_marquee.max_width = screen_w - cat_base_x - 40
    xmb.desc_marquee.max_width = screen_w - cat_base_x - 40

    -- Update marquee
    if selected then
        ui.update_marquee(xmb.item_marquee, dt, ui.measure_text_width(assets.fonts.main, selected.name))
        if selected.description then
            ui.update_marquee(xmb.desc_marquee, dt, ui.measure_text_width(assets.fonts.xs, selected.description))
        else
            xmb.desc_marquee.offset = 0
            xmb.desc_marquee.timer = 0
            xmb.desc_marquee.phase = "pause_start"
        end
    else
        reset_marquee()
    end

    if keyboard.is_active() or xmb.playlist_sidebar_active then
        xmb.last_key = nil
        xmb.repeat_timer = 0
        return
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
                local moved = xmb.navigate(current_key, true)
                if moved and (current_key == "up" or current_key == "down") then
                    xmb.scroll_held_count = xmb.scroll_held_count + 1
                end
                -- Acceleration: after 20 items scrolled, speed up proportionally
                local interval = REPEAT_INTERVAL
                if xmb.scroll_held_count > 20 then
                    local extra = xmb.scroll_held_count - 20
                    -- Ramp from REPEAT_INTERVAL down to a minimum of REPEAT_INTERVAL * 0.25
                    local t = math.min(1, extra / 40)
                    interval = REPEAT_INTERVAL * (1 - t * 0.5)
                end
                xmb.repeat_timer = interval
            end
        else
            -- First frame of a hold (the keypressed already handled the first jump)
            xmb.last_key = current_key
            xmb.repeat_timer = REPEAT_DELAY
            xmb.scroll_held_count = 0
        end
    else
        xmb.last_key = nil
        xmb.repeat_timer = 0
        xmb.scroll_held_count = 0
    end

    -- Process background thumbnail results for lists (max 2 texture uploads per frame to eliminate main-thread stutter)
    if xmb.thumb_out_chan then
        local processed = 0
        while processed < 2 do
            local res = xmb.thumb_out_chan:pop()
            if not res then break end
            if res.type == "thumb_result" and res.key then
                processed = processed + 1
                if res.img_data then
                    local ok, img = pcall(love.graphics.newImage, res.img_data)
                    res.img_data:release()
                    if ok and img then
                        local cache_count = 0
                        for _ in pairs(xmb.thumbs) do cache_count = cache_count + 1 end
                        if cache_count >= 60 then
                            local removed = 0
                            for k, old_img in pairs(xmb.thumbs) do
                                if old_img and old_img.release then
                                    pcall(function() old_img:release() end)
                                end
                                xmb.thumbs[k] = nil
                                xmb.thumb_status[k] = nil
                                xmb.orientations[k] = nil
                                removed = removed + 1
                                if removed >= 20 then break end
                            end
                            collectgarbage("collect")
                        end

                        xmb.thumbs[res.key] = img
                        xmb.thumb_status[res.key] = "loaded"
                    else
                        xmb.thumb_status[res.key] = "failed"
                    end
                elseif res.bytes then
                    local img = utils.load_image_bytes(res.bytes)
                    if img then
                        xmb.thumbs[res.key] = img
                        xmb.thumb_status[res.key] = "loaded"
                    else
                        xmb.thumb_status[res.key] = "failed"
                    end
                else
                    xmb.thumb_status[res.key] = "failed"
                end
                if res.orientation then
                    xmb.orientations[res.key] = res.orientation
                    if res.photo_path then
                        xmb.orientations[res.photo_path] = res.orientation
                    end
                end
            end
        end
    end

    if xmb.dir_count_out_chan then
        local processed = 0
        while processed < 5 do
            local res = xmb.dir_count_out_chan:pop()
            if not res then break end
            processed = processed + 1
            if res.type == "dir_count_result" and res.key then
                xmb.cached_dir_counts[res.key] = res.counts or {}
                xmb.pending_dir_counts[res.key] = nil

                if browser and browser.files then
                    local suffix = (res.media_type == "video" and " videos") or
                                   (res.media_type == "photo" and " photos") or " tracks"
                    for _, item in ipairs(browser.files) do
                        if item.type == "directory" then
                            local count = res.counts[utils.normalize_path(item.path)] or 0
                            item.description = count .. suffix
                        end
                    end
                end
            end
        end
    end
end

function xmb.clear_thumb_cache()
    if xmb.thumbs then
        for k, img in pairs(xmb.thumbs) do
            if img and img.release then
                pcall(function() img:release() end)
            end
        end
    end
    xmb.thumbs = {}
    xmb.thumb_status = {}
    xmb.orientations = {}
    collectgarbage("collect")
end

function xmb.ensure_thumb_worker()
    if not xmb.thumb_in_chan then
        xmb.thumb_in_chan = love.thread.getChannel("list_thumb_in")
        xmb.thumb_out_chan = love.thread.getChannel("list_thumb_out")
    end
    if not xmb.thumb_thread or not xmb.thumb_thread:isRunning() then
        local t = utils.new_worker_thread("list_thumb_worker.lua")
        if t then
            t:start("list_thumb_in", "list_thumb_out")
            xmb.thumb_thread = t
        end
    end
end

function xmb.request_async_thumb(key, path, is_photo, photo_path)
    if not key or not path then return end
    if xmb.thumb_status[key] then return end
    xmb.thumb_status[key] = "pending"

    xmb.ensure_thumb_worker()
    if xmb.thumb_in_chan then
        xmb.thumb_in_chan:push({
            type = "load_thumb",
            key = key,
            path = path,
            photo_path = photo_path or path,
            is_photo = (is_photo == true)
        })
    end
end

local function handle_sidebar_input(key)
    if key == "up" then
        xmb.playlist_sidebar_selected_idx = xmb.playlist_sidebar_selected_idx - 1
        if xmb.playlist_sidebar_selected_idx < 1 then
            xmb.playlist_sidebar_selected_idx = #xmb.playlist_sidebar_items
        end
        ensure_playlist_sidebar_visible()
        if settings.keytone_enabled then assets.play_sfx("nav") end
    elseif key == "down" then
        xmb.playlist_sidebar_selected_idx = xmb.playlist_sidebar_selected_idx + 1
        if xmb.playlist_sidebar_selected_idx > #xmb.playlist_sidebar_items then
            xmb.playlist_sidebar_selected_idx = 1
        end
        ensure_playlist_sidebar_visible()
        if settings.keytone_enabled then assets.play_sfx("nav") end
    elseif key == "return" or key == "enter" or key == "a" or key == "space" then
        local pick = xmb.playlist_sidebar_items[xmb.playlist_sidebar_selected_idx]
        if pick and xmb.playlist_sidebar_track_to_add then
            local is_watchlist_sidebar = (xmb.playlist_sidebar_title == "Add to Watchlist")
            if is_watchlist_sidebar then
                -- Add video to watchlist
                local ok = add_video_to_watchlist(pick.path, xmb.playlist_sidebar_track_to_add)
                if ok then
                    ui.show_toast("Added to watchlist", "playlist_video", "bottom_right")
                    -- Immediate refresh if currently viewing this watchlist
                    if xmb.view_type == "watchlist_videos" and xmb.view_data and utils.normalize_path(xmb.view_data.path) == utils.normalize_path(pick.path) then
                        local video_name = utils.get_track_name(xmb.playlist_sidebar_track_to_add)
                        table.insert(xmb.view_data.tracks, {
                            name = video_name,
                            path = xmb.playlist_sidebar_track_to_add
                        })
                        xmb.refresh_items()
                        prep_files()
                    elseif xmb.view_type == "video_watchlists" then
                        xmb.refresh_items()
                        prep_files()
                    end
                else
                    ui.show_toast("Could not add to watchlist", "info", "top_center")
                end
            else
                -- Add track to music playlist
                local ok = add_track_to_playlist(pick.path, xmb.playlist_sidebar_track_to_add)
                if ok then
                    ui.show_toast("Added to playlist", "playlist_music", "bottom_right")
                    if xmb.view_type == "playlist_tracks" and xmb.view_data and utils.normalize_path(xmb.view_data.path) == utils.normalize_path(pick.path) then
                        local track_name = utils.get_track_name(xmb.playlist_sidebar_track_to_add)
                        table.insert(xmb.view_data.tracks, {
                            name = track_name,
                            path = xmb.playlist_sidebar_track_to_add
                        })
                        xmb.refresh_items()
                        prep_files()
                    elseif xmb.view_type == "music_playlists" then
                        xmb.refresh_items()
                        prep_files()
                    end
                else
                    ui.show_toast("Could not add to playlist", "info", "top_center")
                end
            end
        end
        close_playlist_sidebar()
    elseif key == "backspace" or key == "b" or key == "escape" then
        close_playlist_sidebar()
    end
end

local function handle_settings_view_input(key)
    -- If folder picker is active, handle its navigation separately
    if settings_view.picker_active then
        if key == "up" then
            settings_view.picker_selected_idx = math.max(1, settings_view.picker_selected_idx - 1)
            settings_view.ensure_picker_visible()
            if settings.keytone_enabled then assets.play_sfx("nav") end
        elseif key == "down" then
            settings_view.picker_selected_idx = math.min(#settings_view.picker_items,
                settings_view.picker_selected_idx + 1)
            settings_view.ensure_picker_visible()
            if settings.keytone_enabled then assets.play_sfx("nav") end
        elseif key == "return" or key == "enter" or key == "a" or key == "space" then
            local pick = settings_view.picker_items[settings_view.picker_selected_idx]
            if pick then
                -- If user selected a directory, either drill into it or pick it
                local chosen_path = pick.path
                if chosen_path then
                    settings_view.picker_current_path = chosen_path
                    local parent = utils.get_dirname(settings_view.picker_current_path)
                    settings_view.picker_items = {}
                    if parent and parent ~= "" then
                        table.insert(settings_view.picker_items, { name = "..", path = parent })
                    end
                    local dirs = (function()
                        local items = {}
                        local cmd = "find \"" ..
                            settings_view.picker_current_path ..
                            "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' -type d 2>/dev/null"
                        local h = io.popen(cmd)
                        if h then
                            local out = h:read("*a")
                            h:close()
                            for line in out:gmatch("[^\r\n]+") do
                                table.insert(items, { name = utils.get_filename(line), path = line })
                            end
                        end
                        table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
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
                settings_view.picker_items = {}
                local grand = utils.get_dirname(settings_view.picker_current_path)
                if grand and grand ~= "" then
                    table.insert(settings_view.picker_items, { name = "..", path = grand })
                end
                local dirs = (function()
                    local items = {}
                    local cmd = "find \"" ..
                        settings_view.picker_current_path ..
                        "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' -type d 2>/dev/null"
                    local h = io.popen(cmd)
                    if h then
                        local out = h:read("*a")
                        h:close()
                        for line in out:gmatch("[^\r\n]+") do
                            table.insert(items, { name = utils.get_filename(line), path = line })
                        end
                    end
                    table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
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
        xmb_actions.apply_setting_value(settings, settings_view, browser, xmb, refresh_settings_items)
    elseif key == "backspace" or key == "b" or key == "escape" then
        settings_view.active = false
    end
end

local function handle_context_menu_input(key)
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
end

local function handle_context_menu_open()
    local selected = browser.files[xmb.current_item_idx]
    local cat_id = categories[xmb.current_category_idx].id
    if selected and selected.type == "file" and (cat_id == "photo" or cat_id == "folder") and is_photo_file(selected.path) then
        open_photo_context_menu(selected.path)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    elseif selected and selected.type == "file" and is_video_file(selected.path) and xmb.view_type == "watchlist_videos" then
        open_watchlist_video_context_menu(selected.path, xmb.current_item_idx - 2)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    elseif selected and selected.type == "file" and cat_id == "video" and is_video_file(selected.path) then
        open_video_context_menu(selected.path)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    elseif selected and selected.type == "file" and is_music_file(selected.path) and (cat_id == "music" or xmb.view_type == "playlist_tracks") then
        if xmb.view_type == "playlist_tracks" then
            open_playlist_track_context_menu(selected.path, xmb.current_item_idx - 1)
        else
            open_music_context_menu(selected.path)
        end
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    elseif selected and selected.type == "playlist" then
        open_playlist_context_menu(selected.path)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    elseif selected and selected.type == "watchlist" then
        open_watchlist_context_menu(selected.path)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    end
end

local function handle_item_activation(player, music, viewer)
    local selected = browser.files[xmb.current_item_idx]
    if not (selected and selected.type ~= "info" and selected.type ~= "info_text") then
        return
    end

    if selected.type == "directory" then
        browser.set_state(browser.base_dir, selected.path, current_filter())
        xmb.refresh_items()
        enter_list_view(first_media_item_index(), 120)
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
            local start_path = opt.value and opt.value ~= "" and opt.value or system.get_default_base_dir()
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
                    opt_custom_bg.value = 3 -- 3 = Wallpaper mode
                end
                if opt_custom_bg_path then
                    opt_custom_bg_path.value = "assets/background/bg.jpg"
                end

                settings.apply()
                settings.save()
                ui.show_toast("Default wallpaper restored", "theme", "bottom_right")
                refresh_settings_items(false)
            elseif opt.id == "reindex_media" then
                local photo_dir = settings.get_option("photo_dir").value
                local music_dir = settings.get_option("music_dir").value
                local video_dir = settings.get_option("video_dir").value
                runtime_state.begin_scan(coroutine.create(function()
                    indexing.scan(photo_dir, music_dir, video_dir)
                end))
                indexing.is_scanning = true
                ui.show_toast("Indexing complete", "folder", "bottom_right")
                settings_view.active = false
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
        enter_list_view(1, 120)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
    elseif selected.type == "view_trigger" then
        table.insert(xmb.nav_stack, xmb.current_item_idx)
        xmb.view_type = selected.target_view
        xmb.refresh_items()
        enter_list_view(1, 120)
    elseif selected.type == "directory_trigger" then
        -- If the directory for this category is not configured, prompt user to set it
        if not selected.path or selected.path == "" then
            ui.show_toast("Media directory not set. Please set directory from Settings.", "folder", "top_center")
            if settings.keytone_enabled then
                assets.play_sfx("nav")
            end
        else
            local cat_id = categories[xmb.current_category_idx].id
            if cat_id == "folder" or selected.is_screenshots then
                -- For Files tab storage entries or Screenshots, set base_dir to the selected storage path
                browser.set_state(selected.path, selected.path, current_filter())
            else
                browser.set_state(browser.base_dir, selected.path, current_filter())
            end
            xmb.view_type = "browser"
            xmb.refresh_items()
            enter_list_view(first_media_item_index(), 120)
        end
    elseif selected.type == "album" or selected.type == "artist" then
        table.insert(xmb.nav_stack, xmb.current_item_idx)
        xmb.view_type = (selected.type == "album") and "album_tracks" or "artist_tracks"
        xmb.view_data = selected.data
        xmb.refresh_items()
        local target_idx = (browser.files[1] and browser.files[1].type == "shuffle_play" and #browser.files > 1) and
            2 or 1
        enter_list_view(target_idx, 120)
    elseif selected.type == "shuffle_play" then
        local playlist = selected.tracks and build_playlist_from_items(selected.tracks) or {}
        if #playlist == 0 then
            for _, item in ipairs(browser.files) do
                if item.type == "file" and is_music_file(item.path) then
                    table.insert(playlist, { name = item.name, path = item.path })
                end
            end
        end

        if #playlist > 0 then
            local start_idx = love.math.random(1, #playlist)
            music.play(playlist[start_idx].path, playlist, { shuffle = true })
        end
    elseif selected.type == "video_play_all" then
        if settings.video_player_mode:sub(1, 6) == "ffplay" then
            ui.show_toast("ffplay is not compatible with Play All.", "info", "bottom_right")
        else
            local playlist = build_media_playlist_from_browser()
            if #playlist > 0 then
                local loop = false
                if xmb.view_type == "watchlist_videos" then
                    local opt = settings.get_option("repeat_watchlist")
                    loop = opt and opt.choices[opt.value] == "Yes"
                else
                    local opt = settings.get_option("repeat_folder")
                    loop = opt and opt.choices[opt.value] == "Yes"
                end
                player.play_video(playlist, nil, {
                    loop = loop,
                    shuffle = false
                })
            end
        end
    elseif selected.type == "video_shuffle_play" then
        if settings.video_player_mode:sub(1, 6) == "ffplay" then
            ui.show_toast("ffplay is not compatible with Shuffle Play.", "info", "bottom_right")
        else
            local playlist = build_media_playlist_from_browser()
            if #playlist > 0 then
                local loop = false
                if xmb.view_type == "watchlist_videos" then
                    local opt = settings.get_option("repeat_watchlist")
                    loop = opt and opt.choices[opt.value] == "Yes"
                else
                    local opt = settings.get_option("repeat_folder")
                    loop = opt and opt.choices[opt.value] == "Yes"
                end
                player.play_video(playlist, nil, {
                    loop = loop,
                    shuffle = true
                })
            end
        end
    elseif selected.type == "photo_slideshow" then
        local image_paths = {}
        for _, item in ipairs(browser.files) do
            if item.type == "file" and is_photo_file(item.path) then
                table.insert(image_paths, item.path)
            end
        end
        if #image_paths > 0 then
            player.play_slideshow(image_paths)
        end
    elseif selected.type == "playlist_create" then
        keyboard.open({
            title = "Create Playlist",
            max_length = 50,
            on_submit = function(name)
                local full_path, err, replaced_invalid = create_playlist(name)
                if not full_path then
                    if err == "invalid_name" then
                        ui.show_toast("Enter a valid playlist name", "playlist_add", "top_center")
                    elseif err == "exists" then
                        ui.show_toast("Playlist already exists", "playlist_music", "top_center")
                    else
                        ui.show_toast("Could not create playlist", "info", "top_center")
                    end
                    return
                end

                xmb.refresh_items()
                xmb.current_item_idx = 1
                for i, item in ipairs(browser.files) do
                    if item.path == full_path then
                        xmb.current_item_idx = i
                        break
                    end
                end
                prep_files()
                set_item_focus(xmb.current_item_idx, {
                    slide_x = 120,
                    slide_alpha = 0,
                })
                if replaced_invalid then
                    ui.show_toast("Invalid filename characters", "info", "top_center")
                end
                ui.show_toast("Playlist created", "playlist_music", "bottom_right")
            end,
        })
    elseif selected.type == "playlist" then
        local tracks = parse_m3u_playlist(selected.path)
        table.insert(xmb.nav_stack, xmb.current_item_idx)
        xmb.view_type = "playlist_tracks"
        xmb.view_data = { path = selected.path, tracks = tracks }
        xmb.refresh_items()
        enter_list_view(first_playlist_track_index(), 120)
    elseif selected.type == "watchlist_create" then
        keyboard.open({
            title = "Create Watchlist",
            max_length = 50,
            on_submit = function(name)
                local full_path, err, replaced_invalid = create_watchlist(name)
                if not full_path then
                    if err == "invalid_name" then
                        ui.show_toast("Enter a valid watchlist name", "playlist_add", "top_center")
                    elseif err == "exists" then
                        ui.show_toast("Watchlist already exists", "playlist_video", "top_center")
                    else
                        ui.show_toast("Could not create watchlist", "info", "top_center")
                    end
                    return
                end

                xmb.refresh_items()
                xmb.current_item_idx = 1
                for i, item in ipairs(browser.files) do
                    if item.path == full_path then
                        xmb.current_item_idx = i
                        break
                    end
                end
                prep_files()
                set_item_focus(xmb.current_item_idx, {
                    slide_x = 120,
                    slide_alpha = 0,
                })
                if replaced_invalid then
                    ui.show_toast("Invalid filename characters", "info", "top_center")
                end
                ui.show_toast("Watchlist created", "playlist_video", "bottom_right")
            end,
        })
    elseif selected.type == "watchlist" then
        local tracks = parse_m3u_watchlist(selected.path)
        table.insert(xmb.nav_stack, xmb.current_item_idx)
        xmb.view_type = "watchlist_videos"
        xmb.view_data = { path = selected.path, tracks = tracks }
        xmb.refresh_items()
        local target_idx = (browser.files[1] and (browser.files[1].type == "video_shuffle_play") and #browser.files > 1) and
            3 or 1
        enter_list_view(target_idx, 120)
    end
end

function xmb.keypressed(key, player, music, viewer)
    if indexing and indexing.is_scanning then
        return
    end

    if keyboard.is_active() then
        keyboard.keypressed(key)
        if settings.keytone_enabled then
            assets.play_sfx("nav")
        end
        return
    end

    if xmb.playlist_sidebar_active then
        handle_sidebar_input(key)
        return
    end

    if settings_view.active then
        handle_settings_view_input(key)
        return
    end

    if xmb.context_menu.active then
        handle_context_menu_input(key)
        return
    end

    if key == "up" or key == "down" or key == "left" or key == "right" then
        xmb.navigate(key)
    elseif key == "return" or key == "enter" or key == "a" then
        handle_item_activation(player, music, viewer)
    elseif key == "backspace" or key == "b" then
        if xmb.in_submenu() then
            xmb.go_back()
        end
    elseif key == "x" then
        handle_context_menu_open()
    end
end

return xmb
