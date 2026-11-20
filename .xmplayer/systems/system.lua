-- system.lua
-- Device hardware queries (battery, volume, brightness).
-- Isolated here so utils.lua stays generic and this layer can be swapped
-- easily for a different device target.

local system = {}

local cfw_name = nil
local cached_screenshot_dir = nil
local cached_base_dir = nil
local cached_rocknix_backlight = nil
local cached_backlight_brightness_path = nil
local cached_backlight_max = nil
local backlight_path_checked = false
local disp_attr_checked = false
local has_disp_attr = false
local chai_checked = false
local chai_available = false
local vol_sub_script = "/tmp/xmplayer_vol_sub.sh"
local vol_event_file = "/tmp/xmplayer_chai_vol"
local vol_seq_file = "/tmp/xmplayer_chai_vol_seq"
local last_vol_seq = nil
local vol_sub_registered = false

local function is_windows()
    return package.config:sub(1, 1) == "\\"
end

function system.has_chai()
    if chai_checked then
        return chai_available
    end
    chai_checked = true
    if is_windows() then
        chai_available = false
        return false
    end
    local ok = os.execute("command -v chai >/dev/null 2>&1")
    chai_available = (ok == 0 or ok == true)
    return chai_available
end

local function run_chai(args)
    if not system.has_chai() then return nil end
    local p = io.popen("chai " .. args .. " 2>/dev/null")
    if not p then return nil end
    local out = p:read("*a")
    p:close()
    if not out then return nil end
    out = out:match("^%s*(.-)%s*$")
    if out == "" then return nil end
    return out
end

local function ensure_backlight_paths()
    if backlight_path_checked then
        return cached_backlight_brightness_path
    end
    backlight_path_checked = true

    if package.config:sub(1, 1) == "\\" then
        return nil
    end

    local p = io.popen("ls -d /sys/class/backlight/* 2>/dev/null")
    if p then
        for line in p:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then
                cached_rocknix_backlight = cached_rocknix_backlight or line
                local b_path = line .. "/brightness"
                local f = io.open(b_path, "r")
                if f then
                    f:close()
                    cached_backlight_brightness_path = b_path
                    break
                end
            end
        end
        p:close()
    end
    return cached_backlight_brightness_path
end

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
    if cached_base_dir then return cached_base_dir end
    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        cached_base_dir = "/mnt"
    elseif cfw == "knulli" then
        cached_base_dir = "/userdata"
    elseif cfw == "ROCKNIX" then
        cached_base_dir = "/storage"
    else
        local chai_userdata = run_chai("get-path userdata")
        cached_base_dir = chai_userdata or "/"
    end
    return cached_base_dir
end

function system.get_screenshot_dir()
    if cached_screenshot_dir then return cached_screenshot_dir end

    local chai_ss = run_chai("get-path screenshots")
    if chai_ss then
        cached_screenshot_dir = chai_ss
        return cached_screenshot_dir
    end

    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        cached_screenshot_dir = "/run/muos/storage/screenshot"
    elseif cfw == "knulli" then
        cached_screenshot_dir = "/userdata/screenshots"
    elseif cfw == "ROCKNIX" then
        cached_screenshot_dir = "/storage/roms/screenshots"
    else
        if dir_has_entries("/userdata/screenshots") then
            cached_screenshot_dir = "/userdata/screenshots"
        elseif dir_has_entries("/storage/roms/screenshots") then
            cached_screenshot_dir = "/storage/roms/screenshots"
        elseif dir_has_entries("/run/muos/storage/screenshot") then
            cached_screenshot_dir = "/run/muos/storage/screenshot"
        else
            cached_screenshot_dir = "/userdata/screenshots"
        end
    end
    return cached_screenshot_dir
end

function system.get_battery_percentage()
    local out = run_chai("get-battery-percent")
    if out then
        local pct = tonumber(out:match("(%d+)"))
        if pct then return pct end
    end

    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local f = io.open("/sys/class/power_supply/axp2202-battery/capacity", "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then return tonumber(content:match("(%d+)")) end
        end
    elseif cfw == "knulli" then
        local f = io.open("/tmp/battery.percent", "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then return tonumber(content:match("(%d+)")) end
        end
    elseif cfw == "ROCKNIX" then
        local f = io.open("/sys/class/power_supply/battery/capacity", "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then return tonumber(content:match("(%d+)")) end
        end
    end
    return nil
end

function system.is_charging()
    local out = run_chai("get-battery-status")
    if out then
        local flag = tonumber(out:match("(%d+)"))
        if flag ~= nil then
            return flag == 1
        end
    end

    local cfw = system.get_cfw_name()
    if cfw == "muOS" or cfw == "knulli" then
        local f = io.open("/sys/class/power_supply/axp2202-usb/online", "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content then return (tonumber(content:match("(%d+)")) or 0) == 1 end
        end
    elseif cfw == "ROCKNIX" then
        local f = io.open("/sys/class/power_supply/battery/status", "r")
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

local function read_chai_volume_event()
    if is_windows() then return nil, nil end
    local f = io.open(vol_event_file, "r")
    if not f then return nil, nil end
    local content = f:read("*a")
    f:close()
    if not content then return nil, nil end
    local vol, max_vol, seq = content:match("(%d+)%s+(%d+)%s+(%d+)")
    if not vol then return nil, nil end
    local v = tonumber(vol)
    local m = math.max(1, tonumber(max_vol) or 100)
    local pct = math.max(0, math.min(100, math.floor((v * 100) / m + 0.5)))
    return pct, tonumber(seq)
end

function system.init_volume_subscriber()
    if not system.has_chai() or vol_sub_registered then return end
    os.remove(vol_event_file)
    os.remove(vol_seq_file)
    last_vol_seq = nil

    local f = io.open(vol_sub_script, "w")
    if not f then return end
    f:write("#!/bin/sh\n")
    f:write("N=$(cat " .. vol_seq_file .. " 2>/dev/null)\n")
    f:write("N=$(( ${N:-0} + 1 ))\n")
    f:write("echo \"$N\" > " .. vol_seq_file .. "\n")
    f:write("printf '%s %s %s\\n' \"$1\" \"${2:-100}\" \"$N\" > " .. vol_event_file .. ".tmp\n")
    f:write("mv -f " .. vol_event_file .. ".tmp " .. vol_event_file .. "\n")
    f:close()

    os.execute("chmod +x " .. vol_sub_script .. " && chai add-volume-subscriber " .. vol_sub_script .. " >/dev/null 2>&1")
    vol_sub_registered = true
end

function system.cleanup_volume_subscriber()
    if not vol_sub_registered then return end
    if system.has_chai() then
        os.execute("chai remove-volume-subscriber " .. vol_sub_script .. " >/dev/null 2>&1")
    end
    os.remove(vol_sub_script)
    os.remove(vol_event_file)
    os.remove(vol_event_file .. ".tmp")
    os.remove(vol_seq_file)
    vol_sub_registered = false
    last_vol_seq = nil
end

function system.poll_volume_event()
    local pct, seq = read_chai_volume_event()
    if pct ~= nil and seq ~= nil and seq ~= last_vol_seq then
        last_vol_seq = seq
        return pct
    end
    return nil
end

function system.get_volume()
    local pct = read_chai_volume_event()
    if pct ~= nil then
        return pct
    end

    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local f = io.open("/opt/muos/config/settings/general/volume", "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        if content then return tonumber(content:match("(%d+)")) end
    elseif cfw == "knulli" then
        local p = io.popen("knulli-audio getSystemVolume 2>/dev/null")
        if p then
            local content = p:read("*a")
            p:close()
            if content then return tonumber(content:match("(%d+)")) end
        end
    end
    return nil
end

local function read_fast_brightness()
    if is_windows() then return nil end

    local b_path = ensure_backlight_paths()
    if b_path then
        local fb = io.open(b_path, "r")
        if fb then
            local b_content = fb:read("*a")
            fb:close()
            local b_val = b_content and tonumber(b_content:match("(%d+)"))
            if b_val ~= nil then
                if not cached_backlight_max and cached_rocknix_backlight then
                    local fm = io.open(cached_rocknix_backlight .. "/max_brightness", "r")
                    if fm then
                        local m_content = fm:read("*a")
                        fm:close()
                        local m_val = m_content and tonumber(m_content:match("(%d+)"))
                        if m_val and m_val > 0 then
                            cached_backlight_max = m_val
                        end
                    end
                    cached_backlight_max = cached_backlight_max or 255
                end
                local max_b = cached_backlight_max or 255
                local scaled = math.floor((b_val * 255 + math.floor(max_b / 2)) / max_b)
                return math.min(255, scaled)
            end
        end
    end

    if not disp_attr_checked then
        disp_attr_checked = true
        local f = io.open("/sys/class/disp/disp/attr/sys", "r")
        if f then
            f:close()
            has_disp_attr = true
        end
    end
    if has_disp_attr then
        local f = io.open("/sys/class/disp/disp/attr/sys", "r")
        if f then
            local content = f:read("*a")
            f:close()
            local val = content and tonumber(content:match("backlight%(%s*(%d+)"))
            if val ~= nil then
                return math.min(255, val)
            end
        end
    end

    return nil
end

function system.get_brightness()
    local fast = read_fast_brightness()
    if fast ~= nil then
        return fast
    end

    local out = run_chai("get-brightness")
    if out then
        local val = tonumber(out:match("(%d+)"))
        if val then return val end
    end

    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        local f = io.open("/opt/muos/config/settings/general/brightness", "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        if content then return tonumber(content:match("(%d+)")) end
    elseif cfw == "knulli" then
        local p = io.popen("knulli-brightness 2>/dev/null")
        if p then
            local content = p:read("*a")
            p:close()
            if content then return tonumber(content:match("(%d+)")) end
        end
    elseif cfw == "ROCKNIX" then
        ensure_backlight_paths()
        if cached_rocknix_backlight then
            local fb = io.open(cached_rocknix_backlight .. "/brightness", "r")
            local fm = io.open(cached_rocknix_backlight .. "/max_brightness", "r")
            if fb and fm then
                local b_content = fb:read("*a")
                local m_content = fm:read("*a")
                fb:close()
                fm:close()
                local b_val = tonumber(b_content:match("(%d+)"))
                local m_val = tonumber(m_content:match("(%d+)"))
                if b_val and m_val and m_val > 0 then
                    return math.floor((b_val / m_val) * 255 + 0.5)
                end
            elseif fb then
                fb:close()
            elseif fm then
                fm:close()
            end
        end
    end
    return nil
end

function system.is_backlight_off()
    local fast = read_fast_brightness()
    if fast ~= nil then
        return fast <= 0
    end
    if system.has_chai() then
        local b = system.get_brightness()
        if b ~= nil then
            return b <= 0
        end
    end
    return false
end

function system.set_brightness(level)
    if not level then return end
    local val = math.max(0, math.min(255, math.floor((tonumber(level) or 50) + 0.5)))

    if system.has_chai() then
        os.execute("chai set-brightness " .. val .. " >/dev/null 2>&1")
        return
    end

    local cfw = system.get_cfw_name()
    if cfw == "muOS" then
        if val > 0 then
            local transient = (val > 1) and (val - 1) or (val + 1)
            os.execute("/opt/muos/script/device/bright.sh " .. transient)
        end
        os.execute("/opt/muos/script/device/bright.sh " .. val)
    elseif cfw == "knulli" then
        os.execute("knulli-brightness " .. val)
    elseif cfw == "ROCKNIX" then
        os.execute("brightness set " .. val)
    end
end

return system
