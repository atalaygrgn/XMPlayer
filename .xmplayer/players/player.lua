local history = require("history")
local player = {}

-- Flag to signal main.lua to do a hard refresh
player.needs_refresh = false

function player.play_video(filepath, resume)
    if not filepath or filepath == "" then return end

    local paths = {}
    if type(filepath) == "table" then
        paths = filepath
    else
        paths = { filepath }
    end

    if #paths == 0 then return end

    -- Record history for the first file at least
    history.add(paths[1])

    print("Launching MPV for " .. #paths .. " files")

    local storage_path = love.filesystem.getSource()
    local watch_later_dir = storage_path .. "/config/mpv/watch_later"
    os.execute("mkdir -p " .. watch_later_dir)

    -- Switch gptokeyb to MPV controls
    os.execute("killall -9 gptokeyb2 2>/dev/null")
    os.execute("./bin/gptokeyb2 mpv -c ./config/mpvplayer.gptk &")

    -- Launch MPV (blocks until MPV exits)
    -- --resume-playback=yes: Automatically resume if data exists
    -- --start=0: Start from beginning
    local paths_str = ""
    for _, p in ipairs(paths) do
        paths_str = paths_str .. " \"" .. p .. "\""
    end

    local resume_flag = resume and "--resume-playback=yes" or "--start=0"
    local command = string.format(
        "mpv %s --save-position-on-quit --watch-later-directory=%q --write-filename-in-watch-later-config=yes %s --input-conf=./config/input.conf",
        paths_str, watch_later_dir, resume_flag)

    print("Executing: " .. command)
    os.execute(command)

    print("MPV exited, returning to XMPlayer")

    -- Switch gptokeyb back to XMPlayer controls
    os.execute("killall -9 gptokeyb2 2>/dev/null")
    os.execute("./bin/gptokeyb2 love -c ./config/xmplayer.gptk &")

    -- Signal that we need a hard display refresh
    player.needs_refresh = true
end

return player
