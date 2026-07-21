local sessions = {}
local nextSessionId = 0

local TEST_DIMENSION = 191
local PLAYER_POSITION = {2395.0, -1951.0, 13.4, 270.0}
local VEHICLE_POSITION = {2407.0, -1951.0, 13.15, 90.0}
local TARGET_POSITION = {2381.0, -1951.0, 13.4, 90.0}

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
    if isTimer(session.timeoutTimer) then
        killTimer(session.timeoutTimer)
    end
    for _, element in ipairs({session.shooter, session.target, session.vehicle}) do
        if isElement(element) then
            destroyElement(element)
        end
    end
    if restore then
        restorePlayer(player, session.snapshot)
    end
    sessions[player] = nil
end

local function finishSession(player, reason)
    local session = sessions[player]
    if not session then
        return
    end
    triggerClientEvent(player, "nativeMissionPed:stop", resourceRoot, session.id, reason or "cleanup")
end

addCommandHandler("nativemissionped", function(player)
    if sessions[player] then
        return outputChatBox("[native mission ped] Un test est deja actif. Utilise /nativemissionpedcleanup.", player, 255, 180, 80)
    end

    local snapshot = snapshotPlayer(player)
    setElementInterior(player, 0)
    setElementDimension(player, TEST_DIMENSION)
    setElementPosition(player, PLAYER_POSITION[1], PLAYER_POSITION[2], PLAYER_POSITION[3])
    setElementRotation(player, 0, 0, PLAYER_POSITION[4])

    local vehicle = createVehicle(412, VEHICLE_POSITION[1], VEHICLE_POSITION[2], VEHICLE_POSITION[3], 0, 0, VEHICLE_POSITION[4])
    local shooter = createPed(103, VEHICLE_POSITION[1], VEHICLE_POSITION[2], VEHICLE_POSITION[3] + 1.0, VEHICLE_POSITION[4])
    local target = createPed(105, TARGET_POSITION[1], TARGET_POSITION[2], TARGET_POSITION[3], TARGET_POSITION[4])
    if not isElement(vehicle) or not isElement(shooter) or not isElement(target) then
        for _, element in ipairs({shooter, target, vehicle}) do
            if isElement(element) then destroyElement(element) end
        end
        restorePlayer(player, snapshot)
        return outputChatBox("[native mission ped] Creation du harness impossible.", player, 255, 80, 80)
    end

    for _, element in ipairs({vehicle, shooter, target}) do
        setElementInterior(element, 0)
        setElementDimension(element, TEST_DIMENSION)
    end
    setVehicleColor(vehicle, 105, 30, 59, 105, 30, 59)
    setVehiclePlateText(vehicle, "M_NORM")
    setElementHealth(vehicle, 1000)
    setElementHealth(shooter, 500)
    setElementHealth(target, 500)
    giveWeapon(shooter, 28, 999, true)
    setElementFrozen(target, true)
    warpPedIntoVehicle(shooter, vehicle, 1)
    setElementSyncer(shooter, player, true, true)
    setElementSyncer(vehicle, player, true, true)

    nextSessionId = nextSessionId + 1
    local session = {
        id = nextSessionId,
        snapshot = snapshot,
        vehicle = vehicle,
        shooter = shooter,
        target = target,
        initialTargetHealth = getElementHealth(target),
        ready = false,
        leaseAcquired = false,
        inactiveObserved = false,
        repaired = false,
    }
    sessions[player] = session

    outputChatBox("[native mission ped] Ballas passager dans la Voodoo violette. Le test demarre automatiquement.", player, 100, 220, 130)
    outputChatBox("Attendu: sortie urgente, fuite loin de la voiture, puis retour au combat contre le Grove fige.", player, 220, 220, 220)
    outputChatBox("Nettoyage: /nativemissionpedcleanup", player, 220, 220, 220)
    triggerClientEvent(player, "nativeMissionPed:start", resourceRoot, session.id, shooter, vehicle, target)

    session.timeoutTimer = setTimer(function(targetPlayer, expectedId)
        local active = sessions[targetPlayer]
        if not active or active.id ~= expectedId then
            return
        end
        outputDebugString("[native mission ped] FAIL server timeout after 30 seconds", 2)
        outputChatBox("[native mission ped] FAIL: timeout 30 s. Garde la scene et demande le check logs.", targetPlayer, 255, 80, 80)
    end, 30000, 1, player, session.id)
end)

addEvent("nativeMissionPed:evidence", true)
addEventHandler("nativeMissionPed:evidence", resourceRoot, function(sessionId, evidence, data)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) or type(data) ~= "table" then
        return outputDebugString("[native mission ped] Rejected stale or unauthorized evidence", 2)
    end

    local details = tostring(data.details or "")
    outputDebugString(("[native mission ped] %s %s"):format(tostring(evidence), details), evidence == "failure" and 2 or 3)

    if evidence == "lease" and not session.leaseAcquired then
        if getElementSyncer(session.shooter) ~= player or getElementSyncer(session.vehicle) ~= player or
            getPedOccupiedVehicle(session.shooter) ~= session.vehicle or getPedOccupiedVehicleSeat(session.shooter) ~= 1 then
            return outputChatBox("[native mission ped] FAIL: ownership ou siege invalide avant le cycle syncer.", player, 255, 80, 80)
        end
        session.leaseAcquired = true
        setElementSyncer(session.shooter, false)
        outputChatBox("[native mission ped] Bail acquis. Perte temporaire du syncer pour verifier la desactivation native.", player, 180, 220, 255)
        setTimer(function(targetPlayer, expectedId)
            local active = sessions[targetPlayer]
            if active and active.id == expectedId then
                triggerClientEvent(targetPlayer, "nativeMissionPed:verifyProfile", resourceRoot, active.id, false, "inactive")
            end
        end, 250, 1, player, session.id)
    elseif evidence == "inactive" and session.leaseAcquired and not session.inactiveObserved then
        if getElementSyncer(session.shooter) ~= false then
            return outputChatBox("[native mission ped] FAIL: le serveur voit encore un syncer pendant la phase inactive.", player, 255, 80, 80)
        end
        session.inactiveObserved = true
        setElementSyncer(session.shooter, player, true)
        outputChatBox("[native mission ped] Profil inactif hors syncer. Reprise du meme bail sur une nouvelle generation.", player, 180, 220, 255)
        setTimer(function(targetPlayer, expectedId)
            local active = sessions[targetPlayer]
            if active and active.id == expectedId then
                triggerClientEvent(targetPlayer, "nativeMissionPed:verifyProfile", resourceRoot, active.id, true, "ready")
            end
        end, 250, 1, player, session.id)
    elseif evidence == "ready" and session.leaseAcquired and session.inactiveObserved and not session.ready then
        if getElementSyncer(session.shooter) ~= player or getElementSyncer(session.vehicle) ~= player or
            getPedOccupiedVehicle(session.shooter) ~= session.vehicle or getPedOccupiedVehicleSeat(session.shooter) ~= 1 then
            return outputChatBox("[native mission ped] FAIL: ownership ou siege invalide apres reprise du syncer.", player, 255, 80, 80)
        end
        session.ready = true
        setElementHealth(session.vehicle, 249)
        outputChatBox("[native mission ped] Meme bail reactive. Voodoo a 249 HP: attente de EVENT_VEHICLE_ON_FIRE.", player, 255, 190, 80)
        setTimer(function(targetPlayer, expectedId)
            local active = sessions[targetPlayer]
            if active and active.id == expectedId then
                triggerClientEvent(targetPlayer, "nativeMissionPed:attack", resourceRoot, active.id)
            end
        end, 200, 1, player, session.id)
    elseif evidence == "flee" and not session.repaired then
        session.repaired = true
        setElementHealth(session.vehicle, 1000)
        outputChatBox("[native mission ped] Reponse de fuite observee; Voodoo reparee pour isoler la reprise du combat.", player, 100, 220, 130)
    elseif evidence == "pass" then
        local targetHealth = isElement(session.target) and getElementHealth(session.target) or 0
        local shooterInVehicle = isElement(session.shooter) and getPedOccupiedVehicle(session.shooter) ~= false
        if not session.ready or getElementSyncer(session.shooter) ~= player or shooterInVehicle or targetHealth >= session.initialTargetHealth then
            return outputChatBox("[native mission ped] FAIL: le verdict client ne passe pas les gardes serveur.", player, 255, 80, 80)
        end
        if isTimer(session.timeoutTimer) then killTimer(session.timeoutTimer) end
        outputChatBox(("[native mission ped] PASS: fuite native puis combat repris, cible %.1f -> %.1f HP."):format(
                          session.initialTargetHealth, targetHealth), player, 100, 230, 130)
    elseif evidence == "failure" then
        outputChatBox("[native mission ped] FAIL: " .. details, player, 255, 80, 80)
    end
end)

addEvent("nativeMissionPed:stopped", true)
addEventHandler("nativeMissionPed:stopped", resourceRoot, function(sessionId, details)
    local player = client
    local session = sessions[player]
    if source ~= resourceRoot or not session or session.id ~= tonumber(sessionId) then
        return
    end
    outputDebugString("[native mission ped] cleanup client: " .. tostring(details or ""))
    destroySession(player, true)
    outputChatBox("[native mission ped] Test nettoye et position restauree.", player, 180, 220, 255)
end)

addCommandHandler("nativemissionpedcleanup", function(player)
    if not sessions[player] then
        return outputChatBox("[native mission ped] Aucun test actif.", player, 255, 180, 80)
    end
    finishSession(player, "manual_cleanup")
end)

addEventHandler("onPlayerQuit", root, function()
    destroySession(source, false)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do
        destroySession(player, true)
    end
end)
