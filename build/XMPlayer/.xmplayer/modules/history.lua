local history = {}
history.data = {}
local storage_path = love.filesystem.getSource()
history.file_path = storage_path .. "/history.cfg"

function history.load()
    local f = io.open(history.file_path, "r")
    if f then
        f:close()
        local chunk, err = loadfile(history.file_path)
        if chunk then
            local ok, data = pcall(chunk)
            if ok and type(data) == "table" then
                history.data = data
            end
        end
    end
end

function history.save()
    local data_str = "return {\n"
    for _, path in ipairs(history.data) do
        data_str = data_str .. string.format("  %q,\n", path)
    end
    data_str = data_str .. "}\n"
    local f = io.open(history.file_path, "w")
    if f then
        f:write(data_str)
        f:close()
    end
end

function history.add(path)
    if not path or path == "" then return end
    
    -- Remove if already exists to move to top
    for i, p in ipairs(history.data) do
        if p == path then
            table.remove(history.data, i)
            break
        end
    end
    -- Add to top
    table.insert(history.data, 1, path)
    -- Trim history (50 items)
    while #history.data > 50 do
        table.remove(history.data)
    end
    history.save()
end

function history.clear()
    history.data = {}
    history.save()
end

-- Load on module load
history.load()

return history
