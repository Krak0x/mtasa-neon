local function setTestFogDistance(player, _, requestedDistance)
    if type(requestedDistance) == "string" and requestedDistance:lower() == "reset" then
        if not resetFogDistance() then
            outputChatBox("[Fog test] Failed to restore the vanilla fog distance", player, 255, 100, 100)
            return
        end

        outputChatBox("[Fog test] Fog distance restored to GTA weather/time defaults", root, 100, 255, 100)
        return
    end

    local distance = tonumber(requestedDistance)
    if not distance then
        local currentDistance = getFogDistance()
        local currentStatus = currentDistance and ("Current distance: %.1f."):format(currentDistance)
            or "Current distance: vanilla weather/time value."
        outputChatBox(
            ("%s Usage: /seefar [distance|reset]"):format(currentStatus),
            player,
            255,
            220,
            100
        )
        return
    end

    if not setFogDistance(distance) then
        outputChatBox("[Fog test] Invalid fog distance", player, 255, 100, 100)
        return
    end

    outputChatBox(("[Fog test] Fog distance set to %.1f"):format(getFogDistance()), root, 100, 255, 100)
end

addCommandHandler("seefar", setTestFogDistance)

local function setTestFarClipDistance(player, _, requestedDistance)
    if type(requestedDistance) == "string" and requestedDistance:lower() == "reset" then
        if not resetFarClipDistance() then
            outputChatBox("[Far clip test] Failed to restore the vanilla far clip", player, 255, 100, 100)
            return
        end

        outputChatBox("[Far clip test] Far clip restored to GTA weather/time defaults", root, 100, 255, 100)
        return
    end

    local distance = tonumber(requestedDistance)
    if not distance then
        local currentDistance = getFarClipDistance()
        local currentStatus = currentDistance and ("Current distance: %.1f."):format(currentDistance)
            or "Current distance: vanilla weather/time value."
        outputChatBox(
            ("%s Usage: /seefar2 [distance|reset]"):format(currentStatus),
            player,
            255,
            220,
            100
        )
        return
    end

    if not setFarClipDistance(distance) then
        outputChatBox("[Far clip test] Invalid far clip distance", player, 255, 100, 100)
        return
    end

    outputChatBox(("[Far clip test] Far clip set to %.1f"):format(getFarClipDistance()), root, 100, 255, 100)
end

addCommandHandler("seefar2", setTestFarClipDistance)

addEventHandler("onResourceStart", resourceRoot, function()
    outputServerLog("[World distance test] Ready. Commands: /seefar [distance|reset], /seefar2 [distance|reset]")
end)
