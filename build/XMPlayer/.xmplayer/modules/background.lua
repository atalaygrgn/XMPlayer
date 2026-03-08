local theme = require("theme")
local utils = require("utils")
local settings = require("settings")

local background = {}

local particles = {}
local screen_w, screen_h
local speed = 1.0
local target_speed = 1.0
local gradient_mesh

function background.init()
    screen_w, screen_h = love.graphics.getDimensions()

    -- Initialize particles
    for i = 1, 50 do
        table.insert(particles, {
            x = math.random() * screen_w,
            y = math.random() * screen_h,
            size = math.random(1, 3),
            speed = 10 + math.random() * 20,
            alpha = 0.1 + math.random() * 0.4
        })
    end

    -- Create a mesh for the gradient background
    local vertices = {
        { 0,        0,        0, 0, 1, 1, 1, 1 },
        { screen_w, 0,        0, 0, 1, 1, 1, 1 },
        { screen_w, screen_h, 0, 0, 1, 1, 1, 1 },
        { 0,        screen_h, 0, 0, 1, 1, 1, 1 },
    }
    gradient_mesh = love.graphics.newMesh(vertices, "fan", "static")
end

function background.update(dt, is_paused)
    target_speed = is_paused and 0.15 or 1.0
    -- Smoothly transition speed
    speed = utils.lerp(speed, target_speed, dt * 2)

    -- Update particles
    if settings.show_particles then
        for _, p in ipairs(particles) do
            p.x = p.x + p.speed * dt * speed * 0.5
            if p.x > screen_w then
                p.x = -10
                p.y = math.random() * screen_h
            end
        end
    end
end

local function draw_waveform(music)
    if not music or not music.playing or not music.sound_data then return end

    local w, h = screen_w, screen_h
    local samples = 120 -- How many points in our waveform
    local amplitude = h * 0.15
    local current_sample = music.source:tell("samples")
    local total_samples = music.sound_data:getSampleCount()

    -- Smooth the reactive amplitude based on a window of samples
    local window = 1024
    local rms = 0
    for i = 0, window - 1, 32 do -- subsample for performance
        local s_idx = math.min(total_samples - 1, current_sample + i)
        local sample = music.sound_data:getSample(s_idx)
        rms = rms + sample * sample
    end
    rms = math.sqrt(rms / (window / 32))

    -- Base amplitude based on volume/intensity
    local reactive_amp = amplitude * (0.2 + rms * 2.5)

    -- Draw multiple wave layers
    for layer = 1, 3 do
        local points = {}
        local opacity = (layer == 1) and 0.4 or (layer == 2) and 0.2 or 0.1
        local layer_speed = (layer == 1) and 1.0 or (layer == 2) and 0.7 or 0.4
        local layer_freq = (layer == 1) and 1.0 or (layer == 2) and 0.6 or 0.3

        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], opacity * (music.paused and 0.3 or 1.0))
        love.graphics.setLineWidth(layer == 1 and 2 or 1)

        for i = 0, samples do
            local x = (i / samples) * w

            -- Combine static sine for motion with actual audio sample data
            local sample_offset = math.floor(i * 10)
            local s_idx = math.min(total_samples - 1, current_sample + sample_offset)
            local audio_sample = music.sound_data:getSample(s_idx)

            local y_offset = math.sin(i * 0.1 * layer_freq + love.timer.getTime() * layer_speed) * 10
            local y = (h * 0.6) + (audio_sample * reactive_amp) + y_offset

            table.insert(points, x)
            table.insert(points, y)
        end

        if #points >= 4 then
            love.graphics.line(points)
        end
    end
end

local function draw_psp_waves()
    local w, h = screen_w, screen_h
    local time = love.timer.getTime()

    -- We draw 3 layers of large, slow-moving waves
    for layer = 1, 2 do
        local opacity = (layer == 1) and 0.15 or (layer == 2) and 0.10 or 0.05
        local speed_mult = (layer == 1) and 0.4 or (layer == 2) and 0.2 or 0.1
        local freq_mult = (layer == 1) and 1.0 or (layer == 2) and 0.6 or 0.4
        local amplitude = (layer == 1) and h * 0.1 or (layer == 2) and h * 0.15 or h * 0.2
        local base_y = h * 0.60

        local color = { theme.accent[1], theme.accent[2], theme.accent[3], opacity }
        local fade_color = { theme.accent[1], theme.accent[2], theme.accent[3], 0 }

        local segments = 40
        local vertices = {}

        for i = 0, segments do
            local x = (i / segments) * w
            local y = base_y +
                math.sin(i * 0.2 * freq_mult + time * speed_mult) * amplitude +
                math.sin(i * 0.1 * freq_mult - time * speed_mult * 0.8) * (amplitude * 0.4)

            -- Top vertex (on the wave line, full color)
            table.insert(vertices, { x, y, 0, 0, color[1], color[2], color[3], color[4] })
            -- Bottom vertex (offset downwards, fading to 0 alpha)
            -- This creates the "ribbon" look and eliminates solid lines at the bottom
            table.insert(vertices, { x, y + 250, 0, 0, fade_color[1], fade_color[2], fade_color[3], fade_color[4] })
        end

        -- Create a temporary mesh for the ribbon strip
        local mesh = love.graphics.newMesh(vertices, "strip", "stream")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(mesh)
    end
end

function background.draw(music)
    -- Update gradient colors based on theme
    if gradient_mesh then
        local bg = theme.colors.background
        local acc = theme.accent

        -- Subtle gradient from background color to a tinted version
        local c1 = { bg[1], bg[2], bg[3], 1 }
        local tint = (theme.current_mode == "Light") and 0.3 or 0.15
        local c2 = {
            bg[1] * (1 - tint) + acc[1] * tint,
            bg[2] * (1 - tint) + acc[2] * tint,
            bg[3] * (1 - tint) + acc[3] * tint,
            1
        }

        gradient_mesh:setVertex(1, 0, 0, 0, 0, c1[1], c1[2], c1[3], c1[4])
        gradient_mesh:setVertex(2, screen_w, 0, 0, 0, c1[1], c1[2], c1[3], c1[4])
        gradient_mesh:setVertex(3, screen_w, screen_h, 0, 0, c2[1], c2[2], c2[3], c2[4])
        gradient_mesh:setVertex(4, 0, screen_h, 0, 0, c2[1], c2[2], c2[3], c2[4])

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(gradient_mesh)
    end

    -- Draw PSP waves only if music player is NOT active
    if not (music and music.active) then
        draw_psp_waves()
    end

    -- Draw reactive waveform if music is playing
    if music and music.playing then
        draw_waveform(music)
    end

    -- Draw particles
    if settings.show_particles then
        for _, p in ipairs(particles) do
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], p.alpha * 0.5)
            love.graphics.circle("fill", p.x, p.y, p.size)
        end
    end
end

return background
