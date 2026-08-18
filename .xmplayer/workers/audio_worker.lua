-- audio_worker.lua
-- Background thread worker for FFmpeg audio streaming via io.popen
-- Receives media path and streams PCM data to main thread via channel

local mediaPath = ...
local streamChannelName = select(2, ...)
local controlChannelName = select(3, ...)
local generation = select(4, ...)
local seekTime = select(5, ...)
local targetSampleRate = tonumber(select(6, ...)) or 44100
local audioChannel = love.thread.getChannel(streamChannelName or "audio_stream_channel")
local controlChannel = love.thread.getChannel(controlChannelName or "audio_control_channel")

local seekOpt = ""
if seekTime and tonumber(seekTime) and tonumber(seekTime) > 0 then
    seekOpt = string.format("-ss %.3f ", tonumber(seekTime))
end

-- Determine null device based on path separator to redirect stderr safely (thread safe)
local isWindows = (package.config:sub(1, 1) == "\\")
local devNull = isWindows and "NUL" or "/dev/null"

-- love.timer and love.thread are not auto-loaded in thread contexts; require explicitly
require("love.timer")
require("love.thread")

-- Resolve ffmpeg binary path
local ffmpeg_bin = "ffmpeg"
if not isWindows then
    local source_path = love.filesystem.getSource()
    ffmpeg_bin = '"' .. source_path .. '/bin/ffmpeg"'
    -- Ensure the binary is executable
    os.execute("chmod +x " .. ffmpeg_bin .. " 2>/dev/null")
end

-- Detect chip/chiptune format to decide synthesis options.
-- We use the targetSampleRate passed from the main thread; for chip formats it is 22050Hz.
local ext = mediaPath and mediaPath:match("%.([^%.]+)$")
local chipExts = {
    vgm = true,
    vgz = true,
    gbs = true,
    hes = true,
    kss = true,
    nsf = true,
    nsfe = true,
    spc = true
}
local isChip = ext and chipExts[ext:lower()]

-- For chip files: tell libgme to synthesise at the target rate directly.
-- This halves the internal emulation work compared to the default 44100Hz.
local libgmeInputOpt = ""
if isChip then
    libgmeInputOpt = string.format("-sample_rate %d ", targetSampleRate)
end

-- Force FFmpeg to packetise output into fixed 1024-sample frames via the asetnsamples filter.
-- This prevents libgme from generating large, uneven audio spikes into the pipe and ensures
-- each pipe:read() call returns a predictable, small block of data.
local audioFilterOpt = '-af "asetnsamples=n=1024" '

-- Probe track duration in worker thread asynchronously to avoid freezing main thread
if mediaPath then
    local durationCmd = string.format('%s -i "%s" 2>&1', ffmpeg_bin, mediaPath)
    local durPipe = io.popen(durationCmd, "r")
    if durPipe then
        local output = durPipe:read("*a")
        durPipe:close()
        if output then
            local hh, mm, ss = output:match("Duration: (%d+):(%d+):(%d+%.?%d*)")
            if hh and mm and ss then
                local dur = tonumber(hh) * 3600 + tonumber(mm) * 60 + tonumber(ss)
                audioChannel:push({ type = "duration", duration = dur, generation = generation })
            end
        end
    end
end

-- FFmpeg command: decode to 16-bit PCM at targetSampleRate, stereo, no video.
local ffmpegCmd = string.format(
    '%s -nostdin -v error %s%s-i "%s" -vn %s-f s16le -acodec pcm_s16le -ar %d -ac 2 - 2>%s',
    ffmpeg_bin,
    seekOpt,
    libgmeInputOpt,
    mediaPath,
    audioFilterOpt,
    targetSampleRate,
    devNull
)

-- Open FFmpeg pipe for reading raw PCM data
local pipe = io.popen(ffmpegCmd, "r")

if not pipe then
    audioChannel:push({ type = "error", message = "Failed to open FFmpeg pipe for: " .. mediaPath })
    return
end

-- CRITICAL: readSize exactly matches the asetnsamples filter output (1024 samples × 2ch × 2bytes).
-- pipe:read() now blocks for only ~46ms (at 22050Hz) or ~23ms (at 44100Hz) instead of 512ms,
-- spreading libgme's emulation work into tiny, linear increments that keep the CPU load smooth.
local readSize = 4096  -- 1024 stereo frames
-- Max messages in the channel before the worker yields (~16 × 46ms = ~740ms look-ahead at 22050Hz)
local maxChannelDepth = 16

-- Main streaming loop
while true do
    -- Check for control messages (e.g., stop signal)
    local control = controlChannel:pop()
    if control and control.command == "stop" and control.generation == generation then
        break
    end

    -- Backpressure: yield while the channel is full so we don't flood memory.
    while audioChannel:getCount() >= maxChannelDepth do
        local control2 = controlChannel:pop()
        if control2 and control2.command == "stop" and control2.generation == generation then
            goto worker_done
        end
        love.timer.sleep(0.005)
    end

    -- Read one 1024-sample packet from FFmpeg stdout.
    -- With asetnsamples, FFmpeg guarantees each frame is exactly 4096 bytes (except at EOF),
    -- so no leftover accumulation or string.sub slicing is needed.
    local rawBytes = pipe:read(readSize)

    if rawBytes and #rawBytes > 0 then
        -- Align down to a 4-byte stereo frame boundary (handles the final partial packet at EOF)
        local len = #rawBytes
        local alignedLen = len - (len % 4)
        if alignedLen > 0 then
            audioChannel:push({
                type = "audio_data",
                data = alignedLen == len and rawBytes or string.sub(rawBytes, 1, alignedLen),
                size = alignedLen,
                generation = generation
            })
        end
    elseif rawBytes == "" then
        -- Transient: no data yet; pause briefly to prevent thread spinning
        love.timer.sleep(0.001)
    else
        -- EOF reached
        audioChannel:push({ type = "end", generation = generation })
        break
    end
end
::worker_done::

-- Signal that we're done
audioChannel:push({ type = "thread_done", generation = generation })

-- Close pipe and let process terminate naturally
if pipe then
    pipe:close()
end
