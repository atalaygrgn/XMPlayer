-- metadata_worker.lua
-- Background thread worker for accurate, fast batch metadata extraction

local in_channel_name = ...
local out_channel_name = select(2, ...)

require("love.timer")
require("love.thread")
require("love.filesystem")

local source_path = love.filesystem and love.filesystem.getSource and love.filesystem.getSource() or "."
package.path = source_path .. "/?.lua;"
            .. source_path .. "/data/?.lua;"
            .. source_path .. "/core/?.lua;"
            .. source_path .. "/systems/?.lua;"
            .. source_path .. "/.xmplayer/?.lua;"
            .. source_path .. "/.xmplayer/data/?.lua;"
            .. source_path .. "/.xmplayer/core/?.lua;"
            .. source_path .. "/.xmplayer/systems/?.lua;"
            .. package.path

local ok, metadata = pcall(require, "metadata")
if not ok or not metadata then
    ok, metadata = pcall(require, "data.metadata")
end

local in_channel = love.thread.getChannel(in_channel_name or "metadata_in")
local out_channel = love.thread.getChannel(out_channel_name or "metadata_out")

while true do
    local msg = in_channel:pop()
    if msg then
        if msg.type == "extract_file" then
            local path = msg.path
            local tags = {}
            if metadata and metadata.get_tags then
                tags = metadata.get_tags(path)
            end
            out_channel:push({
                type = "file_tags",
                path = path,
                tags = tags,
                id = msg.id
            })
        elseif msg.type == "stop" then
            break
        end
    else
        love.timer.sleep(0.005)
    end
end
