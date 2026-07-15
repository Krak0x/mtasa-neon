local TASK_NAME = "TASK_COMPLEX_LEAVE_CAR"
local activeTest

local function stopTimers(test)
    if isTimer(test.retryTimer) then
        killTimer(test.retryTimer)
    end
    if isTimer(test.monitorTimer) then
        killTimer(test.monitorTimer)
    end
end

local function report(result, details)
    local test = activeTest
    if not test then
        return
    end

    stopTimers(test)
    activeTest = nil
    triggerServerEvent("nativePedLeaveCar:result", resourceRoot, test.id, test.ped, test.vehicle, result, details)
end

local function beginNativeTask()
    local test = activeTest
    if not test then
        return
    end
    if not isElement(test.ped) or not isElement(test.vehicle) then
        return report("destroyed", "ped ou vehicule detruit avant la task")
    end
    if not isElementStreamedIn(test.ped) or not isElementStreamedIn(test.vehicle) or not isElementSyncer(test.ped) then
        if getTickCount() - test.requestedAt < 5000 then
            test.retryTimer = setTimer(beginNativeTask, 250, 1)
            return
        end
        return report("refused", "ped/vehicule non streame ou client non-syncer apres 5 s")
    end
    if getPedOccupiedVehicle(test.ped) ~= test.vehicle or getPedOccupiedVehicleSeat(test.ped) ~= 1 then
        return report("refused", "Sweet n'est pas passager au moment de la demande")
    end

    local accepted = setPedExitVehicle(test.ped)
    if not accepted then
        return report("refused", "setPedExitVehicle a retourne false")
    end

    test.acceptedAt = getTickCount()
    test.seenNativeTask = false
    test.monitorTimer = setTimer(function()
        local current = activeTest
        if not current then
            return
        end
        if not isElement(current.ped) or not isElement(current.vehicle) then
            return report("destroyed", "ped ou vehicule detruit pendant la task")
        end

        local running = isPedDoingTask(current.ped, TASK_NAME)
        current.seenNativeTask = current.seenNativeTask or running
        local elapsed = getTickCount() - current.acceptedAt
        local occupiedVehicle = getPedOccupiedVehicle(current.ped)

        if current.seenNativeTask and not running then
            if not occupiedVehicle then
                return report("exited", ("elapsed=%d ms, task native observee"):format(elapsed))
            end
            return report("ended_in_vehicle", ("elapsed=%d ms, Sweet occupe encore un vehicule"):format(elapsed))
        end
        if not current.seenNativeTask and elapsed > 5000 then
            return report("not_observed", "TASK_COMPLEX_LEAVE_CAR jamais observee")
        end
        if elapsed > 15000 then
            return report("timeout", ("elapsed=%d ms"):format(elapsed))
        end
    end, 50, 0)
end

addEvent("nativePedLeaveCar:start", true)
addEventHandler("nativePedLeaveCar:start", resourceRoot, function(sessionId, ped, vehicle)
    if activeTest then
        stopTimers(activeTest)
    end
    activeTest = {
        id = sessionId,
        ped = ped,
        vehicle = vehicle,
        requestedAt = getTickCount(),
    }
    beginNativeTask()
end)

addEvent("nativePedLeaveCar:cancel", true)
addEventHandler("nativePedLeaveCar:cancel", resourceRoot, function(sessionId, ped)
    local test = activeTest
    if not test or test.id ~= sessionId or test.ped ~= ped or not isElement(ped) then
        return
    end

    local killed = killPedTask(ped, "primary", 3, false)
    report("cancelled", killed and "slot PRIMARY supprime" or "killPedTask a retourne false")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if activeTest then
        stopTimers(activeTest)
    end
    activeTest = nil
end)
