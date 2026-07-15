local sessions = {}
local nextSessionId = 0

local function destroySession(player)
    local session = sessions[player]
    if not session then
        return
    end

    if isElement(session.ped) then
        destroyElement(session.ped)
    end
    if isElement(session.vehicle) then
        destroyElement(session.vehicle)
    end
    sessions[player] = nil
end

local function offsetFromHeading(x, y, rotation, forward, right)
    local radians = math.rad(rotation)
    return x - math.sin(radians) * forward + math.cos(radians) * right,
           y + math.cos(radians) * forward + math.sin(radians) * right
end

local function reportServerState(player, session, prefix)
    local occupied = isElement(session.ped) and getPedOccupiedVehicle(session.ped) or nil
    local seat = occupied and getPedOccupiedVehicleSeat(session.ped) or -1
    outputChatBox(("[native enter-car] %s: occupied=%s, seat=%d, serverEnterEvent=%s"):format(
                      prefix, tostring(occupied == session.vehicle), seat, tostring(session.serverEntered)), player, 210, 210, 210)
end

local function tryReportPass(player, session)
    if session.clientObserved and session.serverEntered and isElement(session.ped) and getPedOccupiedVehicle(session.ped) == session.vehicle and
        getPedOccupiedVehicleSeat(session.ped) == 1 then
        outputChatBox("[native enter-car] PASS: task observee + entree passager confirmee par le serveur.", player, 100, 230, 130)
    end
end

addCommandHandler("nativeenter", function(player)
    if not isElement(player) then
        return
    end

    destroySession(player)

    local playerX, playerY, playerZ = getElementPosition(player)
    local _, _, playerRotation = getElementRotation(player)
    local vehicleX, vehicleY = offsetFromHeading(playerX, playerY, playerRotation, 8.0, 0)
    local pedX, pedY = offsetFromHeading(vehicleX, vehicleY, playerRotation, -6.0, 3.0)
    local vehicle = createVehicle(492, vehicleX, vehicleY, playerZ + 0.25, 0, 0, playerRotation)
    local ped = vehicle and createPed(270, pedX, pedY, playerZ + 0.15, playerRotation) or nil
    if not isElement(vehicle) or not isElement(ped) then
        if isElement(vehicle) then
            destroyElement(vehicle)
        end
        if isElement(ped) then
            destroyElement(ped)
        end
        outputChatBox("[native enter-car] Impossible de creer Sweet ou la Greenwood.", player, 255, 80, 80)
        return
    end

    local interior, dimension = getElementInterior(player), getElementDimension(player)
    setElementInterior(vehicle, interior)
    setElementInterior(ped, interior)
    setElementDimension(vehicle, dimension)
    setElementDimension(ped, dimension)
    setVehicleEngineState(vehicle, false)
    setElementSyncer(ped, player)

    nextSessionId = nextSessionId + 1
    local session = {
        id = nextSessionId,
        ped = ped,
        vehicle = vehicle,
        serverEntered = false,
        clientObserved = false,
    }
    sessions[player] = session

    outputChatBox("[native enter-car] Sweet va entrer naturellement au siege passager dans 1 seconde.", player, 100, 220, 130)
    outputChatBox("Commandes: /nativeentercancel et /nativeentercleanup", player, 210, 210, 210)

    -- Let streaming and sync ownership settle before the syncer requests MTA's
    -- authoritative enter lifecycle.
    setTimer(function(targetPlayer, expectedId)
        local active = sessions[targetPlayer]
        if not active or active.id ~= expectedId or not isElement(active.ped) or not isElement(active.vehicle) then
            return
        end
        reportServerState(targetPlayer, active, "before")
        triggerClientEvent(targetPlayer, "nativePedEnterCar:start", resourceRoot, active.id, active.ped, active.vehicle)
    end, 1000, 1, player, session.id)
end)

addCommandHandler("nativeentercancel", function(player)
    local session = sessions[player]
    if not session or not isElement(session.ped) then
        outputChatBox("[native enter-car] Aucun test actif.", player, 255, 170, 80)
        return
    end
    triggerClientEvent(player, "nativePedEnterCar:cancel", resourceRoot, session.id, session.ped)
end)

addCommandHandler("nativeentercleanup", function(player)
    destroySession(player)
    outputChatBox("[native enter-car] Test nettoye.", player, 180, 220, 255)
end)

addEvent("nativePedEnterCar:result", true)
addEventHandler("nativePedEnterCar:result", resourceRoot, function(sessionId, ped, vehicle, result, details)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) or session.ped ~= ped or session.vehicle ~= vehicle then
        outputDebugString("[native enter-car] Rejected stale or unauthorized client result", 2)
        return
    end

    if result == "entered" then
        session.clientObserved = true
    end
    local colors = {
        entered = {100, 230, 130},
        cancelled = {255, 190, 80},
        refused = {255, 80, 80},
        api_unavailable = {255, 80, 80},
        destroyed = {255, 80, 80},
        ownership_lost = {255, 80, 80},
        not_observed = {255, 80, 80},
        ended_outside_vehicle = {255, 80, 80},
        timeout = {255, 80, 80},
    }
    local color = colors[result] or {220, 220, 220}
    outputChatBox(("[native enter-car] client=%s: %s"):format(tostring(result), tostring(details or "")), player, unpack(color))
    reportServerState(player, session, "after client result")

    if result == "entered" and not session.serverEntered then
        outputChatBox("[native enter-car] En attente de la confirmation serveur onVehicleEnter.", player, 255, 190, 80)
    end
    tryReportPass(player, session)
end)

addEventHandler("onVehicleEnter", root, function(ped, seat)
    for player, session in pairs(sessions) do
        if source == session.vehicle and ped == session.ped then
            session.serverEntered = tonumber(seat) == 1
            outputChatBox(("[native enter-car] serveur: onVehicleEnter seat=%d"):format(tonumber(seat) or -1), player, 140, 205, 255)
            tryReportPass(player, session)
            break
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    destroySession(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do
        destroySession(player)
    end
end)
