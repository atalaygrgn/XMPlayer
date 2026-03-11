-- system.lua
-- Device hardware queries (battery, volume, brightness).
-- Isolated here so utils.lua stays generic and this layer can be swapped
-- easily for a different device target.

local system = {}

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

return system
