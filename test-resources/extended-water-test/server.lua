local testXs = { 2990, 3010, 5000, 9500, 9990, -9990 }
local testY = 0
local customWaterLevel = 8
local halfSize = 8
local playerTests = {}

local function findTestX(requested)
    local requestedX = tonumber(requested) or 9500
    for _, x in ipairs(testXs) do
        if x == requestedX then
            return x
        end
    end
    return nil
end

local function clearPlayerTest(player)
    local test = playerTests[player]
    if not test then
        return
    end

    if isElement(test.vehicle) then
        destroyElement(test.vehicle)
    end
    if isElement(test.water) then
        destroyElement(test.water)
    end
    playerTests[player] = nil
end

local function runWaterTest(player, _, requested)
    local x = findTestX(requested)
    if not x then
        outputChatBox("[Water world] Valeurs: 2990, 3010, 5000, 9500, 9990, -9990.", player, 255, 180, 80)
        return
    end

    clearPlayerTest(player)

    local water = createWater(
        x - halfSize, testY - halfSize, customWaterLevel,
        x + halfSize, testY - halfSize, customWaterLevel,
        x - halfSize, testY + halfSize, customWaterLevel,
        x + halfSize, testY + halfSize, customWaterLevel
    )

    local vehicle = createVehicle(473, x, testY, customWaterLevel + 3, 0, 0, 0)
    if not vehicle then
        if isElement(water) then
            destroyElement(water)
        end
        outputChatBox("[Water world] ECHEC creation Dinghy.", player, 255, 80, 80)
        return
    end

    playerTests[player] = { water = water, vehicle = vehicle }
    warpPedIntoVehicle(player, vehicle)

    local created = isElement(water)
    local status = created and "OK" or "ECHEC"
    outputChatBox(("[Water world] createWater x=%d z=%d: %s"):format(x, customWaterLevel, status), player, created and 80 or 255, created and 255 or 100, created and 160 or 80)
    outputChatBox("[Water world] /watertest [x] pour changer, /waterback pour revenir.", player, 80, 200, 255)
    triggerClientEvent(player, "extendedWaterRunChecks", resourceRoot, x, testY, customWaterLevel, created)
end

local function returnToSanAndreas(player)
    clearPlayerTest(player)
    setElementPosition(player, 1481, -1771, 19)
    outputChatBox("[Water world] Retour a San Andreas.", player, 80, 200, 255)
end

addEventHandler("onResourceStart", resourceRoot, function()
    outputServerLog("[Water world] Ready. Commande: /watertest [2990|3010|5000|9500|9990|-9990]")
end)

addCommandHandler("watertest", runWaterTest)
addCommandHandler("waterback", returnToSanAndreas)

addEventHandler("onPlayerQuit", root, function()
    clearPlayerTest(source)
end)

addEventHandler("onPlayerWasted", root, function()
    clearPlayerTest(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(playerTests) do
        clearPlayerTest(player)
    end
end)
