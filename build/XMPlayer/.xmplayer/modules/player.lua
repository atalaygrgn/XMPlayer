local history = require("history")
local player = {}

-- Flag to signal main.lua to do a hard refresh
player.needs_refresh = false

function player.play(filepath)
    if not filepath or filepath == "" then return end
    
    -- Record history
    history.add(filepath)
    
    print("Launching MPV for: " .. filepath)
    
    -- Switch gptokeyb to MPV controls
    os.execute("killall -9 gptokeyb2 2>/dev/null")
    os.execute("./bin/gptokeyb2 mpv -c ./config/mpvplayer.gptk &")
    
    -- Launch MPV (blocks until MPV exits)
    local command = "mpv \"" .. filepath .. "\""
    os.execute(command)
    
    print("MPV exited, returning to XMPlayer")
    
    -- Switch gptokeyb back to XMPlayer controls
    os.execute("killall -9 gptokeyb2 2>/dev/null")
    os.execute("./bin/gptokeyb2 love -c ./config/xmplayer.gptk &")
    
    -- Signal that we need a hard display refresh
    player.needs_refresh = true
end

return player
