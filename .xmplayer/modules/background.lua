local theme = require("theme")
local utils = require("utils")
local settings = require("settings")

local background = {}

local particles = {}
local screen_w, screen_h
local speed = 1.0
local target_speed = 1.0
local gradient_mesh
local custom_bg_enabled = false
local custom_bg_image = nil
local custom_bg_path = nil
local wallpaper_blur_enabled = true
local wallpaper_tint_enabled = true
local wallpaper_brightness = 1 -- 1: No Change, 2: Brighter, 3: Darker
local blur_shader = nil

local function load_wallpaper_image(path)
    local utils = require("utils")
    local resolved_path = path or "assets/background/bg.jpg"
    local img = utils.load_image(resolved_path)
    if not img and resolved_path ~= "assets/background/bg.jpg" then
        -- Fallback to bundled wallpaper if selected image is unavailable.
        img = utils.load_image("assets/background/bg.jpg")
    end
    if img then
        img:setFilter("linear", "linear")
    end
    return img
end

function background.init()
    screen_w, screen_h = love.graphics.getDimensions()

    -- Initialize particles
    for i = 1, 50 do
        table.insert(particles, {
            x = math.random() * screen_w,
            y = math.random() * screen_h,
            size = math.random(1, 3),
            speed = 10 + math.random() * 20,
            alpha = 0.4 + math.random() * 0.4
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

    -- Initialize blur shader
    blur_shader = love.graphics.newShader [[
        extern vec2 canvasSize;
        extern float radius;
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec2 blur = radius / canvasSize;
            vec4 sum = Texel(texture, texture_coords) * 0.4;
            sum += Texel(texture, texture_coords + vec2(blur.x, 0.0)) * 0.15;
            sum += Texel(texture, texture_coords - vec2(blur.x, 0.0)) * 0.15;
            sum += Texel(texture, texture_coords + vec2(0.0, blur.y)) * 0.15;
            sum += Texel(texture, texture_coords - vec2(0.0, blur.y)) * 0.15;
            return sum * color;
        }
    ]]
end

function background.update(dt, is_paused)
    target_speed = is_paused and 0.15 or 1.0
    -- Smoothly transition speed
    local speed_lerp_t = math.min(1, dt * 2)
    speed = utils.lerp(speed, target_speed, speed_lerp_t)

    -- Update particles
    if settings.show_particles then
        -- Returning from external players can produce a very large dt.
        -- Clamp integration time so particles do not all wrap to the left at once.
        local particle_dt = math.min(dt, 1 / 30)
        for _, p in ipairs(particles) do
            p.x = p.x + p.speed * particle_dt * speed * 0.5
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
        local opacity = (layer == 1) and 0.8 or (layer == 2) and 0.4 or 0.2
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

local function draw_bars_visualizer(music)
    if not music or not music.playing or not music.sound_data or not music.source then return end

    local w, h = screen_w, screen_h
    local bars = 42
    local gap = 4
    local bottom_y = h
    local max_h = h * 0.28
    local total_width = w
    local bar_w = (total_width - (bars - 1) * gap) / bars
    local start_x = (w - total_width) * 0.5

    local current_sample = math.max(0, music.source:tell("samples"))
    local total_samples = music.sound_data:getSampleCount()
    local paused_alpha = music.paused and 0.35 or 1.0

    for i = 0, bars - 1 do
        local progress = i / math.max(1, (bars - 1))
        local window_size = 480
        local window_start = current_sample + math.floor(progress * 8192)
        local energy = 0

        for j = 0, window_size - 1, 24 do
            local idx = math.min(total_samples - 1, window_start + j)
            local sample = music.sound_data:getSample(idx)
            energy = energy + sample * sample
        end

        local rms = math.sqrt(energy / (window_size / 24))
        local strength = math.min(1.0, rms * 5.2)
        local bar_h = 8 + (strength * max_h)

        local x = start_x + i * (bar_w + gap)
        local y = bottom_y - bar_h
        local alpha = (0.25 + strength * 0.85) * paused_alpha

        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha * 0.95)
        love.graphics.rectangle("fill", x, y, bar_w, bar_h, 2, 2)

        love.graphics.setColor(1, 1, 1, alpha * 0.12)
        love.graphics.rectangle("fill", x, y, bar_w, math.max(2, bar_h * 0.16), 2, 2)
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

function background.set_custom_bg(enabled)
    custom_bg_enabled = enabled
    if custom_bg_enabled then
        custom_bg_image = load_wallpaper_image(custom_bg_path)
    else
        custom_bg_image = nil
    end
end

function background.set_custom_bg_path(path)
    if type(path) == "string" and path ~= "" then
        custom_bg_path = path
    else
        custom_bg_path = nil
    end

    if custom_bg_enabled then
        custom_bg_image = load_wallpaper_image(custom_bg_path)
    end
end

function background.set_wallpaper_blur(enabled)
    wallpaper_blur_enabled = (enabled == true)
end

function background.set_wallpaper_tint(enabled)
    wallpaper_tint_enabled = (enabled == true)
end

function background.set_wallpaper_brightness(mode_index)
    if type(mode_index) ~= "number" then
        wallpaper_brightness = 1
        return
    end
    wallpaper_brightness = math.max(1, math.min(3, math.floor(mode_index)))
end

function background.has_custom_wallpaper()
    return custom_bg_enabled and custom_bg_image ~= nil
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

    -- Draw custom background if enabled
    if custom_bg_enabled and custom_bg_image then
        local sw, sh = custom_bg_image:getDimensions()
        local scale = math.max(screen_w / sw, screen_h / sh)

        local r, g, b = 1, 1, 1
        if wallpaper_tint_enabled then
            local bg = theme.colors.background
            if theme.current_mode == "Light" then
                r, g, b = bg[1] + 0.4, bg[2] + 0.4, bg[3] + 0.4
            else
                r, g, b = bg[1] * 3.0, bg[2] * 3.0, bg[3] * 3.0
            end
        end

        if wallpaper_brightness == 2 then
            r, g, b = r * 1.5, g * 1.5, b * 1.5
        elseif wallpaper_brightness == 3 then
            r, g, b = r * 0.5, g * 0.5, b * 0.5
        end

        if wallpaper_blur_enabled and blur_shader then
            love.graphics.setShader(blur_shader)
            blur_shader:send("canvasSize", { screen_w, screen_h })
            blur_shader:send("radius", 5.0)
        end

        love.graphics.setColor(r, g, b, 1)

        love.graphics.draw(custom_bg_image, screen_w / 2, screen_h / 2, 0, scale, scale, sw / 2, sh / 2)
        love.graphics.setShader()
    end

    -- Draw PSP waves only if music player is NOT active and custom background is NOT enabled
    if not (music and music.active) and not custom_bg_enabled then
        draw_psp_waves()
    end

    -- Draw music visualizer based on selected mode
    if music and music.playing then
        if music.visualizer_mode == "wave" then
            draw_waveform(music)
        elseif music.visualizer_mode == "bars" then
            draw_bars_visualizer(music)
        end
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
