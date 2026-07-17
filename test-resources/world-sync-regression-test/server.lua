local sessions = {}
local nextRunId = 0

local function destroySession(player)
    local session = sessions[player]
    if not session then
        return
    end

    for _, element in ipairs(session.elements) do
        if isElement(element) then
            destroyElement(element)
        end
    end

    sessions[player] = nil
end

local function remember(session, element)
    if element then
        table.insert(session.elements, element)
    end
    return element
end

local function isCurrentRun(player, runId)
    local session = sessions[player]
    return session and session.runId == runId
end

local function sendPolygonCheck(player, runId, polygon, label)
    if not isCurrentRun(player, runId) or not isElement(polygon) then
        return
    end

    triggerClientEvent(
        player,
        "worldSyncRegression:checkPolygon",
        resourceRoot,
        runId,
        polygon,
        label,
        getColPolygonPoints(polygon)
    )
end

local function makePolygon(session, centerX, centerY, yOffset)
    local y = centerY + yOffset
    return remember(
        session,
        createColPolygon(
            centerX,
            y,
            centerX - 4,
            y - 4,
            centerX + 4,
            y - 4,
            centerX + 4,
            y + 4,
            centerX - 4,
            y + 4
        )
    )
end

local validResultLabels = {
    ["SETUP"] = true,
    ["MOVE"] = true,
    ["COL SET"] = true,
    ["COL ADD"] = true,
    ["COL ADD INDEX"] = true,
}

local function recordResult(player, runId, label, passed, details)
    local session = sessions[player]
    if not session or session.runId ~= runId or not validResultLabels[label] or session.results[label] then
        return
    end

    details = details:gsub("[\r\n]", " "):sub(1, 300)
    session.results[label] = true

    local status = passed and "PASS" or "FAIL"
    local color = passed and {80, 255, 160} or {255, 80, 80}
    local message = ("[World sync regression] %s %s: %s"):format(label, status, details)
    outputChatBox(message, player, unpack(color))
    outputServerLog(("%s player=%s run=%d"):format(message, getPlayerName(player), runId))
end

local function startLiveTests(player, session)
    local runId = session.runId
    local playerX, playerY = session.playerX, session.playerY
    local object = session.object

    triggerClientEvent(
        player,
        "worldSyncRegression:watchMove",
        resourceRoot,
        runId,
        object,
        session.startX,
        session.startY,
        session.startZ,
        session.targetX,
        session.targetY,
        session.targetZ
    )

    setTimer(function(testPlayer, testRunId, testObject)
        if not isCurrentRun(testPlayer, testRunId) or not isElement(testObject) then
            return
        end

        local started = moveObject(testObject, 4000, session.targetX, session.targetY, session.targetZ, 0, 0, 90, "Linear")
        if not started then
            recordResult(testPlayer, testRunId, "MOVE", false, "moveObject a refuse l'animation")
        end
    end, 1000, 1, player, runId, object)

    setTimer(function(testPlayer, testRunId, polygon)
        if not isCurrentRun(testPlayer, testRunId) or not isElement(polygon) then
            return
        end

        local ok = setColPolygonPointPosition(polygon, 2, playerX + 6, playerY + 8)
        if not ok then
            recordResult(testPlayer, testRunId, "COL SET", false, "appel serveur refuse")
            return
        end
        sendPolygonCheck(testPlayer, testRunId, polygon, "COL SET")
    end, 1800, 1, player, runId, session.setPolygon)

    setTimer(function(testPlayer, testRunId, polygon)
        if not isCurrentRun(testPlayer, testRunId) or not isElement(polygon) then
            return
        end

        local ok = addColPolygonPoint(polygon, playerX - 7, playerY + 24)
        if not ok then
            recordResult(testPlayer, testRunId, "COL ADD", false, "appel serveur refuse")
            return
        end
        sendPolygonCheck(testPlayer, testRunId, polygon, "COL ADD")
    end, 2600, 1, player, runId, session.appendPolygon)

    setTimer(function(testPlayer, testRunId, polygon)
        if not isCurrentRun(testPlayer, testRunId) or not isElement(polygon) then
            return
        end

        local ok = addColPolygonPoint(polygon, playerX, playerY + 30, 3)
        if not ok then
            recordResult(testPlayer, testRunId, "COL ADD INDEX", false, "appel serveur refuse")
            return
        end
        sendPolygonCheck(testPlayer, testRunId, polygon, "COL ADD INDEX")
    end, 3400, 1, player, runId, session.indexedPolygon)
end

local function beginTest(player)
    destroySession(player)

    nextRunId = nextRunId + 1
    local runId = nextRunId
    local playerX, playerY, playerZ = getElementPosition(player)
    local startX, startY, startZ = playerX + 4, playerY, playerZ - 0.75
    local targetX, targetY, targetZ = startX + 20, startY, startZ
    local session = {
        runId = runId,
        elements = {},
        results = {},
        playerX = playerX,
        playerY = playerY,
        startX = startX,
        startY = startY,
        startZ = startZ,
        targetX = targetX,
        targetY = targetY,
        targetZ = targetZ,
    }
    sessions[player] = session

    local object = remember(session, createObject(1337, startX, startY, startZ))
    local setPolygon = makePolygon(session, playerX, playerY, 12)
    local appendPolygon = makePolygon(session, playerX, playerY, 24)
    local indexedPolygon = makePolygon(session, playerX, playerY, 36)

    if not isElement(object) or not isElement(setPolygon) or not isElement(appendPolygon) or not isElement(indexedPolygon) then
        outputChatBox("[World sync regression] ECHEC de creation des elements.", player, 255, 80, 80)
        destroySession(player)
        return
    end

    session.object = object
    session.setPolygon = setPolygon
    session.appendPolygon = appendPolygon
    session.indexedPolygon = indexedPolygon

    setElementInterior(object, getElementInterior(player))
    setElementDimension(object, getElementDimension(player))
    for _, polygon in ipairs({setPolygon, appendPolygon, indexedPolygon}) do
        setElementInterior(polygon, getElementInterior(player))
        setElementDimension(polygon, getElementDimension(player))
    end

    outputChatBox(("[World sync regression] Run #%d prepare; attente du stream-in client."):format(runId), player, 100, 220, 255)
    outputChatBox("[World sync regression] Ne bouge pas loin et garde le client ouvert.", player, 220, 220, 220)

    triggerClientEvent(
        player,
        "worldSyncRegression:prepare",
        resourceRoot,
        runId,
        object
    )
end

addCommandHandler("worldsynctest", function(player)
    if isElement(player) then
        beginTest(player)
    end
end)

addCommandHandler("worldsynccleanup", function(player)
    if not isElement(player) then
        return
    end
    triggerClientEvent(player, "worldSyncRegression:cancel", resourceRoot)
    destroySession(player)
    outputChatBox("[World sync regression] Elements nettoyes.", player, 180, 220, 255)
end)

addEvent("worldSyncRegression:ready", true)
addEventHandler("worldSyncRegression:ready", resourceRoot, function(runId, object)
    local player = client
    local session = sessions[player]
    if type(runId) ~= "number" or source ~= resourceRoot or not session or session.runId ~= runId or session.object ~= object or session.started then
        return
    end

    session.started = true
    outputChatBox("[World sync regression] Stream-in confirme; live RPCs en cours.", player, 100, 220, 255)
    startLiveTests(player, session)
end)

addEvent("worldSyncRegression:result", true)
addEventHandler("worldSyncRegression:result", resourceRoot, function(runId, label, passed, details)
    local player = client
    if type(runId) ~= "number" or type(label) ~= "string" or type(passed) ~= "boolean" or type(details) ~= "string" then
        return
    end
    if source ~= resourceRoot or not isCurrentRun(player, runId) then
        return
    end
    recordResult(player, runId, label, passed, details)
end)

addEventHandler("onPlayerQuit", root, function()
    destroySession(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do
        destroySession(player)
    end
end)
