-- Ocean Beach's initial Vice City street area, translated with the generated map.
-- The client prepares the surrounding collision and buildings before the
-- server moves the player, avoiding a blind teleport into an unloaded cell.
local target = {x = 7343.25, y = -8416.45, z = 35}
local sanAndreasSpawn = {1481, -1771, 19}
local readyPlayers = {}
local playerVehicles = {}
local pendingTeleports = {}
local nextTeleportToken = 0

local function removePlayerVehicle(player)
    local vehicle = playerVehicles[player]
    if isElement(vehicle) then
        destroyElement(vehicle)
    end
    playerVehicles[player] = nil
end

local function cancelPendingTeleport(player, notifyClient)
    local pending = pendingTeleports[player]
    if not pending then
        return
    end
    if isTimer(pending.timer) then
        killTimer(pending.timer)
    end
    pendingTeleports[player] = nil
    if notifyClient and isElement(player) then
        triggerClientEvent(player, "ugVcPrepareCancelled", resourceRoot, pending.token)
    end
end

addEvent("ugVcClientReady", true)
addEventHandler("ugVcClientReady", resourceRoot, function(success, details)
    if not client or source ~= resourceRoot then
        return
    end
    readyPlayers[client] = success == true
    outputServerLog(("[UG VC] %s ready=%s (%s)"):format(getPlayerName(client), tostring(success == true), tostring(details)))
end)

addEvent("ugVcPositionReady", true)
addEventHandler("ugVcPositionReady", resourceRoot, function(token, success, details)
    if not client or source ~= resourceRoot then
        return
    end
    local pending = pendingTeleports[client]
    if not pending or pending.token ~= token then
        return
    end
    cancelPendingTeleport(client, false)

    if success ~= true then
        outputChatBox("[UG VC] Echec de preparation: " .. tostring(details), client, 255, 80, 80)
        triggerClientEvent(client, "ugVcPrepareCancelled", resourceRoot, token)
        return
    end

    removePlayerVehicle(client)
    local occupiedVehicle = getPedOccupiedVehicle(client)
    if isElement(occupiedVehicle) then
        destroyElement(occupiedVehicle)
    end
    local vehicle = createVehicle(411, target.x, target.y, target.z, 0, 0, 90)
    if not vehicle then
        outputChatBox("[UG VC] ECHEC creation vehicule.", client, 255, 80, 80)
        triggerClientEvent(client, "ugVcPrepareCancelled", resourceRoot, token)
        return
    end

    playerVehicles[client] = vehicle
    warpPedIntoVehicle(client, vehicle)
    triggerClientEvent(client, "ugVcTeleportCommitted", resourceRoot, token)
    outputChatBox("[UG VC] Vice City prete. /vcback pour revenir a San Andreas.", client, 80, 255, 160)
    outputServerLog(("[UG VC] %s teleported (%s)"):format(getPlayerName(client), tostring(details)))
end)

addCommandHandler("vctest", function(player)
    if pendingTeleports[player] then
        outputChatBox("[UG VC] Vice City est deja en preparation.", player, 255, 200, 80)
        return
    end

    nextTeleportToken = nextTeleportToken + 1
    local token = nextTeleportToken
    local timeout = setTimer(function(expectedPlayer, expectedToken)
        local pending = pendingTeleports[expectedPlayer]
        if not pending or pending.token ~= expectedToken then
            return
        end
        pendingTeleports[expectedPlayer] = nil
        if isElement(expectedPlayer) then
            triggerClientEvent(expectedPlayer, "ugVcPrepareCancelled", resourceRoot, expectedToken)
            outputChatBox("[UG VC] Preparation annulee apres 60 secondes.", expectedPlayer, 255, 80, 80)
        end
    end, 60000, 1, player, token)

    pendingTeleports[player] = {token = token, timer = timeout}
    triggerClientEvent(player, "ugVcPreparePosition", resourceRoot, target.x, target.y, target.z, token)
    outputChatBox("[UG VC] Preparation de la zone de spawn...", player, 255, 200, 80)
end)

addCommandHandler("vcback", function(player)
    cancelPendingTeleport(player, true)
    removePlayerVehicle(player)
    setElementPosition(player, sanAndreasSpawn[1], sanAndreasSpawn[2], sanAndreasSpawn[3])
    outputChatBox("[UG VC] Retour a San Andreas; Vice City reste prete en arriere-plan.", player, 80, 200, 255)
end)

addEventHandler("onPlayerQuit", root, function()
    readyPlayers[source] = nil
    cancelPendingTeleport(source, false)
    removePlayerVehicle(source)
end)

addEventHandler("onPlayerWasted", root, function()
    cancelPendingTeleport(source, true)
    removePlayerVehicle(source)
end)
