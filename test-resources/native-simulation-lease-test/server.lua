local sessions = {}
local nextSessionId = 0

local function snapshotPlayer(player)
    local x, y, z = getElementPosition(player)
    local _, _, rotation = getElementRotation(player)
    return {
        x = x,
        y = y,
        z = z,
        rotation = rotation,
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
    }
end

local function restorePlayer(player, snapshot)
    if not isElement(player) or not snapshot then
        return
    end
    removePedFromVehicle(player)
    setElementInterior(player, snapshot.interior)
    setElementDimension(player, snapshot.dimension)
    setElementPosition(player, snapshot.x, snapshot.y, snapshot.z)
    setElementRotation(player, 0, 0, snapshot.rotation)
end

local function destroySession(player, restore)
    local session = sessions[player]
    if not session then
        return
    end

    if isTimer(session.monitorTimer) then
        killTimer(session.monitorTimer)
    end
    if isElement(player) then
        triggerClientEvent(player, "nativeSimulationLease:stop", resourceRoot, session.id)
    end
    if restore then
        restorePlayer(player, session.snapshot)
    end
    for _, element in ipairs({session.ped, session.vehicle, session.probePed, session.probeVehicle}) do
        if isElement(element) then
            destroyElement(element)
        end
    end
    sessions[player] = nil
end

local function createSessionElements(player, snapshot)
    local start = NATIVE_SIMULATION_START
    local vehicle = createVehicle(412, start[1], start[2], start[3], 0, 0, start[4])
    local ped = vehicle and createPed(103, start[1], start[2], start[3] + 0.5, start[4]) or nil
    local probeVehicle = createVehicle(410, start[1] + 8.0, start[2], start[3], 0, 0, start[4])
    local probePed = probeVehicle and createPed(102, start[1] + 8.0, start[2], start[3] + 0.5, start[4]) or nil
    if not isElement(vehicle) or not isElement(ped) or not isElement(probeVehicle) or not isElement(probePed) then
        for _, element in ipairs({ped, vehicle, probePed, probeVehicle}) do
            if isElement(element) then destroyElement(element) end
        end
        return false
    end

    for _, element in ipairs({ped, vehicle, probePed, probeVehicle}) do
        setElementInterior(element, snapshot.interior)
        setElementDimension(element, snapshot.dimension)
    end
    warpPedIntoVehicle(ped, vehicle, 0)
    warpPedIntoVehicle(probePed, probeVehicle, 0)
    setVehicleColor(vehicle, 120, 40, 170, 120, 40, 170)
    setVehiclePlateText(vehicle, "VOODOO")
    setVehicleColor(probeVehicle, 235, 190, 40, 235, 190, 40)
    setVehiclePlateText(probeVehicle, "MANANA")
    setElementFrozen(probeVehicle, true)

    -- The primary island is persistent. The two following non-persistent
    -- assignments deliberately reproduce the cross-element interference that
    -- the old manager-global boolean caused.
    setElementSyncer(ped, player, true)
    setElementSyncer(vehicle, player, true)
    setElementSyncer(probePed, player, false)
    setElementSyncer(probeVehicle, player, false)
    return ped, vehicle, probePed, probeVehicle
end

addCommandHandler("nativesimlease", function(player)
    destroySession(player, true)
    if isPedInVehicle(player) then
        return outputChatBox("[simulation lease] Sors de ton vehicule avant de lancer le harness.", player, 255, 170, 80)
    end

    local snapshot = snapshotPlayer(player)
    setElementInterior(player, snapshot.interior)
    setElementDimension(player, snapshot.dimension)
    setElementPosition(player, NATIVE_SIMULATION_OBSERVER[1], NATIVE_SIMULATION_OBSERVER[2], NATIVE_SIMULATION_OBSERVER[3])
    setElementRotation(player, 0, 0, NATIVE_SIMULATION_OBSERVER[4])

    local ped, vehicle, probePed, probeVehicle = createSessionElements(player, snapshot)
    if not ped then
        restorePlayer(player, snapshot)
        return outputChatBox("[simulation lease] Creation des elements impossible.", player, 255, 80, 80)
    end

    nextSessionId = nextSessionId + 1
    local session = {
        id = nextSessionId,
        snapshot = snapshot,
        ped = ped,
        vehicle = vehicle,
        probePed = probePed,
        probeVehicle = probeVehicle,
        phase = "starting",
        serverSamples = 0,
        farMovement = 0,
        farGroundValid = true,
    }
    sessions[player] = session

    outputChatBox("[simulation lease] Ile native creee. Attends ACCEPT=true avant /nativesimfar.", player, 100, 220, 130)
    outputChatBox("Voodoo 412 VIOLET=vehicule teste; Manana 410 JAUNE=temoin immobile.", player, 210, 210, 210)
    outputChatBox("Commandes: /nativesimfar, /nativesimnear, /nativesimrelease, /nativesimcleanup.", player, 210, 210, 210)
    setTimer(function(target, expectedId)
        local active = sessions[target]
        if active and active.id == expectedId then
            triggerClientEvent(target, "nativeSimulationLease:start", resourceRoot, active.id, active.ped, active.vehicle)
        end
    end, 1000, 1, player, session.id)
end)

addCommandHandler("nativesimfar", function(player)
    local session = sessions[player]
    if not session or session.phase ~= "ready" then
        return outputChatBox("[simulation lease] Lance /nativesimlease et attends ACCEPT=true.", player, 255, 170, 80)
    end

    session.phase = "far"
    session.farStartedAt = getTickCount()
    session.farMovement = 0
    session.farGroundValid = true
    session.invalidGroundZ = nil
    session.lastFarPosition = nil
    setElementPosition(player, NATIVE_SIMULATION_FAR[1], NATIVE_SIMULATION_FAR[2], NATIVE_SIMULATION_FAR[3])
    setElementRotation(player, 0, 0, NATIVE_SIMULATION_FAR[4])
    outputChatBox("[simulation lease] Joueur envoye a Las Venturas. Attends PASS ou ECHEC pendant 15 s.", player, 120, 190, 255)
end)

addCommandHandler("nativesimnear", function(player)
    local session = sessions[player]
    if not session then
        return outputChatBox("[simulation lease] Aucun harness actif.", player, 255, 170, 80)
    end
    local x, y, z = getElementPosition(session.vehicle)
    if z >= NATIVE_SIMULATION_VALID_Z_MIN and z <= NATIVE_SIMULATION_VALID_Z_MAX then
        setElementPosition(player, x + 8.0, y, z + 1.0)
        setElementRotation(player, 0, 0, 90.0)
    else
        setElementPosition(player, NATIVE_SIMULATION_OBSERVER[1], NATIVE_SIMULATION_OBSERVER[2], NATIVE_SIMULATION_OBSERVER[3])
        setElementRotation(player, 0, 0, NATIVE_SIMULATION_OBSERVER[4])
    end
    session.phase = session.released and "released" or "ready"
    outputChatBox(("[simulation lease] Retour pres de la Voodoo 412 (Z=%.2f)."):format(z), player, 180, 220, 255)
end)

addCommandHandler("nativesimrelease", function(player)
    local session = sessions[player]
    if not session or session.released then
        return outputChatBox("[simulation lease] Aucun lease actif a liberer.", player, 255, 170, 80)
    end
    session.released = true
    session.phase = "released"
    triggerClientEvent(player, "nativeSimulationLease:release", resourceRoot, session.id)
    outputChatBox("[simulation lease] Liberation demandee. Loin de la route, STREAM OUT est maintenant attendu.", player, 255, 200, 100)
end)

addCommandHandler("nativesimcleanup", function(player)
    destroySession(player, true)
    outputChatBox("[simulation lease] Harness nettoye et position restauree.", player, 180, 220, 255)
end)

addEvent("nativeSimulationLease:evidence", true)
addEventHandler("nativeSimulationLease:evidence", resourceRoot, function(sessionId, evidence, data)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) or type(data) ~= "table" then
        return outputDebugString("[simulation lease] Rejected stale or unauthorized evidence", 2)
    end

    if evidence == "ready" then
        if data.accepted ~= true then
            outputChatBox("[simulation lease] ECHEC: la sequence native a ete refusee.", player, 255, 80, 80)
            return
        end
        session.phase = "ready"
        outputChatBox(("[simulation lease] ACCEPT=true flag0587=%s leases=%s/%s streamed=%s/%s syncer=%s/%s"):format(
            tostring(data.loadCollisionFlag),
            tostring(data.pedLease), tostring(data.vehicleLease), tostring(data.pedStreamed), tostring(data.vehicleStreamed),
            tostring(data.pedSyncer), tostring(data.vehicleSyncer)), player, 100, 230, 130)
        outputDebugString(("[simulation lease] READY id=%d flag0587=%s pedLease=%s vehicleLease=%s streamed=%s/%s syncer=%s/%s"):format(
            session.id, tostring(data.loadCollisionFlag), tostring(data.pedLease), tostring(data.vehicleLease), tostring(data.pedStreamed), tostring(data.vehicleStreamed),
            tostring(data.pedSyncer), tostring(data.vehicleSyncer)), 3)
    elseif evidence == "sample" then
        outputDebugString(("[simulation lease] CLIENT id=%d phase=%s elapsed=%d index=%d stream=%s/%s sync=%s/%s pos=%.3f,%.3f,%.3f speed=%.3f distance=%.1f"):format(
            session.id, session.phase, tonumber(data.elapsed) or -1, tonumber(data.index) or -2, tostring(data.pedStreamed),
            tostring(data.vehicleStreamed), tostring(data.pedSyncer), tostring(data.vehicleSyncer), tonumber(data.x) or 0,
            tonumber(data.y) or 0, tonumber(data.z) or 0, tonumber(data.speed) or 0, tonumber(data.distance) or -1), 3)
    elseif evidence == "streamout" then
        local expected = session.released == true
        outputChatBox(("[simulation lease] STREAM OUT %s: %s"):format(expected and "attendu" or "INATTENDU", tostring(data.element)),
            player, expected and 255 or 255, expected and 200 or 80, expected and 100 or 80)
        outputDebugString(("[simulation lease] STREAMOUT id=%d expected=%s element=%s"):format(session.id, tostring(expected), tostring(data.element)),
            expected and 3 or 2)
    elseif evidence == "released" then
        outputChatBox(("[simulation lease] RELEASE ped=%s vehicle=%s"):format(tostring(data.ped), tostring(data.vehicle)), player, 255, 200, 100)
    elseif evidence == "failure" then
        outputChatBox(("[simulation lease] ECHEC client: %s"):format(tostring(data.reason)), player, 255, 80, 80)
        outputDebugString(("[simulation lease] FAILURE id=%d %s"):format(session.id, tostring(data.reason)), 2)
    end
end)

addEvent("nativeSimulationLease:position", true)
addEventHandler("nativeSimulationLease:position", resourceRoot, function(sessionId, x, y, z)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) or session.phase ~= "far" then
        return
    end
    if not tonumber(x) or not tonumber(y) or not tonumber(z) then
        return
    end

    if z < NATIVE_SIMULATION_VALID_Z_MIN or z > NATIVE_SIMULATION_VALID_Z_MAX then
        session.farGroundValid = false
        session.invalidGroundZ = z
    end
    if session.lastFarPosition then
        -- Vertical falling or bouncing must never satisfy the route verdict.
        session.farMovement = session.farMovement + getDistanceBetweenPoints2D(session.lastFarPosition[1], session.lastFarPosition[2], x, y)
    end
    session.lastFarPosition = {x, y, z}
end)

setTimer(function()
    for player, session in pairs(sessions) do
        if isElement(player) and isElement(session.ped) and isElement(session.vehicle) then
            session.serverSamples = session.serverSamples + 1
            local pedPersistent = getElementSyncer(session.ped) == player
            local vehiclePersistent = getElementSyncer(session.vehicle) == player
            local x, y, z = getElementPosition(session.vehicle)
            if session.serverSamples % 2 == 0 then
                outputDebugString(("[simulation lease] SERVER id=%d phase=%s sync=%s/%s pos=%.3f,%.3f,%.3f farMovement2D=%.2f groundValid=%s"):format(
                    session.id, session.phase, tostring(pedPersistent), tostring(vehiclePersistent), x, y, z, session.farMovement,
                    tostring(session.farGroundValid)), 3)
            end

            if session.phase == "far" and not session.result then
                local elapsed = getTickCount() - session.farStartedAt
                if not pedPersistent or not vehiclePersistent then
                    session.result = "failed"
                    outputChatBox("[simulation lease] ECHEC: le syncer persistant a ete perdu hors distance.", player, 255, 80, 80)
                elseif elapsed >= 15000 then
                    if session.farMovement >= 20.0 and session.farGroundValid then
                        session.result = "passed"
                        outputChatBox(("[simulation lease] PASS: syncers conserves, Z valide et %.1f m 2D simules hors stream normal."):format(session.farMovement),
                            player, 100, 230, 130)
                    elseif not session.farGroundValid then
                        session.result = "failed"
                        outputChatBox(("[simulation lease] ECHEC: la Voodoo a quitte la route (Z=%.2f), mouvement 2D=%.1f m."):format(
                            session.invalidGroundZ or z, session.farMovement), player, 255, 80, 80)
                    else
                        session.result = "failed"
                        outputChatBox(("[simulation lease] ECHEC: seulement %.1f m observes hors stream normal."):format(session.farMovement),
                            player, 255, 80, 80)
                    end
                end
            end
        end
    end
end, 1000, 0)

addEventHandler("onPlayerQuit", root, function()
    destroySession(source, false)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do
        destroySession(player, true)
    end
end)

outputDebugString("[simulation lease] Ready. Use /nativesimlease while on foot.", 3)
