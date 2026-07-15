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

local function forwardOffset(x, y, rotation, distance)
    local radians = math.rad(rotation)
    return x - math.sin(radians) * distance, y + math.cos(radians) * distance
end

local function reportServerState(player, session, prefix)
    local occupied = isElement(session.ped) and getPedOccupiedVehicle(session.ped) or nil
    local seat = occupied and getPedOccupiedVehicleSeat(session.ped) or -1
    outputChatBox(("[native leave-car] %s: occupied=%s, seat=%d, serverExitEvent=%s"):format(prefix, tostring(occupied == session.vehicle), seat,
                                                                                         tostring(session.serverExited)), player, 210, 210, 210)
end

addCommandHandler("nativeleave", function(player)
    if not isElement(player) then
        return
    end

    destroySession(player)

    local playerX, playerY, playerZ = getElementPosition(player)
    local _, _, playerRotation = getElementRotation(player)
    local vehicleX, vehicleY = forwardOffset(playerX, playerY, playerRotation, 4.0)
    local vehicle = createVehicle(492, vehicleX, vehicleY, playerZ + 0.25, 0, 0, playerRotation)
    local ped = vehicle and createPed(270, vehicleX, vehicleY, playerZ + 1.0, playerRotation) or nil
    if not isElement(vehicle) or not isElement(ped) then
        if isElement(vehicle) then
            destroyElement(vehicle)
        end
        if isElement(ped) then
            destroyElement(ped)
        end
        outputChatBox("[native leave-car] Impossible de creer Sweet ou la Greenwood.", player, 255, 80, 80)
        return
    end

    local interior, dimension = getElementInterior(player), getElementDimension(player)
    setElementInterior(vehicle, interior)
    setElementInterior(ped, interior)
    setElementDimension(vehicle, dimension)
    setElementDimension(ped, dimension)
    warpPedIntoVehicle(ped, vehicle, 1)
    setElementSyncer(ped, player)

    nextSessionId = nextSessionId + 1
    local session = {
        id = nextSessionId,
        ped = ped,
        vehicle = vehicle,
        serverExited = false,
        clientObserved = false,
    }
    sessions[player] = session

    outputChatBox("[native leave-car] Sweet est passager. Sortie native demandee dans 1 seconde.", player, 100, 220, 130)
    outputChatBox("Commandes: /nativeleavecancel et /nativeleavecleanup", player, 210, 210, 210)

    -- The synchronized ped needs a settled vehicle seat and syncer before the
    -- request/confirmation path can construct GTA's native leave-car task.
    setTimer(function(targetPlayer, expectedId)
        local active = sessions[targetPlayer]
        if not active or active.id ~= expectedId or not isElement(active.ped) or not isElement(active.vehicle) then
            return
        end
        reportServerState(targetPlayer, active, "before")
        triggerClientEvent(targetPlayer, "nativePedLeaveCar:start", resourceRoot, active.id, active.ped, active.vehicle)
    end, 1000, 1, player, session.id)
end)

addCommandHandler("nativeleavecancel", function(player)
    local session = sessions[player]
    if not session or not isElement(session.ped) then
        outputChatBox("[native leave-car] Aucun test actif.", player, 255, 170, 80)
        return
    end
    triggerClientEvent(player, "nativePedLeaveCar:cancel", resourceRoot, session.id, session.ped)
end)

addCommandHandler("nativeleavecleanup", function(player)
    destroySession(player)
    outputChatBox("[native leave-car] Test nettoye.", player, 180, 220, 255)
end)

addEvent("nativePedLeaveCar:result", true)
addEventHandler("nativePedLeaveCar:result", resourceRoot, function(sessionId, ped, vehicle, result, details)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) or session.ped ~= ped or session.vehicle ~= vehicle then
        outputDebugString("[native leave-car] Rejected stale or unauthorized client result", 2)
        return
    end

    if result == "exited" then
        session.clientObserved = true
    end
    local colors = {
        exited = {100, 230, 130},
        cancelled = {255, 190, 80},
        refused = {255, 80, 80},
        destroyed = {255, 80, 80},
        not_observed = {255, 80, 80},
        ended_in_vehicle = {255, 80, 80},
        timeout = {255, 80, 80},
    }
    local color = colors[result] or {220, 220, 220}
    outputChatBox(("[native leave-car] client=%s: %s"):format(tostring(result), tostring(details or "")), player, unpack(color))
    reportServerState(player, session, "after client result")

    if result == "exited" and session.serverExited and not getPedOccupiedVehicle(session.ped) then
        outputChatBox("[native leave-car] PASS: task observee + sortie confirmee par le serveur.", player, 100, 230, 130)
    elseif result == "exited" then
        outputChatBox("[native leave-car] En attente de la confirmation serveur onVehicleExit.", player, 255, 190, 80)
    end
end)

addEventHandler("onVehicleExit", root, function(ped, seat)
    for player, session in pairs(sessions) do
        if source == session.vehicle and ped == session.ped then
            session.serverExited = true
            outputChatBox(("[native leave-car] serveur: onVehicleExit seat=%d"):format(tonumber(seat) or -1), player, 140, 205, 255)
            if session.clientObserved and not getPedOccupiedVehicle(ped) then
                outputChatBox("[native leave-car] PASS: task observee + sortie confirmee par le serveur.", player, 100, 230, 130)
            end
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
