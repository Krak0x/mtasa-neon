local activeTest

local function report(evidence, data)
    if not activeTest then
        return false
    end
    triggerServerEvent("nativeSimulationLease:evidence", resourceRoot, activeTest.id, evidence, data or {})
    return true
end

local function releaseLeases(test)
    local pedReleased = true
    local vehicleReleased = true
    if test.pedLease then
        pedReleased = releaseElementStreamingLease(test.pedLease)
        test.pedLease = nil
    end
    if test.vehicleLease then
        vehicleReleased = releaseElementStreamingLease(test.vehicleLease)
        test.vehicleLease = nil
    end
    return pedReleased, vehicleReleased
end

local function stopTest(killTask)
    local test = activeTest
    if not test then
        return
    end
    if isTimer(test.retryTimer) then killTimer(test.retryTimer) end
    if isTimer(test.monitorTimer) then killTimer(test.monitorTimer) end
    if killTask and test.accepted and isElement(test.ped) then
        killPedTask(test.ped, "primary", 3, false)
    end
    if test.missionActorApplied and isElement(test.ped) and type(setPedMissionActor) == "function" then
        setPedMissionActor(test.ped, test.wasMissionActor)
    end
    releaseLeases(test)
    activeTest = nil
end

local function beginSimulation()
    local test = activeTest
    if not test or not isElement(test.ped) or not isElement(test.vehicle) then
        return stopTest(false)
    end
    if not isElementStreamedIn(test.ped) or not isElementStreamedIn(test.vehicle) or not isElementSyncer(test.ped) or not isElementSyncer(test.vehicle) then
        if getTickCount() - test.requestedAt < 8000 then
            test.retryTimer = setTimer(beginSimulation, 250, 1)
            return
        end
        report("failure", {reason = "double stream/ownership absent apres 8 s"})
        return stopTest(false)
    end

    if type(acquireElementStreamingLease) ~= "function" or type(releaseElementStreamingLease) ~= "function" then
        report("failure", {reason = "API streaming lease absente du client Neon"})
        return stopTest(false)
    end
    if type(setPedTaskSequence) ~= "function" or type(getPedTaskSequenceProgress) ~= "function" then
        report("failure", {reason = "API sequence native absente du client Neon"})
        return stopTest(false)
    end
    if type(setVehicleLoadCollisionFlag) ~= "function" then
        report("failure", {reason = "API SET_LOAD_COLLISION_FOR_CAR_FLAG absente du client Neon"})
        return stopTest(false)
    end

    test.pedLease = acquireElementStreamingLease(test.ped)
    test.vehicleLease = acquireElementStreamingLease(test.vehicle)
    if not test.pedLease or not test.vehicleLease then
        report("failure", {reason = "acquisition du lease ped/vehicule refusee"})
        return stopTest(false)
    end

    test.wasMissionActor = isPedMissionActor(test.ped)
    if not setPedMissionActor(test.ped, true) then
        report("failure", {reason = "PED_MISSION refuse"})
        return stopTest(false)
    end
    test.missionActorApplied = true

    -- SWEET3 sets opcode 0587 to FALSE on this exact chase vehicle. GTA then
    -- ghosts the mission car while route collision is absent instead of
    -- letting gravity pull it through unloaded world geometry.
    test.loadCollisionFlagApplied = setVehicleLoadCollisionFlag(test.vehicle, false)
    if not test.loadCollisionFlagApplied then
        report("failure", {reason = "SET_LOAD_COLLISION_FOR_CAR_FLAG refuse"})
        return stopTest(false)
    end

    local sequence = {}
    for index, point in ipairs(NATIVE_SIMULATION_ROUTE) do
        sequence[index] = {
            task = "drive_to",
            x = point[1], y = point[2], z = point[3], speed = point[4],
            mode = "normal", vehicleModel = 412, drivingStyle = "avoid_cars",
        }
    end

    test.startedAt = getTickCount()
    test.accepted = setPedTaskSequence(test.ped, sequence, true)
    report("ready", {
        accepted = test.accepted,
        pedLease = test.pedLease,
        vehicleLease = test.vehicleLease,
        pedStreamed = isElementStreamedIn(test.ped),
        vehicleStreamed = isElementStreamedIn(test.vehicle),
        pedSyncer = isElementSyncer(test.ped),
        vehicleSyncer = isElementSyncer(test.vehicle),
        loadCollisionFlag = test.loadCollisionFlagApplied,
    })
    if not test.accepted then
        return stopTest(false)
    end

    test.monitorTimer = setTimer(function()
        local current = activeTest
        if not current or not isElement(current.ped) or not isElement(current.vehicle) then
            return
        end
        local x, y, z = getElementPosition(current.vehicle)
        local vx, vy, vz = getElementVelocity(current.vehicle)
        local px, py, pz = getElementPosition(localPlayer)
        local sample = {
            elapsed = getTickCount() - current.startedAt,
            index = getPedTaskSequenceProgress(current.ped),
            pedStreamed = isElementStreamedIn(current.ped),
            vehicleStreamed = isElementStreamedIn(current.vehicle),
            pedSyncer = isElementSyncer(current.ped),
            vehicleSyncer = isElementSyncer(current.vehicle),
            x = x, y = y, z = z,
            speed = math.sqrt(vx * vx + vy * vy + vz * vz),
            distance = getDistanceBetweenPoints3D(px, py, pz, x, y, z),
        }
        report("sample", sample)
        triggerServerEvent("nativeSimulationLease:position", resourceRoot, current.id, x, y, z)
    end, 1000, 0)
end

addEvent("nativeSimulationLease:start", true)
addEventHandler("nativeSimulationLease:start", resourceRoot, function(sessionId, ped, vehicle)
    stopTest(true)
    activeTest = {id = sessionId, ped = ped, vehicle = vehicle, requestedAt = getTickCount(), accepted = false}
    beginSimulation()
end)

addEvent("nativeSimulationLease:release", true)
addEventHandler("nativeSimulationLease:release", resourceRoot, function(sessionId)
    local test = activeTest
    if not test or test.id ~= sessionId then
        return
    end
    local pedReleased, vehicleReleased = releaseLeases(test)
    report("released", {ped = pedReleased, vehicle = vehicleReleased})
end)

addEvent("nativeSimulationLease:stop", true)
addEventHandler("nativeSimulationLease:stop", resourceRoot, function(sessionId)
    if activeTest and activeTest.id == sessionId then
        stopTest(true)
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    local test = activeTest
    if not test then
        return
    end
    if source == test.ped then
        report("streamout", {element = "ped"})
    elseif source == test.vehicle then
        report("streamout", {element = "vehicle"})
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopTest(true)
end)
