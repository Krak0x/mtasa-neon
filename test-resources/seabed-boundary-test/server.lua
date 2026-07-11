local allowedBoundaries = {
    [3000] = true,
    [5000] = true,
    [7500] = true,
    [9000] = true,
    [9500] = true,
    [10000] = true,
}

local returnPositions = {}

local function describeBoundary()
    local boundary = getWorldSeaBedOuterBoundary()
    return boundary and tostring(math.floor(boundary)) or "unlimited"
end

local function runSeaBedTest(player, _, requested)
    if requested == "reset" or requested == "unlimited" then
        resetWorldSeaBedOuterBoundary()
    else
        local boundary = tonumber(requested)
        if not boundary or not allowedBoundaries[boundary] then
            outputChatBox("[Seabed test] Valeurs: 3000, 5000, 7500, 9000, 9500, 10000, reset.", player, 255, 180, 80)
            outputChatBox("[Seabed test] Actuel: " .. describeBoundary(), player, 80, 200, 255)
            return
        end
        setWorldSeaBedOuterBoundary(boundary)
    end

    local applied = describeBoundary()
    outputChatBox("[Seabed test] Limite appliquee: " .. applied, root, 80, 255, 160)
    triggerClientEvent(root, "seaBedBoundaryRunChecks", resourceRoot, applied)
end

local function goToSeaBedTest(player, _, requestedX)
    local x = tonumber(requestedX) or 9500
    if x < 3000 or x > 9999 then
        outputChatBox("[Seabed test] X doit etre entre 3000 et 9999.", player, 255, 100, 80)
        return
    end

    if not returnPositions[player] then
        local px, py, pz = getElementPosition(player)
        returnPositions[player] = { px, py, pz, getElementInterior(player), getElementDimension(player), isElementFrozen(player) }
    end

    setElementInterior(player, 0)
    setElementDimension(player, 0)
    setElementPosition(player, x, 2500, -20)
    setElementFrozen(player, true)
    outputChatBox(("[Seabed test] Position figee x=%.0f y=2500 z=-20. Compare /seabedtest 10000 puis 7500."):format(x), player, 80, 200, 255)
end

local function returnFromSeaBedTest(player)
    local position = returnPositions[player]
    if not position then
        outputChatBox("[Seabed test] Aucune position de retour.", player, 255, 180, 80)
        return
    end

    setElementInterior(player, position[4])
    setElementDimension(player, position[5])
    setElementPosition(player, position[1], position[2], position[3])
    setElementFrozen(player, position[6])
    returnPositions[player] = nil
    outputChatBox("[Seabed test] Position restauree.", player, 80, 200, 255)
end

addCommandHandler("seabedtest", runSeaBedTest)
addCommandHandler("seabedgoto", goToSeaBedTest)
addCommandHandler("seabedback", returnFromSeaBedTest)

addEventHandler("onResourceStart", resourceRoot, function()
    outputServerLog("[Seabed test] Ready: /seabedgoto [x], /seabedtest [boundary|reset], /seabedback")
end)

addEventHandler("onPlayerQuit", root, function()
    returnPositions[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, position in pairs(returnPositions) do
        if isElement(player) then
            setElementFrozen(player, position[6])
        end
    end
    resetWorldSeaBedOuterBoundary()
end)
