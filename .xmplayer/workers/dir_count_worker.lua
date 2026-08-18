-- dir_count_worker.lua
-- Background thread worker for non-blocking directory media count precomputation

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

local in_channel = love.thread.getChannel(in_channel_name or "dir_count_in")
local out_channel = love.thread.getChannel(out_channel_name or "dir_count_out")

local function get_dirname(path)
    if not path or type(path) ~= "string" then return "" end
    local dir = path:match("(.*)/[^/]+$")
    return dir or ""
end

local function normalize_path(p)
    if not p then return "" end
    p = p:gsub("\\", "/"):gsub("/+", "/")
    if p:sub(-1) == "/" and #p > 1 then p = p:sub(1, -2) end
    return p
end

local function scan_dir_recursive(dir, exts)
    dir = normalize_path(dir)
    local files_list = {}
    if not exts or #exts == 0 then return files_list end

    local pattern_parts = {}
    for _, ext in ipairs(exts) do
        local e = ext:sub(2)
        table.insert(pattern_parts, "-name '*." .. e:lower() .. "'")
        table.insert(pattern_parts, "-name '*." .. e:upper() .. "'")
    end
    local cmd = [[find "]] .. dir .. [[" -type f \( ]] .. table.concat(pattern_parts, " -o ") .. [[ \) 2>/dev/null]]

    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            table.insert(files_list, normalize_path(line))
        end
        handle:close()
    end
    return files_list
end

while true do
    local msg = in_channel:pop()
    if msg then
        if msg.type == "compute_counts" then
            local current_dir = msg.current_dir
            local media_type = msg.media_type
            local exts = msg.exts
            local files_list = msg.files_list
            local key = msg.key

            if not files_list or #files_list == 0 then
                if current_dir and exts and #exts > 0 then
                    files_list = scan_dir_recursive(current_dir, exts)
                else
                    files_list = {}
                end
            end

            local dir_counts = {}
            for _, path in ipairs(files_list) do
                local parent = get_dirname(path)
                while parent and parent ~= "" do
                    local norm_parent = normalize_path(parent)
                    dir_counts[norm_parent] = (dir_counts[norm_parent] or 0) + 1
                    local next_parent = get_dirname(norm_parent)
                    if next_parent == norm_parent or norm_parent == "/" then
                        break
                    end
                    parent = next_parent
                end
            end

            out_channel:push({
                type = "dir_count_result",
                current_dir = current_dir,
                media_type = media_type,
                counts = dir_counts,
                key = key
            })
        elseif msg.type == "stop" then
            break
        end
    else
        love.timer.sleep(0.01)
    end
end
