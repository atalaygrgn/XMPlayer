local theme = require("theme")
local assets = require("assets")
local utils = require("utils")
local viewport = require("viewport")
local runtime_state = require("runtime_state")
local settings = require("settings")
local ui = {}

ui.active_toasts = {}

function ui.measure_text_width(font, text)
    return font:getWidth(text or "")
end

function ui.measure_text_height(font)
    return font:getHeight()
end

function ui.print_text(text, x, y, font, color)
    if font then
        love.graphics.setFont(font)
    end
    if color then
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    end
    local scale = (simpleScale and simpleScale.scale) or 1
    if scale ~= 1 then
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(1 / scale, 1 / scale)
        love.graphics.print(text or "", 0, 0)
        love.graphics.pop()
    else
        love.graphics.print(text or "", x, y)
    end
end

function ui.printf_text(text, x, y, limit, align, font, color)
    if font then
        love.graphics.setFont(font)
    end
    if color then
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    end
    local scale = (simpleScale and simpleScale.scale) or 1
    if scale ~= 1 then
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(1 / scale, 1 / scale)
        love.graphics.printf(text or "", 0, 0, (limit or 0) * scale, align)
        love.graphics.pop()
    else
        love.graphics.printf(text or "", x, y, limit or 0, align)
    end
end

-- Gloss Shader for premium glass icons (Static 3D look)
ui.gloss_shader = love.graphics.newShader [[
    uniform vec3 accent_color;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        if (texcolor.a <= 0.001) return vec4(0.0);

        // Base color with vertex tint
        vec4 base = texcolor * color;

        // Slightly tint base color to the accent theme color, then dim it to 88% to let gloss pop
        vec3 surface = mix(base.rgb, accent_color, 0.2) * 0.88;

        // 3D Bottom Highlight (Static) with larger vertical radius
        // Concentrated at the bottom, falling off towards the center
        float bottom_glow = smoothstep(0.3, 1.0, texture_coords.y);
        float horizontal_focus = 1.0 - pow(abs(texture_coords.x - 0.5) * 1.8, 2.0);
        float gloss = clamp(bottom_glow * horizontal_focus, 0.0, 1.0) * 0.45 * texcolor.a;

        // Subtle top darkening to enhance depth
        float top_dim = smoothstep(0.4, 0.0, texture_coords.y) * 0.18;

        vec4 res = vec4(surface, base.a);
        res.rgb = res.rgb * (1.0 - top_dim) + vec3(1.0) * gloss;

        return res;
    }
]]

-- Marquee component state management and rendering
function ui.new_marquee(max_width, speed, pause_start, pause_end)
    return {
        offset = 0,
        timer = 0,
        phase = "pause_start",
        max_width = max_width or 200,
        speed = speed or 40,
        pause_start = pause_start or 3.0,
        pause_end = pause_end or 1.5
    }
end

function ui.update_marquee(m, dt, text_width)
    if text_width <= m.max_width then
        m.offset = 0
        m.timer = 0
        m.phase = "pause_start"
        return
    end

    local max_offset = text_width - m.max_width + 20
    m.timer = m.timer + dt

    if m.phase == "pause_start" then
        if m.timer > m.pause_start then
            m.phase = "scrolling"
            m.timer = 0
        end
    elseif m.phase == "scrolling" then
        m.offset = m.offset + dt * m.speed
        if m.offset >= max_offset then
            m.offset = max_offset
            m.phase = "pause_end"
            m.timer = 0
        end
    elseif m.phase == "pause_end" then
        if m.timer > m.pause_end then
            m.offset = 0
            m.phase = "pause_start"
            m.timer = 0
        end
    end
end

function ui.draw_marquee(m, text, x, y, font, color, abs_x, abs_y, glow_color)
    local text_w = ui.measure_text_width(font, text)
    love.graphics.setFont(font)
    local alpha = color[4] or 1

    local function draw_text(ox, oy, c)
        love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
        if text_w > m.max_width then
            local sx = abs_x or x
            local sy = abs_y or y
            viewport.set_scissor(sx, sy, m.max_width, ui.measure_text_height(font) + 4)
            ui.print_text(text, x - m.offset + (ox or 0), y + (oy or 0), font)
            love.graphics.setScissor()
        else
            ui.print_text(text, x + (ox or 0), y + (oy or 0), font)
        end
    end
    -- Adaptive intensities
    local shadow_alpha = theme.shadow_intensity * alpha
    local glow_mult = (theme.current_mode == "Dark") and 1.5 or 1.3

    -- Draw Smudged Shadow
    for i = 1, 4 do
        local offset = i + 1
        local layer_alpha = shadow_alpha * (1.1 - i * 0.25)
        draw_text(offset, offset, { 0, 0, 0, layer_alpha })
    end

    if glow_color then
        for i = 1, theme.glow_radius do
            local layer_alpha = (theme.glow_intensity * glow_mult / i) * alpha
            draw_text(-i, 0, { glow_color[1], glow_color[2], glow_color[3], layer_alpha })
            draw_text(i, 0, { glow_color[1], glow_color[2], glow_color[3], layer_alpha })
            draw_text(0, -i, { glow_color[1], glow_color[2], glow_color[3], layer_alpha })
            draw_text(0, i, { glow_color[1], glow_color[2], glow_color[3], layer_alpha })
        end
    end

    draw_text(0, 0, color)
end

-- Progress bar component
function ui.draw_progress_bar(x, y, w, h, progress, color, bg_color)
    -- Background
    love.graphics.setColor(bg_color[1], bg_color[2], bg_color[3], bg_color[4] or 0.1)
    love.graphics.rectangle("fill", x, y, w, h, 2, 2)

    -- Fill
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.9)
    love.graphics.rectangle("fill", x, y, w * progress, h, 2, 2)
end

-- Icon helper
function ui.draw_indexing_popup(progress_text, final_message)
    local screen_w, screen_h = viewport.get()
    local accent = theme.accent
    local t = love.timer.getTime()

    -- Centered product title
    local title_font = assets.fonts.large
    ui.draw_glow_text("XMPlayer", 0, screen_h * 0.5 - ui.measure_text_height(title_font) * 0.5, title_font,
        { 1, 1, 1, 1 }, accent, screen_w, "center")

    -- Top-left version tag
    local version_opt = settings.get_option("version")
    local version_str = version_opt and version_opt.value or "v0.2.1 Sage Symphony"
    ui.print_text(version_str, 20, 20, assets.fonts.xs, { accent[1], accent[2], accent[3], 0.75 })

    -- Bottom-right indexing status with subtle pulse
    local status = progress_text or "Scanning media..."
    local status_text
    if final_message then
        status_text = status
    else
        local dots = string.rep(".", (math.floor(t * 2) % 3) + 1)
        status_text = "Indexing" .. dots .. "  " .. status
    end

    local status_font = assets.fonts.xs or assets.fonts.small
    local sw = ui.measure_text_width(status_font, status_text)
    local pulse = 0.62 + (math.sin(t * 3.0) + 1) * 0.14
    love.graphics.setColor(accent[1], accent[2], accent[3], pulse)
    ui.print_text(status_text, screen_w - sw - 20, screen_h - 36, status_font)
end

function ui.draw_icon(icon, x, y, size, color, alpha, thumbnail, rotation, no_tint)
    if not icon and not thumbnail then return end
    rotation = rotation or 0

    if thumbnail and type(thumbnail) ~= "string" then
        local iw = thumbnail:getWidth()
        local ih = thumbnail:getHeight()
        local scale = size / math.max(iw, ih)
        -- Thumbnails should keep their original colors.
        love.graphics.setShader()
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(thumbnail, x, y, rotation, scale, scale, iw / 2, ih / 2)
    elseif icon then
        -- Apply Gloss Shader for monochrome/theme-tinted icons only.
        if not no_tint then
            if ui.gloss_shader:hasUniform("accent_color") and theme and theme.accent then
                ui.gloss_shader:send("accent_color", { theme.accent[1], theme.accent[2], theme.accent[3] })
            end
            love.graphics.setShader(ui.gloss_shader)
        else
            love.graphics.setShader()
        end
        local img_w = icon:getWidth()
        local img_h = icon:getHeight()
        local scale = size / math.max(img_w, img_h)
        love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
        love.graphics.draw(icon, x, y, rotation, scale, scale, img_w / 2, img_h / 2)
    end

    love.graphics.setShader()
end

-- Draw text with a soft glow effect
function ui.draw_glow_text(text, x, y, font, color, glow_color, limit, align)
    local alpha = color[4] or 1
    if font then
        love.graphics.setFont(font)
    end

    -- Adaptive intensities
    local shadow_alpha = theme.shadow_intensity * alpha
    local glow_mult = (theme.current_mode == "Dark") and 1.5 or 1.3

    -- Draw Smudged Shadow
    for i = 1, 4 do
        local offset = i + 1
        local layer_alpha = shadow_alpha * (1.1 - i * 0.25)
        love.graphics.setColor(0, 0, 0, layer_alpha)
        if limit and align then
            ui.printf_text(text, x + offset, y + offset, limit, align, font)
        else
            ui.print_text(text, x + offset, y + offset, font)
        end
    end

    -- Draw glow layers
    if glow_color then
        local gc = glow_color or theme.accent
        for i = 1, theme.glow_radius do
            local layer_alpha = (theme.glow_intensity * glow_mult / i) * alpha
            love.graphics.setColor(gc[1], gc[2], gc[3], layer_alpha)
            if limit and align then
                ui.printf_text(text, x - i, y, limit, align, font)
                ui.printf_text(text, x + i, y, limit, align, font)
                ui.printf_text(text, x, y - i, limit, align, font)
                ui.printf_text(text, x, y + i, limit, align, font)
            else
                ui.print_text(text, x - i, y, font)
                ui.print_text(text, x + i, y, font)
                ui.print_text(text, x, y - i, font)
                ui.print_text(text, x, y + i, font)
            end
        end
    end

    -- Main text
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    if limit and align then
        ui.printf_text(text, x, y, limit, align, font)
    else
        ui.print_text(text, x, y, font)
    end
end

-- Draw icon/thumbnail with a soft glow effect
function ui.draw_glow_icon(icon, x, y, size, color, alpha, glow_color, thumbnail, rotation, no_tint)
    local img = (thumbnail and type(thumbnail) ~= "string") and thumbnail or icon
    if not img then return end

    rotation = rotation or 0
    local a = alpha or 1

    local img_w = img:getWidth()
    local img_h = img:getHeight()
    local base_scale = size / math.max(img_w, img_h)

    if thumbnail then
        -- Thumbnails should preserve source colors and avoid theme tinting.
        love.graphics.setShader()
        love.graphics.setColor(1, 1, 1, a)
    else
        -- Adaptive intensities
        local shadow_alpha = theme.shadow_intensity * a
        local glow_base = (theme.current_mode == "Dark") and (theme.glow_intensity * 1.2) or (theme.glow_intensity * 1.1)
        -- Draw Smudged Shadow
        for i = 1, 4 do
            local offset = i + 1
            local layer_alpha = shadow_alpha * (1.1 - i * 0.25)
            love.graphics.setColor(0, 0, 0, layer_alpha)
            love.graphics.draw(img, x + offset, y + offset, rotation, base_scale, base_scale, img_w / 2, img_h / 2)
        end

        -- Draw glow layers
        if glow_color then
            local gc = glow_color or theme.accent
            local time = love.timer.getTime()
            local pulse = 0.8 + 0.2 * math.sin(time * 3) -- Pulse between 0.6 and 1.0

            for i = 1, theme.glow_radius do
                -- Create a smoother, non-linear alpha decay for a softer look
                local layer_alpha = (glow_base * 0.8 / (i ^ 1.2)) * a * pulse
                local scale = base_scale * (1.0 + (i * 0.05)) * (0.98 + pulse * 0.02) -- Adjusted scale pulse

                love.graphics.setColor(gc[1], gc[2], gc[3], layer_alpha)
                love.graphics.draw(img, x, y, rotation, scale, scale, img_w / 2, img_h / 2)
            end
        end

        -- Main image
        if not no_tint then
            if ui.gloss_shader:hasUniform("accent_color") and theme and theme.accent then
                ui.gloss_shader:send("accent_color", { theme.accent[1], theme.accent[2], theme.accent[3] })
            end
            love.graphics.setShader(ui.gloss_shader)
        else
            love.graphics.setShader()
        end
        love.graphics.setColor(color[1], color[2], color[3], a)
    end
    love.graphics.draw(img, x, y, rotation, base_scale, base_scale, img_w / 2, img_h / 2)

    love.graphics.setShader()
end

-- Toast Notification System
function ui.show_toast(text, icon_name, position)
    local toast = {
        text = text,
        icon = icon_name and assets.get_image(icon_name) or nil,
        position = position or "top_center",
        timer = 3.0,
        fade_time = 0.3,
        alpha = 0
    }
    table.insert(ui.active_toasts, toast)
end

function ui.show_volume_toast(volume)
    -- Check if volume toast already exists
    for _, t in ipairs(ui.active_toasts) do
        if t.type == "volume" then
            t.target_level = volume
            t.timer = 1.5 -- Show for 1.5 seconds when changed
            return
        end
    end

    local toast = {
        type = "volume",
        target_level = volume,
        display_level = volume, -- Start at current for first showing
        position = "top_center",
        timer = 1.5,
        fade_time = 0.3,
        alpha = 0
    }
    table.insert(ui.active_toasts, toast)
end

function ui.show_brightness_toast(brightness)
    -- Check if brightness toast already exists
    for _, t in ipairs(ui.active_toasts) do
        if t.type == "brightness" then
            t.target_level = brightness
            t.timer = 1.5
            return
        end
    end

    local toast = {
        type = "brightness",
        target_level = brightness,
        display_level = brightness, -- Start at current for first showing
        position = "top_center",
        timer = 1.5,
        fade_time = 0.3,
        alpha = 0
    }
    table.insert(ui.active_toasts, toast)
end

function ui.update_toasts(dt)
    for i = #ui.active_toasts, 1, -1 do
        local t = ui.active_toasts[i]
        t.timer = t.timer - dt

        -- Lerp level for volume/brightness
        if t.display_level and t.target_level then
            t.display_level = utils.lerp(t.display_level, t.target_level, dt * 10)
        end

        -- Handle alpha for fade in/out
        if t.timer > 2.7 then
            t.alpha = (3.0 - t.timer) / 0.3
        elseif t.timer < 0.3 then
            t.alpha = t.timer / 0.3
        else
            t.alpha = 1
        end

        if t.timer <= 0 then
            table.remove(ui.active_toasts, i)
        end
    end
end

function ui.draw_toasts()
    local sw, sh = viewport.get()
    local font = assets.fonts.small
    local padding = 15
    local icon_size = 28

    for _, t in ipairs(ui.active_toasts) do
        local box_w, box_h
        local x, y

        if t.type == "volume" or t.type == "brightness" then
            local icon_size = (runtime_state.current_view == "music") and 24 or 28
            local spacing = 8
            local max_bar_w = 180
            local bar_w = math.min(max_bar_w, math.max(40, sw * 0.45))

            local overlay_y = (runtime_state.current_view == "music") and 12 or 26
            local overlay_h = 18
            local bar_h = 8

            -- Group width (icon + gap + bar)
            local group_w = icon_size + spacing + bar_w
            local group_x = (sw - group_w) / 2

            local icon_cx = group_x + icon_size / 2
            local bar_x = group_x + icon_size + spacing

            local level = t.display_level or t.target_level or 0
            local max_level = (t.type == "brightness") and 255 or 100
            local progress = math.max(0, math.min(1, level / max_level))
            local icon_img

            if t.type == "volume" then
                if (t.target_level or 0) == 0 then
                    icon_img = assets.get_image("volume_mute")
                elseif (t.target_level or 0) < 50 then
                    icon_img = assets.get_image("volume_down")
                else
                    icon_img = assets.get_image("volume_up")
                end
            else
                icon_img = assets.get_image("brightness")
            end

            if icon_img then
                ui.draw_icon(icon_img, icon_cx, overlay_y + overlay_h / 2, icon_size, { 1, 1, 1 }, t.alpha, nil, nil,
                    true)
            end

            ui.draw_progress_bar(bar_x, overlay_y + (overlay_h - bar_h) / 2, bar_w, bar_h, progress,
                { 1, 1, 1, 0.8 * t.alpha },
                { 1, 1, 1, 0.14 * t.alpha })
        else
            local tw = ui.measure_text_width(font, t.text or "")
            local th = ui.measure_text_height(font)
            box_w = tw + padding * 2
            if t.icon then box_w = box_w + icon_size + 10 end
            box_h = math.max(th, icon_size) + padding

            if t.position == "top_center" then
                x = (sw - box_w) / 2
                y = 4 + (1 - t.alpha) * -20 -- Subtle float animation
            else                            -- bottom_right
                x = sw - box_w - 30
                y = sh - box_h - 30 + (1 - t.alpha) * 20
            end

            -- Background (Glassmorphism look)
            love.graphics.setColor(0.1, 0.1, 0.15, 0.85 * t.alpha)
            love.graphics.rectangle("fill", x, y, box_w, box_h, 12, 12)

            -- Border with accent color
            local ac = theme.accent
            love.graphics.setColor(ac[1], ac[2], ac[3], 0.5 * t.alpha)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x, y, box_w, box_h, 12, 12)

            -- Icon
            local cur_x = x + padding
            if t.icon then
                ui.draw_icon(t.icon, cur_x + icon_size / 2, y + box_h / 2, icon_size, { 1, 1, 1 }, t.alpha)
                cur_x = cur_x + icon_size + 10
            end

            -- Text
            ui.print_text(t.text or "", cur_x, y + (box_h - th) / 2, font, { 1, 1, 1, t.alpha })
        end
    end
end

return ui
