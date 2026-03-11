local viewer = {}

viewer.active = false
viewer.current_image = nil
viewer.current_path = ""
viewer.playlist = {}
viewer.current_index = 1

viewer.zoom = 1.0
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
        viewer.reset_view()
    else
        print("Failed to load image: " .. tostring(result))
        viewer.current_image = nil
    end
end

function viewer.reset_view()
    if not viewer.current_image then return end
    
    local w, h = love.graphics.getDimensions()
    local img_w, img_h = viewer.current_image:getDimensions()
    
    local scale_w = w / img_w
    local scale_h = h / img_h
    viewer.zoom = math.min(scale_w, scale_h)
    
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
    
    if love.keyboard.isDown("y") then
        if love.keyboard.isDown("up") then viewer.pan_y = viewer.pan_y + pan_speed * dt end
        if love.keyboard.isDown("down") then viewer.pan_y = viewer.pan_y - pan_speed * dt end
        if love.keyboard.isDown("left") then viewer.pan_x = viewer.pan_x + pan_speed * dt end
        if love.keyboard.isDown("right") then viewer.pan_x = viewer.pan_x - pan_speed * dt end
    end
end

return viewer
