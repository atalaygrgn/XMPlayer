-- list_thumb_worker.lua
-- Background worker thread for non-blocking list thumbnail loading & CPU image decoding

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

local in_channel = love.thread.getChannel(in_channel_name or "list_thumb_in")
local out_channel = love.thread.getChannel(out_channel_name or "list_thumb_out")

local function read_file_bytes(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function scale_down_image_data_cpu(img_data, target_size)
    if not img_data then return nil end
    local w, h = img_data:getDimensions()
    if not w or not h or w <= 0 or h <= 0 then return img_data end
    local scale = target_size / math.max(w, h)
    if scale >= 1 then return img_data end

    local tw, th = math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))
    local scaled_id = love.image.newImageData(tw, th)
    for y = 0, th - 1 do
        local sy = math.min(h - 1, math.floor(y / scale))
        for x = 0, tw - 1 do
            local sx = math.min(w - 1, math.floor(x / scale))
            local r, g, b, a = img_data:getPixel(sx, sy)
            scaled_id:setPixel(x, y, r, g, b, a)
        end
    end
    img_data:release()
    return scaled_id
end

local function process_thumb_request(msg)
    local path = msg.path
    local photo_path = msg.photo_path or msg.path
    local is_photo = msg.is_photo == true

    if not path or path == "" then
        return nil, 1
    end

    -- 1. Extract EXIF orientation from original photo path (if photo)
    local orientation = 1
    if is_photo and photo_path and utils and utils.get_jpeg_orientation then
        orientation = utils.get_jpeg_orientation(photo_path) or 1
    end

    -- 2. Try fast EXIF thumbnail extraction for JPEG photos
    local bytes = nil
    local ext = path:match("%.([^%.]+)$")
    if is_photo and ext and (ext:lower() == "jpg" or ext:lower() == "jpeg") and utils and utils.get_jpeg_metadata then
        local _, thumb_bytes = utils.get_jpeg_metadata(path, true)
        if thumb_bytes and #thumb_bytes > 100 and thumb_bytes:byte(1) == 0xFF and thumb_bytes:byte(2) == 0xD8 then
            bytes = thumb_bytes
        end
    end

    -- If no EXIF thumb, read target file bytes (skip files > 5MB to prevent RAM spikes)
    if not bytes then
        local f_chk = io.open(path, "rb")
        if f_chk then
            local sz = f_chk:seek("end")
            f_chk:close()
            if sz and sz > 5 * 1024 * 1024 then
                return nil, orientation
            end
        end
        bytes = read_file_bytes(path)
    end

    if not bytes or #bytes == 0 then
        return nil, orientation
    end

    -- 3. Perform CPU image decompression (newImageData) in worker thread to prevent main-thread lag
    local img_data = nil
    local ok_id, err_id = pcall(function()
        local fd = love.filesystem.newFileData(bytes, "thumb_temp")
        local id = love.image.newImageData(fd)
        fd:release()
        return id
    end)

    if ok_id and err_id then
        img_data = scale_down_image_data_cpu(err_id, 128)
    end

    return img_data, orientation
end

while true do
    local msg = in_channel:pop()
    if msg then
        if msg.type == "load_thumb" then
            local img_data, orientation = process_thumb_request(msg)
            out_channel:push({
                type = "thumb_result",
                key = msg.key,
                photo_path = msg.photo_path,
                img_data = img_data,
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
