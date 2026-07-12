local enabledByResource = false

local function outputStats()
    local stats = engineGetDistantLightStats()
    local message = ("[Project2DFX] enabled=%s definitions=%d active=%d/%d distance=%.0f"):format(
        tostring(stats.enabled),
        stats.definitions,
        stats.activeCoronas,
        stats.coronaCapacity,
        stats.drawDistance
    )
    outputChatBox(message, 255, 210, 80)
    outputDebugString(message)
end

local function setProject2DFX(_, state, requestedDistance)
    state = state and state:lower() or ""
    if state ~= "on" and state ~= "off" and state ~= "rebuild" then
        outputChatBox("[Project2DFX] /project2dfx [on|off|rebuild] [300-5000]", 255, 210, 80)
        return
    end

    if state == "rebuild" then
        engineRebuildDistantLights()
        outputStats()
        return
    end

    if state == "on" then
        local distance = tonumber(requestedDistance) or 2000
        if not engineSetDistantLightsDrawDistance(distance) then
            outputChatBox("[Project2DFX] Distance must be between 300 and 5000", 255, 100, 100)
            return
        end
        engineSetDistantLightsEnabled(true)
        enabledByResource = true
    else
        engineSetDistantLightsEnabled(false)
        enabledByResource = false
    end

    outputStats()
end

addCommandHandler("project2dfx", setProject2DFX)
addCommandHandler("project2dfxstats", outputStats)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if enabledByResource then
        engineSetDistantLightsEnabled(false)
    end
end)

outputChatBox("[Project2DFX] /project2dfx on [300-5000], /project2dfxstats, /project2dfx off", 255, 210, 80)
