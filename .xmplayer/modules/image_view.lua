local assets = require("assets")
local viewer = require("image_viewer")

local image_view = {}

function image_view.draw()
    if not viewer.active then return end

    local w, h = love.graphics.getDimensions()

    -- Black background
    love.graphics.setColor(0, 0, 0, viewer.fade_alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if viewer.current_image then
        love.graphics.setColor(1, 1, 1, viewer.fade_alpha)
        local img_w, img_h = viewer.current_image:getDimensions()
        love.graphics.draw(viewer.current_image, viewer.pan_x, viewer.pan_y, 0, viewer.zoom, viewer.zoom, img_w / 2, img_h / 2)
    else
        love.graphics.setColor(1, 1, 1, viewer.fade_alpha)
        love.graphics.printf("No image loaded", 0, h / 2, w, "center")
    end

    if #viewer.playlist > 0 and viewer.playlist[viewer.current_index] then
        local item = viewer.playlist[viewer.current_index]

        love.graphics.setColor(0, 0, 0, 0.4 * viewer.fade_alpha)
        love.graphics.rectangle("fill", 0, h - 50, w, 50)

        love.graphics.setColor(1, 1, 1, 0.8 * viewer.fade_alpha)
        love.graphics.setFont(assets.fonts.xs)

        local info_str = string.format("[%d/%d] %s", viewer.current_index, #viewer.playlist, item.name)
        love.graphics.printf(info_str, 20, h - 35, w - 40, "left")
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
        viewer.zoom = viewer.zoom * zoom_speed
        return true
    elseif key == "b" or key == "backspace" then
        viewer.zoom = viewer.zoom / zoom_speed
        return true
    elseif not love.keyboard.isDown("y") then
        if key == "right" then
            viewer.next_image()
            return true
        elseif key == "left" then
            viewer.prev_image()
            return true
        end
    end

    return false
end

return image_view
