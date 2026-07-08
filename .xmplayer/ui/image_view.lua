local assets = require("assets")
local viewer = require("image_viewer")
local ui = require("ui")
local viewport = require("viewport")

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
        love.graphics.draw(viewer.current_image, viewer.pan_x, viewer.pan_y, viewer.rotation, viewer.zoom, viewer.zoom, img_w / 2, img_h / 2)
    else
        love.graphics.setColor(1, 1, 1, viewer.fade_alpha)
        ui.printf_text("No image loaded", 0, h / 2, w, "center", assets.fonts.xs, { 1, 1, 1, viewer.fade_alpha })
    end

    if viewer.show_info and #viewer.playlist > 0 and viewer.playlist[viewer.current_index] then
        local item = viewer.playlist[viewer.current_index]

        love.graphics.setColor(0, 0, 0, 0.4 * viewer.fade_alpha)
        love.graphics.rectangle("fill", 0, h - 50, w, 50)

        love.graphics.setColor(1, 1, 1, 0.8 * viewer.fade_alpha)
        local info_str = string.format("[%d/%d] %s", viewer.current_index, #viewer.playlist, item.name)
        ui.printf_text(info_str, 20, h - 35, w - 40, "left", assets.fonts.xs, { 1, 1, 1, 0.8 * viewer.fade_alpha })
    end
end

local zoom_speed = 1.2

function image_view.keypressed(key)
    if not viewer.active then return false end

    if key == "space" then
        viewer.close()
        return true
    end

    if key == "a" or key == "return" then
        viewer.reset_view()
        return true
    elseif key == "x" then
        viewer.target_zoom = viewer.target_zoom * zoom_speed
        return true
    elseif key == "b" or key == "backspace" then
        viewer.target_zoom = viewer.target_zoom / zoom_speed
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
