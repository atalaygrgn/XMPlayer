local theme = require("theme")
local browser = require("browser")
local categories = require("categories")
local settings = require("settings")

local xmb = {}

xmb.current_category_idx = 3 -- Default to Videos
xmb.current_item_idx = 1

-- Animation state
xmb.category_scroll_x = 0
xmb.target_category_scroll_x = 0
xmb.item_scroll_y = 0
xmb.target_item_scroll_y = 0
xmb.list_marquee_offset = 0
xmb.list_marquee_timer = 0
xmb.list_marquee_phase = "pause_start" -- "pause_start", "scrolling", "pause_end"

-- Slide transition state
xmb.list_slide_x = 0
xmb.list_slide_alpha = 1

-- Navigation history stack (stores item index when entering subfolders)
xmb.nav_stack = {}

-- Continuous Repeat State
xmb.repeat_timer = 0
xmb.last_key = nil
local REPEAT_DELAY = 0.4
local REPEAT_INTERVAL = 0.08

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function prep_files(fonts)
    if not fonts then return end
    local screen_w = love.graphics.getWidth()
    local cat_base_x = screen_w * 0.25
    local max_w = screen_w - cat_base_x - 40
    local font = fonts.small -- used for truncated inactive names
    
    for _, item in ipairs(browser.files) do
        item.display_name = item.name
        if font:getWidth(item.name) > max_w then
            for j = #item.name, 1, -1 do
                local sub = item.name:sub(1, j) .. "..."
                if font:getWidth(sub) <= max_w then
                    item.display_name = sub
                    break
                end
            end
        end
    end
end

-- Check if the XMB is currently inside a submenu (subfolder or settings group)
function xmb.in_submenu()
    local cat = categories[xmb.current_category_idx]
    if cat.id == "settings" then
        return settings.in_submenu()
    elseif cat.path then
        return browser.current_dir ~= browser.base_dir
    end
    return false
end

-- Go back one level in the current submenu
function xmb.go_back(fonts, sfx)
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
        prep_files(fonts)
    elseif cat.path then
        if browser.current_dir ~= browser.base_dir then
            browser.current_dir = browser.current_dir:match("(.*)/")
            if not browser.current_dir or browser.current_dir == "" then browser.current_dir = "/" end
            browser.scan()
            xmb.current_item_idx = math.min(prev_idx, #browser.files)
            prep_files(fonts)
        end
    end
    xmb.list_marquee_offset = 0
    xmb.list_marquee_timer = 0
    xmb.list_marquee_phase = "pause_start"
    -- Snap vertical scroll to new position instantly
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 45
    xmb.item_scroll_y = xmb.target_item_scroll_y
    -- Slide in from the left (going back)
    xmb.list_slide_x = -120
    xmb.list_slide_alpha = 0
    if sfx and sfx.nav and settings.keytone_enabled then
        sfx.nav:stop()
        sfx.nav:play()
    end
end

function xmb.refresh_browser(fonts, slide_dir)
    local cat = categories[xmb.current_category_idx]
    if cat.path then
        browser.base_dir = cat.path
        browser.current_dir = cat.path
        browser.set_filter(cat.filter)
        browser.scan()
    elseif cat.id == "settings" then
        settings.current_group = nil -- Reset to top-level on category switch
        browser.files = settings.get_browser_items()
    else
        browser.files = {{name = cat.name .. " (Coming Soon)", path = "", type = "info"}}
    end
    xmb.current_item_idx = 1
    xmb.list_marquee_offset = 0
    xmb.list_marquee_timer = 0
    xmb.list_marquee_phase = "pause_start"
    xmb.nav_stack = {} -- Clear history on category switch
    -- Snap vertical scroll to top instantly
    xmb.target_item_scroll_y = 0
    xmb.item_scroll_y = 0
    -- Slide direction based on navigation
    local slide = (slide_dir == "left") and -120 or 120
    xmb.list_slide_x = slide
    xmb.list_slide_alpha = 0
    
    if fonts then
        prep_files(fonts)
    end
end

-- Shared navigation logic for single press and continuous scroll
function xmb.navigate(dir, fonts, sfx)
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
            xmb.go_back(fonts, sfx)
            return true -- already played sfx in go_back
        else
            local old_cat = xmb.current_category_idx
            xmb.current_category_idx = math.max(1, xmb.current_category_idx - 1)
            if old_cat ~= xmb.current_category_idx then
                xmb.refresh_browser(fonts, "left")
                moved = true
            end
        end
    elseif dir == "right" then
        if not xmb.in_submenu() then
            local old_cat = xmb.current_category_idx
            xmb.current_category_idx = math.min(#categories, xmb.current_category_idx + 1)
            if old_cat ~= xmb.current_category_idx then
                xmb.refresh_browser(fonts, "right")
                moved = true
            end
        end
    elseif dir == "down" then
        local old_idx = xmb.current_item_idx
        xmb.current_item_idx = math.min(#browser.files, xmb.current_item_idx + 1)
        if old_idx ~= xmb.current_item_idx then
            xmb.list_marquee_offset = 0
            xmb.list_marquee_timer = 0
            xmb.list_marquee_phase = "pause_start"
            moved = true
        end
    elseif dir == "up" then
        local old_idx = xmb.current_item_idx
        xmb.current_item_idx = math.max(1, xmb.current_item_idx - 1)
        if old_idx ~= xmb.current_item_idx then
            xmb.list_marquee_offset = 0
            xmb.list_marquee_timer = 0
            xmb.list_marquee_phase = "pause_start"
            moved = true
        end
    end

    if moved and sfx and sfx.nav and settings.keytone_enabled then
        sfx.nav:stop()
        sfx.nav:play()
    end
    return moved
end

function xmb.update(dt, fonts, sfx)
    -- Smooth scroll
    xmb.category_scroll_x = lerp(xmb.category_scroll_x, xmb.target_category_scroll_x, dt * 10)
    xmb.item_scroll_y = lerp(xmb.item_scroll_y, xmb.target_item_scroll_y, dt * 10)
    
    -- Slide transition animation
    xmb.list_slide_x = lerp(xmb.list_slide_x, 0, dt * 12)
    xmb.list_slide_alpha = lerp(xmb.list_slide_alpha, 1, dt * 10)
    if math.abs(xmb.list_slide_x) < 0.5 then xmb.list_slide_x = 0 end
    if xmb.list_slide_alpha > 0.99 then xmb.list_slide_alpha = 1 end
    
    local selected = browser.files[xmb.current_item_idx]
    settings.update(dt, selected and selected.setting_idx)
    
    -- Categories are centered at 1/4 of screen width
    xmb.target_category_scroll_x = -(xmb.current_category_idx - 1) * (theme.icon_size + theme.icon_spacing)
    
    -- Items are scrolled based on current selection
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 45
    
    local cat_base_x = love.graphics.getWidth() * 0.25
    
    -- Active Item Marquee
    local selected = browser.files[xmb.current_item_idx]
    if selected and fonts then
        local text_w = fonts.main:getWidth(selected.name)
        local max_w = love.graphics.getWidth() - cat_base_x - 40
        if text_w > max_w then
            local max_offset = text_w - max_w + 20 -- scroll just enough to reveal the end (+20px padding)
            xmb.list_marquee_timer = xmb.list_marquee_timer + dt
            if xmb.list_marquee_phase == "pause_start" then
                -- Wait before starting to scroll
                if xmb.list_marquee_timer > 1.5 then
                    xmb.list_marquee_phase = "scrolling"
                    xmb.list_marquee_timer = 0
                end
            elseif xmb.list_marquee_phase == "scrolling" then
                -- Scroll left until end of text is visible
                xmb.list_marquee_offset = xmb.list_marquee_offset + dt * 50
                if xmb.list_marquee_offset >= max_offset then
                    xmb.list_marquee_offset = max_offset
                    xmb.list_marquee_phase = "pause_end"
                    xmb.list_marquee_timer = 0
                end
            elseif xmb.list_marquee_phase == "pause_end" then
                -- Pause at the end, then reset
                if xmb.list_marquee_timer > 1.0 then
                    xmb.list_marquee_offset = 0
                    xmb.list_marquee_phase = "pause_start"
                    xmb.list_marquee_timer = 0
                end
            end
        else
            xmb.list_marquee_offset = 0
            xmb.list_marquee_timer = 0
            xmb.list_marquee_phase = "pause_start"
        end
    else
        xmb.list_marquee_offset = 0
        xmb.list_marquee_timer = 0
        xmb.list_marquee_phase = "pause_start"
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
                xmb.navigate(current_key, fonts, sfx)
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

function xmb.draw(images, fonts)
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    
    local main_font = fonts.main
    local small_font = fonts.small
    
    -- Draw Horizontal Category Bar
    local cat_base_x = screen_w * 0.25
    local cat_y = screen_h * 0.25
    
    love.graphics.push()
    love.graphics.translate(cat_base_x + xmb.category_scroll_x, cat_y)
    
    for i, cat in ipairs(categories) do
        local x = (i - 1) * (theme.icon_size + theme.icon_spacing)
        local is_focused = (i == xmb.current_category_idx)
        
        -- Calculate base scale to make icon fit theme.icon_size
        local img = images[cat.id]
        local base_scale = theme.icon_size / img:getWidth()
        local scale = is_focused and base_scale * 1.1 or base_scale * 0.7
        local alpha = is_focused and 1 or 0.4
        
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], alpha)
        love.graphics.draw(img, x, 0, 0, scale, scale, img:getWidth()/2, img:getHeight()/2)
        
        if is_focused then
            love.graphics.setFont(main_font)
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], alpha)
            love.graphics.printf(cat.name, x - 100, theme.icon_size/2 + 15, 200, "center")
        end
    end
    love.graphics.pop()
    
    -- ─── Left Arrow Indicator (submenu back) ───
    if xmb.in_submenu() then
        local arrow_x = cat_base_x - 96
        local arrow_y = cat_y + theme.icon_size + 70
        local pulse = 0.5 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], pulse)
        -- Draw a simple left-pointing triangle
        love.graphics.polygon("fill",
            arrow_x + 12, arrow_y,
            arrow_x + 24, arrow_y - 10,
            arrow_x + 24, arrow_y + 10
        )
    end
    
    -- ─── Vertical Item List ───
    local list_x = cat_base_x
    local list_base_y = cat_y + theme.icon_size + 60
    
    -- XMB-style Alpha Fading & Clipping
    local fade_top = cat_y + theme.icon_size / 2 + 50
    local fade_range = 80
    
    love.graphics.setScissor(0, fade_top - 20, screen_w, screen_h - (fade_top - 20))
    
    love.graphics.push()
    love.graphics.translate(list_x + xmb.list_slide_x, list_base_y + xmb.item_scroll_y)
    
    -- OPTIMIZATION: Viewport Culling
    -- Only iterate over items that are actually on screen
    local item_h = 45
    local first = math.max(1, math.floor(-xmb.item_scroll_y / item_h) - 2)
    local last = math.min(#browser.files, first + math.ceil(screen_h / item_h) + 4)
    
    local list_icon_size = 32
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
            local cat_id = categories[xmb.current_category_idx].id
            local icon = images.folder_icon
            if item.type == "file" then
                if cat_id == "video" then icon = images.video_icon
                elseif cat_id == "music" then icon = images.music_icon
                elseif cat_id == "photo" then icon = images.photo_icon
                else icon = images.video_icon
                end
            elseif item.type == "settings_group" then
                icon = images.folder_icon
            end
            
            local icon_scale = list_icon_size / icon:getWidth()
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], final_alpha)
            love.graphics.draw(icon, -45, y + 5, 0, icon_scale, icon_scale)
            
            -- Draw text
            local font = is_focused and main_font or small_font
            love.graphics.setFont(font)
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], final_alpha)
            
            local max_w = screen_w - list_x - 40
            
            if is_focused then
                -- Marquee for active item
                local text_w = font:getWidth(item.name)
                if text_w > max_w then
                    love.graphics.setScissor(list_x, screen_y, max_w, item_h)
                    love.graphics.print(item.name, -xmb.list_marquee_offset, y)
                    love.graphics.setScissor()
                    love.graphics.setScissor(0, fade_top - 20, screen_w, screen_h - (fade_top - 20))
                else
                    love.graphics.print(item.name, 0, y)
                end
            else
                -- OPTIMIZATION: Use pre-cached truncated name
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
            settings.draw_popup(selected.setting_idx, fonts)
        end
    end
end

function xmb.keypressed(key, player, music, viewer, fonts, sfx)
    if settings.active then
        if key == "up" or key == "down" then
            xmb.navigate(key, fonts, sfx)
        elseif key == "return" or key == "enter" or key == "a" then
            local selected = browser.files[xmb.current_item_idx]
            local opt = settings.options[selected.setting_idx]
            opt.value = settings.selected_option_idx
            
            -- Keep panel open but apply immediately
            settings.apply()
            
            local old_idx = xmb.current_item_idx
            browser.files = settings.get_browser_items()
            prep_files(fonts)
            xmb.current_item_idx = old_idx -- Keep focus on the same setting
        elseif key == "backspace" or key == "b" or key == "escape" then
            settings.active = false
        end
        return
    end

    if key == "up" or key == "down" or key == "left" or key == "right" then
        xmb.navigate(key, fonts, sfx)
    elseif key == "return" or key == "enter" or key == "a" then
        local selected = browser.files[xmb.current_item_idx]
        if selected and selected.type ~= "info" then
            if selected.type == "directory" then
                -- Remember position before entering
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                browser.current_dir = selected.path
                browser.scan()
                xmb.current_item_idx = 1
                prep_files(fonts)
                -- Snap vertical scroll to top instantly
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                -- Slide in from the right (entering subfolder)
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
                else
                    print("Open " .. selected.path .. " not implemented for category: " .. cat_id)
                end
            elseif selected.type == "setting" then
                local opt = settings.options[selected.setting_idx]
                if opt.type == "choice" then
                    settings.active = true
                    settings.selected_option_idx = opt.value
                elseif opt.type == "path" then
                    -- Handle path selection (future)
                    print("Path selection for " .. opt.name .. " not yet implemented")
                end
            elseif selected.type == "settings_group" then
                -- Remember position before entering
                table.insert(xmb.nav_stack, xmb.current_item_idx)
                -- Enter the settings sub-group
                settings.enter_group(selected.group_id)
                browser.files = settings.get_browser_items()
                xmb.current_item_idx = 1
                prep_files(fonts)
                xmb.list_marquee_offset = 0
                xmb.list_marquee_timer = 0
                xmb.list_marquee_phase = "pause_start"
                -- Snap vertical scroll to top instantly
                xmb.target_item_scroll_y = 0
                xmb.item_scroll_y = 0
                -- Slide in from the right (entering group)
                xmb.list_slide_x = 120
                xmb.list_slide_alpha = 0
                if sfx and sfx.nav and settings.keytone_enabled then
                    sfx.nav:stop()
                    sfx.nav:play()
                end
            end
        end
    elseif key == "backspace" or key == "b" then
        if xmb.in_submenu() then
            xmb.go_back(fonts, sfx)
        end
    end
end

return xmb
