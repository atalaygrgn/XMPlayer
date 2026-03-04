local player = {}

-- Flag to signal main.lua to do a hard refresh
player.needs_refresh = false

function player.play(filepath)
    if not filepath or filepath == "" then return end
    
    print("Launching MPV for: " .. filepath)
    
    -- Switch gptokeyb to MPV controls
    os.execute("killall -9 gptokeyb2 2>/dev/null")
    os.execute("./gptokeyb2 mpv -c ./mpvplayer.gptk &")
    
    -- Launch MPV (blocks until MPV exits)
    local command = "mpv \"" .. filepath .. "\""
    os.execute(command)
    
    print("MPV exited, returning to XMPlayer")
    
    -- Clear the Linux framebuffer device to black (wipes MPV's direct output)
    os.execute("dd if=/dev/zero of=/dev/fb0 bs=1M count=4 2>/dev/null")
    
    -- Switch gptokeyb back to XMPlayer controls
    os.execute("killall -9 gptokeyb2 2>/dev/null")
    os.execute("./gptokeyb2 love -c ./xmplayer.gptk &")
    
    -- Signal that we need a hard display refresh
    player.needs_refresh = true
end

return player
