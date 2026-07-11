local function report(name, passed, details)
    local status = passed and "OK" or "ECHEC"
    local color = passed and { 80, 255, 160 } or { 255, 80, 80 }
    local message = ("[Water world] %s: %s (%s)"):format(name, status, details)
    outputChatBox(message, color[1], color[2], color[3])
    outputDebugString(message)
end

local function runChecks(x, y, customLevel, waterCreated)
    local level = getWaterLevel(x, y, customLevel + 10, true)
    local expectedLevel = waterCreated and customLevel or 0
    local levelMatches = type(level) == "number" and math.abs(level - expectedLevel) < 0.75
    report("getWaterLevel", levelMatches, type(level) == "number" and ("niveau %.2f, attendu %.2f"):format(level, expectedLevel) or "aucun niveau")

    local hit, hitX, hitY, hitZ = testLineAgainstWater(x, y, customLevel + 12, x, y, -5)
    local hitMatches = hit and math.abs(hitZ - expectedLevel) < 0.75
    report("line-of-sight", hitMatches, hit and ("impact z=%.2f, attendu %.2f"):format(hitZ, expectedLevel) or "aucun impact")

    local vehicle = getPedOccupiedVehicle(localPlayer)
    local vehicleZ
    if isElement(vehicle) then
        local _, _, z = getElementPosition(vehicle)
        vehicleZ = z
    end
    report("Dinghy", isElement(vehicle), vehicleZ and ("z=%.2f"):format(vehicleZ) or "absent")
end

addEvent("extendedWaterRunChecks", true)
addEventHandler("extendedWaterRunChecks", resourceRoot, function(x, y, customLevel, waterCreated)
    outputDebugString(("[Water world] test x=%d created=%s customLevel=%.2f"):format(x, tostring(waterCreated), customLevel))
    setTimer(runChecks, 1500, 1, x, y, customLevel, waterCreated)
    setTimer(runChecks, 4000, 1, x, y, customLevel, waterCreated)
end)
