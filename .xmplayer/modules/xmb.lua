local theme = require("theme")
local browser = require("browser")
local categories = require("categories")

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

function xmb.refresh_browser(fonts)
    local cat = categories[xmb.current_category_idx]
    if cat.path then
        browser.base_dir = cat.path
        browser.current_dir = cat.path
        browser.set_filter(cat.filter)
        browser.scan()
    else
        browser.files = {{name = cat.name .. " (Coming Soon)", path = "", type = "info"}}
    end
    xmb.current_item_idx = 1
    xmb.list_marquee_offset = 0
    xmb.list_marquee_timer = 0
    
    if fonts then
        prep_files(fonts)
    end
end

function xmb.update(dt, fonts)
    -- Smooth scroll
    xmb.category_scroll_x = lerp(xmb.category_scroll_x, xmb.target_category_scroll_x, dt * 10)
    xmb.item_scroll_y = lerp(xmb.item_scroll_y, xmb.target_item_scroll_y, dt * 10)
    
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
            xmb.list_marquee_timer = xmb.list_marquee_timer + dt
            if xmb.list_marquee_timer > 1.5 then
                xmb.list_marquee_offset = xmb.list_marquee_offset + dt * 50
                if xmb.list_marquee_offset > text_w + 60 then
                    xmb.list_marquee_offset = -40
                    xmb.list_marquee_timer = 0
                end
            end
        else
            xmb.list_marquee_offset = 0
            xmb.list_marquee_timer = 0
        end
    else
        xmb.list_marquee_offset = 0
        xmb.list_marquee_timer = 0
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
    
    -- ─── Vertical Item List ───
    local list_x = cat_base_x
    local list_base_y = cat_y + theme.icon_size + 60
    
    -- XMB-style Alpha Fading & Clipping
    local fade_top = cat_y + theme.icon_size / 2 + 50
    local fade_range = 80
    
    love.graphics.setScissor(0, fade_top - 20, screen_w, screen_h - (fade_top - 20))
    
    love.graphics.push()
    love.graphics.translate(list_x, list_base_y + xmb.item_scroll_y)
    
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
        
        local item_alpha = 1.0
        if screen_y < list_base_y then
            local dist = list_base_y - screen_y
            item_alpha = math.max(0, 1.0 - (dist / fade_range))
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
end

function xmb.keypressed(key, player, music, viewer, fonts)
    if key == "right" then
        xmb.current_category_idx = (xmb.current_category_idx % #categories) + 1
        xmb.refresh_browser(fonts)
    elseif key == "left" then
        xmb.current_category_idx = (xmb.current_category_idx - 2 + #categories) % #categories + 1
        xmb.refresh_browser(fonts)
    elseif key == "down" then
        xmb.current_item_idx = math.min(#browser.files, xmb.current_item_idx + 1)
        xmb.list_marquee_offset = 0
        xmb.list_marquee_timer = 0
    elseif key == "up" then
        xmb.current_item_idx = math.max(1, xmb.current_item_idx - 1)
        xmb.list_marquee_offset = 0
        xmb.list_marquee_timer = 0
    elseif key == "return" or key == "enter" or key == "a" then
        local selected = browser.files[xmb.current_item_idx]
        if selected and selected.type ~= "info" then
            if selected.type == "directory" then
                browser.current_dir = selected.path
                browser.scan()
                xmb.current_item_idx = 1
                prep_files(fonts)
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
            end
        end
    elseif key == "backspace" or key == "b" then
        if browser.current_dir ~= browser.base_dir then
            browser.current_dir = browser.current_dir:match("(.*)/")
            if not browser.current_dir or browser.current_dir == "" then browser.current_dir = "/" end
            browser.scan()
            xmb.current_item_idx = 1
            prep_files(fonts)
        end
    end
end

return xmb
