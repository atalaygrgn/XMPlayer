local theme = require("theme")
local utils = require("utils")
local settings = require("settings")
local xmb = require("xmb")
local categories = require("categories")
local viewport = require("viewport")
local assets = require("assets")

local background = {}

local particles = {}
local screen_w, screen_h
local speed = 1.0
local target_speed = 1.0
local gradient_mesh
local background_mode = 1 -- 1: Waves, 2: Ribbon, 3: Wallpaper
local custom_bg_image = nil
local custom_bg_path = nil
local wallpaper_blur_enabled = true
local wallpaper_tint_enabled = true
local wallpaper_brightness = 1 -- 1: No Change, 2: Brighter, 3: Darker
local wallpaper_type = 1       -- 1: Static, 2: Scrolling, 3: Seamless
local blur_shader = nil

local walk_state
local update_walk, draw_walk

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
        -- allow repeating for seamless textures
        if pcall(function() return img.setWrap end) then
            pcall(function() img:setWrap("repeat", "repeat") end)
        end
    end
    return img
end

function background.set_wallpaper_type(mode_index)
    if type(mode_index) ~= "number" then
        wallpaper_type = 1
        return
    end
    wallpaper_type = math.max(1, math.min(3, math.floor(mode_index)))
end

function background.init()
    screen_w, screen_h = viewport.get()

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
    target_speed = is_paused and 0.15 or 1.25
    -- Smoothly transition speed
    local speed_lerp_t = math.min(1, dt * 2)
    speed = utils.lerp(speed, target_speed, speed_lerp_t)

    -- Update particles
    if settings.show_particles then
        -- Returning from external players can produce a very large dt.
        -- Clamp integration time so particles do not all wrap to the left at once.
        local particle_dt = math.min(dt, 1 / 30)
        local vertical_drift = is_paused and 2.0 or 5.0
        for _, p in ipairs(particles) do
            p.x = p.x + p.speed * particle_dt * speed * 0.5
            p.y = p.y + math.sin((p.x + p.size) * 0.02 + love.timer.getTime() * 0.8) * particle_dt * vertical_drift
            if p.x > screen_w then
                p.x = -10
                p.y = math.random() * screen_h
            elseif p.y < -10 then
                p.y = screen_h + 10
            elseif p.y > screen_h + 10 then
                p.y = -10
            end
        end
    end

    local music = require("music_player")
    if music and music.active and music.visualizer_mode == "walk" then
        update_walk(dt, music)
    else
        walk_state.initialized = false
    end
end

walk_state = {
    initialized = false,
    beat_timer = 0,
    runner = {
        x = 0,
        y = 0,
        vy = 0,
        is_jumping = false,
        jump_t = 0,
        jump_dur = 0.5,
        jump_height = 0,
        base_y = 0,
        run_cycle = 0,
        flip_angle = 0,
    },
    blocks = {},
    trail_particles = {},
    sprout_types = { "flower", "star", "diamond" },
    scroll_speed = 180,

    base_jump_height = 40,
    max_jump_height = 80,
    base_sprout_height = 20,
    max_sprout_height = 80,
}

local function init_walk()
    local w, h = screen_w or 640, screen_h or 480
    walk_state.runner.x = w * 0.4
    walk_state.runner.base_y = h * 0.75
    walk_state.runner.y = walk_state.runner.base_y
    walk_state.runner.vy = 0
    walk_state.runner.is_jumping = false
    walk_state.runner.jump_t = 0
    walk_state.runner.run_cycle = 0
    walk_state.runner.flip_angle = 0

    walk_state.beat_timer = 0
    walk_state.blocks = {}
    walk_state.stars = {}
    walk_state.trail_particles = {}

    local spacing = walk_state.scroll_speed * 0.5
    for i = 0, 8 do
        local bx = walk_state.runner.x + i * spacing
        table.insert(walk_state.blocks, {
            x = bx,
            y = walk_state.runner.base_y + 15,
            opened = false,
            sprout_height = 0,
            sprout_max_height = 0,
            sprout_type = "flower"
        })
    end



    walk_state.initialized = true
end

update_walk = function(dt, music)
    if not walk_state.initialized then
        init_walk()
    end

    if music.paused then
        local run = walk_state.runner
        if run.y < run.base_y then
            run.y = math.min(run.base_y, run.y + 500 * dt)
            run.flip_angle = utils.smooth(run.flip_angle, 0, dt, 10)
            if run.y >= run.base_y then
                run.is_jumping = false
                run.flip_angle = 0
            end
        else
            run.y = run.base_y
            run.is_jumping = false
            run.flip_angle = 0
        end
        return
    end

    local rms = 0.05
    local treble = 0.05
    if music.sound_data then
        local SAMPLE_RATE = music.sound_data.getSampleRate and music.sound_data:getSampleRate() or 44100
        local current_sample = math.floor(music.elapsed * SAMPLE_RATE)
        local total_samples = music.sound_data:getSampleCount()

        local window = 512
        local sum = 0
        local diff_sum = 0
        for i = 0, window - 1, 16 do
            local s_idx = math.min(total_samples - 1, current_sample + i)
            local sample = music.sound_data:getSample(s_idx)
            sum = sum + sample * sample

            local s_next = math.min(total_samples - 1, s_idx + 1)
            local diff = sample - music.sound_data:getSample(s_next)
            diff_sum = diff_sum + diff * diff
        end
        rms = math.sqrt(sum / (window / 16))
        treble = math.sqrt(diff_sum / (window / 16))
    end


    walk_state.runner.run_cycle = walk_state.runner.run_cycle + dt * 12
    walk_state.beat_timer = walk_state.beat_timer + dt

    if walk_state.beat_timer >= 0.5 then
        walk_state.beat_timer = walk_state.beat_timer - 0.5

        if walk_state.runner.is_jumping then
            walk_state.runner.is_jumping = false
            walk_state.runner.flip_angle = 0

            local closest_block = nil
            local min_dist = 9999
            for _, b in ipairs(walk_state.blocks) do
                local dist = math.abs(b.x - walk_state.runner.x)
                if dist < min_dist then
                    min_dist = dist
                    closest_block = b
                end
            end

            if closest_block and not closest_block.opened then
                closest_block.opened = true
                closest_block.sprout_max_height = walk_state.base_sprout_height +
                    math.min(walk_state.max_sprout_height, rms * 350)
                closest_block.sprout_type = walk_state.sprout_types[math.random(1, #walk_state.sprout_types)]

                for k = 1, 12 do
                    local angle = math.random() * math.pi * 2
                    local p_speed = 30 + math.random() * 80
                    table.insert(walk_state.trail_particles, {
                        x = walk_state.runner.x,
                        y = walk_state.runner.base_y,
                        vx = math.cos(angle) * p_speed,
                        vy = -math.random(10, 80),
                        size = math.random(15, 35) / 10,
                        alpha = 1.0,
                        life = 0.4 + math.random() * 0.3,
                        color = { theme.accent[1], theme.accent[2], theme.accent[3] }
                    })
                end
            end
        end

        walk_state.runner.is_jumping = true
        walk_state.runner.jump_t = 0
        walk_state.runner.jump_height = walk_state.base_jump_height + math.min(walk_state.max_jump_height, rms * 400)
    end

    if walk_state.runner.is_jumping then
        walk_state.runner.jump_t = walk_state.runner.jump_t + dt
        if walk_state.runner.jump_t > 0.5 then
            walk_state.runner.jump_t = 0.5
        end
        local progress = walk_state.runner.jump_t / 0.5
        walk_state.runner.y = walk_state.runner.base_y - walk_state.runner.jump_height * math.sin(progress * math.pi)

        if walk_state.runner.jump_height > 100 then
            walk_state.runner.flip_angle = progress * math.pi * 2
        else
            walk_state.runner.flip_angle = 0
        end
    else
        walk_state.runner.y = walk_state.runner.base_y
        walk_state.runner.flip_angle = 0
    end

    for _, b in ipairs(walk_state.blocks) do
        b.x = b.x - walk_state.scroll_speed * dt
        if b.opened and b.sprout_height < b.sprout_max_height then
            b.sprout_height = utils.smooth(b.sprout_height, b.sprout_max_height, dt, 8)
        end
    end

    for i = #walk_state.blocks, 1, -1 do
        if walk_state.blocks[i].x < -100 then
            table.remove(walk_state.blocks, i)
        end
    end

    local rightmost_x = -100
    for _, b in ipairs(walk_state.blocks) do
        if b.x > rightmost_x then
            rightmost_x = b.x
        end
    end
    local w = screen_w or 640
    local spacing = walk_state.scroll_speed * 0.5
    if rightmost_x < w + 200 then
        table.insert(walk_state.blocks, {
            x = rightmost_x + spacing,
            y = walk_state.runner.base_y + 15,
            opened = false,
            sprout_height = 0,
            sprout_max_height = 0,
            sprout_type = "flower"
        })
    end

    for i = #walk_state.trail_particles, 1, -1 do
        local p = walk_state.trail_particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 200 * dt
        p.life = p.life - dt
        p.alpha = math.max(0, p.life / 0.5)
        if p.life <= 0 then
            table.remove(walk_state.trail_particles, i)
        end
    end
end

draw_walk = function(music)
    if not walk_state.initialized then return end

    local alpha = music.fade_alpha or 1
    love.graphics.push("all")



    for _, b in ipairs(walk_state.blocks) do
        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.7 * alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", b.x - 15, b.y - 15, 30, 30, 4, 4)

        love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.15 * alpha)
        love.graphics.rectangle("fill", b.x - 14, b.y - 14, 28, 28, 4, 4)

        love.graphics.setColor(1, 1, 1, 0.8 * alpha)
        love.graphics.circle("fill", b.x, b.y, 3)

        if b.opened then
            local r_scale = math.min(15, b.sprout_height * 0.5)
            love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], (1 - r_scale / 15) * 0.8 * alpha)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", b.x, b.y, r_scale)
        end

        if b.sprout_height > 0 then
            local hx, hy = b.x, b.y - 15 - b.sprout_height
            love.graphics.setColor(0.3, 0.8, 0.4, 0.8 * alpha)
            love.graphics.setLineWidth(2)
            love.graphics.line(b.x, b.y - 15, b.x, b.y - 15 - b.sprout_height)

            if b.sprout_height > 10 then
                love.graphics.circle("fill", b.x - 3, b.y - 15 - b.sprout_height * 0.4, 2)
                love.graphics.circle("fill", b.x + 3, b.y - 15 - b.sprout_height * 0.7, 2)
            end

            if b.sprout_type == "flower" then
                love.graphics.setColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha)
                love.graphics.circle("fill", hx, hy, 3.5)
                love.graphics.setColor(1, 0.5, 0.7, 0.75 * alpha)
                love.graphics.circle("fill", hx - 3.5, hy, 2.5)
                love.graphics.circle("fill", hx + 3.5, hy, 2.5)
                love.graphics.circle("fill", hx, hy - 3.5, 2.5)
                love.graphics.circle("fill", hx, hy + 3.5, 2.5)
            elseif b.sprout_type == "star" then
                love.graphics.setColor(1, 0.9, 0.3, 0.9 * alpha)
                love.graphics.line(hx - 5, hy, hx + 5, hy)
                love.graphics.line(hx, hy - 5, hx, hy + 5)
                love.graphics.circle("fill", hx, hy, 1.5)
            else
                love.graphics.setColor(0.3, 0.7, 1.0, 0.9 * alpha)
                love.graphics.polygon("fill", hx, hy - 5, hx + 3.5, hy, hx, hy + 5, hx - 3.5, hy)
            end
        end
    end

    for _, p in ipairs(walk_state.trail_particles) do
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], p.alpha * alpha)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end

    local run = walk_state.runner
    local img = assets.images.walker or assets.get_image("walker")
    if img then
        local img_w, img_h = img:getDimensions()

        local target_h = 32
        local scale = target_h / img_h

        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.push()
        love.graphics.translate(run.x, run.y - target_h / 2)
        love.graphics.rotate(run.flip_angle)

        love.graphics.draw(img, 0, 0, 0, scale, scale, img_w / 2, img_h / 2)
        love.graphics.pop()
    end

    love.graphics.pop()
end

local function draw_waveform(music)
    if not music or not music.playing or not music.sound_data then return end

    local w, h = screen_w, screen_h
    local samples = 120 -- How many points in our waveform
    local amplitude = h * 0.1

    -- Calculate current sample index from elapsed time
    local SAMPLE_RATE = music.sound_data.getSampleRate and music.sound_data:getSampleRate() or 44100
    local current_sample = math.floor(music.elapsed * SAMPLE_RATE)
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
            local y = (h * 0.65) + (audio_sample * reactive_amp) + y_offset

            table.insert(points, x)
            table.insert(points, y)
        end

        if #points >= 4 then
            love.graphics.line(points)
        end
    end
end

local function draw_bars_visualizer(music)
    if not music or not music.playing or not music.sound_data then return end

    local w, h = screen_w, screen_h
    local bars = 42
    local gap = 4
    local bottom_y = h
    local max_h = h * 0.2
    local total_width = w
    local bar_w = (total_width - (bars - 1) * gap) / bars
    local start_x = (w - total_width) * 0.5

    -- Calculate current sample index from elapsed time
    local SAMPLE_RATE = music.sound_data.getSampleRate and music.sound_data:getSampleRate() or 44100
    local current_sample = math.max(0, math.floor(music.elapsed * SAMPLE_RATE))
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
        local strength = math.min(1.0, rms * 2)
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

local function draw_particle(p)
    local red, green, blue = theme.accent[1], theme.accent[2], theme.accent[3]
    local base_radius = math.max(1, p.size)
    local segments = math.max(12, math.floor(base_radius * 8))
    local opacity = p.alpha * 0.2

    love.graphics.setColor(red, green, blue, opacity * 0.08)
    love.graphics.circle("fill", p.x, p.y, base_radius * 2, segments)

    love.graphics.setColor(red, green, blue, opacity * 0.18)
    love.graphics.circle("fill", p.x, p.y, base_radius * 1, segments)

    love.graphics.setColor(1, 1, 1, opacity * 0.5)
    love.graphics.circle("fill", p.x, p.y, base_radius, segments)
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

local function draw_ribbon_layer(time, base_y, amplitude, base_thickness, variation_thick, opacity, speed_t, freq_x,
                                 seed_offset)
    local w, h = screen_w, screen_h
    local segments = 60

    local r, g, b = theme.accent[1], theme.accent[2], theme.accent[3]

    if theme.current_mode == "Light" then
        local tint_factor = 0.3
        r = r * (1 - tint_factor) + tint_factor
        g = g * (1 - tint_factor) + tint_factor
        b = b * (1 - tint_factor) + tint_factor
        opacity = math.min(1.0, opacity * 1.3)
    end

    local color_center = { r, g, b, opacity }
    local color_edge = { r, g, b, 0 }

    local vertices_top = {}
    local vertices_bottom = {}

    for i = 0, segments do
        local u = i / segments
        local x = u * w

        -- High quality noise-based movement: combining a main wave and a secondary harmonic
        local noise_val1 = love.math.noise(u * freq_x + time * speed_t, seed_offset)
        local noise_val2 = love.math.noise(u * freq_x * 2.5 - time * speed_t * 1.5, seed_offset + 10)
        local combined_noise = (noise_val1 * 2 - 1) + 0.3 * (noise_val2 * 2 - 1)

        local y = base_y + combined_noise * amplitude

        -- Thickness modulation using noise
        local thick_noise = love.math.noise(u * (freq_x * 0.5) + time * (speed_t * 0.5), seed_offset + 20)
        local half_thick = (base_thickness + thick_noise * variation_thick) * 0.5

        -- Top half vertices (strip zig-zag: edge, center, edge, center...)
        table.insert(vertices_top,
            { x, y - half_thick, 0, 0, color_edge[1], color_edge[2], color_edge[3], color_edge[4] })
        table.insert(vertices_top,
            { x, y, 0, 0, color_center[1], color_center[2], color_center[3], color_center[4] })

        -- Bottom half vertices
        table.insert(vertices_bottom,
            { x, y, 0, 0, color_center[1], color_center[2], color_center[3], color_center[4] })
        table.insert(vertices_bottom,
            { x, y + half_thick, 0, 0, color_edge[1], color_edge[2], color_edge[3], color_edge[4] })
    end

    local mesh_top = love.graphics.newMesh(vertices_top, "strip", "stream")
    local mesh_bottom = love.graphics.newMesh(vertices_bottom, "strip", "stream")

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh_top)
    love.graphics.draw(mesh_bottom)
end

local function draw_ribbon_background()
    local h = screen_h
    local time = love.timer.getTime()

    -- Ribbons
    -- Background layer
    draw_ribbon_layer(time, h * 0.58, h * 0.09, 80, 40, 0.45, 0.04, 0.6, 1.0)
    -- Middle layer
    draw_ribbon_layer(time, h * 0.55, h * 0.10, 60, 30, 0.4, -0.07, 1.0, 5.0)
    -- Foreground layer
    draw_ribbon_layer(time, h * 0.58, h * 0.08, 60, 20, 0.35, 0.10, 1.4, 10.0)
end

local current_wallpaper_path = nil
local is_loading_wallpaper = false

function background.set_wallpaper_texture(img)
    if custom_bg_image and custom_bg_image.release and custom_bg_image ~= img then
        pcall(function() custom_bg_image:release() end)
    end
    custom_bg_image = img
    is_loading_wallpaper = false
end

function background.ensure_wallpaper_worker()
    if not background.wallpaper_in_chan then
        background.wallpaper_in_chan = love.thread.getChannel("wallpaper_in")
        background.wallpaper_out_chan = love.thread.getChannel("wallpaper_out")
        background.wallpaper_thread = love.thread.newThread("workers/wallpaper_worker.lua")
        background.wallpaper_thread:start("wallpaper_in", "wallpaper_out")
    end
end

function background.load_wallpaper_async(path)
    local resolved_path = (type(path) == "string" and path ~= "") and path or "assets/background/bg.jpg"
    if current_wallpaper_path == resolved_path and (custom_bg_image ~= nil or is_loading_wallpaper) then
        return
    end

    current_wallpaper_path = resolved_path
    is_loading_wallpaper = true

    background.ensure_wallpaper_worker()
    if background.wallpaper_in_chan then
        background.wallpaper_in_chan:push({
            type = "load_wallpaper",
            path = resolved_path
        })
    end
end

function background.set_background_mode(mode)
    -- mode: 1 = Waves, 2 = Ribbon, 3 = Wallpaper
    local new_mode = math.max(1, math.min(3, math.floor(mode)))
    if new_mode == background_mode and (new_mode ~= 3 or custom_bg_image ~= nil or is_loading_wallpaper) then
        return
    end

    background_mode = new_mode
    if background_mode == 3 then
        if not custom_bg_image then
            if love.timer and love.timer.getTime() < 2.0 then
                custom_bg_image = load_wallpaper_image(custom_bg_path)
                current_wallpaper_path = custom_bg_path or "assets/background/bg.jpg"
            else
                background.load_wallpaper_async(custom_bg_path)
            end
        end
    else
        if custom_bg_image and custom_bg_image.release then
            pcall(function() custom_bg_image:release() end)
        end
        custom_bg_image = nil
        is_loading_wallpaper = false
    end
end

function background.set_custom_bg(enabled)
    background.set_background_mode(enabled and 3 or 1)
end

function background.set_custom_bg_path(path)
    local new_path = (type(path) == "string" and path ~= "") and path or nil
    if new_path == custom_bg_path and (background_mode ~= 3 or custom_bg_image ~= nil or is_loading_wallpaper) then
        return
    end

    custom_bg_path = new_path
    if background_mode == 3 then
        if love.timer and love.timer.getTime() < 2.0 then
            custom_bg_image = load_wallpaper_image(custom_bg_path)
            current_wallpaper_path = custom_bg_path or "assets/background/bg.jpg"
        else
            background.load_wallpaper_async(custom_bg_path)
        end
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
    wallpaper_brightness = math.max(1, math.min(5, math.floor(mode_index)))
end

function background.has_custom_wallpaper()
    return background_mode == 3 and custom_bg_image ~= nil
end

function background.draw(music)
    -- Poll dedicated wallpaper worker thread
    if background.wallpaper_out_chan then
        local res = background.wallpaper_out_chan:pop()
        if res and res.type == "wallpaper_result" then
            if res.img_data then
                local ok, img = pcall(love.graphics.newImage, res.img_data)
                res.img_data:release()
                if ok and img then
                    img:setFilter("linear", "linear")
                    pcall(function() img:setWrap("repeat", "repeat") end)
                    background.set_wallpaper_texture(img)
                end
            end
        end
    end
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

    -- Draw background based on selected mode
    if background_mode == 3 and custom_bg_image then
        -- Wallpaper mode
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
            r, g, b = r * 0.75, g * 0.75, b * 0.75
        elseif wallpaper_brightness == 3 then
            r, g, b = r * 0.5, g * 0.5, b * 0.5
        elseif wallpaper_brightness == 4 then
            r, g, b = r * 1.25, g * 1.25, b * 1.25
        elseif wallpaper_brightness == 5 then
            r, g, b = r * 1.5, g * 1.5, b * 1.5
        end

        if wallpaper_blur_enabled and blur_shader then
            love.graphics.setShader(blur_shader)
            blur_shader:send("canvasSize", { screen_w, screen_h })
            blur_shader:send("radius", 5.0)
        end

        love.graphics.setColor(r, g, b, 1)

        local scaled_w = sw * scale
        local scaled_h = sh * scale

        if wallpaper_type == 1 then
            -- Static: centered image (default)
            love.graphics.draw(custom_bg_image, screen_w / 2, screen_h / 2, 0, scale, scale, sw / 2, sh / 2)
        elseif wallpaper_type == 2 then
            -- Scrolling: shift X based on category scroll position (limited to image bounds)
            local step = (theme.icon_size + theme.icon_spacing)
            local total_range = 0
            if #categories and #categories > 1 then
                total_range = -(#categories - 1) * step
            end
            local cat_scroll = xmb and xmb.category_scroll_x or 0
            local normalized = 0.5
            if total_range ~= 0 then
                normalized = (cat_scroll - total_range) / (0 - total_range)
            end
            normalized = math.max(0, math.min(1, normalized))
            local max_shift = math.max(0, scaled_w - screen_w)
            local x_offset = (normalized - 0.5) * max_shift
            love.graphics.draw(custom_bg_image, screen_w / 2 + x_offset, screen_h / 2, 0, scale, scale, sw / 2, sh / 2)
        else
            -- Seamless: tile horizontally and slowly translate texture
            local t = love.timer.getTime()
            local speed_px = -5 -- pixels per second at native scale
            local offset = (t * speed_px) % scaled_w
            local tiles = math.ceil(screen_w / scaled_w) + 2
            local base_x = screen_w / 2 - offset
            for k = -1, tiles do
                local cx = base_x + k * scaled_w
                love.graphics.draw(custom_bg_image, cx, screen_h / 2, 0, scale, scale, sw / 2, sh / 2)
            end
        end

        love.graphics.setShader()
    end

    -- Draw background waves based on selected mode
    if not (music and music.active) then
        if background_mode == 1 then
            draw_psp_waves()
        elseif background_mode == 2 then
            draw_ribbon_background()
        end
    end

    -- Draw music visualizer based on selected mode
    if music and music.playing then
        if music.visualizer_mode == "wave" then
            draw_waveform(music)
        elseif music.visualizer_mode == "bars" then
            draw_bars_visualizer(music)
        elseif music.visualizer_mode == "walk" then
            draw_walk(music)
        end
    end

    -- Draw particles
    if settings.show_particles then
        for _, p in ipairs(particles) do
            draw_particle(p)
        end
    end
end

return background
