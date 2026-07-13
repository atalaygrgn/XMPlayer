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
local isWindows = (package.config:sub(1,1) == "\\")
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
    vgm=true, vgz=true, gym=true, gbs=true, hes=true,
    kss=true, sap=true, ay=true, nsf=true, nsfe=true, spc=true
}
local isChip = ext and chipExts[ext:lower()]

-- For chip files: tell libgme to synthesise at the target rate directly.
-- This halves the internal emulation work compared to the default 44100Hz.
-- Always set -ar on output so FFmpeg's output matches what LÖVE expects.
local libgmeInputOpt = ""
if isChip then
    libgmeInputOpt = string.format("-sample_rate %d ", targetSampleRate)
end

-- FFmpeg command: decode to 16-bit PCM at targetSampleRate, stereo, no video.
local ffmpegCmd = string.format(
    '%s -nostdin -v error %s%s-i "%s" -vn -f s16le -acodec pcm_s16le -ar %d -ac 2 - 2>%s',
    ffmpeg_bin,
    seekOpt,
    libgmeInputOpt,
    mediaPath,
    targetSampleRate,
    devNull
)

-- Open FFmpeg pipe for reading raw PCM data
local pipe = io.popen(ffmpegCmd, "r")

if not pipe then
    audioChannel:push({ type = "error", message = "Failed to open FFmpeg pipe for: " .. mediaPath })
    return
end

-- Read size: 512ms of audio per pipe:read() call (at the target rate) to reduce syscall frequency
local readSize = math.floor(targetSampleRate * 0.5) * 2 * 2  -- 0.5s * 2ch * 2bytes
-- Each channel message is one small slice (~92ms at 44100, ~184ms at 22050)
-- Align sliceSize to 4-byte sample frame boundary
local sliceSize = 16384  -- 4096 stereo frames = 92ms @ 44100, 184ms @ 22050
if sliceSize > readSize then sliceSize = readSize end
-- Max messages in the channel before the worker yields (each is 92ms, so ~16 = ~1.5s ahead)
local maxChannelDepth = 16

-- Leftover bytes from a previous read that didn't fill a complete slice
local leftover = ""

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

    -- Read a large chunk from FFmpeg stdout (fewer syscalls = less starvation risk)
    local rawBytes = pipe:read(readSize)

    if rawBytes and #rawBytes > 0 then
        -- Prepend any leftover bytes from the previous read
        local combined = leftover .. rawBytes
        leftover = ""

        -- Slice the combined data into small messages here in the worker thread.
        -- The main thread receives small, uniformly-sized messages with zero slicing work.
        local pos = 1
        local combinedLen = #combined
        while pos <= combinedLen do
            local endPos = pos + sliceSize - 1
            if endPos > combinedLen then
                -- Incomplete slice: save for next iteration
                leftover = string.sub(combined, pos)
                break
            end
            local slice = string.sub(combined, pos, endPos)
            audioChannel:push({
                type = "audio_data",
                data = slice,
                size = sliceSize,
                generation = generation
            })
            pos = endPos + 1
        end
    elseif rawBytes == "" then
        -- Transient: no data yet (should not normally happen with blocking read)
    else
        -- EOF: flush any remaining leftover bytes as a final partial slice
        if #leftover > 0 then
            -- Align down to a full sample frame (4 bytes per frame)
            local alignedLen = #leftover - (#leftover % 4)
            if alignedLen > 0 then
                audioChannel:push({
                    type = "audio_data",
                    data = string.sub(leftover, 1, alignedLen),
                    size = alignedLen,
                    generation = generation
                })
            end
        end
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


