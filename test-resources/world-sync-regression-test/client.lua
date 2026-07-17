local activeRunId
local activeTimers = {}
local reportedLabels = {}

local function cancelActiveTimers()
    for _, timer in ipairs(activeTimers) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    activeTimers = {}
end

local function rememberTimer(timer)
    table.insert(activeTimers, timer)
    return timer
end

local function report(runId, label, passed, details)
    if activeRunId ~= runId or reportedLabels[label] then
        return
    end
    reportedLabels[label] = true
    triggerServerEvent("worldSyncRegression:result", resourceRoot, runId, label, passed, details)
    outputDebugString(("[World sync regression] %s %s: %s"):format(label, passed and "PASS" or "FAIL", details))
end

local function distance2D(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

addEvent("worldSyncRegression:prepare", true)
addEventHandler("worldSyncRegression:prepare", resourceRoot, function(runId, object)
    cancelActiveTimers()
    activeRunId = runId
    reportedLabels = {}

    local attempts = 0
    local timer

    timer = rememberTimer(setTimer(function()
        attempts = attempts + 1
        if isElement(object) and isElementStreamedIn(object) then
            killTimer(timer)
            triggerServerEvent("worldSyncRegression:ready", resourceRoot, runId, object)
        elseif attempts >= 100 then
            killTimer(timer)
            report(runId, "SETUP", false, "objet non streame apres 10 secondes")
        end
    end, 100, 0))
end)

addEvent("worldSyncRegression:cancel", true)
addEventHandler("worldSyncRegression:cancel", resourceRoot, function()
    activeRunId = nil
    cancelActiveTimers()
end)

addEvent("worldSyncRegression:watchMove", true)
addEventHandler("worldSyncRegression:watchMove", resourceRoot, function(runId, object, startX, startY, startZ, targetX, targetY, targetZ)
    if activeRunId ~= runId then
        return
    end

    local validSamples = 0
    local intermediateSamples = 0
    local movingSamples = 0
    local maxStep = 0
    local maxCrossTrack = 0
    local regressed = false
    local overshot = false
    local lastX, lastY
    local lastProgress = 0
    local timer

    timer = rememberTimer(setTimer(function()
        if not isElement(object) then
            if isTimer(timer) then
                killTimer(timer)
            end
            report(runId, "MOVE", false, "objet detruit ou absent cote client")
            return
        end

        local x, y, z = getElementPosition(object)
        validSamples = validSamples + 1

        if lastX then
            local step = distance2D(lastX, lastY, x, y)
            maxStep = math.max(maxStep, step)
            if step > 0.02 then
                movingSamples = movingSamples + 1
            end
        end
        lastX, lastY = x, y

        local totalDistance = distance2D(startX, startY, targetX, targetY)
        local progress = totalDistance > 0 and (x - startX) / (targetX - startX) or 1
        maxCrossTrack = math.max(maxCrossTrack, math.abs(y - startY), math.abs(z - startZ))
        if progress < lastProgress - 0.01 then
            regressed = true
        end
        if progress < -0.04 or progress > 1.04 then
            overshot = true
        end
        lastProgress = math.max(lastProgress, progress)

        if progress > 0.05 and progress < 0.95 then
            intermediateSamples = intermediateSamples + 1
        end
    end, 100, 65))

    rememberTimer(setTimer(function()
        if not isElement(object) then
            report(runId, "MOVE", false, "objet absent au verdict")
            return
        end

        local x, y, z = getElementPosition(object)
        local finalError = getDistanceBetweenPoints3D(x, y, z, targetX, targetY, targetZ)
        local passed = validSamples >= 50 and intermediateSamples >= 10 and movingSamples >= 10 and maxStep <= 5 and maxCrossTrack <= 0.25 and not regressed and not overshot and finalError <= 0.75
        local details = ("samples=%d intermediate=%d moving=%d maxStep=%.2f cross=%.2f regress=%s overshoot=%s finalError=%.2f"):format(
            validSamples,
            intermediateSamples,
            movingSamples,
            maxStep,
            maxCrossTrack,
            tostring(regressed),
            tostring(overshot),
            finalError
        )
        report(runId, "MOVE", passed, details)
    end, 6750, 1))
end)

local function comparePoints(actual, expected)
    if type(actual) ~= "table" then
        return false, "getColPolygonPoints n'a pas renvoye de table"
    end
    if #actual ~= #expected then
        return false, ("count client=%d serveur=%d"):format(#actual, #expected)
    end

    for index, expectedPoint in ipairs(expected) do
        local actualPoint = actual[index]
        if type(actualPoint) ~= "table" then
            return false, ("point %d absent"):format(index)
        end

        local xError = math.abs(actualPoint[1] - expectedPoint[1])
        local yError = math.abs(actualPoint[2] - expectedPoint[2])
        if xError > 0.02 or yError > 0.02 then
            return false, ("point %d client=(%.3f, %.3f) serveur=(%.3f, %.3f)"):format(
                index,
                actualPoint[1],
                actualPoint[2],
                expectedPoint[1],
                expectedPoint[2]
            )
        end
    end

    return true, ("%d points identiques"):format(#expected)
end

addEvent("worldSyncRegression:checkPolygon", true)
addEventHandler("worldSyncRegression:checkPolygon", resourceRoot, function(runId, polygon, label, expectedPoints)
    if activeRunId ~= runId then
        return
    end

    -- The expected-state event follows the live RPC on the reliable stream. A
    -- short delay also makes the check robust to the client processing frame.
    rememberTimer(setTimer(function()
        if not isElement(polygon) then
            report(runId, label, false, "polygon absent cote client")
            return
        end

        local passed, details = comparePoints(getColPolygonPoints(polygon), expectedPoints)
        report(runId, label, passed, details)
    end, 300, 1))
end)
