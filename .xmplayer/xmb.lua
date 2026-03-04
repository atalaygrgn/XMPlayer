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

local function lerp(a, b, t)
    return a + (b - a) * t
end

function xmb.refresh_browser()
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
end

function xmb.update(dt)
    -- Smooth scroll
    xmb.category_scroll_x = lerp(xmb.category_scroll_x, xmb.target_category_scroll_x, dt * 10)
    xmb.item_scroll_y = lerp(xmb.item_scroll_y, xmb.target_item_scroll_y, dt * 10)
    
    -- Categories are centered at 1/4 of screen width
    xmb.target_category_scroll_x = -(xmb.current_category_idx - 1) * (theme.icon_size + theme.icon_spacing)
    
    -- Items are centered vertically
    xmb.target_item_scroll_y = -(xmb.current_item_idx - 1) * 40
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
        
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(img, x, 0, 0, scale, scale, img:getWidth()/2, img:getHeight()/2)
        
        if is_focused then
            love.graphics.setFont(main_font)
            love.graphics.printf(cat.name, x - 100, theme.icon_size/2 + 15, 200, "center")
        end
    end
    love.graphics.pop()
    
    -- Draw Vertical Item List
    local list_x = cat_base_x
    local list_base_y = cat_y + theme.icon_size + 60
    
    love.graphics.push()
    love.graphics.translate(list_x, list_base_y + xmb.item_scroll_y)
    
    local list_icon_size = 32
    for i, item in ipairs(browser.files) do
        local y = (i - 1) * 45
        local is_focused = (i == xmb.current_item_idx)
        local alpha = is_focused and 1 or 0.5
        
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
        
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(icon, -45, y + 5, 0, icon_scale, icon_scale)
        
        -- Draw text
        love.graphics.setFont(is_focused and main_font or small_font)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.print(item.name, 0, y + (is_focused and 0 or 4))
    end
    love.graphics.pop()
end

function xmb.keypressed(key, player, music)
    if key == "right" then
        xmb.current_category_idx = (xmb.current_category_idx % #categories) + 1
        xmb.refresh_browser()
    elseif key == "left" then
        xmb.current_category_idx = (xmb.current_category_idx - 2 + #categories) % #categories + 1
        xmb.refresh_browser()
    elseif key == "down" then
        xmb.current_item_idx = math.min(#browser.files, xmb.current_item_idx + 1)
    elseif key == "up" then
        xmb.current_item_idx = math.max(1, xmb.current_item_idx - 1)
    elseif key == "return" or key == "enter" or key == "a" then
        local selected = browser.files[xmb.current_item_idx]
        if selected and selected.type ~= "info" then
            if selected.type == "directory" then
                browser.current_dir = selected.path
                browser.scan()
                xmb.current_item_idx = 1
            elseif selected.type == "file" then
                local cat_id = categories[xmb.current_category_idx].id
                if cat_id == "video" then
                    player.play(selected.path)
                elseif cat_id == "music" and music then
                    music.play(selected.path)
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
        end
    end
end

return xmb
