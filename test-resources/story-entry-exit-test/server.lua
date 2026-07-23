local TEST_DIMENSION = 4104
local sessions = {}
local sessionsByHandle = {}

local function snapshotPlayer(player)
    local x, y, z = getElementPosition(player)
    local rx, ry, rz = getElementRotation(player)
    return {
        position = {x, y, z},
        rotation = {rx, ry, rz},
        interior = getElementInterior(player),
        cameraInterior = getCameraInterior(player),
        dimension = getElementDimension(player),
        frozen = isElementFrozen(player),
    }
end

local function restorePlayer(player, snapshot)
    if not isElement(player) or not snapshot then
        return
    end
    setElementInterior(player, snapshot.interior)
    setCameraInterior(player, snapshot.cameraInterior)
    setElementDimension(player, snapshot.dimension)
    setElementPosition(player, snapshot.position[1], snapshot.position[2], snapshot.position[3])
    setElementRotation(player, snapshot.rotation[1], snapshot.rotation[2], snapshot.rotation[3])
    setElementFrozen(player, snapshot.frozen)
end

local function stopTest(player, reason, restore)
    local session = sessions[player]
    if not session then
        return false
    end
    sessions[player] = nil
    if isElement(session.handle) then
        sessionsByHandle[session.handle] = nil
        local handle = session.handle
        session.handle = nil
        pcall(function()
            exports["story-entry-exit-runtime"]:releaseStoryEntryExit(handle)
        end)
    end
    if restore then
        restorePlayer(player, session.snapshot)
    end
    if isElement(player) then
        outputChatBox("[ENEX test] stopped: " .. tostring(reason), player, 255, 210, 100)
    end
    return true
end

local function startTest(player)
    stopTest(player, "replaced", true)
    removePedFromVehicle(player)
    local session = {player = player, snapshot = snapshotPlayer(player)}
    sessions[player] = session

    setElementInterior(player, 0)
    setCameraInterior(player, 0)
    setElementDimension(player, TEST_DIMENSION)
    setElementPosition(player, 2244.48, -1664.06, 14.4690)
    setElementRotation(player, 0.0, 0.0, 357.0)
    setElementFrozen(player, false)

    local handle, reason = exports["story-entry-exit-runtime"]:acquireStoryEntryExit(
                               player, "cschp_ls", TEST_DIMENSION,
                               {fadeOut = 1.0, blackHold = 0.25, fadeIn = 1.0})
    if not handle then
        restorePlayer(player, session.snapshot)
        sessions[player] = nil
        outputChatBox("[ENEX test] acquisition failed: " .. tostring(reason), player, 255, 80, 80)
        return
    end
    session.handle = handle
    sessionsByHandle[handle] = session
    outputChatBox("[ENEX test] Walk into Binco's yellow doorway. Entry and exit are automatic and on-foot only.", player,
                  120, 255, 160)
end

addCommandHandler("enextest", startTest)
addCommandHandler("enexteststop", function(player)
    stopTest(player, "command", true)
end)

addEventHandler("onStoryEntryExitStateChange", root, function(state, data)
    local session = sessionsByHandle[source]
    if not session or not isElement(session.player) then
        return
    end
    if state == "active" or state == "fading_out" or state == "committed" or state == "entered" or state == "exited" then
        outputChatBox(("[ENEX test] %s epoch=%s interior=%s"):format(
                          state, tostring(type(data) == "table" and data.epoch or "?"),
                          tostring(type(data) == "table" and data.interior or getElementInterior(session.player))),
                      session.player, 120, 220, 255)
    elseif state == "failed" then
        outputChatBox("[ENEX test] failed: " .. tostring(type(data) == "table" and data.reason or "unknown"), session.player,
                      255, 80, 80)
        stopTest(session.player, "runtime failure", true)
    end
end)

addEventHandler("onElementDestroy", root, function()
    local session = sessionsByHandle[source]
    if not session then
        return
    end
    sessionsByHandle[source] = nil
    session.handle = nil
    stopTest(session.player, "lease destroyed", true)
end)

addEventHandler("onPlayerQuit", root, function()
    stopTest(source, "player quit", false)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    local players = {}
    for player in pairs(sessions) do
        players[#players + 1] = player
    end
    for _, player in ipairs(players) do
        stopTest(player, "resource stop", true)
    end
end)
