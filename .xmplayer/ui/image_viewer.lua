local viewer = {}
local viewport = require("viewport")

viewer.active = false
viewer.current_image = nil
viewer.current_path = ""
viewer.playlist = {}
viewer.current_index = 1

viewer.zoom = 1.0
viewer.target_zoom = 1.0
viewer.zoom_step = 0
viewer.animated_step = 0
viewer.min_step = -5
viewer.max_step = 10
viewer.min_zoom = 0.1
viewer.max_zoom = 10.0
viewer.rotation = 0
viewer.target_rotation = 0
viewer.show_info = true
viewer.show_details = false -- Info popup view (hidden by default)
viewer.info_alpha = 1.0
viewer.details_alpha = 0.0
viewer.zoom_bar_timer = 0
viewer.zoom_bar_alpha = 0.0
viewer.photo_props = nil
viewer.pan_x = 0
viewer.pan_y = 0
viewer.fade_alpha = 0

-- Loading state for popup feedback
viewer.is_loading = false
viewer.loading_alpha = 0.0
viewer.pending_load_path = nil
viewer.loading_frames = 0

-- Controls
local pan_speed = 400

function viewer.init()
    -- Subsystem init happens in assets.load()
end

function viewer.show_loading_and_load(path)
    viewer.is_loading = true
    viewer.current_path = path

    local ok, image_view = pcall(require, "image_view")
    if ok and image_view and image_view.draw then
        local simpleScale = _G.simpleScale
        local theme = pcall(require, "theme") and require("theme") or nil
        if simpleScale and simpleScale.set then
            simpleScale.set()
        end
        love.graphics.clear(0, 0, 0, 1)
        image_view.draw()
        if simpleScale and simpleScale.unSet then
            simpleScale.unSet(theme and theme.colors and theme.colors.background)
        end
        love.graphics.present()
    end

    viewer.load_image(path)
    viewer.is_loading = false
end

function viewer.open(path, files_list)
    viewer.active = true
    viewer.fade_alpha = 1.0
    viewer.current_path = path

    -- Build playlist from the provided files_list (from browser)
    viewer.playlist = {}
    local valid_exts = { jpg = true, jpeg = true, png = true, bmp = true, tga = true }
    for _, file in ipairs(files_list or {}) do
        if file.type == "file" then
            local ext = file.path:match("%.([^%.]+)$")
            if ext and valid_exts[ext:lower()] then
                table.insert(viewer.playlist, file)
            end
        end
    end

    -- Find current index
    viewer.current_index = 1
    for i, item in ipairs(viewer.playlist) do
        if item.path == path then
            viewer.current_index = i
            break
        end
    end

    viewer.show_loading_and_load(path)
end

function viewer.load_image(path)
    if viewer.current_image then
        pcall(function() viewer.current_image:release() end)
        viewer.current_image = nil
    end
    collectgarbage("collect")

    local file_handle = io.open(path, "rb")
    if not file_handle then
        viewer.photo_props = nil
        return false
    end

    local size = file_handle:seek("end")
    if size and size > 50 * 1024 * 1024 then
        file_handle:close()
        viewer.photo_props = nil
        return false
    end
    file_handle:seek("set", 0)

    local file_data_raw = file_handle:read("*a")
    file_handle:close()

    if not file_data_raw or #file_data_raw == 0 then
        viewer.photo_props = nil
        return false
    end

    local fd, id, img
    local ok, result = pcall(function()
        local filename = path:match("([^/]+)$") or "image"
        fd = love.filesystem.newFileData(file_data_raw, filename)
        file_data_raw = nil

        id = love.image.newImageData(fd)
        fd:release()
        fd = nil

        local w, h = id:getDimensions()
        local max_texture_size = 4096
        if love.graphics and love.graphics.getSystemLimit then
            local ok_limit, val = pcall(love.graphics.getSystemLimit, "texturesize")
            if ok_limit and val and val > 0 then
                max_texture_size = val
            end
        end
        local settings = require("settings")
        local configured_limit = settings.max_texture_size or 2048
        local limit = math.min(max_texture_size, configured_limit)

        if w > limit or h > limit then
            local scale = limit / math.max(w, h)
            local tw, th = math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))

            local ffi_ok, ffi = pcall(require, "ffi")
            if ffi_ok and id.getFFIPointer then
                local ptr = ffi.cast("uint32_t*", id:getFFIPointer())
                local scaled_id = love.image.newImageData(tw, th)
                local s_ptr = ffi.cast("uint32_t*", scaled_id:getFFIPointer())

                local x_ratio = math.floor((w * 65536) / tw)
                local y_ratio = math.floor((h * 65536) / th)

                for y = 0, th - 1 do
                    local sy = math.floor(y * y_ratio / 65536)
                    if sy >= h then sy = h - 1 end
                    local src_row = sy * w
                    local dst_row = y * tw
                    for x = 0, tw - 1 do
                        local sx = math.floor(x * x_ratio / 65536)
                        if sx >= w then sx = w - 1 end
                        s_ptr[dst_row + x] = ptr[src_row + sx]
                    end
                end
                id:release()
                id = scaled_id
            else
                local scaled_id = love.image.newImageData(tw, th)
                local scale_x = tw / w
                local scale_y = th / h
                for y = 0, th - 1 do
                    local sy = math.min(h - 1, math.floor(y / scale_y))
                    for x = 0, tw - 1 do
                        local sx = math.min(w - 1, math.floor(x / scale_x))
                        local r, g, b, a = id:getPixel(sx, sy)
                        scaled_id:setPixel(x, y, r, g, b, a)
                    end
                end
                id:release()
                id = scaled_id
            end
        end

        img = love.graphics.newImage(id)
        id:release()
        id = nil
        return img
    end)

    if fd then pcall(function() fd:release() end) end
    if id then pcall(function() id:release() end) end

    if ok and img then
        viewer.current_image = img

        -- Parse EXIF orientation for correction rotation
        local utils = require("utils")
        local orientation = utils.get_jpeg_orientation(path)
        local initial_rot = 0
        local orient_str = "Normal (0°)"
        if orientation == 3 then
            initial_rot = math.pi
            orient_str = "180°"
        elseif orientation == 6 then
            initial_rot = math.pi / 2
            orient_str = "90° CW"
        elseif orientation == 8 then
            initial_rot = 3 * math.pi / 2
            orient_str = "270° CW"
        end
        viewer.exif_rotation = initial_rot
        viewer.target_rotation = initial_rot

        local img_w, img_h = img:getDimensions()
        local ext = path:match("%.([^%.]+)$") or "image"
        local mp = (img_w * img_h) / 1000000
        local mp_str = string.format("%.1f MP", mp)
        viewer.photo_props = {
            path = path,
            resolution = string.format("%d × %d", img_w, img_h),
            megapixels = mp_str,
            size = utils.format_size(size or 0),
            format = ext:upper(),
            orientation = orient_str
        }

        viewer.reset_view(true)
    else
        print("Failed to load image: " .. tostring(result or "unknown error"))
        if viewer.current_image then
            viewer.current_image:release()
        end
        viewer.current_image = nil
        viewer.photo_props = nil
    end

    if id then id:release() end
    if fd then fd:release() end
end

function viewer.reset_view(snap)
    if not viewer.current_image then return end

    viewer.target_rotation = viewer.exif_rotation or 0

    local w, h = viewport.get()
    local img_w, img_h = viewer.current_image:getDimensions()

    local rot_90_count = math.floor(math.abs(viewer.target_rotation / (math.pi / 2)) + 0.5)
    local eff_w, eff_h = img_w, img_h
    if rot_90_count % 2 == 1 then
        eff_w, eff_h = img_h, img_w
    end

    local scale_w = w / eff_w
    local scale_h = h / eff_h
    local target = math.min(scale_w, scale_h)

    local zoom_speed = 1.25
    viewer.fit_zoom = target
    viewer.zoom_step = 0
    viewer.animated_step = 0
    viewer.min_step = -6
    viewer.max_step = 12

    viewer.min_zoom = target * (zoom_speed ^ viewer.min_step)
    viewer.max_zoom = target * (zoom_speed ^ viewer.max_step)

    viewer.target_zoom = target
    if snap then
        viewer.zoom = target
        viewer.rotation = viewer.target_rotation
    end

    -- Center the image
    viewer.pan_x = w / 2
    viewer.pan_y = h / 2
end

function viewer.show_zoom_bar()
    viewer.zoom_bar_timer = 1.5
end

function viewer.change_zoom_step(dir)
    local zoom_speed = 1.25
    local min_s = viewer.min_step or -6
    local max_s = viewer.max_step or 12
    local new_step = math.max(min_s, math.min(max_s, (viewer.zoom_step or 0) + dir))
    if new_step ~= viewer.zoom_step then
        viewer.zoom_step = new_step
        viewer.target_zoom = (viewer.fit_zoom or 1.0) * (zoom_speed ^ new_step)
        viewer.show_zoom_bar()
    end
end

function viewer.next_image()
    if #viewer.playlist == 0 then return end
    viewer.current_index = viewer.current_index + 1
    if viewer.current_index > #viewer.playlist then
        viewer.current_index = 1
    end
    viewer.show_loading_and_load(viewer.playlist[viewer.current_index].path)
end

function viewer.prev_image()
    if #viewer.playlist == 0 then return end
    viewer.current_index = viewer.current_index - 1
    if viewer.current_index < 1 then
        viewer.current_index = #viewer.playlist
    end
    viewer.show_loading_and_load(viewer.playlist[viewer.current_index].path)
end

function viewer.close()
    viewer.active = false
    viewer.is_loading = false
    if viewer.current_image then
        viewer.current_image:release()
    end
    viewer.current_image = nil
    viewer.photo_props = nil
end

function viewer.update(dt)
    if not viewer.active then return end

    if viewer.fade_alpha < 1 then
        viewer.fade_alpha = math.min(1, viewer.fade_alpha + dt * 4)
    end

    -- Smooth fade in/out lerp for filename footer
    local target_info_alpha = viewer.show_info and 1.0 or 0.0
    if viewer.info_alpha ~= target_info_alpha then
        local lerp = 1 - math.exp(-12 * dt)
        viewer.info_alpha = viewer.info_alpha + (target_info_alpha - viewer.info_alpha) * lerp
        if math.abs(viewer.info_alpha - target_info_alpha) < 0.001 then
            viewer.info_alpha = target_info_alpha
        end
    end

    -- Smooth fade in/out lerp for photo properties popup
    local target_details_alpha = viewer.show_details and 1.0 or 0.0
    if viewer.details_alpha ~= target_details_alpha then
        local lerp = 1 - math.exp(-12 * dt)
        viewer.details_alpha = viewer.details_alpha + (target_details_alpha - viewer.details_alpha) * lerp
        if math.abs(viewer.details_alpha - target_details_alpha) < 0.001 then
            viewer.details_alpha = target_details_alpha
        end
    end

    -- Smooth fade in/out lerp for zoom progress bar popup
    if viewer.zoom_bar_timer > 0 then
        viewer.zoom_bar_timer = math.max(0, viewer.zoom_bar_timer - dt)
    end
    local target_zoom_bar_alpha = (viewer.zoom_bar_timer > 0) and 1.0 or 0.0
    if viewer.zoom_bar_alpha ~= target_zoom_bar_alpha then
        local lerp = 1 - math.exp(-10 * dt)
        viewer.zoom_bar_alpha = viewer.zoom_bar_alpha + (target_zoom_bar_alpha - viewer.zoom_bar_alpha) * lerp
        if math.abs(viewer.zoom_bar_alpha - target_zoom_bar_alpha) < 0.001 then
            viewer.zoom_bar_alpha = target_zoom_bar_alpha
        end
    end

    if viewer.animated_step ~= viewer.zoom_step then
        local lerp = 1 - math.exp(-10 * dt)
        viewer.animated_step = viewer.animated_step + (viewer.zoom_step - viewer.animated_step) * lerp
        if math.abs(viewer.animated_step - viewer.zoom_step) < 0.001 then
            viewer.animated_step = viewer.zoom_step
        end
    end

    if viewer.zoom ~= viewer.target_zoom then
        local old_zoom = viewer.zoom
        local lerp_factor = 1 - math.exp(-10 * dt)
        local new_zoom = viewer.zoom + (viewer.target_zoom - viewer.zoom) * lerp_factor
        if math.abs(new_zoom - viewer.target_zoom) < 0.0001 then
            new_zoom = viewer.target_zoom
        end

        local w, h = viewport.get()
        local sx, sy = w / 2, h / 2
        local scale_ratio = new_zoom / old_zoom

        viewer.pan_x = sx - scale_ratio * (sx - viewer.pan_x)
        viewer.pan_y = sy - scale_ratio * (sy - viewer.pan_y)
        viewer.zoom = new_zoom
    end

    if viewer.rotation ~= viewer.target_rotation then
        local diff = viewer.target_rotation - viewer.rotation
        diff = (diff + math.pi) % (2 * math.pi) - math.pi

        local lerp_factor = 1 - math.exp(-10 * dt)
        viewer.rotation = viewer.rotation + diff * lerp_factor
        viewer.rotation = viewer.rotation % (2 * math.pi)

        if math.abs(diff) < 0.0001 then
            viewer.rotation = viewer.target_rotation
        end
    end

    if viewer.current_image then
        local w, h = viewport.get()
        local img_w, img_h = viewer.current_image:getDimensions()

        -- Check target rotation to determine effective width and height
        local rot_90_count = math.floor(math.abs(viewer.target_rotation / (math.pi / 2)) + 0.5)
        local eff_w, eff_h = img_w, img_h
        if rot_90_count % 2 == 1 then
            eff_w, eff_h = img_h, img_w
        end

        if love.keyboard.isDown("up") then viewer.pan_y = viewer.pan_y + pan_speed * dt end
        if love.keyboard.isDown("down") then viewer.pan_y = viewer.pan_y - pan_speed * dt end
        if love.keyboard.isDown("left") then viewer.pan_x = viewer.pan_x + pan_speed * dt end
        if love.keyboard.isDown("right") then viewer.pan_x = viewer.pan_x - pan_speed * dt end

        -- Clamp pan positions to borders
        local half_img_w = (eff_w / 2) * viewer.zoom
        local min_x, max_x
        if eff_w * viewer.zoom > w then
            min_x = w - half_img_w
            max_x = half_img_w
        else
            min_x = half_img_w
            max_x = w - half_img_w
        end
        viewer.pan_x = math.max(min_x, math.min(max_x, viewer.pan_x))

        local half_img_h = (eff_h / 2) * viewer.zoom
        local min_y, max_y
        if eff_h * viewer.zoom > h then
            min_y = h - half_img_h
            max_y = half_img_h
        else
            min_y = half_img_h
            max_y = h - half_img_h
        end
        viewer.pan_y = math.max(min_y, math.min(max_y, viewer.pan_y))
    end
end

return viewer
