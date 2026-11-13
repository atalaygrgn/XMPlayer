-- m3u.lua
-- Unified parser, generator, and file manager for M3U playlists and watchlists.

local utils = require("utils")

local m3u = {}

function m3u.shell_quote(path)
    if not path then return "''" end
    return "'" .. tostring(path):gsub("'", [['"'"']]) .. "'"
end

function m3u.sanitize_name(name)
    local original = utils.trim(name or "")
    local cleaned = original
    cleaned = cleaned:gsub("[%c]", "")
    cleaned = cleaned:gsub("[/\\:%*%?\"<>|]", "_")
    cleaned = utils.trim(cleaned)
    if cleaned == "" then
        return nil, nil
    end
    return cleaned, (cleaned ~= original)
end

function m3u.ensure_dir(dir_path)
    local path_sep = package.config:sub(1, 1)
    if path_sep == "\\" then
        os.execute("if not exist \"" .. dir_path .. "\" mkdir \"" .. dir_path .. "\" >nul 2>nul")
    else
        os.execute("mkdir -p " .. m3u.shell_quote(dir_path) .. " 2>/dev/null")
    end
end

function m3u.path_for_name(dir_path, name)
    local final_name = name
    if not final_name:lower():match("%.m3u8?$") then
        final_name = final_name .. ".m3u"
    end
    return dir_path .. "/" .. final_name, final_name
end

function m3u.list(dir_path, item_type, icon)
    m3u.ensure_dir(dir_path)

    local results = {}
    local cmd = "find " .. m3u.shell_quote(dir_path)
        .. " -maxdepth 1 -mindepth 1 -type f \\( -iname '*.m3u' -o -iname '*.m3u8' \\) 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            local path = utils.trim(line or "")
            if path ~= "" then
                local filename = utils.get_filename(path) or path
                local display_name = filename:gsub("%.m3u8?$", "")
                table.insert(results, {
                    name = display_name,
                    type = item_type,
                    icon = icon,
                    path = path,
                })
            end
        end
        handle:close()
    end

    table.sort(results, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return results
end

function m3u.create(dir_path, name)
    m3u.ensure_dir(dir_path)

    local safe_name, replaced_invalid = m3u.sanitize_name(name)
    if not safe_name then
        return nil, "invalid_name"
    end

    local full_path = m3u.path_for_name(dir_path, safe_name)
    local existing = io.open(full_path, "r")
    if existing then
        existing:close()
        return nil, "exists"
    end

    local file, err = io.open(full_path, "w")
    if not file then
        return nil, err or "write_failed"
    end
    file:close()
    return full_path, nil, replaced_invalid
end

function m3u.rename(dir_path, old_path, new_name)
    m3u.ensure_dir(dir_path)

    if not old_path or old_path == "" then
        return nil, "missing_path"
    end

    local safe_name, replaced_invalid = m3u.sanitize_name(new_name)
    if not safe_name then
        return nil, "invalid_name"
    end

    local new_path = m3u.path_for_name(dir_path, safe_name)
    if utils.normalize_path(old_path) == utils.normalize_path(new_path) then
        return old_path, nil, replaced_invalid
    end

    local existing = io.open(new_path, "r")
    if existing then
        existing:close()
        return nil, "exists"
    end

    local ok, err = os.rename(old_path, new_path)
    if not ok then
        return nil, err or "rename_failed"
    end

    return new_path, nil, replaced_invalid
end

function m3u.remove(path)
    if not path or path == "" then
        return nil, "missing_path"
    end

    local ok, err = os.remove(path)
    if not ok then
        return nil, err or "remove_failed"
    end

    return true
end

function m3u.parse(m3u_path, validator_fn)
    local tracks = {}
    local file = io.open(m3u_path, "r")
    if not file then
        return tracks
    end

    local dir = utils.get_dirname(m3u_path)
    for line in file:lines() do
        local entry = utils.trim(line or "")
        if entry ~= "" and entry:sub(1, 1) ~= "#" then
            entry = entry:gsub("\\", "/")
            local resolved = entry
            if resolved:sub(1, 1) ~= "/" and not resolved:match("^%a:/") then
                resolved = dir .. "/" .. resolved
            end

            if not validator_fn or validator_fn(resolved) then
                table.insert(tracks, {
                    name = utils.get_track_name(resolved),
                    path = resolved,
                })
            end
        end
    end

    file:close()
    return tracks
end

function m3u.add_entry(m3u_path, entry_path)
    if not m3u_path or not entry_path then return nil, "missing" end
    local entry = entry_path:gsub("\\", "/")
    local f, err = io.open(m3u_path, "a")
    if not f then return nil, err end
    f:write(entry .. "\n")
    f:close()
    return true
end

function m3u.remove_entry(m3u_path, target_index, validator_fn)
    local file = io.open(m3u_path, "r")
    if not file then return false, "could_not_read" end

    local lines = {}
    local dir = utils.get_dirname(m3u_path)
    local valid_count = 0

    for line in file:lines() do
        local is_target = false
        local entry = utils.trim(line or "")
        if entry ~= "" and entry:sub(1, 1) ~= "#" then
            entry = entry:gsub("\\", "/")
            local resolved = entry
            if resolved:sub(1, 1) ~= "/" and not resolved:match("^%a:/") then
                resolved = dir .. "/" .. resolved
            end

            if not validator_fn or validator_fn(resolved) then
                valid_count = valid_count + 1
                if valid_count == target_index then
                    is_target = true
                end
            end
        end

        if not is_target then
            table.insert(lines, line)
        end
    end
    file:close()

    local file_w, err = io.open(m3u_path, "w")
    if not file_w then return false, err or "could_not_write" end

    for _, line in ipairs(lines) do
        file_w:write(line .. "\n")
    end
    file_w:close()

    return true
end

return m3u
