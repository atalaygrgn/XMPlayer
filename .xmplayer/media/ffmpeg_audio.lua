-- ffmpeg_audio.lua
-- Manages FFmpeg audio playback via background thread
-- Provides QueueableSource interface for LÖVE audio system

local ffmpeg_audio = {}

-- Try to load FFI for faster memory operations
local ffi = nil
local hasFFI = pcall(function() ffi = require("ffi") end)

-- Audio configuration
local SAMPLE_RATE = 44100
local CHANNELS = 2
local BIT_DEPTH = 16
local BYTES_PER_SAMPLE = (BIT_DEPTH / 8) * CHANNELS    -- 4 bytes: 2 channels * 2 bytes each
local MIN_PLAY_FRAMES = math.floor(SAMPLE_RATE * 0.05) -- 50ms worth of frames before forcing play

-- Thread and channel management
local audioThread = nil
local audioChannel = nil
local controlChannel = nil
local queueableSource = nil
local streamChannelName = "audio_stream_channel"
local controlChannelName = "audio_control_channel"
local currentGeneration = 0
local terminatingChannels = {}

-- Playback state
local isPlaying = false
local isPaused = false
local hasStartedPlayback = false -- Track if we've initiated playback at least once
local playbackHasStarted = false -- True after queueableSource:play() actually called
local currentFilePath = nil
local totalDuration = 0
local elapsedTime = 0
local startTime = 0  -- Wall clock time when playback started
local pausedTime = 0 -- Time at pause moment

-- Sample tracking for visualizers
local totalSamplesQueued = 0           -- Total samples ever pushed to queue
local sampleRingBuffer = {}            -- For visualizer access
local ringBufferSize = SAMPLE_RATE * 2 -- 2 seconds of samples for visualizer
local currentSeekTime = 0
local totalSamplesQueuedAtSeek = 0

-- Initialize ring buffer (stores raw sample values for visualization)
local function initRingBuffer()
    sampleRingBuffer = {}
    for i = 1, ringBufferSize do
        sampleRingBuffer[i] = 0
    end
end

-- Extract sample data from 16-bit PCM bytes and update ring buffer
local function processPCMChunk(rawBytes)
    if not rawBytes or #rawBytes < 2 then return 0 end

    local sampleCount = #rawBytes / BYTES_PER_SAMPLE

    -- Parse 16-bit signed little-endian PCM samples
    for i = 1, #rawBytes, 2 do
        -- Read two bytes as little-endian 16-bit signed integer
        local byte1 = string.byte(rawBytes, i)
        local byte2 = string.byte(rawBytes, i + 1)
        local sample = byte1 + (byte2 * 256)

        -- Convert to signed
        if sample > 32767 then
            sample = sample - 65536
        end

        -- Normalize to -1.0 to 1.0 range
        sample = sample / 32768.0

        -- Store in ring buffer for visualizer
        local ringIdx = (totalSamplesQueued % ringBufferSize) + 1
        sampleRingBuffer[ringIdx] = sample
        totalSamplesQueued = totalSamplesQueued + 1
    end

    return sampleCount
end

-- Get duration via ffmpeg
local function getDuration(filepath)
    local isWindows = (package.config:sub(1,1) == "\\")
    local ffmpeg_bin = "ffmpeg"
    if not isWindows then
        local source_path = love.filesystem.getSource()
        ffmpeg_bin = '"' .. source_path .. '/bin/ffmpeg"'
    end

    -- Run ffmpeg -i and capture stderr
    local cmd = string.format('%s -i "%s" 2>&1', ffmpeg_bin, filepath)
    local pipe = io.popen(cmd, "r")
    if not pipe then
        return 0
    end

    local output = pipe:read("*a")
    pipe:close()

    if not output then return 0 end

    -- Parse the duration format: Duration: hh:mm:ss.cc
    local hh, mm, ss = output:match("Duration: (%d+):(%d+):(%d+%.?%d*)")
    if hh and mm and ss then
        local duration = tonumber(hh) * 3600 + tonumber(mm) * 60 + tonumber(ss)
        return duration
    end

    return 0
end

function ffmpeg_audio.init()
    audioChannel = love.thread.getChannel(streamChannelName)
    controlChannel = love.thread.getChannel(controlChannelName)

    -- Create QueueableSource for 44100Hz, 16-bit, stereo
    queueableSource = love.audio.newQueueableSource(SAMPLE_RATE, BIT_DEPTH, CHANNELS)

    initRingBuffer()
end

function ffmpeg_audio.load(filepath)
    -- Stop any current playback and ensure thread terminates
    if audioThread and controlChannel then
        controlChannel:push({ command = "stop", generation = currentGeneration })
    end
    if queueableSource then
        queueableSource:stop()
    end

    currentFilePath = filepath
    isPlaying = false
    isPaused = false
    hasStartedPlayback = false
    elapsedTime = 0
    startTime = 0
    totalSamplesQueued = 0
    currentSeekTime = 0
    totalSamplesQueuedAtSeek = 0

    initRingBuffer()

    if streamChannelName then
        table.insert(terminatingChannels, streamChannelName)
    end

    currentGeneration = currentGeneration + 1
    streamChannelName = "audio_stream_channel_" .. currentGeneration
    controlChannelName = "audio_control_channel_" .. currentGeneration

    audioChannel = love.thread.getChannel(streamChannelName)
    controlChannel = love.thread.getChannel(controlChannelName)

    -- Clear any pending messages from previous thread
    while audioChannel:pop() do end

    -- Get duration
    totalDuration = getDuration(filepath)

    -- Start FFmpeg background thread (non-blocking)
    audioThread = love.thread.newThread("audio_worker.lua")
    audioThread:start(filepath, streamChannelName, controlChannelName, currentGeneration)

    return true
end

function ffmpeg_audio.play()
    if not queueableSource then return end

    if isPaused then
        -- Resume from pause
        queueableSource:play()
        playbackHasStarted = true
        startTime = love.timer.getTime() - pausedTime
        isPaused = false
        isPlaying = true
    elseif not isPlaying and not hasStartedPlayback then
        -- Start new playback for the first time
        -- Don't actually play() yet - wait for update() to queue data first
        isPlaying = true
        hasStartedPlayback = true
    end
end

function ffmpeg_audio.pause()
    if not queueableSource then return end

    if isPlaying and not isPaused then
        queueableSource:pause()
        pausedTime = elapsedTime
        isPaused = true
    end
end

function ffmpeg_audio.stop()
    if queueableSource then
        queueableSource:stop()
    end

    if audioThread and controlChannel then
        controlChannel:push({ command = "stop", generation = currentGeneration })
    end

    isPlaying = false
    isPaused = false
    hasStartedPlayback = false
    playbackHasStarted = false
    currentFilePath = nil
end

function ffmpeg_audio.update()
    -- Process terminating channels from previous generations to prevent memory leak
    for i = #terminatingChannels, 1, -1 do
        local chanName = terminatingChannels[i]
        local chan = love.thread.getChannel(chanName)
        local keep = true
        while true do
            local msg = chan:pop()
            if not msg then
                break
            end
            if msg.type == "thread_done" then
                keep = false
            end
        end
        if not keep then
            table.remove(terminatingChannels, i)
        end
    end

    -- Check for thread errors
    if audioThread then
        local err = audioThread:getError()
        if err then
            print("FFmpeg thread error: " .. tostring(err))
            ffmpeg_audio.stop()
            return
        end
    end

    -- Process incoming PCM data from thread
    local bufferCount = queueableSource:getFreeBufferCount()
    while bufferCount > 0 do
        local message = audioChannel:pop()

        if not message then
            break
        end

        if not message.generation or message.generation == currentGeneration then
            if message.type == "audio_data" then
                -- Convert PCM bytes to SoundData and queue it
                local sampleCount = processPCMChunk(message.data)

                local ok, soundData = pcall(function()
                    local sd = love.sound.newSoundData(sampleCount, SAMPLE_RATE, BIT_DEPTH, CHANNELS)

                    -- Copy bytes into SoundData if FFI is available
                    if hasFFI and ffi then
                        local ptr = sd.getFFIPointer and sd:getFFIPointer() or sd:getPointer()
                        if ptr then
                            ffi.copy(ptr, message.data, message.size)
                        end
                    else
                        -- Fallback: manually set samples (slower but works without FFI)
                        for i = 1, sampleCount do
                            for ch = 1, CHANNELS do
                                local byteIdx = (i - 1) * BYTES_PER_SAMPLE + (ch - 1) * 2 + 1
                                local byte1 = string.byte(message.data, byteIdx)
                                local byte2 = string.byte(message.data, byteIdx + 1)
                                local sample = byte1 + (byte2 * 256)
                                if sample > 32767 then
                                    sample = sample - 65536
                                end
                                sample = sample / 32768.0
                                sd:setSample((i - 1) * CHANNELS + ch, sample)
                            end
                        end
                    end

                    return sd
                end)

                if ok and soundData then
                    queueableSource:queue(soundData)
                    bufferCount = queueableSource:getFreeBufferCount()

                    -- If this is the first playback and we have buffered at least 2 chunks, start playing
                    if isPlaying and not isPaused and hasStartedPlayback and not queueableSource:isPlaying() then
                        local shouldPlay = false
                        if bufferCount < 3 then
                            shouldPlay = true
                        elseif ffmpeg_audio.getSampleCount() >= MIN_PLAY_FRAMES then
                            shouldPlay = true
                        end

                        if shouldPlay then
                            queueableSource:play()
                            startTime = love.timer.getTime() - elapsedTime
                            playbackHasStarted = true
                        end
                    end
                else
                    print("Failed to create SoundData: " .. tostring(soundData))
                end
            elseif message.type == "end" or message.type == "thread_done" then
                -- Stream ended or thread finishing
                if message.type == "thread_done" then
                    audioThread = nil
                end
                break
            elseif message.type == "error" then
                -- Error in thread
                print("FFmpeg error: " .. (message.message or "unknown"))
                ffmpeg_audio.stop()
                break
            end
        end
    end

    -- Update elapsed time if playing
    if isPlaying and not isPaused and queueableSource:isPlaying() then
        elapsedTime = love.timer.getTime() - startTime
        -- Cap elapsed time at duration
        if totalDuration > 0 then
            elapsedTime = math.min(elapsedTime, totalDuration)
        end
    elseif isPlaying and not isPaused and not queueableSource:isPlaying() then
        -- Only treat as track end if playback actually started
        if playbackHasStarted then
            -- Source stopped playing (track ended)
            isPlaying = false
            playbackHasStarted = false
        end
    end
end

function ffmpeg_audio.isPlaying()
    -- Return the internal playback state
    -- The actual QueueableSource will start playing once data is buffered
    return isPlaying
end

function ffmpeg_audio.isPaused()
    return isPaused
end

function ffmpeg_audio.getElapsedTime()
    return elapsedTime
end

function ffmpeg_audio.getDuration()
    return totalDuration
end

function ffmpeg_audio.getCurrentFilePath()
    return currentFilePath
end

-- Get sample data for visualizer (from ring buffer)
function ffmpeg_audio.getSampleCount()
    local decoded_since_seek = (totalSamplesQueued - totalSamplesQueuedAtSeek) / CHANNELS
    return math.floor(decoded_since_seek + currentSeekTime * SAMPLE_RATE)
end

function ffmpeg_audio.getSample(index)
    if not sampleRingBuffer or index < 0 then
        return 0
    end
    -- Translate track-relative frame index to the physical sample offset in ring buffer
    local delta_index = index - currentSeekTime * SAMPLE_RATE
    local sample_idx = totalSamplesQueuedAtSeek + delta_index * CHANNELS
    local ringIdx = math.floor(sample_idx % ringBufferSize) + 1
    local val = sampleRingBuffer[ringIdx]
    return val or 0
end

function ffmpeg_audio.seek(time)
    if not currentFilePath then return end

    local targetTime = math.max(0, math.min(time, totalDuration - 0.5))

    if audioThread and controlChannel then
        controlChannel:push({ command = "stop", generation = currentGeneration })
    end

    if queueableSource then
        queueableSource:stop()
    end

    elapsedTime = targetTime
    startTime = love.timer.getTime() - targetTime
    currentSeekTime = targetTime
    totalSamplesQueuedAtSeek = totalSamplesQueued
    if isPaused then
        pausedTime = targetTime
    end

    if streamChannelName then
        table.insert(terminatingChannels, streamChannelName)
    end

    currentGeneration = currentGeneration + 1
    streamChannelName = "audio_stream_channel_" .. currentGeneration
    controlChannelName = "audio_control_channel_" .. currentGeneration
    audioChannel = love.thread.getChannel(streamChannelName)
    controlChannel = love.thread.getChannel(controlChannelName)

    -- Clear pending stream packets
    while audioChannel:pop() do end

    -- Start new thread at targetTime
    audioThread = love.thread.newThread("audio_worker.lua")
    audioThread:start(currentFilePath, streamChannelName, controlChannelName, currentGeneration, targetTime)

    playbackHasStarted = false
    hasStartedPlayback = true
end

-- Compatibility wrapper for old SoundData interface
function ffmpeg_audio.getSoundDataCompat()
    return {
        getDuration = function() return totalDuration end,
        getSampleCount = function() return ffmpeg_audio.getSampleCount() end,
        getSample = function(_, idx) return ffmpeg_audio.getSample(idx) end,
    }
end

return ffmpeg_audio
