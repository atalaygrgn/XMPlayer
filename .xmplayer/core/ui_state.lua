local ui_state = {}

function ui_state.new_animator(initial, target)
    return {
        value = initial,
        target = target or initial,
        speed = 12,
    }
end

function ui_state.update_animator(anim, dt, target, speed)
    if not anim then return nil end
    if target ~= nil then
        anim.target = target
    end
    if speed ~= nil then
        anim.speed = speed
    end
    anim.value = anim.value + (anim.target - anim.value) * math.min(1, dt * anim.speed)
    return anim.value
end

return ui_state
