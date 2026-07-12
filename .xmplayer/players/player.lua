local history = require("history")
local system = require("system")
local player = {}

-- Flag to signal main.lua to do a hard refresh
player.needs_refresh = false

local function get_saved_playback_position(filepath, watch_later_dir)
    local p = io.popen("ls " .. watch_later_dir .. " 2>/dev/null")
    if not p then return nil end

    local position = nil
    for filename in p:lines() do
        local full_path = watch_later_dir .. "/" .. filename
        local f = io.open(full_path, "r")
        if f then
            local lines = {}
            for line in f:lines() do
                table.insert(lines, line)
            end
            f:close()

            -- Check if this watch-later file belongs to our video
            local belongs_to_us = false
            for _, line in ipairs(lines) do
                if line:match("^#%s*(.-)%s*$") == filepath then
                    belongs_to_us = true
                    break
                end
            end

            if belongs_to_us then
                -- Find the start position
                for _, line in ipairs(lines) do
                    local start_val = line:match("^start=([%d%.]+)")
                    if start_val then
                        position = tonumber(start_val)
                        break
                    end
                end
                break
            end
        end
    end
    p:close()
    return position
end

function player.play_video(filepath, resume)
    if not filepath or filepath == "" then return end

    local paths = {}
    if type(filepath) == "table" then
        paths = filepath
    else
        paths = { filepath }
    end

    if #paths == 0 then return end

    local settings = require("settings")
    local ui = require("ui")

    -- 1. Check player setting and availability
    if settings.video_player_mode == "mpv" then
        local ok = os.execute("command -v mpv >/dev/null 2>&1")
        if not (ok == true or ok == 0) then
            ui.show_toast("mpv not available", "info", "top_center")
            return false
        end
    elseif settings.video_player_mode == "ffplay" then
        local ok = os.execute("command -v ffplay >/dev/null 2>&1")
        if not (ok == true or ok == 0) then
            ui.show_toast("ffplay not available", "info", "top_center")
            return false
        end
    end

    -- Record history for the first file at least
    history.add(paths[1])

    -- Resolve gptokeyb details dynamically based on CFW and environment variables
    local cfw = system.get_cfw_name()
    local gptokeyb_exe = nil
    local kill_cmd = nil

    if cfw == "muOS" then
        gptokeyb_exe = "./bin/gptokeyb2"
        kill_cmd = "killall -9 gptokeyb2 2>/dev/null"
    else
        gptokeyb_exe = os.getenv("GPTOKEYB") or "gptokeyb"
        kill_cmd = "killall -9 gptokeyb gptokeyb2 2>/dev/null"
    end

    if settings.video_player_mode == "mpv" then
        print("Launching MPV for " .. #paths .. " files")

        local storage_path = love.filesystem.getSource()
        local watch_later_dir = storage_path .. "/config/mpv/watch_later"
        os.execute("mkdir -p " .. watch_later_dir)

        -- Switch gptokeyb to MPV controls (only on muOS)
        if cfw == "muOS" then
            os.execute(kill_cmd)
            os.execute(gptokeyb_exe .. " mpv -c ./config/mpvplayer.gptk &")
        end

        -- Launch MPV (blocks until MPV exits)
        local paths_str = ""
        for _, p in ipairs(paths) do
            paths_str = paths_str .. " \"" .. p .. "\""
        end

        local resume_flag = resume and "--resume-playback=yes" or "--start=0"
        local command = string.format(
            "mpv %s --save-position-on-quit --watch-later-directory=%q --write-filename-in-watch-later-config=yes %s --input-conf=./config/input.conf --config-dir=./config",
            paths_str, watch_later_dir, resume_flag)

        print("Executing: " .. command)
        os.execute(command)

        print("MPV exited, returning to XMPlayer")

        -- Switch gptokeyb back to XMPlayer controls
        os.execute(kill_cmd)
        if cfw == "muOS" then
            os.execute("./bin/gptokeyb2 love -c ./config/xmplayer.gptk &")
        else
            local love_gptk = os.getenv("LOVE_GPTK") or "love"
            os.execute(gptokeyb_exe .. " " .. love_gptk .. " -c ./config/xmplayer.gptk &")
        end
    elseif settings.video_player_mode == "ffplay" then
        print("Launching FFplay for " .. #paths .. " files")

        local storage_path = love.filesystem.getSource()
        local watch_later_dir = storage_path .. "/config/mpv/watch_later"

        local vf_arg = ""
        if settings.ffplay_aspect_ratio and settings.ffplay_aspect_ratio ~= "Original" then
            local ratio = settings.ffplay_aspect_ratio:gsub(":", "/")
            vf_arg = string.format(' -vf "setdar=%s"', ratio)
        end

        -- Launch FFplay sequentially
        for _, p in ipairs(paths) do
            -- Start gptokeyb daemon mapping for this ffplay instance
            os.execute(kill_cmd)
            os.execute(gptokeyb_exe .. " ffplay -c ./config/ffplay.gptk &")

            local ss_arg = ""
            if resume then
                local pos = get_saved_playback_position(p, watch_later_dir)
                if pos and pos > 0 then
                    ss_arg = string.format(" -ss %.3f", pos)
                end
            end

            local command = string.format('ffplay -fs -autoexit -noborder%s%s "%s"', vf_arg, ss_arg, p)
            print("Executing: " .. command)
            os.execute(command)
        end

        print("FFplay exited, returning to XMPlayer")

        -- Switch gptokeyb back to XMPlayer controls
        os.execute(kill_cmd)
        if cfw == "muOS" then
            os.execute("./bin/gptokeyb2 love -c ./config/xmplayer.gptk &")
        else
            local love_gptk = os.getenv("LOVE_GPTK") or "love"
            os.execute(gptokeyb_exe .. " " .. love_gptk .. " -c ./config/xmplayer.gptk &")
        end
    end

    -- Signal that we need a hard display refresh
    player.needs_refresh = true
end

return player
