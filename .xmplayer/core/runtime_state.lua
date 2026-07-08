local runtime_state = {
    scan_co = nil,
    was_music_active = false,
    launch_status_message = nil,
    launch_status_timer = 0,
    launch_status_duration = 2.5,

    battery_percentage = nil,
    is_charging = false,
    battery_timer = 0,
    battery_update_interval = 10,

    last_volume = nil,
    last_brightness = nil,
    ui_timer = 0,
    ui_check_interval = 0.1,

    current_view = "xmb",
}

function runtime_state.clear_launch_status()
    runtime_state.launch_status_message = nil
    runtime_state.launch_status_timer = 0
end

function runtime_state.set_launch_status(message, duration)
    runtime_state.launch_status_message = message
    runtime_state.launch_status_timer = duration or runtime_state.launch_status_duration
end

function runtime_state.begin_scan(co)
    runtime_state.scan_co = co
end

function runtime_state.clear_scan()
    runtime_state.scan_co = nil
end

return runtime_state
