-- xmb_draw.lua
-- Renders the XMB category bar, vertical item list, and settings popup.
-- All navigation state is owned by xmb.lua; this module is read-only.

local xmb            = require("xmb")
local browser        = require("browser")
local categories     = require("categories")
local theme          = require("theme")
local assets         = require("assets")
local ui             = require("ui")
local settings_view  = require("settings_view")
local video_manager  = require("video_manager")
local indexing       = require("indexing")
local utils          = require("utils")

local xmb_draw = {}

function xmb_draw.draw()
    local screen_w, screen_h = love.graphics.getDimensions()

    -- ─── Horizontal Category Bar ───
    local cat_base_x = screen_w * 0.25
    local cat_y      = screen_h * 0.25

    love.graphics.push()
    love.graphics.translate(cat_base_x + xmb.category_scroll_x, cat_y)

    for i, cat in ipairs(categories) do
        local x          = (i - 1) * (theme.icon_size + theme.icon_spacing)
        local is_focused = (i == xmb.current_category_idx)

        local img        = assets.images["cat_" .. cat.id]
        local base_scale = theme.icon_size / img:getWidth()
        local scale      = is_focused and base_scale * 1.1 or base_scale * 0.7
        local alpha      = is_focused and 0.8 or 0.4

        if is_focused then
            ui.draw_glow_icon(img, x, 0, theme.icon_size * 1.1, theme.text, alpha)
            ui.draw_glow_text(cat.name, x - 100, theme.icon_size / 2 + 12, assets.fonts.main,
                { theme.text[1], theme.text[2], theme.text[3], alpha }, nil, 200, "center")
        else
            love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], alpha)
            love.graphics.draw(img, x, 0, 0, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
        end
    end
    love.graphics.pop()

    -- ─── Left Arrow Indicator (submenu back) ───
    if xmb.in_submenu() then
        local arrow_x = cat_base_x - 90
        local arrow_y = cat_y + theme.icon_size + 87
        local pulse   = 0.5 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], pulse)
        love.graphics.polygon("fill",
            arrow_x + 12, arrow_y,
            arrow_x + 24, arrow_y - 10,
            arrow_x + 24, arrow_y + 10)
    end

    -- ─── Vertical Item List ───
    local list_x      = cat_base_x + 32
    local list_base_y = cat_y + theme.icon_size + 75
    local fade_top    = cat_y + theme.icon_size / 2 + 50
    local fade_range  = 100

    love.graphics.setScissor(0, fade_top - 20, screen_w, screen_h - (fade_top - 20))
    love.graphics.push()
    love.graphics.translate(list_x + xmb.list_slide_x, list_base_y + xmb.item_scroll_y)

    local item_h = 75
    local first  = math.max(1, math.floor(-xmb.item_scroll_y / item_h) - 2)
    local last   = math.min(#browser.files, first + math.ceil(screen_h / item_h) + 4)
    local cat_id = categories[xmb.current_category_idx].id

    for i = first, last do
        local item     = browser.files[i]
        local y        = (i - 1) * item_h
        local screen_y = list_base_y + xmb.item_scroll_y + y

        local item_alpha = xmb.list_slide_alpha
        if screen_y < list_base_y then
            local dist = list_base_y - screen_y
            item_alpha = math.max(0, xmb.list_slide_alpha * (1.0 - (dist / fade_range)))
        end

        local is_focused  = (i == xmb.current_item_idx)
        local base_alpha  = is_focused and 0.8 or 0.5
        local final_alpha = base_alpha * item_alpha

        if final_alpha > 0 then
            -- Resolve icon
            local icon  = assets.images.folder
            local thumb = nil

            if item.type == "file" and (cat_id == "photo" or item.icon == "photo") then
                icon = assets.images.photo
                local info = indexing.data.photos[item.path]
                local thumb_path = (info and info.thumb_path) or item.path
                if thumb_path then
                    if not xmb.thumbs[thumb_path] then
                        xmb.thumbs[thumb_path] = utils.load_image(thumb_path)
                    end
                    thumb = xmb.thumbs[thumb_path]
                end
                if not thumb and item.path then
                    if not xmb.thumbs[item.path] then
                        xmb.thumbs[item.path] = utils.load_image(item.path)
                    end
                    thumb = xmb.thumbs[item.path]
                end
            elseif item.icon and assets.images[item.icon] then
                icon = assets.images[item.icon]
            elseif item.type == "directory" then
                icon = assets.images.folder
            elseif item.type == "album" then
                icon = assets.images.album
                local album = item.data
                local thumb_path = album and album.thumb_path
                if thumb_path and thumb_path ~= "" then
                    if not xmb.thumbs[thumb_path] then
                        xmb.thumbs[thumb_path] = utils.load_image(thumb_path)
                    end
                    thumb = xmb.thumbs[thumb_path]
                end
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
                else
                    icon = assets.images.file
                end
            end

            -- Draw icon
            if is_focused then
                -- local icon_y = item.description and (y + 24) or (y + 14)
                local icon_y = y + 14
                ui.draw_glow_icon(icon, -36, icon_y, 48, theme.text, final_alpha, theme.text, thumb)
            else
                ui.draw_icon(icon, -36, y + 14, 48, theme.text, final_alpha, thumb)
            end

            -- Watched overlay for video files
            if item.type == "file" and cat_id == "video" and video_manager.is_watched(item.path) then
                ui.draw_icon(assets.images.eye, -52, y, 36, { 1, 1, 1 }, 1)
            end

            -- Draw text
            if is_focused then
                if item.description then
                    ui.draw_marquee(xmb.item_marquee, item.name, 0, y - 8, assets.fonts.main,
                    { theme.text[1], theme.text[2], theme.text[3], final_alpha },
                    list_x + xmb.list_slide_x, screen_y - 8)
                else
                    ui.draw_marquee(xmb.item_marquee, item.name, 0, y, assets.fonts.main,
                    { theme.text[1], theme.text[2], theme.text[3], final_alpha },
                    list_x + xmb.list_slide_x, screen_y)
                end
                

                if item.description then
                    local desc_y = y + 24
                    local line_w = screen_w * 0.7
                    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], final_alpha * 0.3)
                    love.graphics.line(0, desc_y, line_w, desc_y)
                    love.graphics.setFont(assets.fonts.xs)
                    love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], final_alpha * 0.8)
                    love.graphics.print(item.description, 0, desc_y + 5)
                end
            else
                love.graphics.setFont(assets.fonts.small)
                love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], final_alpha)
                love.graphics.print(item.display_name or item.name, 0, y + 4)
            end
        end
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- ─── Settings Popup ───
    if settings_view.active or settings_view.alpha > 0 then
        local selected = browser.files[xmb.current_item_idx]
        if selected and selected.setting_idx then
            settings_view.draw_popup(selected.setting_idx)
        end
    end
    -- Draw compact folder picker if active
    if settings_view.picker_active or settings_view.picker_alpha > 0 then
        settings_view.draw_folder_picker()
    end

    -- ─── Context Menu Popup ───
    local menu = xmb.context_menu
    if menu and (menu.active or menu.alpha > 0) then
        local alpha = menu.alpha
        local panel_w = 300
        local panel_h = 80 + (#menu.items * 50)
        local panel_x = screen_w - panel_w - 20
        local panel_y = screen_h * 0.15

        love.graphics.setColor(0.05, 0.05, 0.08, 0.94 * alpha)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 16, 16)

        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.35 * alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 16, 16)

        love.graphics.setFont(assets.fonts.main)
        ui.draw_glow_text(menu.title or "Options", panel_x + 24, panel_y + 20, assets.fonts.main,
            { theme.text[1], theme.text[2], theme.text[3], alpha }, nil)

        love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.22 * alpha)
        love.graphics.rectangle("fill", panel_x + 22, panel_y + 64, panel_w - 44, 1)

        for i, option in ipairs(menu.items) do
            local row_y = panel_y + 82 + (i - 1) * 50
            local focused = (i == menu.selected_idx)

            if focused then
                love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.28 * alpha)
                love.graphics.rectangle("fill", panel_x + 18, row_y - 6, panel_w - 36, 40, 10, 10)
            end

            love.graphics.setFont(assets.fonts.small)
            if focused then
                ui.draw_glow_text(option.label, panel_x + 32, row_y, assets.fonts.small,
                    { theme.text[1], theme.text[2], theme.text[3], alpha }, nil)
            else
                love.graphics.setColor(theme.text[1], theme.text[2], theme.text[3], 0.75 * alpha)
                love.graphics.print(option.label, panel_x + 32, row_y)
            end
        end
    end
end

return xmb_draw
