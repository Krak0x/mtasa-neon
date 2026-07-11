local testXs = { 2990, 3010, 5000, 7000, 9500 }
local testZ = 20
local sanAndreasSpawn = { 1481, -1771, 19 }
local testElements = {}
local playerVehicles = {}
local playerBuildings = {}

local function remember(element)
    if element then
        table.insert(testElements, element)
    end
    return element
end

local function createTestArea(x)
    for row = -1, 1 do
        for column = -1, 1 do
            local floor = remember(createObject(3095, x + column * 10, row * 10, testZ - 1))
            if floor then
                setElementFrozen(floor, true)
            end
        end
    end

    remember(createObject(3095, x + 15, 0, testZ + 4, 0, 90, 0))
    remember(createObject(3095, x - 15, 0, testZ + 4, 0, 90, 0))
    remember(createObject(3095, x, 15, testZ + 4, 90, 0, 0))
    remember(createObject(3095, x, -15, testZ + 4, 90, 0, 0))
end

local function findTestX(requested)
    local requestedX = tonumber(requested) or 7000
    for _, x in ipairs(testXs) do
        if x == requestedX then
            return x
        end
    end
    return nil
end

local function removePlayerVehicle(player)
    local vehicle = playerVehicles[player]
    if isElement(vehicle) then
        destroyElement(vehicle)
    end
    playerVehicles[player] = nil
end

local function removePlayerBuilding(player)
    local building = playerBuildings[player]
    if isElement(building) then
        destroyElement(building)
    end
    playerBuildings[player] = nil
end

local function goToExtendedWorld(player, _, requested)
    local x = findTestX(requested)
    if not x then
        outputChatBox("[Extended world] Valeurs: 2990, 3010, 5000, 7000, 9500.", player, 255, 180, 80)
        return
    end

    removePlayerVehicle(player)
    local vehicle = createVehicle(411, x, 0, testZ + 2, 0, 0, 90)
    if not vehicle then
        outputChatBox("[Extended world] Echec de creation du vehicule.", player, 255, 80, 80)
        return
    end

    playerVehicles[player] = vehicle
    warpPedIntoVehicle(player, vehicle)
    setElementPosition(vehicle, x, 0, testZ + 2)
    setElementVelocity(vehicle, 0, 0, 0)
    outputChatBox(("[Extended world] Zone x=%d. /sanandreas pour revenir, /ewtest [x] pour changer."):format(x), player, 80, 255, 160)
    triggerClientEvent(player, "extendedWorldRunChecks", resourceRoot, x, 0, testZ)
end

local function testBuilding(player, _, requested)
    local x = findTestX(requested)
    if not x then
        outputChatBox("[Building world] Valeurs: 2990, 3010, 5000, 7000, 9500.", player, 255, 180, 80)
        return
    end

    removePlayerVehicle(player)
    removePlayerBuilding(player)
    local building = createBuilding(3095, x, 50, testZ - 1)
    if not building then
        outputChatBox("[Building world] ECHEC createBuilding.", player, 255, 80, 80)
        return
    end
    playerBuildings[player] = building

    local vehicle = createVehicle(411, x, 50, testZ + 2, 0, 0, 90)
    if not vehicle then
        removePlayerBuilding(player)
        outputChatBox("[Building world] Batiment cree, vehicule ECHEC.", player, 255, 80, 80)
        return
    end
    playerVehicles[player] = vehicle
    warpPedIntoVehicle(player, vehicle)
    outputChatBox(("[Building world] createBuilding x=%d: OK. Test collision/LOS en cours."):format(x), player, 80, 255, 160)
    triggerClientEvent(player, "extendedWorldRunChecks", resourceRoot, x, 50, testZ)
end

local function returnToSanAndreas(player)
    removePlayerVehicle(player)
    setElementPosition(player, sanAndreasSpawn[1], sanAndreasSpawn[2], sanAndreasSpawn[3])
    outputChatBox("[Extended world] Retour a San Andreas.", player, 80, 200, 255)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, x in ipairs(testXs) do
        createTestArea(x)
    end
    outputServerLog(("[Extended world] %d elements de test crees."):format(#testElements))
end)

addCommandHandler("ewtest", goToExtendedWorld)
addCommandHandler("bwtest", testBuilding)
addCommandHandler("sanandreas", returnToSanAndreas)

addEventHandler("onPlayerQuit", root, function()
    removePlayerVehicle(source)
    removePlayerBuilding(source)
end)

addEventHandler("onPlayerWasted", root, function()
    removePlayerVehicle(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(playerVehicles) do
        removePlayerVehicle(player)
    end

    for player in pairs(playerBuildings) do
        removePlayerBuilding(player)
    end

    for _, element in ipairs(testElements) do
        if isElement(element) then
            destroyElement(element)
        end
    end
    testElements = {}
end)
