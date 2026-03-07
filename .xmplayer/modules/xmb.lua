local theme = require("theme")
local browser = require("browser")
local categories = require("categories")
local settings = require("settings")
local assets = require("assets")
local ui = require("ui")
local utils = require("utils")
local indexing = require("indexing")
local history = require("history")

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

-- Navigation history stack (stores state when entering sub-menus)
-- Each entry: {item_idx, dir, view_type, view_data}
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

-- Helper for path checks
local function in_subpath(base, current)
    return utils.is_subpath(base, current)
end

local function prep_files()
    local screen_w = love.graphics.getWidth()
    local cat_base_x = screen_w * 0.25
    local max_w = screen_w - cat_base_x - 40
    local font = assets.fonts.small
    
    for _, item in ipairs(browser.files) do
        item.name = utils.clean_utf8(item.name)
        item.display_name = utils.truncate_text(item.name, font, max_w)
    end
end

function xmb.in_submenu()
    local cat = categories[xmb.current_category_idx]
    if cat.id == "settings" then
        return settings.in_submenu()
    end
    
    if (cat.id == "music" or cat.id == "video" or cat.id == "photo") and xmb.view_type ~= "category_root" then
        return true
    end
    
    if cat.path then
        return utils.normalize_path(browser.current_dir) ~= utils.normalize_path(browser.base_dir)
    end
    return false
end

-- Go back one level in the current submenu
function xmb.go_back()
    -- Restore previous item index from stack
    local prev_idx = 1
    if #xmb.nav_stack > 0 then
        prev_idx = table.remove(xmb.nav_stack)
    end
    
    local cat = categories[xmb.current_category_idx]
    if cat.id == "settings" then
        settings.go_back()
        browser.files = settings.get_browser_items()
        xmb.current_item_idx = math.min(prev_idx, #browser.files)
        prep_files()
    elseif cat.path then
        if xmb.view_type ~= "browser" then
            -- Handle categorical views
            if xmb.view_type == "album_tracks" or xmb.view_type == "artist_tracks" then
                if xmb.view_type == "album_tracks" then xmb.view_type = "music_albums" else xmb.view_type = "music_artists" end
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
            
            if (cat.id == "music" or cat.id == "video" or cat.id == "photo") and current == base then
                -- Return to categorical root
                xmb.view_type = "category_root"
                xmb.refresh_items()
                xmb.current_item_idx = math.min(prev_idx, #browser.files)
                prep_files()
            elseif current ~= base then
                local parent = utils.get_dirname(browser.current_dir)
                if parent ~= "" and utils.is_subpath(base, parent) then
                    browser.current_dir = parent
                    browser.scan()
                    xmb.current_item_idx = math.min(prev_idx, #browser.files)
                    prep_files()
                else
                    browser.current_dir = base
                    browser.scan()
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
    browser.files = {}
    
    if cat.id == "music" then
        if xmb.view_type == "category_root" then
            table.insert(browser.files, {name = "Albums", type = "view_trigger", target_view = "music_albums", icon = "albums"})
            table.insert(browser.files, {name = "Artists", type = "view_trigger", target_view = "music_artists", icon = "mic"})
            table.insert(browser.files, {name = "Music Files", type = "directory_trigger", path = cat.path, icon = "folder_music"})
            browser.base_dir = cat.path
            browser.current_dir = cat.path
            browser.set_filter(cat.filter)
        elseif xmb.view_type == "music_albums" then
            for key, album in pairs(indexing.data.music.albums) do
                table.insert(browser.files, {name = album.name, type = "album", data = album})
            end
            table.sort(browser.files, function(a, b) return a.name:lower() < b.name:lower() end)
        elseif xmb.view_type == "music_artists" then
            for name, artist in pairs(indexing.data.music.artists) do
                table.insert(browser.files, {name = name, type = "artist", data = artist})
            end
            table.sort(browser.files, function(a, b) return a.name:lower() < b.name:lower() end)
        elseif xmb.view_type == "album_tracks" then
            for _, path in ipairs(xmb.view_data.tracks) do
                local info = indexing.data.music.files[path]
                table.insert(browser.files, {name = info.title or "Unknown", path = path, type = "file"})
            end
        elseif xmb.view_type == "artist_tracks" then
            for _, path in ipairs(xmb.view_data.tracks) do
                local info = indexing.data.music.files[path]
                table.insert(browser.files, {name = info.title or "Unknown", path = path, type = "file"})
            end
        elseif xmb.view_type == "browser" then
            browser.scan()
        end
    elseif cat.id == "video" then
        if xmb.view_type == "category_root" then
            table.insert(browser.files, {name = "Watch History", type = "view_trigger", target_view = "video_history", icon = "history"})
            table.insert(browser.files, {name = "Video Files", type = "directory_trigger", path = cat.path, icon = "folder_video"})
            browser.base_dir = cat.path
            browser.current_dir = cat.path
            browser.set_filter(cat.filter)
        elseif xmb.view_type == "video_history" then
            for _, path in ipairs(history.data) do
                table.insert(browser.files, {name = utils.get_filename(path), path = path, type = "file"})
            end
        elseif xmb.view_type == "browser" then
            browser.scan()
        end
    elseif cat.id == "photo" then
        if xmb.view_type == "category_root" then
            table.insert(browser.files, {name = "Photo Files", type = "directory_trigger", path = cat.path, icon = "folder_image"})
            browser.base_dir = cat.path
            browser.current_dir = cat.path
            browser.set_filter(cat.filter)
        elseif xmb.view_type == "browser" then
            browser.scan()
        end
    elseif cat.id == "settings" then
        browser.files = settings.get_browser_items()
    elseif cat.path then
        browser.base_dir = cat.path
        if xmb.view_type == "browser" then
            browser.set_filter(cat.filter)
            browser.scan()
        end
    end
end

function xmb.refresh_browser(slide_dir)
    local cat = categories[xmb.current_category_idx]
    if cat.id == "music" or cat.id == "video" or cat.id == "photo" then
        xmb.view_type = "category_root"
    else
        xmb.view_type = "browser"
    end
    
    xmb.view_data = nil
    
    -- Ensure browser state is clean for the new category
    browser.base_dir = cat.path or "/mnt/sdcard"
    browser.current_dir = browser.base_dir
    browser.set_filter(cat.filter)
    
    xmb.refresh_items()
    
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
    if settings.active then
        local old_idx = settings.selected_option_idx
        if dir == "up" then
            settings.selected_option_idx = math.max(1, settings.selected_option_idx - 1)
        elseif dir == "down" then
            local selected = browser.files[xmb.current_item_idx]
            if selected and selected.setting_idx then
                local opt = settings.options[selected.setting_idx]
                settings.selected_option_idx = math.min(#opt.choices, settings.selected_option_idx + 1)
            end
        end
        moved = (old_idx ~= settings.selected_option_idx)
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
    -- Smooth scroll
    xmb.category_scroll_x = utils.lerp(xmb.category_scroll_x, xmb.target_category_scroll_x, dt * 10)
    xmb.item_scroll_y = utils.lerp(xmb.item_scroll_y, xmb.target_item_scroll_y, dt * 10)
    
    -- Slide transition animation
    xmb.list_slide_x = utils.lerp(xmb.list_slide_x, 0, dt * 12)
    xmb.list_slide_alpha = utils.lerp(xmb.list_slide_alpha, 1, dt * 10)
    if math.abs(xmb.list_slide_x) < 0.5 then xmb.list_slide_x = 0 end
    if xmb.list_slide_alpha > 0.99 then xmb.list_slide_alpha = 1 end
    
    local selected = browser.files[xmb.current_item_idx]
    settings.update(dt, selected and selected.setting_idx)
    
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
    if up then current_key = "up"
    elseif down then current_key = "down"
    elseif left then current_key = "left"
    elseif right then current_key = "right"
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

function xmb.draw()
    local screen_w, screen_h = love.graphics.getDimensions()
    
    -- Draw Horizontal Category Bar
    local cat_base_x = screen_w * 0.2
    local cat_y = screen_h * 0.25
    
    love.graphics.push()
    love.graphics.translate(cat_base_x + xmb.category_scroll_x, cat_y)
    
    for i, cat in ipairs(categories) do
        local x = (i - 1) * (theme.icon_size + theme.icon_spacing)
        local is_focused = (i == xmb.current_category_idx)
        
        local img = assets.images["cat_" .. cat.id]
        local base_scale = theme.icon_size / img:getWidth()
        local scale = is_focused and base_scale * 1.1 or base_scale * 0.7
        local alpha = is_focused and 1 or 0.4
        
        if is_focused then
            ui.draw_glow_icon(img, x, 0, theme.icon_size * 1.1, theme.text, alpha)
            
            ui.draw_glow_text(cat.name, x - 100, theme.icon_size/2 + 12, assets.fonts.main, {theme.text[1], theme.text[2], theme.text[3], alpha}, nil, 200, "center")
        else
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], alpha)
            love.graphics.draw(img, x, 0, 0, scale, scale, img:getWidth()/2, img:getHeight()/2)
        end
    end
    love.graphics.pop()
    
    -- ─── Left Arrow Indicator (submenu back) ───
    if xmb.in_submenu() then
        local arrow_x = cat_base_x - 90
        local arrow_y = cat_y + theme.icon_size + 87
        local pulse = 0.5 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], pulse)
        love.graphics.polygon("fill", arrow_x + 12, arrow_y, arrow_x + 24, arrow_y - 10, arrow_x + 24, arrow_y + 10)
    end
    
    -- ─── Vertical Item List ───
    local list_x = cat_base_x + 32
    local list_base_y = cat_y + theme.icon_size + 75
    local fade_top = cat_y + theme.icon_size / 2 + 50
    local fade_range = 100
    
    love.graphics.setScissor(0, fade_top - 20, screen_w, screen_h - (fade_top - 20))
    love.graphics.push()
    love.graphics.translate(list_x + xmb.list_slide_x, list_base_y + xmb.item_scroll_y)
    
    local item_h = 75
    local first = math.max(1, math.floor(-xmb.item_scroll_y / item_h) - 2)
    local last = math.min(#browser.files, first + math.ceil(screen_h / item_h) + 4)
    
    local cat_id = categories[xmb.current_category_idx].id

    for i = first, last do
        local item = browser.files[i]
        local y = (i - 1) * item_h
        local screen_y = list_base_y + xmb.item_scroll_y + y
        
        local item_alpha = xmb.list_slide_alpha
        if screen_y < list_base_y then
            local dist = list_base_y - screen_y
            item_alpha = math.max(0, xmb.list_slide_alpha * (1.0 - (dist / fade_range)))
        end
        
        local is_focused = (i == xmb.current_item_idx)
        local base_alpha = is_focused and 1 or 0.5
        local final_alpha = base_alpha * item_alpha
        
        if final_alpha > 0 then
            -- Draw icon
            local icon = assets.images.folder
            local thumb = nil
            
            if item.icon and assets.images[item.icon] then
                icon = assets.images[item.icon]
            elseif item.type == "directory" then
                icon = assets.images.folder
            elseif item.type == "album" then
                icon = assets.images.album
            elseif item.type == "artist" then
                icon = assets.images.artist
            elseif item.type == "file" then
                if cat_id == "video" then 
                    icon = assets.images.file_video
                elseif cat_id == "music" then 
                    if xmb.view_type == "album_tracks" or xmb.view_type == "artist_tracks" then
                        icon = assets.images.track
                    else
                        icon = assets.images.file_music
                    end
                elseif cat_id == "photo" then 
                    icon = assets.images.photo
                    local info = indexing.data.photos[item.path]
                    if info and info.thumb_path then
                        if not xmb.thumbs[info.thumb_path] then
                            xmb.thumbs[info.thumb_path] = utils.load_image(info.thumb_path)
                        end
                        thumb = xmb.thumbs[info.thumb_path]
                    end
                elseif cat_id == "folder" then
                    icon = assets.images.file
                else 
                    icon = assets.images.file
                end
            end

            if is_focused then
                ui.draw_glow_icon(icon, -36, y + 14, 48, theme.text, final_alpha, theme.accent, thumb)
            else
                ui.draw_icon(icon, -36, y + 14, 48, theme.text, final_alpha, thumb)
            end
            
            -- Draw text
            if is_focused then
                ui.draw_marquee(xmb.item_marquee, item.name, 0, y, assets.fonts.main, {theme.text[1], theme.text[2], theme.text[3], final_alpha}, list_x + xmb.list_slide_x, screen_y)
            else
                love.graphics.setFont(assets.fonts.small)
                love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], final_alpha)
                love.graphics.print(item.display_name or item.name, 0, y + 4)
            end
        end
    end
    love.graphics.pop()
    love.graphics.setScissor()

    -- Draw Settings Popup
    if settings.active or settings.alpha > 0 then
        local selected = browser.files[xmb.current_item_idx]
        if selected and selected.setting_idx then
            settings.draw_popup(selected.setting_idx)
        end
    end
end

function xmb.keypressed(key, player, music, viewer)
    if settings.active then
        if key == "up" or key == "down" then
            xmb.navigate(key)
        elseif key == "return" or key == "enter" or key == "a" or key == "space" then
            local selected = browser.files[xmb.current_item_idx]
            local opt = settings.options[selected.setting_idx]
            opt.value = settings.selected_option_idx
            settings.apply()
            settings.save()
            
            local old_idx = xmb.current_item_idx
            browser.files = settings.get_browser_items()
            prep_files()
            xmb.current_item_idx = old_idx -- Keep focus on the same setting
        elseif key == "backspace" or key == "b" or key == "escape" then
            settings.active = false
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
                browser.current_dir = selected.path
                browser.scan()
                xmb.current_item_idx = 1
                prep_files()
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
            elseif selected.type == "file" then
                local cat_id = categories[xmb.current_category_idx].id
                if cat_id == "video" then
                    player.play(selected.path)
                elseif cat_id == "music" and music then
                    music.play(selected.path)
                elseif cat_id == "photo" and viewer then
                    viewer.open(selected.path, browser.files)
                end
            elseif selected.type == "setting" then
                local opt = settings.options[selected.setting_idx]
                if opt.type == "choice" then
                    settings.active = true
                    settings.selected_option_idx = opt.value
                elseif opt.type == "action" then
                    if opt.id == "clear_history" then
                        history.clear()
                        ui.show_toast("Watch history cleared", "history", "bottom_right")
                        -- Refresh browser items to show (maybe nothing changed visually but action happened)
                        browser.files = settings.get_browser_items()
                        prep_files()
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
                browser.files = settings.get_browser_items()
                xmb.current_item_idx = 1
                prep_files()
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
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                browser.current_dir = selected.path
                xmb.view_type = "browser"
                xmb.refresh_items()
                xmb.current_item_idx = 1
                prep_files()
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
            elseif selected.type == "album" or selected.type == "artist" then
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                xmb.view_type = (selected.type == "album") and "album_tracks" or "artist_tracks"
                xmb.view_data = selected.data
                xmb.refresh_items()
                xmb.current_item_idx = 1
                prep_files()
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
            end
        end
    elseif key == "backspace" or key == "b" then
        if xmb.in_submenu() then
            xmb.go_back()
        end
    end
end

return xmb
