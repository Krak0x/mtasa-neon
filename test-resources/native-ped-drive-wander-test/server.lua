local sessions = {}
local nextSessionId = 0

local function destroySession(player)
    local session = sessions[player]
    if not session then
        return
    end
    if isTimer(session.monitorTimer) then
        killTimer(session.monitorTimer)
    end
    if isElement(session.ped) then
        destroyElement(session.ped)
    end
    if isElement(session.vehicle) then
        destroyElement(session.vehicle)
    end
    sessions[player] = nil
end

local function forwardOffset(x, y, rotation, distance)
    local radians = math.rad(rotation)
    return x - math.sin(radians) * distance, y + math.cos(radians) * distance
end

addCommandHandler("nativedrivewander", function(player)
    destroySession(player)

    local playerX, playerY, playerZ = getElementPosition(player)
    local _, _, playerRotation = getElementRotation(player)
    local vehicleX, vehicleY = forwardOffset(playerX, playerY, playerRotation, 6.0)
    local vehicle = createVehicle(492, vehicleX, vehicleY, playerZ + 0.35, 0, 0, playerRotation)
    local ped = vehicle and createPed(270, vehicleX, vehicleY, playerZ + 1.0, playerRotation) or nil
    if not isElement(vehicle) or not isElement(ped) then
        if isElement(vehicle) then destroyElement(vehicle) end
        if isElement(ped) then destroyElement(ped) end
        outputChatBox("[native drive-wander] Impossible de creer Sweet ou la Greenwood.", player, 255, 80, 80)
        return
    end

    local interior, dimension = getElementInterior(player), getElementDimension(player)
    setElementInterior(vehicle, interior)
    setElementInterior(ped, interior)
    setElementDimension(vehicle, dimension)
    setElementDimension(ped, dimension)
    warpPedIntoVehicle(ped, vehicle, 1)
    -- DriveWander mutates both the ped task and the vehicle autopilot. Keeping
    -- one persistent owner for both is what lets ordinary MTA sync carry it.
    setElementSyncer(ped, player, true, true)
    setElementSyncer(vehicle, player, true, true)

    nextSessionId = nextSessionId + 1
    local session = {
        id = nextSessionId,
        ped = ped,
        vehicle = vehicle,
        startX = vehicleX,
        startY = vehicleY,
        observed = false,
        persistent = false,
        passed = false,
    }
    sessions[player] = session

    outputChatBox("[native drive-wander] Sweet est passager, conducteur vide. 05D2 dans 1 seconde.", player, 100, 220, 130)
    outputChatBox("Commandes: /nativedrivewandercancel et /nativedrivewandercleanup", player, 210, 210, 210)

    setTimer(function(targetPlayer, expectedId)
        local active = sessions[targetPlayer]
        if not active or active.id ~= expectedId then
            return
        end
        triggerClientEvent(targetPlayer, "nativePedDriveWander:start", resourceRoot, active.id, active.ped, active.vehicle)
        active.monitorTimer = setTimer(function()
            if not isElement(active.vehicle) or not isElement(active.ped) then
                return
            end
            local x, y = getElementPosition(active.vehicle)
            local distance = getDistanceBetweenPoints2D(x, y, active.startX, active.startY)
            if active.observed and active.persistent and not active.passed and distance >= 4.0 and getPedOccupiedVehicle(active.ped) == active.vehicle and
                getPedOccupiedVehicleSeat(active.ped) == 1 and getElementSyncer(active.vehicle) == targetPlayer then
                active.passed = true
                outputChatBox(("[native drive-wander] PASS: task stable 15 s + %.2f m synchronises, Sweet toujours passager."):format(distance),
                              targetPlayer, 100, 230, 130)
            end
        end, 250, 0)
    end, 1000, 1, player, session.id)
end)

addEvent("nativePedDriveWander:result", true)
addEventHandler("nativePedDriveWander:result", resourceRoot, function(sessionId, ped, vehicle, result, details)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) or session.ped ~= ped or session.vehicle ~= vehicle then
        outputDebugString("[native drive-wander] Rejected stale or unauthorized result", 2)
        return
    end

    if result == "observed" then
        session.observed = true
    elseif result == "persistent" then
        session.persistent = true
    end
    local good = result == "observed" or result == "persistent" or result == "cancelled"
    outputDebugString(("[native drive-wander] client=%s: %s"):format(tostring(result), tostring(details or "")), good and 3 or 2)
    outputChatBox(("[native drive-wander] client=%s: %s"):format(tostring(result), tostring(details or "")), player,
                  good and 100 or 255, good and 220 or 80, good and 130 or 80)
end)

addCommandHandler("nativedrivewandercancel", function(player)
    local session = sessions[player]
    if not session then
        return outputChatBox("[native drive-wander] Aucun test actif.", player, 255, 170, 80)
    end
    triggerClientEvent(player, "nativePedDriveWander:cancel", resourceRoot, session.id, session.ped, session.vehicle)
end)

addCommandHandler("nativedrivewandercleanup", function(player)
    destroySession(player)
    outputChatBox("[native drive-wander] Test nettoye.", player, 180, 220, 255)
end)

addEventHandler("onPlayerQuit", root, function()
    destroySession(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do
        destroySession(player)
    end
end)
