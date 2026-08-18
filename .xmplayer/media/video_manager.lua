local utils = require("utils")

local video_manager = {}
local storage_path = love.filesystem.getSource()
video_manager.watched_file = storage_path .. "/watched.cfg"
video_manager.watch_later_dir = storage_path .. "/config/mpv/watch_later"
video_manager.watched_data = {}

function video_manager.load_watched()
    local f = io.open(video_manager.watched_file, "r")
    if f then
        f:close()
        local chunk, err = loadfile(video_manager.watched_file)
        if chunk then
            local ok, data = pcall(chunk)
            if ok and type(data) == "table" then
                video_manager.watched_data = data
                return
            end
        end
    end
    video_manager.watched_data = {}
end

function video_manager.save_watched()
    local data_str = "return {\n"
    for path, _ in pairs(video_manager.watched_data) do
        data_str = data_str .. string.format("  [%q] = true,\n", path)
    end
    data_str = data_str .. "}\n"
    local f = io.open(video_manager.watched_file, "w")
    if f then
        f:write(data_str)
        f:close()
    end
end

function video_manager.is_watched(path)
    return video_manager.watched_data[path] == true
end

function video_manager.set_watched(path, watched)
    if watched then
        if not video_manager.watched_data[path] then
            video_manager.watched_data[path] = true
            -- Clear resume data if marking as watched
            video_manager.clear_resume(path)
        end
    else
        video_manager.watched_data[path] = nil
    end
    video_manager.save_watched()
    return video_manager.is_watched(path)
end

function video_manager.toggle_watched(path)
    return video_manager.set_watched(path, not video_manager.is_watched(path))
end

local function read_resume_path(full_watch_path)
    local f = io.open(full_watch_path, "r")
    if not f then return nil end

    local content = f:read("*a")
    f:close()

    if not content then return nil end

    -- Ignore redirect entries created by mpv for parent folders/playlists
    if content:match("# redirect entry") then
        return nil
    end

    local path = content:match("# path: *([^\n\r]+)")
    if not path then
        path = content:match("#path: *([^\n\r]+)")
    end
    if not path then
        path = content:match("# *(/[^\n\r]+)")
    end

    if path then
        return utils.trim(path)
    end

    return nil
end

function video_manager.prune_stale_state(valid_paths)
    valid_paths = valid_paths or {}

    local changed = false

    for path in pairs(video_manager.watched_data) do
        local f = io.open(path, "r")
        if f then
            f:close()
        elseif not valid_paths[path] then
            video_manager.watched_data[path] = nil
            changed = true
        end
    end

    if changed then
        video_manager.save_watched()
    end

    local dir = utils.normalize_path(video_manager.watch_later_dir)
    os.execute("mkdir -p \"" .. dir .. "\"")

    local handle = io.popen("ls -1 \"" .. dir .. "\" 2>/dev/null")
    if handle then
        for filename in handle:lines() do
            filename = utils.trim(filename)
            if filename ~= "" and filename ~= "." and filename ~= ".." then
                local full_watch_path = dir .. "/" .. filename
                local path = read_resume_path(full_watch_path)
                local exists_on_disk = false
                if path then
                    local f = io.open(path, "r")
                    if f then
                        f:close()
                        exists_on_disk = true
                    end
                end
                if not path or (not valid_paths[path] and not exists_on_disk) then
                    os.remove(full_watch_path)
                    changed = true
                end
            end
        end
        handle:close()
    end

    return changed
end

function video_manager.clear_resume(path)
    if not path or path == "" then return end

    -- We need to find the watch-later file for this path
    -- Since it's an MD5 of the path, we could calculate it,
    -- but easier to just scan the directory if it's small,
    -- or use the fact that we wrote the filename in the config.

    local handle = io.popen("ls " .. video_manager.watch_later_dir .. " 2>/dev/null")
    if handle then
        for filename in handle:lines() do
            local full_path = video_manager.watch_later_dir .. "/" .. filename
            local resume_path = read_resume_path(full_path)
            if resume_path and resume_path == path then
                os.remove(full_path)
                break
            end
        end
        handle:close()
    end
end

function video_manager.clear_history()
    video_manager.watched_data = {}
    video_manager.save_watched()

    local dir = utils.normalize_path(video_manager.watch_later_dir)
    os.execute("mkdir -p \"" .. dir .. "\"")

    local handle = io.popen("ls -1 \"" .. dir .. "\" 2>/dev/null")
    if handle then
        for filename in handle:lines() do
            filename = utils.trim(filename)
            if filename ~= "" and filename ~= "." and filename ~= ".." then
                os.remove(dir .. "/" .. filename)
            end
        end
        handle:close()
    end
end

function video_manager.get_resume_list()
    local list = {}
    local dir = utils.normalize_path(video_manager.watch_later_dir)

    -- Ensure dir exists
    os.execute("mkdir -p \"" .. dir .. "\"")

    local handle = io.popen("ls -1 \"" .. dir .. "\" 2>/dev/null")
    if handle then
        for filename in handle:lines() do
            filename = utils.trim(filename)
            if filename ~= "" and filename ~= "." and filename ~= ".." then
                local full_watch_path = dir .. "/" .. filename
                local path = read_resume_path(full_watch_path)

                if path then
                    -- Check if video file actually exists
                    local check = io.open(path, "r")
                    if check then
                        check:close()
                        table.insert(list, { name = utils.get_filename(path), path = path })
                    else
                        -- Video missing, clean up the stale resume data
                        print("VideoManager: Cleaning up stale resume for " .. path)
                        os.remove(full_watch_path)
                    end
                else
                    print("VideoManager: Could not find path comment in " .. filename)
                end
            end
        end
        handle:close()
    end
    print("VideoManager: Scan complete. Found " .. #list .. " valid resume entries.")
    return list
end

-- Init
video_manager.load_watched()

return video_manager
