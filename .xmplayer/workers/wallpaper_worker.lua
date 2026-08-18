-- wallpaper_worker.lua
-- Dedicated background worker thread for non-blocking wallpaper image loading and downscaling

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

local in_channel = love.thread.getChannel(in_channel_name or "wallpaper_in")
local out_channel = love.thread.getChannel(out_channel_name or "wallpaper_out")

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

while true do
    local msg = in_channel:pop()
    if msg then
        if msg.type == "load_wallpaper" then
            local path = msg.path or "assets/background/bg.jpg"
            local bytes = read_file_bytes(path)
            if not bytes and path ~= "assets/background/bg.jpg" then
                bytes = read_file_bytes("assets/background/bg.jpg")
            end
            local img_data = nil
            if bytes and #bytes > 0 then
                pcall(function()
                    local fd = love.filesystem.newFileData(bytes, "wallpaper_temp")
                    local id = love.image.newImageData(fd)
                    fd:release()
                    img_data = scale_down_image_data_cpu(id, 2048)
                end)
            end
            out_channel:push({
                type = "wallpaper_result",
                path = path,
                img_data = img_data
            })
        elseif msg.type == "stop" then
            break
        end
    else
        love.timer.sleep(0.01)
    end
end
