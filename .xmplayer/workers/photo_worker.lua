-- photo_worker.lua
-- Pure CPU background thread worker (0% GPU stalls, 0% glReadPixels, 0% audio buffer starvation)

local in_channel_name = ...
local out_channel_name = select(2, ...)

require("love.timer")
require("love.thread")
require("love.filesystem")
require("love.image")

local source_path = love.filesystem and love.filesystem.getSource and love.filesystem.getSource() or "."
package.path = source_path .. "/?.lua;"
    .. source_path .. "/data/?.lua;"
    .. source_path .. "/core/?.lua;"
    .. source_path .. "/systems/?.lua;"
    .. source_path .. "/workers/?.lua;"
    .. source_path .. "/.xmplayer/?.lua;"
    .. source_path .. "/.xmplayer/data/?.lua;"
    .. source_path .. "/.xmplayer/core/?.lua;"
    .. source_path .. "/.xmplayer/systems/?.lua;"
    .. source_path .. "/.xmplayer/workers/?.lua;"
    .. package.path

local ok, utils = pcall(require, "utils")
if not ok or not utils then
    ok, utils = pcall(require, "core.utils")
end

local in_channel = love.thread.getChannel(in_channel_name or "photo_in")
local out_channel = love.thread.getChannel(out_channel_name or "photo_out")

local function ensure_thumb_dir(thumb_dir)
    if os.execute("test -d \"" .. thumb_dir .. "\"") ~= 0 then
        os.execute("mkdir -p \"" .. thumb_dir .. "\"")
    end
end

local function scale_image_data_cpu(img_data, target_size)
    local w, h = img_data:getDimensions()
    if not w or not h or w <= 0 or h <= 0 then return nil end
    local scale = target_size / math.max(w, h)
    if scale >= 1 then return nil end

    local tw, th = math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))
    local scaled_id = love.image.newImageData(tw, th)
    for y = 0, th - 1 do
        local sy = math.floor(y / scale)
        if sy >= h then sy = h - 1 end
        for x = 0, tw - 1 do
            local sx = math.floor(x / scale)
            if sx >= w then sx = w - 1 end
            local r, g, b, a = img_data:getPixel(sx, sy)
            scaled_id:setPixel(x, y, r, g, b, a)
        end
    end
    return scaled_id
end

local function process_photo(image_path, thumb_dir)
    local ext = image_path:match("%.([^%.]+)$")
    local orientation = 1
    local safe_name = image_path:gsub("[^%w]", "_")

    local f_chk = io.open(image_path, "rb")
    if f_chk then
        local sz = f_chk:seek("end")
        f_chk:close()
        if sz and sz > 5 * 1024 * 1024 then
            return image_path, orientation
        end
    end

    if ext and (ext:lower() == "jpg" or ext:lower() == "jpeg") and utils and utils.get_jpeg_metadata then
        local parsed_orientation, thumb_bytes = utils.get_jpeg_metadata(image_path, true)
        orientation = parsed_orientation or 1
        if thumb_bytes and #thumb_bytes > 100 and thumb_bytes:byte(1) == 0xFF and thumb_bytes:byte(2) == 0xD8 then
            local thumb_path = thumb_dir .. "/" .. safe_name .. ".jpg"
            ensure_thumb_dir(thumb_dir)
            local f = io.open(thumb_path, "wb")
            if f then
                f:write(thumb_bytes)
                f:close()
                return thumb_path, orientation
            end
        end
    end

    local ok, img_data = pcall(love.image.newImageData, image_path)
    if not ok or not img_data then
        local f = io.open(image_path, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data then
                local file_data = love.filesystem.newFileData(data, "temp_img")
                ok, img_data = pcall(love.image.newImageData, file_data)
                file_data:release()
            end
        end
    end

    if not ok or not img_data then
        return nil, orientation
    end

    local final_thumb_path = image_path
    local scaled_data = scale_image_data_cpu(img_data, 120)
    if scaled_data then
        local thumb_path = thumb_dir .. "/" .. safe_name .. ".png"
        ensure_thumb_dir(thumb_dir)
        local encoded = scaled_data:encode("png")
        if encoded then
            local f = io.open(thumb_path, "wb")
            if f then
                f:write(encoded:getString())
                f:close()
                final_thumb_path = thumb_path
            end
            encoded:release()
        end
        scaled_data:release()
    end

    img_data:release()
    return final_thumb_path, orientation
end

while true do
    local msg = in_channel:pop()
    if msg then
        if msg.type == "process_photo" then
            local thumb_path, orientation = process_photo(msg.path, msg.thumb_dir)
            out_channel:push({
                type = "photo_result",
                path = msg.path,
                thumb_path = thumb_path,
                orientation = orientation,
                id = msg.id
            })
        elseif msg.type == "stop" then
            break
        end
    else
        love.timer.sleep(0.005)
    end
end
