-- system.lua
-- Device hardware queries (battery, volume, brightness).
-- Isolated here so utils.lua stays generic and this layer can be swapped
-- easily for a different device target.

local system = {}

-- Path is same for muOS & Knulli
function system.get_battery_percentage()
    local path = "/sys/class/power_supply/axp2202-battery/capacity"
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content then
        return tonumber(content:match("(%d+)"))
    end
    return nil
end

-- Path is same for muOS & Knulli
function system.is_charging()
    local path = "/sys/class/power_supply/axp2202-usb/online"
    local f = io.open(path, "r")
    if not f then return false end
    local content = f:read("*a")
    f:close()
    if content then
        return (tonumber(content:match("(%d+)")) or 0) == 1
    end
    return false
end

function system.get_volume()
    local path = "/opt/muos/config/settings/general/volume"
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content then
        return tonumber(content:match("(%d+)"))
    end
    return nil
end

function system.get_brightness()
    local path = "/opt/muos/config/settings/general/brightness"
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content then
        return tonumber(content:match("(%d+)"))
    end
    return nil
end

function system.set_brightness(level)
    if not level then return end

    local val = tonumber(level) or 50
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
end

return system
