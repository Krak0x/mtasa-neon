local TASK_NAME = "TASK_COMPLEX_ENTER_CAR_AS_PASSENGER"
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
    triggerServerEvent("nativePedEnterCar:result", resourceRoot, test.id, test.ped, test.vehicle, result, details)
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
    if getPedOccupiedVehicle(test.ped) then
        return report("refused", "Sweet occupe deja un vehicule")
    end
    if getVehicleOccupant(test.vehicle, 1) then
        return report("refused", "le siege passager avant est deja occupe")
    end
    if type(setPedEnterVehicle) ~= "function" then
        return report("api_unavailable", "setPedEnterVehicle absent du client Neon")
    end

    -- SCM seat 0 means the first passenger slot; MTA reserves seat 0 for the
    -- driver, so the equivalent public-API seat is 1.
    test.accepted = setPedEnterVehicle(test.ped, test.vehicle, 1)
    if not test.accepted then
        return report("refused", "setPedEnterVehicle a retourne false")
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
        if not isElementSyncer(current.ped) then
            return report("ownership_lost", "client non-syncer pendant la task")
        end

        local running = isPedDoingTask(current.ped, TASK_NAME)
        current.seenNativeTask = current.seenNativeTask or running
        local elapsed = getTickCount() - current.acceptedAt
        local occupiedVehicle = getPedOccupiedVehicle(current.ped)
        local occupiedSeat = occupiedVehicle and getPedOccupiedVehicleSeat(current.ped) or -1

        if current.seenNativeTask and not running then
            if occupiedVehicle == current.vehicle and occupiedSeat == 1 then
                return report("entered", ("elapsed=%d ms, task native observee, seat=%d"):format(elapsed, occupiedSeat))
            end
            return report("ended_outside_vehicle", ("elapsed=%d ms, occupied=%s, seat=%d"):format(elapsed,
                                                                                                  tostring(occupiedVehicle == current.vehicle),
                                                                                                  occupiedSeat))
        end
        if not current.seenNativeTask and elapsed > 5000 then
            return report("not_observed", "TASK_COMPLEX_ENTER_CAR_AS_PASSENGER jamais observee")
        end
        if elapsed > 20000 then
            return report("timeout", ("elapsed=%d ms, occupied=%s, seat=%d"):format(elapsed,
                                                                                    tostring(occupiedVehicle == current.vehicle),
                                                                                    occupiedSeat))
        end
    end, 50, 0)
end

addEvent("nativePedEnterCar:start", true)
addEventHandler("nativePedEnterCar:start", resourceRoot, function(sessionId, ped, vehicle)
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

addEvent("nativePedEnterCar:cancel", true)
addEventHandler("nativePedEnterCar:cancel", resourceRoot, function(sessionId, ped)
    local test = activeTest
    if not test or test.id ~= sessionId or test.ped ~= ped or not isElement(ped) then
        return
    end

    local killed = test.accepted and killPedTask(ped, "primary", 3, false)
    report("cancelled", killed and "slot PRIMARY supprime" or "task absente ou killPedTask refuse")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if activeTest then
        stopTimers(activeTest)
    end
    activeTest = nil
end)
