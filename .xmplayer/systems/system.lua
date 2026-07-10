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
        if dir_has_entries("/userdata") then
            return "/userdata"
        elseif dir_has_entries("/storage") then
            return "/storage"
        elseif dir_has_entries("/roms") then
            return "/roms"
        elseif dir_has_entries("/mnt") then
            return "/mnt"
        else
            return "/"
        end
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

local function get_battery_info()
    local cap = nil
    local charging = false

    -- Check Knulli specific cached battery files first for accurate percentage
    local f_pct = io.open("/tmp/battery.percent", "r")
    if f_pct then
        local content = f_pct:read("*a")
        f_pct:close()
        cap = tonumber(content:match("(%d+)"))
    end

    -- If not found (or not on Knulli), fall back to querying power supply directories
    if not cap then
        -- List all power supply directories
        local p = io.popen("ls -d /sys/class/power_supply/* 2>/dev/null")
        if p then
            for line in p:lines() do
                line = line:match("^%s*(.-)%s*$")
                if line ~= "" then
                    -- Check capacity file first
                    local cap_file = line .. "/capacity"
                    local f = io.open(cap_file, "r")
                    if f then
                        local content = f:read("*a")
                        f:close()
                        cap = tonumber(content:match("(%d+)"))
                    else
                        -- Fallback to uevent
                        local uevent_file = line .. "/uevent"
                        local fu = io.open(uevent_file, "r")
                        if fu then
                            local content = fu:read("*a")
                            fu:close()
                            local cap_str = content:match("POWER_SUPPLY_CAPACITY=(%d+)")
                            if cap_str then
                                cap = tonumber(cap_str)
                            else
                                -- Fallback to charge_now / charge_full
                                local now_str = content:match("POWER_SUPPLY_CHARGE_NOW=(%d+)")
                                local max_str = content:match("POWER_SUPPLY_CHARGE_FULL=(%d+)")
                                if now_str and max_str then
                                    local now = tonumber(now_str)
                                    local max = tonumber(max_str)
                                    if max and max > 0 then
                                        cap = math.floor((now / max) * 100 + 0.5)
                                    end
                                end
                            end
                        end
                    end

                    -- Check charging status if not already determined from Knulli files
                    if not f_stat then
                        local status_file = line .. "/status"
                        local fs = io.open(status_file, "r")
                        if fs then
                            local content = fs:read("*a")
                            fs:close()
                            if content and content:match("Charging") then
                                charging = true
                            end
                        end
                    end

                    -- If we found capacity, we can stop scanning
                    if cap then
                        break
                    end
                end
            end
            p:close()
        end
    end

    -- General charging status fallback checking all power supplies online status
    if not charging and not f_stat then
        local p_online = io.popen("ls /sys/class/power_supply/*/online 2>/dev/null")
        if p_online then
            for line in p_online:lines() do
                line = line:match("^%s*(.-)%s*$")
                local f = io.open(line, "r")
                if f then
                    local content = f:read("*a")
                    f:close()
                    if (tonumber(content:match("(%d+)")) or 0) == 1 then
                        charging = true
                        break
                    end
                end
            end
            p_online:close()
        end
    end

    return cap, charging
end

function system.get_battery_percentage()
    local cap, _ = get_battery_info()
    return cap
end

function system.is_charging()
    local _, charging = get_battery_info()
    return charging
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
    end
end

return system
