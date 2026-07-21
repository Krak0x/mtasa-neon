local activeTest

local function report(evidence, data)
    local test = activeTest
    if not test then
        return
    end
    triggerServerEvent("nativeMissionPed:evidence", resourceRoot, test.id, evidence, data or {})
end

local function stopTimers(test)
    if isTimer(test.retryTimer) then killTimer(test.retryTimer) end
    if isTimer(test.profileTimer) then killTimer(test.profileTimer) end
    if isTimer(test.monitorTimer) then killTimer(test.monitorTimer) end
end

local function stopTest(reason, notifyServer)
    local test = activeTest
    if not test then
        return
    end
    stopTimers(test)
    if test.eventProfileToken and type(releasePedNativeEventProfile) == "function" then
        releasePedNativeEventProfile(test.eventProfileToken)
        test.eventProfileToken = nil
    end
    if isElement(test.shooter) then
        if test.taskAccepted then
            killPedTask(test.shooter, "primary", 3, false)
        end
        if test.missionActorApplied and type(setPedMissionActor) == "function" then
            setPedMissionActor(test.shooter, test.wasMissionActor)
        end
    end
    activeTest = nil
    if notifyServer then
        triggerServerEvent("nativeMissionPed:stopped", resourceRoot, test.id, reason or "stopped")
    end
end

local function taskActive(ped, name)
    return type(isPedDoingTask) == "function" and isPedDoingTask(ped, name) == true
end

local function beginPolicy()
    local test = activeTest
    if not test or not isElement(test.shooter) or not isElement(test.vehicle) or not isElement(test.target) then
        return
    end
    if not isElementStreamedIn(test.shooter) or not isElementStreamedIn(test.vehicle) or not isElementSyncer(test.shooter) or
        not isElementSyncer(test.vehicle) then
        if getTickCount() - test.requestedAt < 8000 then
            test.retryTimer = setTimer(beginPolicy, 200, 1)
            return
        end
        report("failure", {details = "streaming/syncer absent apres 8 s"})
        return
    end
    if type(setPedMissionActor) ~= "function" or type(isPedMissionActor) ~= "function" or type(setPedKillOnFoot) ~= "function" or
        type(acquirePedNativeEventProfile) ~= "function" or type(releasePedNativeEventProfile) ~= "function" or
        type(isPedNativeEventProfileActive) ~= "function" then
        report("failure", {details = "API native mission ped ou kill-on-foot absente"})
        return
    end

    test.wasMissionActor = isPedMissionActor(test.shooter)
    if not setPedMissionActor(test.shooter, true) or not isPedMissionActor(test.shooter) then
        report("failure", {details = "setPedMissionActor refuse"})
        return
    end
    test.missionActorApplied = true
    test.eventProfileToken = acquirePedNativeEventProfile(test.shooter, "mission")
    if not test.eventProfileToken or not isPedNativeEventProfileActive(test.shooter, test.eventProfileToken) then
        report("failure", {details = "bail du profil evenementiel mission refuse ou inactif"})
        return
    end
    report("lease", {details = ("PED_MISSION + bail evenementiel acquis token=%d; cycle syncer demande"):format(
                                  test.eventProfileToken)})
end

local function verifyProfileState(expectedActive, evidence)
    local test = activeTest
    if not test or not test.eventProfileToken or not isElement(test.shooter) then
        return
    end
    local startedAt = getTickCount()
    local function sample()
        local current = activeTest
        if not current or current ~= test or not isElement(current.shooter) then
            return
        end
        local syncer = isElementSyncer(current.shooter) == true
        local active = isPedNativeEventProfileActive(current.shooter, current.eventProfileToken) == true
        if active == expectedActive and syncer == expectedActive then
            report(evidence, {details = ("token=%d syncer=%s active=%s"):format(
                                         current.eventProfileToken, tostring(syncer), tostring(active))})
        elseif getTickCount() - startedAt < 5000 then
            current.profileTimer = setTimer(sample, 100, 1)
        else
            report("failure", {details = ("cycle syncer timeout attendu=%s syncer=%s active=%s"):format(
                                           tostring(expectedActive), tostring(syncer), tostring(active))})
        end
    end
    sample()
end

local function beginMonitor()
    local test = activeTest
    if not test or not test.taskAccepted then
        return
    end
    test.monitorStartedAt = getTickCount()
    test.monitorTimer = setTimer(function()
        local current = activeTest
        if not current or not isElement(current.shooter) or not isElement(current.vehicle) or not isElement(current.target) then
            return
        end

        local simplest = type(getPedSimplestTask) == "function" and getPedSimplestTask(current.shooter) or false
        if simplest ~= current.lastSimplest then
            current.lastSimplest = simplest
            report("task", {details = ("simplest=%s"):format(tostring(simplest))})
        end

        local leaveAndFlee = taskActive(current.shooter, "TASK_COMPLEX_LEAVE_CAR_AND_FLEE")
        local smartFlee = taskActive(current.shooter, "TASK_COMPLEX_SMART_FLEE_ENTITY")
        local kill = taskActive(current.shooter, "TASK_COMPLEX_KILL_PED_ON_FOOT")
        local inVehicle = getPedOccupiedVehicle(current.shooter) == current.vehicle
        local sx, sy, sz = getElementPosition(current.shooter)
        local vx, vy, vz = getElementPosition(current.vehicle)
        local distanceFromVehicle = getDistanceBetweenPoints3D(sx, sy, sz, vx, vy, vz)
        current.maxDistanceFromVehicle = math.max(current.maxDistanceFromVehicle, distanceFromVehicle)

        if (leaveAndFlee or smartFlee) and not current.fleeObserved then
            current.fleeObserved = true
            report("flee", {details = ("leaveAndFlee=%s smartFlee=%s inVehicle=%s distance=%.2f"):format(
                                      tostring(leaveAndFlee), tostring(smartFlee), tostring(inVehicle), distanceFromVehicle)})
        end
        if current.fleeObserved and not inVehicle then
            current.leftVehicle = true
        end
        if current.fleeObserved and current.leftVehicle and current.maxDistanceFromVehicle >= 8.0 and kill and not leaveAndFlee and not smartFlee then
            current.combatResumed = true
        end

        local targetHealth = getElementHealth(current.target)
        if current.combatResumed and targetHealth < current.initialTargetHealth - 0.1 and not current.passed then
            current.passed = true
            report("pass", {details = ("maxDistance=%.2f targetHealth=%.1f kill=%s"):format(
                                      current.maxDistanceFromVehicle, targetHealth, tostring(kill))})
        elseif getTickCount() - current.monitorStartedAt >= 25000 and not current.passed then
            report("failure", {details = ("timeout flee=%s left=%s maxDistance=%.2f resumed=%s targetHealth=%.1f simplest=%s"):format(
                                          tostring(current.fleeObserved), tostring(current.leftVehicle), current.maxDistanceFromVehicle,
                                          tostring(current.combatResumed), targetHealth, tostring(simplest))})
            killTimer(current.monitorTimer)
        end
    end, 50, 0)
end

addEvent("nativeMissionPed:start", true)
addEventHandler("nativeMissionPed:start", resourceRoot, function(sessionId, shooter, vehicle, target)
    if source ~= resourceRoot then
        return
    end
    stopTest("replaced", false)
    activeTest = {
        id = tonumber(sessionId),
        shooter = shooter,
        vehicle = vehicle,
        target = target,
        requestedAt = getTickCount(),
        initialTargetHealth = isElement(target) and getElementHealth(target) or 500,
        maxDistanceFromVehicle = 0,
    }
    beginPolicy()
end)

addEvent("nativeMissionPed:attack", true)
addEventHandler("nativeMissionPed:attack", resourceRoot, function(sessionId)
    local test = activeTest
    if source ~= resourceRoot or not test or test.id ~= tonumber(sessionId) or not isElement(test.shooter) or not isElement(test.target) then
        return
    end
    if type(setPedWeaponAccuracy) == "function" then setPedWeaponAccuracy(test.shooter, 60) end
    if type(setPedWeaponShootingRate) == "function" then setPedWeaponShootingRate(test.shooter, 70) end
    test.taskAccepted = setPedKillOnFoot(test.shooter, test.target) == true
    report(test.taskAccepted and "attack" or "failure", {
        details = test.taskAccepted and "TASK_KILL_CHAR_ON_FOOT accepte sous la reponse incendie" or "setPedKillOnFoot refuse",
    })
    if test.taskAccepted then
        beginMonitor()
    end
end)

addEvent("nativeMissionPed:verifyProfile", true)
addEventHandler("nativeMissionPed:verifyProfile", resourceRoot, function(sessionId, expectedActive, evidence)
    local test = activeTest
    if source == resourceRoot and test and test.id == tonumber(sessionId) and type(expectedActive) == "boolean" and
        (evidence == "inactive" or evidence == "ready") then
        verifyProfileState(expectedActive, evidence)
    end
end)

addEvent("nativeMissionPed:stop", true)
addEventHandler("nativeMissionPed:stop", resourceRoot, function(sessionId, reason)
    if source == resourceRoot and activeTest and activeTest.id == tonumber(sessionId) then
        stopTest(reason or "stopped", true)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopTest("resource_stop", false)
end)
