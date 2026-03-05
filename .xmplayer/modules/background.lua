local theme = require("theme")
local background = {}

local particles = {}
local screen_w, screen_h
local speed = 1.0
local target_speed = 1.0

function background.init()
    screen_w = love.graphics.getWidth()
    screen_h = love.graphics.getHeight()
    
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
end

function background.update(dt, is_paused)
    target_speed = is_paused and 0.15 or 1.0
    -- Smoothly transition speed
    speed = speed + (target_speed - speed) * dt * 2
    
    -- Update particles
    for _, p in ipairs(particles) do
        p.x = p.x + p.speed * dt * speed * 0.5
        if p.x > screen_w then
            p.x = -10
            p.y = math.random() * screen_h
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

function background.draw(music)
    local w = screen_w
    local h = screen_h
    
    -- Background is cleared in main.lua with theme color
    
    -- Draw reactive waveform
    if music and music.playing then
        draw_waveform(music)
    end
    
    -- Draw particles
    for _, p in ipairs(particles) do
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], p.alpha * 0.5)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end
    
    -- Depth overlays (subtle light gradients/vignettes)
    -- love.graphics.setColor(1, 1, 1, 0.4)
    -- love.graphics.rectangle("fill", 0, 0, w, h * 0.3)
    
    -- love.graphics.setColor(0.8, 0.9, 1.0, 0.2)
    -- love.graphics.rectangle("fill", 0, h * 0.7, w, h * 0.3)
end

return background
