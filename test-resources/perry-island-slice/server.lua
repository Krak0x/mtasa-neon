local target = {
    x = 9000,
    y = -144.106003,
    z = 24,
}

local sanAndreasSpawn = {1481, -1771, 19}
local readyPlayers = {}
local playerVehicles = {}

local function removePlayerVehicle(player)
    local vehicle = playerVehicles[player]
    if isElement(vehicle) then
        destroyElement(vehicle)
    end
    playerVehicles[player] = nil
end

addEvent("perrySliceClientReady", true)
addEventHandler("perrySliceClientReady", resourceRoot, function(success, details)
    if not client or source ~= resourceRoot then
        return
    end

    readyPlayers[client] = success == true
    outputServerLog(("[Perry slice] %s ready=%s (%s)"):format(getPlayerName(client), tostring(success == true), tostring(details)))
end)

addCommandHandler("perrytest", function(player)
    if not readyPlayers[player] then
        outputChatBox("[Perry slice] Les assets client ne sont pas encore prets.", player, 255, 180, 80)
        return
    end

    removePlayerVehicle(player)
    local vehicle = createVehicle(411, target.x, target.y, target.z, 0, 0, 90)
    if not vehicle then
        outputChatBox("[Perry slice] ECHEC creation vehicule.", player, 255, 80, 80)
        return
    end

    playerVehicles[player] = vehicle
    warpPedIntoVehicle(player, vehicle)
    outputChatBox("[Perry] Ile complete a x=9000. /perryback pour revenir.", player, 80, 255, 160)
end)

addCommandHandler("perryback", function(player)
    removePlayerVehicle(player)
    setElementPosition(player, sanAndreasSpawn[1], sanAndreasSpawn[2], sanAndreasSpawn[3])
    outputChatBox("[Perry slice] Retour a San Andreas.", player, 80, 200, 255)
end)

addEventHandler("onPlayerQuit", root, function()
    readyPlayers[source] = nil
    removePlayerVehicle(source)
end)

addEventHandler("onPlayerWasted", root, function()
    removePlayerVehicle(source)
end)
