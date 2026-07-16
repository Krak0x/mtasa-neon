local EVENTS = {
    ar = 37416, -- Yo, watch my back while I tag this sucker.
    ca = 37444, -- There's another two Balla tags in this hood.
    cb = 37445, -- You go get 'em and I'll keep the engine running.
}

local active = {handles = {}, timers = {}}

local function log(message, level)
    local line = ("[native audio] %s"):format(message)
    outputDebugString(line, level == "bad" and 2 or 3)
    outputChatBox(line, level == "bad" and 255 or 120, level == "bad" and 80 or 230, level == "bad" and 80 or 150)
end

local function apiAvailable()
    for _, name in ipairs({"requestMissionAudio", "isMissionAudioLoaded", "playMissionAudio", "isMissionAudioFinished", "releaseMissionAudio"}) do
        if type(_G[name]) ~= "function" then
            log(("API absente: %s"):format(name), "bad")
            return false
        end
    end
    return true
end

local function remember(handle)
    if handle then
        active.handles[handle] = true
    end
    return handle
end

local function forget(handle)
    active.handles[handle] = nil
end

local function release(handle)
    if not handle then
        return false
    end
    local released = releaseMissionAudio(handle)
    forget(handle)
    return released
end

local function clearTest()
    for timer in pairs(active.timers) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    active.timers = {}

    local handles = {}
    for handle in pairs(active.handles) do
        handles[#handles + 1] = handle
    end
    for _, handle in ipairs(handles) do
        release(handle)
    end
end

local function repeatUntil(label, predicate, timeoutMs, callback)
    local startedAt = getTickCount()
    local timer
    timer = setTimer(function()
        if predicate() then
            active.timers[timer] = nil
            killTimer(timer)
            callback(true)
        elseif getTickCount() - startedAt >= timeoutMs then
            active.timers[timer] = nil
            killTimer(timer)
            log(("FAIL %s: timeout apres %d ms"):format(label, timeoutMs), "bad")
            callback(false)
        end
    end, 50, 0)
    active.timers[timer] = true
end

local function playAndWait(name, handle, callback)
    if not playMissionAudio(handle) then
        log(("FAIL %s: play refuse"):format(name), "bad")
        return callback(false)
    end
    log(("%s joue (handle %u)"):format(name, handle))
    repeatUntil(name .. " finished", function()
        return isMissionAudioFinished(handle)
    end, 15000, callback)
end

local function requestAndLoad(name, callback)
    local eventId = EVENTS[name]
    local handle = remember(requestMissionAudio(eventId))
    if not handle then
        log(("FAIL %s: request event %d refusee"):format(name, eventId), "bad")
        return callback(false)
    end

    log(("%s demande: event=%d handle=%u"):format(name, eventId, handle))
    repeatUntil(name .. " loaded", function()
        return isMissionAudioLoaded(handle)
    end, 10000, function(ok)
        callback(ok, handle)
    end)
end

addCommandHandler("nativeaudio", function(_, name)
    if not apiAvailable() then
        return
    end
    clearTest()
    name = tostring(name or "ar"):lower()
    if not EVENTS[name] then
        return log("usage: /nativeaudio ar|ca|cb", "bad")
    end

    requestAndLoad(name, function(loaded, handle)
        if not loaded then
            return clearTest()
        end
        playAndWait(name, handle, function(finished)
            release(handle)
            if finished then
                log(("PASS %s: fin naturelle puis release"):format(name))
            else
                log(("FAIL %s"):format(name), "bad")
            end
        end)
    end)
end)

addCommandHandler("nativeaudiosequence", function()
    if not apiAvailable() then
        return
    end
    clearTest()

    local ca = remember(requestMissionAudio(EVENTS.ca))
    local ar = remember(requestMissionAudio(EVENTS.ar))
    if not ca or not ar then
        log("FAIL sequence: preload simultane CA+AR refuse", "bad")
        return clearTest()
    end

    repeatUntil("CA+AR loaded", function()
        return isMissionAudioLoaded(ca) and isMissionAudioLoaded(ar)
    end, 10000, function(loaded)
        if not loaded then
            return clearTest()
        end
        playAndWait("AR", ar, function(arFinished)
            release(ar)
            if not arFinished then
                return clearTest()
            end
            playAndWait("CA", ca, function(caFinished)
                release(ca)
                if not caFinished then
                    return clearTest()
                end
                requestAndLoad("cb", function(cbLoaded, cb)
                    if not cbLoaded then
                        return clearTest()
                    end
                    playAndWait("CB", cb, function(cbFinished)
                        release(cb)
                        if cbFinished then
                            log("PASS sequence AR -> CA -> CB")
                        else
                            log("FAIL sequence CB", "bad")
                        end
                    end)
                end)
            end)
        end)
    end)
end)

addCommandHandler("nativeaudioguards", function()
    if not apiAvailable() then
        return
    end
    clearTest()
    local below = requestMissionAudio(1799)
    local above = requestMissionAudio(45401)
    if below or above then
        log("FAIL un event invalide a recu un handle", "bad")
    else
        log("PASS invalid events refuses")
    end

    local h1 = remember(requestMissionAudio(37416))
    local h2 = remember(requestMissionAudio(37417))
    local h3 = remember(requestMissionAudio(37418))
    local h4 = remember(requestMissionAudio(37444))
    local h5 = remember(requestMissionAudio(37445))
    if h1 and h2 and h3 and h4 and not h5 then
        log("PASS quatre slots, cinquieme refuse")
    elseif h5 then
        log("FAIL le cinquieme handle a ete accepte", "bad")
    else
        log("INFO allocation partielle: un slot natif etait peut-etre deja occupe")
    end
    clearTest()
end)

addCommandHandler("nativeaudioclear", function()
    clearTest()
    log("handles explicitement liberes")
end)

addCommandHandler("nativeaudiorestart", function()
    if not apiAvailable() then
        return
    end
    clearTest()
    requestAndLoad("ar", function(loaded, handle)
        if not loaded then
            return clearTest()
        end
        if not playMissionAudio(handle) then
            log("FAIL restart: play refuse", "bad")
            return clearTest()
        end
        -- Do not release here: CResource teardown must clear the native slot.
        triggerServerEvent("nativeMissionAudioTest:restart", resourceRoot)
    end)
end)

log("ready: /nativeaudio, /nativeaudiosequence, /nativeaudioguards, /nativeaudioclear, /nativeaudiorestart")
