local assets = require("assets")
local viewer = require("image_viewer")
local ui = require("ui")
local viewport = require("viewport")
local utils = require("utils")

local image_view = {}

function image_view.draw()
    if not viewer.active then return end

    local w, h = viewport.get()

    -- Black background
    love.graphics.setColor(0, 0, 0, viewer.fade_alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if viewer.current_image then
        love.graphics.setColor(1, 1, 1, viewer.fade_alpha)
        local img_w, img_h = viewer.current_image:getDimensions()
        love.graphics.draw(viewer.current_image, viewer.pan_x, viewer.pan_y, viewer.rotation, viewer.zoom, viewer.zoom,
            img_w / 2, img_h / 2)
    else
        --love.graphics.setColor(1, 1, 1, viewer.fade_alpha)
        --ui.printf_text("No image loaded", 0, h / 2, w, "center", assets.fonts.xs, { 1, 1, 1, viewer.fade_alpha })
    end

    -- Filename Footer with smooth fade in/out animation
    if viewer.info_alpha and viewer.info_alpha > 0 and #viewer.playlist > 0 and viewer.playlist[viewer.current_index] then
        local alpha = viewer.info_alpha * viewer.fade_alpha
        local item = viewer.playlist[viewer.current_index]

        love.graphics.setColor(0, 0, 0, 0.4 * alpha)
        love.graphics.rectangle("fill", 0, h - 50, w, 50)

        love.graphics.setColor(1, 1, 1, 0.8 * alpha)
        local prefix = string.format("[%d/%d] ", viewer.current_index, #viewer.playlist)
        local max_w = w - 40
        local name_w = max_w - ui.measure_text_width(assets.fonts.xs, prefix)
        if name_w < 20 then name_w = math.max(0, max_w - 20) end
        local display_name = utils.truncate_text(item.name, assets.fonts.xs, name_w)
        local info_str = prefix .. display_name
        ui.printf_text(info_str, 20, h - 35, w - 40, "left", assets.fonts.xs, { 1, 1, 1, 0.8 * alpha })
    end

    -- Photo Info Popup on the top-right of the screen with smooth fade in/out animation
    if viewer.details_alpha and viewer.details_alpha > 0 and viewer.photo_props then
        local alpha = viewer.details_alpha * viewer.fade_alpha
        local props = viewer.photo_props
        local panel_w = math.min(w - 30, 280)
        local panel_h = 210
        local margin = 15
        local px = w - panel_w - margin
        local py = margin

        -- Dark semi-transparent panel with subtle rounded border
        love.graphics.setColor(0.06, 0.07, 0.10, 0.88 * alpha)
        love.graphics.rectangle("fill", px, py, panel_w, panel_h, 8, 8)

        love.graphics.setColor(1, 1, 1, 0.15 * alpha)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", px, py, panel_w, panel_h, 8, 8)

        love.graphics.setColor(1, 1, 1, 0.95 * alpha)
        ui.print_text("Properties", px + 15, py + 8, assets.fonts.small, { 1, 1, 1, alpha })

        love.graphics.setColor(0.5, 0.5, 0.5, 0.35 * alpha)
        love.graphics.rectangle("fill", px + 12, py + 42, panel_w - 24, 1)

        -- Property rows
        local rx = px + 12
        local val_x = px + 128
        local max_val_w = panel_w - 120
        local ry = py + 50
        local row_h = 30

        local fields = {
            { label = "Resolution",  val = props.resolution },
            { label = "Megapixels",  val = props.megapixels or "N/A" },
            { label = "Size",        val = props.size },
            { label = "Format",      val = props.format },
            { label = "Orientation", val = props.orientation }
        }

        for _, field in ipairs(fields) do
            love.graphics.setColor(0.7, 0.75, 0.8, 0.8 * alpha)
            ui.print_text(field.label .. ":", rx, ry, assets.fonts.xs, { 0.7, 0.75, 0.8, alpha })

            love.graphics.setColor(1, 1, 1, 0.8 * alpha)
            local val_str = utils.truncate_text(field.val, assets.fonts.xs, max_val_w)
            ui.print_text(val_str, val_x, ry, assets.fonts.xs, { 1, 1, 1, alpha })

            ry = ry + row_h
        end
    end

    -- Thin vertical Zoom Progress Bar (bottom right above footer and under properties popup)
    if viewer.zoom_bar_alpha and viewer.zoom_bar_alpha > 0 then
        local alpha = viewer.zoom_bar_alpha * viewer.fade_alpha
        local bar_w = 8
        local bar_h = 100
        local margin_r = 25
        local bx = w - margin_r - bar_w
        local by = h - 65 - bar_h

        -- Dark capsule background
        love.graphics.setColor(0.06, 0.07, 0.10, 0.85 * alpha)
        love.graphics.rectangle("fill", bx, by, bar_w, bar_h, 4, 4)

        love.graphics.setColor(1, 1, 1, 0.15 * alpha)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", bx, by, bar_w, bar_h, 4, 4)

        -- Center marker notch for default fit-to-screen zoom (step 0)
        local min_s = viewer.min_step or -6
        local max_s = viewer.max_step or 12
        local inner_h = bar_h - 4
        local fit_ratio = (0 - min_s) / math.max(1, max_s - min_s)
        local center_y = (by + bar_h - 2) - math.floor(fit_ratio * inner_h)

        love.graphics.setColor(1, 1, 1, 0.6 * alpha)
        love.graphics.rectangle("fill", bx - 2, center_y, bar_w + 2, 2)

        -- Progress Fill (smooth lerped step: step 0 aligns with notch)
        local step = viewer.animated_step or viewer.zoom_step or 0
        local ratio = (step - min_s) / math.max(1, max_s - min_s)
        ratio = math.max(0, math.min(1, ratio))

        local fill_h = math.max(4, math.floor(ratio * inner_h))
        local fill_y = (by + bar_h - 2) - fill_h

        love.graphics.setColor(0.2, 0.6, 1.0, 0.9 * alpha)
        love.graphics.rectangle("fill", bx + 2, fill_y, bar_w - 4, fill_h, 2, 2)
    end

    -- ─── Center Loading Photo Popup ───
    if viewer.is_loading then
        local theme = require("theme")
        local box_w = 220
        local box_h = 60
        local bx = (w - box_w) / 2
        local by = (h - box_h) / 2

        -- Dark semi-transparent backdrop panel
        love.graphics.setColor(0.06, 0.07, 0.10, 0.94)
        love.graphics.rectangle("fill", bx, by, box_w, box_h, 10, 10)

        -- Glowing theme accent border
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.7)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", bx, by, box_w, box_h, 10, 10)

        -- Static "Loading Photo..." text
        ui.printf_text("Loading Photo...", bx, by + 16, box_w, "center", assets.fonts.small, { 1, 1, 1, 1 })
    end
end

function image_view.keypressed(key)
    if not viewer.active then return false end

    if key == "space" then
        viewer.close()
        return true
    end

    if key == "e" or key == "r2" or key == "tab" then
        viewer.show_details = not viewer.show_details
        return true
    end

    if key == "a" or key == "return" then
        viewer.reset_view()
        return true
    elseif key == "x" then
        viewer.change_zoom_step(1)
        return true
    elseif key == "b" or key == "backspace" then
        viewer.change_zoom_step(-1)
        return true
    elseif key == "y" then
        viewer.target_rotation = (viewer.target_rotation + math.pi / 2) % (2 * math.pi)
        return true
    elseif key == "z" then
        viewer.show_info = not viewer.show_info
        return true
    elseif key == "pageup" then
        viewer.prev_image()
        return true
    elseif key == "pagedown" then
        viewer.next_image()
        return true
    end

    return false
end

return image_view
