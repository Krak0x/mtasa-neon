local TASK_NAME = "TASK_COMPLEX_CAR_DRIVE_WANDER"
local activeTest

local function stopTimers(test)
    if isTimer(test.retryTimer) then
        killTimer(test.retryTimer)
    end
    if isTimer(test.monitorTimer) then
        killTimer(test.monitorTimer)
    end
end

local function report(result, details, terminal)
    local test = activeTest
    if not test then
        return
    end
    triggerServerEvent("nativePedDriveWander:result", resourceRoot, test.id, test.ped, test.vehicle, result, details)
    if terminal then
        stopTimers(test)
        if test.taskAccepted and isElement(test.ped) and result ~= "cancelled" then
            killPedTask(test.ped, "primary", 3, false)
        end
        if test.missionActorApplied and isElement(test.ped) and type(setPedMissionActor) == "function" then
            setPedMissionActor(test.ped, test.wasMissionActor)
        end
        activeTest = nil
    end
end

local function beginNativeTask()
    local test = activeTest
    if not test then
        return
    end
    if not isElement(test.ped) or not isElement(test.vehicle) then
        return report("destroyed", "ped ou vehicule absent avant 05D2", true)
    end
    if not isElementStreamedIn(test.ped) or not isElementStreamedIn(test.vehicle) or not isElementSyncer(test.ped) or
        not isElementSyncer(test.vehicle) then
        if getTickCount() - test.requestedAt < 5000 then
            test.retryTimer = setTimer(beginNativeTask, 250, 1)
            return
        end
        return report("ownership_refused", "Sweet/Greenwood non stream ou client pas double syncer apres 5 s", true)
    end
    if getPedOccupiedVehicle(test.ped) ~= test.vehicle or getPedOccupiedVehicleSeat(test.ped) ~= 1 or getVehicleController(test.vehicle) then
        return report("invalid_state", "Sweet doit etre passager avec siege conducteur vide", true)
    end
    if type(setPedDriveWander) ~= "function" then
        return report("api_unavailable", "setPedDriveWander absent du client Neon", true)
    end
    if type(setPedMissionActor) ~= "function" or type(isPedMissionActor) ~= "function" then
        return report("api_unavailable", "mission-actor API absente du client Neon", true)
    end
    test.wasMissionActor = isPedMissionActor(test.ped)
    if not setPedMissionActor(test.ped, true) or not isPedMissionActor(test.ped) then
        return report("mission_actor_refused", "PED_MISSION non applique a Sweet", true)
    end
    test.missionActorApplied = true
    if not setPedDriveWander(test.ped, test.vehicle, 20.0, "avoid_cars") then
        return report("refused", "setPedDriveWander a retourne false", true)
    end

    test.taskAccepted = true
    test.acceptedAt = getTickCount()
    test.monitorTimer = setTimer(function()
        local current = activeTest
        if not current then
            return
        end
        if not isElement(current.ped) or not isElement(current.vehicle) then
            return report("destroyed", "ped ou vehicule detruit pendant la task", true)
        end
        if not isElementSyncer(current.ped) or not isElementSyncer(current.vehicle) then
            return report("ownership_lost", "double ownership perdu pendant la task", true)
        end

        local running = isPedDoingTask(current.ped, TASK_NAME)
        local elapsed = getTickCount() - current.acceptedAt
        if running and not current.observed then
            current.observed = true
            report("observed", ("TASK_COMPLEX_CAR_DRIVE_WANDER apres %d ms"):format(elapsed), false)
        elseif current.observed and running and not current.persistent and elapsed >= 15000 then
            current.persistent = true
            report("persistent", ("PED_MISSION confirme; task toujours active apres %d ms"):format(elapsed), false)
        elseif current.observed and not running then
            return report("ended", ("task indefinite disparue apres %d ms"):format(elapsed), true)
        elseif not current.observed and elapsed > 5000 then
            return report("not_observed", "TASK_COMPLEX_CAR_DRIVE_WANDER jamais observee", true)
        end
    end, 50, 0)
end

addEvent("nativePedDriveWander:start", true)
addEventHandler("nativePedDriveWander:start", resourceRoot, function(sessionId, ped, vehicle)
    if activeTest then
        stopTimers(activeTest)
    end
    activeTest = {id = sessionId, ped = ped, vehicle = vehicle, requestedAt = getTickCount(), observed = false}
    beginNativeTask()
end)

addEvent("nativePedDriveWander:cancel", true)
addEventHandler("nativePedDriveWander:cancel", resourceRoot, function(sessionId, ped, vehicle)
    local test = activeTest
    if not test or test.id ~= sessionId or test.ped ~= ped or test.vehicle ~= vehicle or not isElement(ped) then
        return
    end
    local killed = killPedTask(ped, "primary", 3, false)
    report(killed and "cancelled" or "cancel_failed", killed and "PRIMARY supprime; GTA restaure l'autopilot" or "killPedTask a retourne false", true)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if activeTest then
        killPedTask(activeTest.ped, "primary", 3, false)
        if activeTest.missionActorApplied and isElement(activeTest.ped) and type(setPedMissionActor) == "function" then
            setPedMissionActor(activeTest.ped, activeTest.wasMissionActor)
        end
        stopTimers(activeTest)
    end
    activeTest = nil
end)
