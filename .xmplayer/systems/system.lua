-- system.lua
-- Device hardware queries (battery, volume, brightness).
-- Isolated here so utils.lua stays generic and this layer can be swapped
-- easily for a different device target.

local system = {}

local cfw_name = nil

-- Helper to check if a directory contains any entries
local function dir_has_entries(path)
    if not path or path == "" then return false end
    local cmd = "find \"" .. path .. "\" -maxdepth 1 -mindepth 1 -not -path '*/.*' 2>/dev/null"
    local h = io.popen(cmd)
    if not h then return false end
    for _ in h:lines() do
        h:close()
        return true
    end
    h:close()
    return false
end

function system.get_cfw_name()
    if cfw_name then return cfw_name end

    local env_cfw = os.getenv("CFW_NAME")
    if env_cfw and env_cfw ~= "" then
        cfw_name = env_cfw
        return cfw_name
    end

    -- Check if it's muOS
    local f = io.open("/opt/muos/config/settings/general/volume", "r")
    if f then
        f:close()
        cfw_name = "muOS"
        return cfw_name
    end

    -- Check if it's Knulli
    local k_f = io.open("/boot/boot/batocera.board.capability", "r")
    if k_f then
        k_f:close()
        cfw_name = "knulli"
        return cfw_name
    end
    if dir_has_entries("/userdata") then
        cfw_name = "knulli"
        return cfw_name
    end

    -- Check if it's Rocknix
    if dir_has_entries("/storage") then
        cfw_name = "ROCKNIX"
        return cfw_name
    end

    cfw_name = "unknown"
    return cfw_name
end

function system.get_default_base_dir()
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        return "/mnt"
    elseif cfw == "knulli" then
        return "/userdata"
    elseif cfw == "ROCKNIX" then
        return "/storage"
    else
        return "/"
    end
end

function system.get_screenshot_dir()
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        return "/run/muos/storage/screenshot"
    elseif cfw == "knulli" then
        return "/userdata/screenshots"
    elseif cfw == "ROCKNIX" then
        return "/storage/roms/screenshots"
    else
        if dir_has_entries("/userdata/screenshots") then
            return "/userdata/screenshots"
        elseif dir_has_entries("/storage/roms/screenshots") then
            return "/storage/roms/screenshots"
        elseif dir_has_entries("/run/muos/storage/screenshot") then
            return "/run/muos/storage/screenshot"
        else
            return "/userdata/screenshots"
        end
    end
end

function system.get_battery_percentage()
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local path = "/sys/class/power_supply/axp2202-battery/capacity"
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then
                return tonumber(content:match("(%d+)"))
            end
        end
    elseif cfw == "knulli" then
        local f = io.open("/tmp/battery.percent", "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then
                return tonumber(content:match("(%d+)"))
            end
        end
    elseif cfw == "ROCKNIX" then
        local path = "/sys/class/power_supply/battery/capacity"
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then
                return tonumber(content:match("(%d+)"))
            end
        end
    end
    return nil
end

function system.is_charging()
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local path = "/sys/class/power_supply/axp2202-usb/online"
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then
                return (tonumber(content:match("(%d+)")) or 0) == 1
            end
        end
    elseif cfw == "knulli" then
        local path = "/sys/class/power_supply/axp2202-usb/online"
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then
                return (tonumber(content:match("(%d+)")) or 0) == 1
            end
        end
    elseif cfw == "ROCKNIX" then
        local path = "/sys/class/power_supply/battery/status"
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content and (content:lower():match("charging") or content:lower():match("full")) then
                return true
            end
        end
    end
    return nil
end

function system.get_volume()
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local path = "/opt/muos/config/settings/general/volume"
        local f = io.open(path, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        if content then
            return tonumber(content:match("(%d+)"))
        end
    elseif cfw == "knulli" then
        local p = io.popen("knulli-audio getSystemVolume 2>/dev/null")
        if p then
            local content = p:read("*a")
            p:close()
            if content then
                return tonumber(content:match("(%d+)"))
            end
        end
    end
    return nil
end

function system.get_brightness()
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local path = "/opt/muos/config/settings/general/brightness"
        local f = io.open(path, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        if content then
            return tonumber(content:match("(%d+)"))
        end
    elseif cfw == "knulli" then
        local p = io.popen("knulli-brightness 2>/dev/null")
        if p then
            local content = p:read("*a")
            p:close()
            if content then
                return tonumber(content:match("(%d+)"))
            end
        end
    elseif cfw == "ROCKNIX" then
        -- Read Rocknix backlight value and calculate percentage
        local p = io.popen("ls -d /sys/class/backlight/* 2>/dev/null")
        if p then
            for line in p:lines() do
                line = line:match("^%s*(.-)%s*$")
                if line ~= "" then
                    local b_file = line .. "/brightness"
                    local m_file = line .. "/max_brightness"
                    local fb = io.open(b_file, "r")
                    local fm = io.open(m_file, "r")
                    if fb and fm then
                        local b_content = fb:read("*a")
                        local m_content = fm:read("*a")
                        fb:close()
                        fm:close()
                        local b_val = tonumber(b_content:match("(%d+)"))
                        local m_val = tonumber(m_content:match("(%d+)"))
                        if b_val and m_val and m_val > 0 then
                            p:close()
                            return math.floor((b_val / m_val) * 100 + 0.5)
                        end
                    elseif fb then
                        fb:close()
                    end
                end
            end
            p:close()
        end
    end
    return nil
end

function system.set_brightness(level)
    local cfw = system.get_cfw_name()
    if not level then return end

    local val = tonumber(level) or 50
    if cfw == "muOS" then
        if val > 0 then
            -- Workaround for muOS: the bright.sh script caches the brightness state in its database
            -- and skips writing to hardware if the new value matches the cached value.
            -- Setting brightness to 0 (sleep) does not update the cached database value, so restoring
            -- back to the original level would be ignored. We force a hardware refresh by applying
            -- a transient offset first.
            local transient = (val > 1) and (val - 1) or (val + 1)
            os.execute("/opt/muos/script/device/bright.sh " .. transient)
        end

        -- Invoke the official muOS brightness script to update backlight and blank state
        os.execute("/opt/muos/script/device/bright.sh " .. val)
    elseif cfw == "knulli" then
        os.execute("knulli-brightness " .. val)
    elseif cfw == "ROCKNIX" then
        os.execute("brightness set " .. val)
    end
end

return system
