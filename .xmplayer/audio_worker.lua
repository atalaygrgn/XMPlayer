-- audio_worker.lua
-- Background thread worker for FFmpeg audio streaming via io.popen
-- Receives media path and streams PCM data to main thread via channel

local mediaPath = ...
local streamChannelName = select(2, ...)
local controlChannelName = select(3, ...)
local generation = select(4, ...)
local seekTime = select(5, ...)
local audioChannel = love.thread.getChannel(streamChannelName or "audio_stream_channel")
local controlChannel = love.thread.getChannel(controlChannelName or "audio_control_channel")

local seekOpt = ""
if seekTime and tonumber(seekTime) and tonumber(seekTime) > 0 then
    seekOpt = string.format("-ss %.3f ", tonumber(seekTime))
end

-- FFmpeg command: decode to 16-bit PCM at 44100Hz stereo, no video.
local ffmpegCmd = string.format(
    'ffmpeg -nostdin -v error %s-i "%s" -vn -f s16le -acodec pcm_s16le -ar 44100 -ac 2 -',
    seekOpt,
    mediaPath
)

-- Open FFmpeg pipe for reading raw PCM data
local pipe = io.popen(ffmpegCmd, "r")

if not pipe then
    audioChannel:push({ type = "error", message = "Failed to open FFmpeg pipe for: " .. mediaPath })
    return
end

-- Chunk size: 4096 samples * 2 channels * 2 bytes per sample = 16384 bytes
-- This represents ~92ms of audio at 44100Hz
local chunkSize = 16384

-- Main streaming loop
while true do
    -- Check for control messages (e.g., stop signal)
    local control = controlChannel:pop()
    if control and control.command == "stop" and control.generation == generation then
        break
    end

    -- Read PCM chunk from FFmpeg stdout
    local rawBytes = pipe:read(chunkSize)

    if rawBytes and #rawBytes > 0 then
        -- Push raw PCM data to main thread
        audioChannel:push({
            type = "audio_data",
            data = rawBytes,
            size = #rawBytes
        })
    elseif rawBytes == "" then
        -- No data yet; keep waiting.
        -- io.popen:read(chunkSize) should block until data arrives or EOF,
        -- so an empty string is treated as a transient condition.
    else
        -- EOF or pipe closed by ffmpeg.
        audioChannel:push({ type = "end", generation = generation })
        break
    end
end

-- Signal that we're done
audioChannel:push({ type = "thread_done", generation = generation })

-- Close pipe and let process terminate naturally
if pipe then
    pipe:close()
end


