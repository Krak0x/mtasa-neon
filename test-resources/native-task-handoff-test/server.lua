local sessions = {}
local nextSessionId = 0

local function log(player, message, r, g, b)
    outputServerLog("[task handoff] " .. getPlayerName(player) .. ": " .. message)
    outputChatBox("[task handoff] " .. message, player, r or 220, g or 220, b or 220)
end

local function runtimeRunning()
    local runtime = getResourceFromName("native-task-runtime")
    return runtime and getResourceState(runtime) == "running"
end

local function savePlayer(player)
    local x, y, z = getElementPosition(player)
    local _, _, rotation = getElementRotation(player)
    return {x = x, y = y, z = z, rotation = rotation, dimension = getElementDimension(player), interior = getElementInterior(player)}
end

local function cleanup(player, restore)
    local session = sessions[player]
    if not session then
        return
    end
    if isElement(session.task) and runtimeRunning() then
        exports["native-task-runtime"]:cancelNativeDriveRoute(session.task)
    end
    if isElement(session.ped) then destroyElement(session.ped) end
    if isElement(session.vehicle) then destroyElement(session.vehicle) end
    if restore and isElement(player) and session.saved then
        setElementInterior(player, session.saved.interior)
        setElementDimension(player, session.saved.dimension)
        setElementPosition(player, session.saved.x, session.saved.y, session.saved.z)
        setElementRotation(player, 0, 0, session.saved.rotation)
    end
    sessions[player] = nil
end

local function startTest(player)
    cleanup(player, true)
    if not runtimeRunning() then
        return log(player, "FAIL: start native-task-runtime avant ce harness", 255, 80, 80)
    end

    nextSessionId = nextSessionId + 1
    local session = {id = nextSessionId, player = player, saved = savePlayer(player), minimumIndex = 0}
    sessions[player] = session

    setElementInterior(player, 0)
    setElementDimension(player, 0)
    setElementPosition(player, NATIVE_HANDOFF_START.x - 8, NATIVE_HANDOFF_START.y, NATIVE_HANDOFF_START.z + 1)

    session.vehicle = createVehicle(412, NATIVE_HANDOFF_START.x, NATIVE_HANDOFF_START.y, NATIVE_HANDOFF_START.z,
                                    0, 0, NATIVE_HANDOFF_START.rotation, "HANDOFF")
    session.ped = createPed(102, NATIVE_HANDOFF_START.x, NATIVE_HANDOFF_START.y, NATIVE_HANDOFF_START.z + 1)
    if not session.vehicle or not session.ped then
        log(player, "FAIL: creation Voodoo/ped refusee", 255, 80, 80)
        return cleanup(player, true)
    end
    setVehicleColor(session.vehicle, 86, 7, 7, 86, 7, 7)
    warpPedIntoVehicle(session.ped, session.vehicle, 0)

    local handle, reason = exports["native-task-runtime"]:createNativeDriveRoute(session.ped, session.vehicle, NATIVE_HANDOFF_ROUTE,
                                                                                   player, {
        loadCollision = false,
        validZMin = 8,
        validZMax = 20,
        fallbackOwners = {player},
    })
    if not handle then
        log(player, "FAIL: runtime refuse la route: " .. tostring(reason), 255, 80, 80)
        return cleanup(player, true)
    end
    session.task = handle
    log(player, "epoch 1 demande. Attends ACTIVE, puis /nativehandofffar et /nativehandoffcycle", 120, 220, 255)
end

addCommandHandler("nativehandoff", startTest)

addCommandHandler("nativehandofffar", function(player)
    local session = sessions[player]
    if not session then return log(player, "lance /nativehandoff d'abord", 255, 180, 80) end
    setElementPosition(player, NATIVE_HANDOFF_FAR.x, NATIVE_HANDOFF_FAR.y, NATIVE_HANDOFF_FAR.z)
    log(player, "joueur eloigne. La Voodoo doit continuer hors distance normale de stream", 120, 220, 255)
end)

addCommandHandler("nativehandoffcycle", function(player)
    local session = sessions[player]
    if not session or not isElement(session.task) then return log(player, "aucune route active", 255, 180, 80) end
    local state = exports["native-task-runtime"]:getNativeDriveRouteState(session.task)
    if not state or state.state ~= "active" then
        return log(player, "attends un etat ACTIVE avant le cycle", 255, 180, 80)
    end
    session.preHandoffIndex = state.routeIndex
    session.preHandoffX, session.preHandoffY, session.preHandoffZ = getElementPosition(session.vehicle)
    session.awaitingEpoch = state.epoch + 1
    session.postEpochOrigin = nil
    session.streamedOutPed = false
    session.streamedOutVehicle = false
    local accepted, reason = exports["native-task-runtime"]:handoffNativeDriveRoute(session.task, player, true)
    if not accepted then
        return log(player, "FAIL: handoff refuse: " .. tostring(reason), 255, 80, 80)
    end
    log(player, "revoke demande loin de la route; attends les deux STREAM-OUT puis ACTIVE epoch 2", 120, 220, 255)
end)

addCommandHandler("nativehandoffnear", function(player)
    local session = sessions[player]
    if not session or not isElement(session.vehicle) then return log(player, "aucun vehicule de test", 255, 180, 80) end
    local x, y, z = getElementPosition(session.vehicle)
    setElementPosition(player, x - 8, y, z + 2)
    log(player, "retour pres de la position serveur courante", 120, 220, 255)
end)

addCommandHandler("nativehandoffcleanup", function(player)
    cleanup(player, true)
    log(player, "cleanup termine", 160, 255, 160)
end)

addEventHandler("onNativeDriveRouteStateChange", root, function(state, data)
    for player, session in pairs(sessions) do
        if source == session.task then
            local ownerName = isElement(data.owner) and getPlayerName(data.owner) or "none"
            if data.streamOutElement == "ped" then session.streamedOutPed = true end
            if data.streamOutElement == "vehicle" then session.streamedOutVehicle = true end
            if state ~= "active" or data.sample ~= true then
                log(player, string.format("state=%s epoch=%d index=%d owner=%s streamout=%s/%s", state, data.epoch,
                                          data.routeIndex, ownerName, tostring(data.streamedOutPed),
                                          tostring(data.streamedOutVehicle)), 200, 220, 255)
            end

            if state == "active" and data.routeIndex < session.minimumIndex then
                log(player, "FAIL: regression de l'index logique", 255, 80, 80)
            end
            session.minimumIndex = math.max(session.minimumIndex, data.routeIndex)

            if session.awaitingEpoch and state == "active" and data.epoch == session.awaitingEpoch then
                if not session.postEpochOrigin then
                    session.postEpochOrigin = {getElementPosition(session.vehicle)}
                    local regressed = data.routeIndex < (session.preHandoffIndex or 0)
                    local gap = data.handoffDistance or getDistanceBetweenPoints3D(session.preHandoffX, session.preHandoffY,
                                                                                   session.preHandoffZ,
                                                                                   session.postEpochOrigin[1],
                                                                                   session.postEpochOrigin[2],
                                                                                   session.postEpochOrigin[3])
                    local invalidResume = regressed or gap > 15
                    log(player, string.format("epoch repris: index=%d (avant=%d), discontinuite=%.2f m, stream-out=%s/%s",
                                              data.routeIndex, session.preHandoffIndex or -1, gap,
                                              tostring(session.streamedOutPed), tostring(session.streamedOutVehicle)),
                        invalidResume and 255 or 160, invalidResume and 80 or 255, 120)
                else
                    local x, y, z = getElementPosition(session.vehicle)
                    local moved = getDistanceBetweenPoints2D(session.postEpochOrigin[1], session.postEpochOrigin[2], x, y)
                    if moved >= 20 and not session.passed then
                        session.passed = true
                        local syncersGood = getElementSyncer(session.ped) == player and getElementSyncer(session.vehicle) == player
                        if session.streamedOutPed and session.streamedOutVehicle and syncersGood then
                            log(player, string.format("PASS: epoch reconstruit, %.1f m observes, Z=%.2f, index=%d", moved, z,
                                                      data.routeIndex), 100, 255, 100)
                        else
                            log(player, "FAIL: mouvement sans double stream-out ou double syncer", 255, 80, 80)
                        end
                    end
                end
            elseif state == "failed" then
                log(player, "FAIL runtime: " .. tostring(data.reason), 255, 80, 80)
            end
            break
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    cleanup(source, false)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    local players = {}
    for player in pairs(sessions) do players[#players + 1] = player end
    for _, player in ipairs(players) do cleanup(player, true) end
end)

outputServerLog("[task handoff] Ready. Commands: /nativehandoff, /nativehandofffar, /nativehandoffcycle, /nativehandoffnear.")
