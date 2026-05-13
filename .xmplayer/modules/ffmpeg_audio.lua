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
local BYTES_PER_SAMPLE = (BIT_DEPTH / 8) * CHANNELS  -- 4 bytes: 2 channels * 2 bytes each
local MIN_PLAY_FRAMES = math.floor(SAMPLE_RATE * 0.05) -- 50ms worth of frames before forcing play

-- Thread and channel management
local audioThread = nil
local audioChannel = nil
local controlChannel = nil
local queueableSource = nil
local streamChannelName = "audio_stream_channel"
local controlChannelName = "audio_control_channel"
local currentGeneration = 0

-- Playback state
local isPlaying = false
local isPaused = false
local hasStartedPlayback = false  -- Track if we've initiated playback at least once
local playbackHasStarted = false -- True after queueableSource:play() actually called
local currentFilePath = nil
local totalDuration = 0
local elapsedTime = 0
local startTime = 0  -- Wall clock time when playback started
local pausedTime = 0  -- Time at pause moment

-- Sample tracking for visualizers
local totalSamplesQueued = 0  -- Total samples ever pushed to queue
local sampleRingBuffer = {}  -- For visualizer access
local ringBufferSize = SAMPLE_RATE * 2  -- 2 seconds of samples for visualizer

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

-- Get duration via ffprobe
local function getDuration(filepath)
    -- Use ffprobe to extract duration quickly
    local ffprobeCmd = string.format(
        'ffprobe -v error -show_entries format=duration -of "default=noprint_wrappers=1:nokey=1:nokey=1" "%s"',
        filepath
    )
    
    local pipe = io.popen(ffprobeCmd, "r")
    if not pipe then
        return 0
    end
    
    local output = pipe:read("*a")
    pipe:close()
    
    -- Parse the duration value
    local duration = tonumber(output)
    return duration or 0
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
    
    initRingBuffer()
    
    audioChannel = love.thread.getChannel(streamChannelName)
    controlChannel = love.thread.getChannel(controlChannelName)
    currentGeneration = currentGeneration + 1

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

        if message.generation and message.generation ~= currentGeneration then
            break
        end

        if message.type == "audio_data" then
            -- Convert PCM bytes to SoundData and queue it
            local sampleCount = processPCMChunk(message.data)
            
            local ok, soundData = pcall(function()
                local sd = love.sound.newSoundData(sampleCount, SAMPLE_RATE, BIT_DEPTH, CHANNELS)
                
                -- Copy bytes into SoundData if FFI is available
                if hasFFI and ffi then
                    local ptr = sd:getPointer()
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
                if isPlaying and hasStartedPlayback and not queueableSource:isPlaying() then
                    local shouldPlay = false
                    if bufferCount < 3 then
                        shouldPlay = true
                    elseif ffmpeg_audio.getSampleCount() >= MIN_PLAY_FRAMES then
                        shouldPlay = true
                    end

                    if shouldPlay then
                        queueableSource:play()
                        startTime = love.timer.getTime()
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
    return math.floor(totalSamplesQueued / CHANNELS)
end

function ffmpeg_audio.getSample(index)
    if not sampleRingBuffer or index < 0 then
        return 0
    end
    local ringIdx = (index % ringBufferSize) + 1
    return sampleRingBuffer[ringIdx]
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
