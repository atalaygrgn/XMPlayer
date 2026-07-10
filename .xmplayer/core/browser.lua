local utils = require("utils")
local indexing = require("indexing")
local system = require("system")
local browser = {}

browser.base_dir = system.get_default_base_dir()
browser.current_dir = browser.base_dir
browser.files = {}
browser.selected_index = 1
browser.filter = nil

local extensions = indexing.compatible_extensions

function browser.set_filter(type)
    browser.filter = extensions[type]
end

function browser.scan(path)
    path = path or browser.current_dir
    browser.files = {}

    -- Retrieve all directories first to build a lookup set
    local dir_command = "find \"" .. path .. "\" -maxdepth 1 -mindepth 1 -type d -not -path '*/.*' 2>/dev/null"
    local dir_handle = io.popen(dir_command)
    local dir_set = {}
    if dir_handle then
        local dir_output = dir_handle:read("*a")
        dir_handle:close()
        for line in dir_output:gmatch("[^\r\n]+") do
            dir_set[line] = true
        end
    end

    -- Retrieve all entries (files and directories)
    local all_command = "find \"" .. path .. "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' 2>/dev/null"
    local all_handle = io.popen(all_command)
    if not all_handle then return end

    local all_output = all_handle:read("*a")
    all_handle:close()

    local dirs = {}
    local files = {}

    for line in all_output:gmatch("[^\r\n]+") do
        if line ~= path then
            local filename = utils.get_filename(line)
            local is_dir = dir_set[line] == true
            if is_dir then
                table.insert(dirs, { name = filename, path = line, type = "directory" })
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
                    table.insert(files, { name = filename, path = line, type = "file" })
                end
            end
        end
    end

    table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)

    for _, v in ipairs(dirs) do table.insert(browser.files, v) end
    for _, v in ipairs(files) do table.insert(browser.files, v) end

    if #browser.files == 0 then
        table.insert(browser.files, { name = "Empty Folder", path = "", type = "info" })
    end
end

function browser.set_state(base_dir, current_dir, filter)
    browser.base_dir = base_dir
    browser.current_dir = current_dir
    browser.set_filter(filter)
end

function browser.set_files(list)
    browser.files = list
end

return browser
