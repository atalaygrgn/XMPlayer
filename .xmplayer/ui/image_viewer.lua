local viewer = {}
local viewport = require("viewport")

viewer.active = false
viewer.current_image = nil
viewer.current_path = ""
viewer.playlist = {}
viewer.current_index = 1

viewer.zoom = 1.0
viewer.target_zoom = 1.0
viewer.rotation = 0
viewer.target_rotation = 0
viewer.show_info = true
viewer.pan_x = 0
viewer.pan_y = 0
viewer.fade_alpha = 0

-- Controls
local pan_speed = 400

function viewer.init()
    -- Subsystem init happens in assets.load()
end

function viewer.open(path, files_list)
    viewer.active = true
    viewer.fade_alpha = 0
    viewer.current_path = path
    
    -- Build playlist from the provided files_list (from browser)
    viewer.playlist = {}
    local valid_exts = {jpg=true, jpeg=true, png=true, bmp=true, tga=true}
    for _, file in ipairs(files_list) do
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
    
    viewer.load_image(path)
end

function viewer.load_image(path)
    local file_handle = io.open(path, "rb")
    if not file_handle then
        viewer.current_image = nil
        return false
    end

    local file_data_raw = file_handle:read("*a")
    file_handle:close()

    if not file_data_raw or #file_data_raw == 0 then
        viewer.current_image = nil
        return false
    end

    local ok, result = pcall(function()
        local filename = path:match("([^/]+)$") or "image"
        local fd = love.filesystem.newFileData(file_data_raw, filename)
        local id = love.image.newImageData(fd)
        return love.graphics.newImage(id)
    end)
    
    if ok then
        viewer.current_image = result
        viewer.reset_view(true)
    else
        print("Failed to load image: " .. tostring(result))
        viewer.current_image = nil
    end
end

function viewer.reset_view(snap)
    if not viewer.current_image then return end
    
    local w, h = viewport.get()
    local img_w, img_h = viewer.current_image:getDimensions()
    
    local scale_w = w / img_w
    local scale_h = h / img_h
    local target = math.min(scale_w, scale_h)
    
    viewer.target_zoom = target
    viewer.target_rotation = 0
    if snap then
        viewer.zoom = target
        viewer.rotation = 0
    end
    
    -- Center the image
    viewer.pan_x = w / 2
    viewer.pan_y = h / 2
end

function viewer.next_image()
    if #viewer.playlist == 0 then return end
    viewer.current_index = viewer.current_index + 1
    if viewer.current_index > #viewer.playlist then
        viewer.current_index = 1
    end
    viewer.load_image(viewer.playlist[viewer.current_index].path)
end

function viewer.prev_image()
    if #viewer.playlist == 0 then return end
    viewer.current_index = viewer.current_index - 1
    if viewer.current_index < 1 then
        viewer.current_index = #viewer.playlist
    end
    viewer.load_image(viewer.playlist[viewer.current_index].path)
end

function viewer.close()
    viewer.active = false
    viewer.current_image = nil
end

function viewer.update(dt)
    if not viewer.active then return end
    
    if viewer.fade_alpha < 1 then
        viewer.fade_alpha = math.min(1, viewer.fade_alpha + dt * 4)
    end
    
    if viewer.zoom ~= viewer.target_zoom then
        local lerp_factor = 1 - math.exp(-10 * dt)
        viewer.zoom = viewer.zoom + (viewer.target_zoom - viewer.zoom) * lerp_factor
        if math.abs(viewer.zoom - viewer.target_zoom) < 0.0001 then
            viewer.zoom = viewer.target_zoom
        end
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
