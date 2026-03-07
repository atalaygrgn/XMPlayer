local utils = require("utils")
local browser = {}

browser.base_dir = "/mnt/sdcard"
browser.current_dir = browser.base_dir
browser.files = {}
browser.selected_index = 1
browser.filter = nil

local extensions = {
    video = {".mp4", ".mkv", ".avi", ".mov", ".wmv"},
    music = {".mp3", ".wav", ".flac", ".ogg", ".m4a"},
    photo = {".jpg", ".jpeg", ".png", ".gif", ".bmp"},
}

function browser.set_filter(type)
    browser.filter = extensions[type]
end

function browser.scan(path)
    path = path or browser.current_dir
    browser.files = {}
    
    -- Using os.execute/io.popen for muOS compatibility as love.filesystem is restricted
    local command = "find \"" .. path .. "\" -maxdepth 1 -not -path '*/.*' 2>/dev/null"
    local handle = io.popen(command)
    if not handle then return end
    
    local output = handle:read("*a")
    handle:close()

    local dirs = {}
    local files = {}

    for line in output:gmatch("[^\r\n]+") do
        if line ~= path then
            local filename = utils.get_filename(line)
            -- Check if it's a directory
            local is_dir = os.execute("test -d \"" .. line .. "\"") == 0
            if is_dir then
                table.insert(dirs, {name = filename, path = line, type = "directory"})
            else
                local match = false
                if browser.filter then
                    local ext = utils.get_extension(filename)
                    if ext then
                        for _, fext in ipairs(browser.filter) do
                            if ext == fext then
                                match = true
                                break
                            end
                        end
                    end
                else
                    match = true -- No filter means show everything
                end
                
                if match then
                    table.insert(files, {name = filename, path = line, type = "file"})
                end
            end
        end
    end

    table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)

    for _, v in ipairs(dirs) do table.insert(browser.files, v) end
    for _, v in ipairs(files) do table.insert(browser.files, v) end

    if #browser.files == 0 then
        table.insert(browser.files, {name = "Empty Folder", path = "", type = "info"})
    end
end

return browser
