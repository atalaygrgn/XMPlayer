-- ffmpeg_audio.lua
-- Manages FFmpeg audio playback via background thread
-- Provides QueueableSource interface for LÖVE audio system

local utils = require("utils")
local ffmpeg_audio = {}

-- Try to load FFI for faster memory operations
local ffi = nil
local hasFFI = pcall(function() ffi = require("ffi") end)
local int16_t_ptr_type = nil
local int16_t_mut_ptr_type = nil
if hasFFI and ffi then
    local ok, t = pcall(function() return ffi.typeof("const int16_t*") end)
    if ok and t then
        int16_t_ptr_type = t
    end
    local ok_m, tm = pcall(function() return ffi.typeof("int16_t*") end)
    if ok_m and tm then
        int16_t_mut_ptr_type = tm
    end
end

-- Audio configuration
local SAMPLE_RATE = 44100 -- hardware/default
local CHANNELS = 2
local BIT_DEPTH = 16
local BYTES_PER_SAMPLE = (BIT_DEPTH / 8) * CHANNELS -- 4 bytes: 2 channels * 2 bytes each

-- Per-track sample rate (reduced for chip formats to cut synthesis CPU cost in half)
local currentSampleRate = SAMPLE_RATE

-- 1.5s pre-buffer at current rate before starting playback
local function minPlayFrames() return math.floor(currentSampleRate * 1.5) end

-- Chip/chiptune extensions that benefit from reduced synthesis rate
local CHIP_EXTENSIONS = {
    vgm = true,
    vgz = true,
    gbs = true,
    hes = true,
    kss = true,
    nsf = true,
    nsfe = true,
    spc = true
}

-- Thread and channel management
local audioThread = nil
local audioChannel = nil
local controlChannel = nil
local queueableSource = nil
local streamChannelName = "audio_stream_channel"
local controlChannelName = "audio_control_channel"
local currentGeneration = 0
local terminatingChannels = {}
local QUEUE_BUFFERS = 24
local hasReachedEOF = false

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
local totalSamplesQueued = 0                       -- Total samples ever pushed to queue
local sampleRingBuffer = {}                        -- For visualizer access
local ringBufferSize = SAMPLE_RATE * CHANNELS * 2 -- 2 seconds of stereo samples for visualizer
local currentSeekTime = 0
local totalSamplesQueuedAtSeek = 0

-- 3-Band Biquad Equalizer (Bass: Low Shelf 120Hz, Mids: Peaking 1000Hz, Highs: High Shelf 6000Hz)
-- Gain levels (dB): Neutral = 0, Slight Boost = +2.5, Moderate Boost = +4.5,
-- High Boost = +6.5, Heavy Boost = +8.5, Slight Cut = -2.5, Cut = -5.0
local EQ_PRESETS = {
    ["Flat"]       = { low =  0.0, mid =  0.0, high =  0.0 },
    ["Rock"]       = { low =  6.5, mid = -2.5, high =  6.5 },
    ["Pop"]        = { low =  4.5, mid =  0.0, high =  4.5 },
    ["Jazz"]       = { low =  2.5, mid =  4.5, high = -2.5 },
    ["Classical"]  = { low =  2.5, mid =  0.0, high =  4.5 },
    ["Electronic"] = { low =  8.5, mid = -2.5, high =  6.5 },
    ["Vocal"]      = { low = -5.0, mid =  8.5, high = -5.0 },
}

local currentEqPreset = "Flat"
local eqActive = false
local eqPreGain = 1.0
local eqBand1 = { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0 }
local eqBand2 = { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0 }
local eqBand3 = { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0 }

-- Biquad delay lines (Direct Form II Transposed) per stereo channel and band
local z1L1, z2L1, z1R1, z2R1 = 0, 0, 0, 0
local z1L2, z2L2, z1R2, z2R2 = 0, 0, 0, 0
local z1L3, z2L3, z1R3, z2R3 = 0, 0, 0, 0

local function resetEqState()
    z1L1, z2L1, z1R1, z2R1 = 0, 0, 0, 0
    z1L2, z2L2, z1R2, z2R2 = 0, 0, 0, 0
    z1L3, z2L3, z1R3, z2R3 = 0, 0, 0, 0
end

local function calcLowShelf(gainDB, freq, sampleRate)
    if math.abs(gainDB) < 0.01 then
        return { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0 }
    end
    local A = 10 ^ (gainDB / 40)
    local w0 = 2 * math.pi * freq / sampleRate
    local cosw0 = math.cos(w0)
    local sinw0 = math.sin(w0)
    local twoSqrtAAlpha = math.sqrt(2 * A) * sinw0

    local b0 = A * ((A + 1) - (A - 1) * cosw0 + twoSqrtAAlpha)
    local b1 = 2 * A * ((A - 1) - (A + 1) * cosw0)
    local b2 = A * ((A + 1) - (A - 1) * cosw0 - twoSqrtAAlpha)
    local a0 = (A + 1) + (A - 1) * cosw0 + twoSqrtAAlpha
    local a1 = -2 * ((A - 1) + (A + 1) * cosw0)
    local a2 = (A + 1) + (A - 1) * cosw0 - twoSqrtAAlpha

    return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function calcPeakingEQ(gainDB, freq, Q, sampleRate)
    if math.abs(gainDB) < 0.01 then
        return { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0 }
    end
    local A = 10 ^ (gainDB / 40)
    local w0 = 2 * math.pi * freq / sampleRate
    local cosw0 = math.cos(w0)
    local sinw0 = math.sin(w0)
    local alpha = sinw0 / (2 * Q)

    local b0 = 1 + alpha * A
    local b1 = -2 * cosw0
    local b2 = 1 - alpha * A
    local a0 = 1 + alpha / A
    local a1 = -2 * cosw0
    local a2 = 1 - alpha / A

    return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function calcHighShelf(gainDB, freq, sampleRate)
    if math.abs(gainDB) < 0.01 then
        return { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0 }
    end
    local safeFreq = math.min(freq, sampleRate * 0.42)
    local A = 10 ^ (gainDB / 40)
    local w0 = 2 * math.pi * safeFreq / sampleRate
    local cosw0 = math.cos(w0)
    local sinw0 = math.sin(w0)
    local twoSqrtAAlpha = math.sqrt(2 * A) * sinw0

    local b0 = A * ((A + 1) + (A - 1) * cosw0 + twoSqrtAAlpha)
    local b1 = -2 * A * ((A - 1) + (A + 1) * cosw0)
    local b2 = A * ((A + 1) + (A - 1) * cosw0 - twoSqrtAAlpha)
    local a0 = (A + 1) - (A - 1) * cosw0 + twoSqrtAAlpha
    local a1 = 2 * ((A - 1) - (A + 1) * cosw0)
    local a2 = (A + 1) - (A - 1) * cosw0 - twoSqrtAAlpha

    return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function updateEqCoefficients()
    local p = EQ_PRESETS[currentEqPreset] or EQ_PRESETS["Flat"]
    if math.abs(p.low) < 0.01 and math.abs(p.mid) < 0.01 and math.abs(p.high) < 0.01 then
        eqActive = false
        eqPreGain = 1.0
        return
    end
    eqActive = true
    local sr = currentSampleRate > 0 and currentSampleRate or SAMPLE_RATE
    eqBand1 = calcLowShelf(p.low, 120, sr)
    eqBand2 = calcPeakingEQ(p.mid, 1000, 0.8, sr)
    eqBand3 = calcHighShelf(p.high, 6000, sr)

    -- Headroom pre-gain to prevent digital clipping on heavy boosts
    local maxBoost = math.max(0, p.low, p.mid, p.high)
    eqPreGain = 10 ^ ((-maxBoost * 0.35) / 20)
end

local function new_audio_worker()
    return utils.new_worker_thread("audio_worker.lua")
end

-- Initialize ring buffer (stores raw sample values for visualization)
local function initRingBuffer()
    sampleRingBuffer = {}
    for i = 1, ringBufferSize do
        sampleRingBuffer[i] = 0
    end
end

-- Extract sample data from 16-bit PCM bytes, optionally apply 3-band EQ, and populate SoundData
local function processAndQueueChunk(rawBytes, rawSize)
    if not rawBytes or #rawBytes < 2 then return nil end

    local sampleCount = math.floor(#rawBytes / BYTES_PER_SAMPLE)
    local sd = love.sound.newSoundData(sampleCount, currentSampleRate, BIT_DEPTH, CHANNELS)

    if not eqActive then
        -- Fast path when EQ is Flat
        if int16_t_ptr_type then
            local int16_ptr = ffi.cast(int16_t_ptr_type, rawBytes)
            local num_samples = sampleCount * CHANNELS
            for i = 0, num_samples - 1 do
                local ringIdx = (totalSamplesQueued % ringBufferSize) + 1
                sampleRingBuffer[ringIdx] = int16_ptr[i] / 32768.0
                totalSamplesQueued = totalSamplesQueued + 1
            end
            local dst_ptr = sd.getFFIPointer and sd:getFFIPointer() or sd:getPointer()
            if dst_ptr then
                ffi.copy(dst_ptr, rawBytes, rawSize or #rawBytes)
                return sd
            end
        end

        for i = 1, sampleCount do
            for ch = 1, CHANNELS do
                local byteIdx = (i - 1) * BYTES_PER_SAMPLE + (ch - 1) * 2 + 1
                local byte1 = string.byte(rawBytes, byteIdx)
                local byte2 = string.byte(rawBytes, byteIdx + 1)
                local sample = byte1 + (byte2 * 256)
                if sample > 32767 then
                    sample = sample - 65536
                end
                local norm = sample / 32768.0
                local ringIdx = (totalSamplesQueued % ringBufferSize) + 1
                sampleRingBuffer[ringIdx] = norm
                totalSamplesQueued = totalSamplesQueued + 1
                sd:setSample((i - 1) * CHANNELS + (ch - 1), norm)
            end
        end
        return sd
    end

    -- Equalizer active path: 3-band cascaded biquad filtering
    local b1_0, b1_1, b1_2, a1_1, a1_2 = eqBand1.b0, eqBand1.b1, eqBand1.b2, eqBand1.a1, eqBand1.a2
    local b2_0, b2_1, b2_2, a2_1, a2_2 = eqBand2.b0, eqBand2.b1, eqBand2.b2, eqBand2.a1, eqBand2.a2
    local b3_0, b3_1, b3_2, a3_1, a3_2 = eqBand3.b0, eqBand3.b1, eqBand3.b2, eqBand3.a1, eqBand3.a2
    local pre = eqPreGain

    local s1L1, s2L1, s1R1, s2R1 = z1L1, z2L1, z1R1, z2R1
    local s1L2, s2L2, s1R2, s2R2 = z1L2, z2L2, z1R2, z2R2
    local s1L3, s2L3, s1R3, s2R3 = z1L3, z2L3, z1R3, z2R3

    local src_ptr = int16_t_ptr_type and ffi.cast(int16_t_ptr_type, rawBytes) or nil
    local dst_raw = (int16_t_mut_ptr_type and (sd.getFFIPointer and sd:getFFIPointer() or sd:getPointer())) or nil
    local dst_ptr = dst_raw and ffi.cast(int16_t_mut_ptr_type, dst_raw) or nil

    for i = 0, sampleCount - 1 do
        local xL, xR
        local baseIdx = i * 2
        if src_ptr then
            xL = (src_ptr[baseIdx] / 32768.0) * pre
            xR = (src_ptr[baseIdx + 1] / 32768.0) * pre
        else
            local bIdx = i * 4 + 1
            local sL = string.byte(rawBytes, bIdx) + string.byte(rawBytes, bIdx + 1) * 256
            if sL > 32767 then sL = sL - 65536 end
            local sR = string.byte(rawBytes, bIdx + 2) + string.byte(rawBytes, bIdx + 3) * 256
            if sR > 32767 then sR = sR - 65536 end
            xL = (sL / 32768.0) * pre
            xR = (sR / 32768.0) * pre
        end

        -- Band 1 (Low Shelf)
        local yL1 = b1_0 * xL + s1L1
        s1L1 = b1_1 * xL - a1_1 * yL1 + s2L1
        s2L1 = b1_2 * xL - a1_2 * yL1

        local yR1 = b1_0 * xR + s1R1
        s1R1 = b1_1 * xR - a1_1 * yR1 + s2R1
        s2R1 = b1_2 * xR - a1_2 * yR1

        -- Band 2 (Mid Peaking)
        local yL2 = b2_0 * yL1 + s1L2
        s1L2 = b2_1 * yL1 - a2_1 * yL2 + s2L2
        s2L2 = b2_2 * yL1 - a2_2 * yL2

        local yR2 = b2_0 * yR1 + s1R2
        s1R2 = b2_1 * yR1 - a2_1 * yR2 + s2R2
        s2R2 = b2_2 * yR1 - a2_2 * yR2

        -- Band 3 (High Shelf)
        local yL = b3_0 * yL2 + s1L3
        s1L3 = b3_1 * yL2 - a3_1 * yL + s2L3
        s2L3 = b3_2 * yL2 - a3_2 * yL

        local yR = b3_0 * yR2 + s1R3
        s1R3 = b3_1 * yR2 - a3_1 * yR + s2R3
        s2R3 = b3_2 * yR2 - a3_2 * yR

        -- Clamp to [-1.0, 1.0]
        if yL > 1.0 then yL = 1.0 elseif yL < -1.0 then yL = -1.0 end
        if yR > 1.0 then yR = 1.0 elseif yR < -1.0 then yR = -1.0 end

        local rIdxL = (totalSamplesQueued % ringBufferSize) + 1
        sampleRingBuffer[rIdxL] = yL
        totalSamplesQueued = totalSamplesQueued + 1

        local rIdxR = (totalSamplesQueued % ringBufferSize) + 1
        sampleRingBuffer[rIdxR] = yR
        totalSamplesQueued = totalSamplesQueued + 1

        if dst_ptr then
            dst_ptr[baseIdx] = math.floor(yL * 32767)
            dst_ptr[baseIdx + 1] = math.floor(yR * 32767)
        else
            sd:setSample(baseIdx, yL)
            sd:setSample(baseIdx + 1, yR)
        end
    end

    z1L1, z2L1, z1R1, z2R1 = s1L1, s2L1, s1R1, s2R1
    z1L2, z2L2, z1R2, z2R2 = s1L2, s2L2, s1R2, s2R2
    z1L3, z2L3, z1R3, z2R3 = s1L3, s2L3, s1R3, s2R3

    return sd
end

-- Get duration via ffmpeg
local function getDuration(filepath)
    local isWindows = (package.config:sub(1, 1) == "\\")
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

    -- QueueableSource is created per-load (rate may differ per track)
    -- Initialise with default rate so the object is never nil before first load
    queueableSource = love.audio.newQueueableSource(SAMPLE_RATE, BIT_DEPTH, CHANNELS, QUEUE_BUFFERS)

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
    hasReachedEOF = false
    elapsedTime = 0
    startTime = 0
    totalSamplesQueued = 0
    currentSeekTime = 0
    totalSamplesQueuedAtSeek = 0

    -- Detect chip/chiptune format and choose synthesis sample rate.
    -- Chip formats synthesize at half rate (22050Hz) to cut CPU cost by ~50%.
    -- LÖVE will present the audio at that rate; hardware resamples transparently.
    local ext = filepath and filepath:match("%.([^%.]+)$")
    if ext and CHIP_EXTENSIONS[ext:lower()] then
        currentSampleRate = 22050
    else
        currentSampleRate = SAMPLE_RATE
    end

    -- Recreate QueueableSource to match this track's sample rate
    if queueableSource then
        queueableSource:stop()
    end
    queueableSource = love.audio.newQueueableSource(currentSampleRate, BIT_DEPTH, CHANNELS, QUEUE_BUFFERS)

    initRingBuffer()
    resetEqState()
    updateEqCoefficients()

    currentFilePath = filepath
    currentGeneration = currentGeneration + 1
    streamChannelName = "audio_stream_" .. currentGeneration
    controlChannelName = "audio_control_" .. currentGeneration

    audioChannel = love.thread.getChannel(streamChannelName)
    controlChannel = love.thread.getChannel(controlChannelName)

    -- Clear any pending messages from previous thread
    while audioChannel:pop() do end

    -- Reset total duration (will be populated asynchronously by worker thread)
    totalDuration = 0

    -- Start FFmpeg background thread, passing the target sample rate so the worker
    -- can configure libgme synthesis rate and output -ar to match.
    audioThread = new_audio_worker()
    audioThread:start(filepath, streamChannelName, controlChannelName, currentGeneration, nil, currentSampleRate)

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

    -- Process incoming PCM data from thread.
    -- While paused we skip this entirely: the queueable source already has up to 2.2s
    -- of pre-buffered audio for smooth resume, and advancing totalSamplesQueued while
    -- elapsedTime is frozen would desync the ring buffer and break the visualizer.
    local bufferCount = queueableSource:getFreeBufferCount()
    if not isPaused then
        while bufferCount > 0 do
            local message = audioChannel:pop()

            if not message then
                break
            end

            if not message.generation or message.generation == currentGeneration then
                if message.type == "audio_data" then
                    -- Messages arrive pre-sliced (4096 bytes / 1024 stereo frames) from the worker thread.
                    local ok, soundData = pcall(processAndQueueChunk, message.data, message.size)

                    if ok and soundData then
                        queueableSource:queue(soundData)
                        bufferCount = queueableSource:getFreeBufferCount()

                        -- Start playback once we have enough frames buffered
                        if isPlaying and not isPaused and hasStartedPlayback and not queueableSource:isPlaying() then
                            local shouldPlay = false
                            if bufferCount < 3 then
                                shouldPlay = true
                            elseif ffmpeg_audio.getSampleCount() >= minPlayFrames() then
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
                elseif message.type == "duration" then
                    totalDuration = message.duration or 0
                elseif message.type == "end" or message.type == "thread_done" then
                    -- Stream ended or thread finishing
                    hasReachedEOF = true
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
        end -- while bufferCount > 0
    end     -- if not isPaused

    -- Update elapsed time if playing
    if isPlaying and not isPaused and queueableSource:isPlaying() then
        local now = love.timer.getTime()
        elapsedTime = now - startTime

        local freeBuffers = queueableSource:getFreeBufferCount()
        local queuedBuffers = math.max(0, QUEUE_BUFFERS - freeBuffers)
        local decodedFrames = ffmpeg_audio.getSampleCount()
        local streamPlayedTime = math.max(currentSeekTime, (decodedFrames - queuedBuffers * 1024) / currentSampleRate)

        -- Resync wall-clock timer if it drifted from actual audio playback (e.g. after device sleep/wake)
        if math.abs(elapsedTime - streamPlayedTime) > 0.15 then
            elapsedTime = streamPlayedTime
            startTime = now - elapsedTime
        end

        -- Cap elapsed time at duration
        if totalDuration > 0 then
            elapsedTime = math.min(elapsedTime, totalDuration)
        end
    elseif isPlaying and not isPaused and not queueableSource:isPlaying() then
        -- Only treat as track end if playback actually started, the thread has fully decoded the stream,
        -- and the queueable source has completely played through all queued buffers.
        if playbackHasStarted and hasReachedEOF and queueableSource:getFreeBufferCount() >= QUEUE_BUFFERS then
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
function ffmpeg_audio.getSampleRate()
    return currentSampleRate
end

function ffmpeg_audio.getSampleCount()
    local decoded_since_seek = (totalSamplesQueued - totalSamplesQueuedAtSeek) / CHANNELS
    return math.floor(decoded_since_seek + currentSeekTime * currentSampleRate)
end

function ffmpeg_audio.getSample(index)
    if not sampleRingBuffer or index < 0 then
        return 0
    end
    -- Translate track-relative frame index to the physical sample offset in ring buffer
    local delta_index = index - currentSeekTime * currentSampleRate
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
    resetEqState()
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
    audioThread = new_audio_worker()
    audioThread:start(currentFilePath, streamChannelName, controlChannelName, currentGeneration, targetTime,
        currentSampleRate)

    playbackHasStarted = false
    hasStartedPlayback = true
    hasReachedEOF = false
end

function ffmpeg_audio.setEqualizerPreset(preset)
    if EQ_PRESETS[preset] then
        currentEqPreset = preset
    else
        currentEqPreset = "Flat"
    end
    updateEqCoefficients()
end

function ffmpeg_audio.getEqualizerPreset()
    return currentEqPreset
end

-- Compatibility wrapper for old SoundData interface
function ffmpeg_audio.getSoundDataCompat()
    return {
        getDuration    = function() return totalDuration end,
        getSampleRate  = function() return ffmpeg_audio.getSampleRate() end,
        getSampleCount = function() return ffmpeg_audio.getSampleCount() end,
        getSample      = function(_, idx) return ffmpeg_audio.getSample(idx) end,
    }
end

return ffmpeg_audio
