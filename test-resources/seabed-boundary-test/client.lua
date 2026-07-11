local testX, testY = 9500, 2500
local currentBoundary = "unlimited"

local function report(name, passed, details)
    local status = passed and "OK" or "ECHEC"
    local color = passed and { 80, 255, 160 } or { 255, 80, 80 }
    local message = ("[Seabed test] %s: %s (%s)"):format(name, status, details)
    outputChatBox(message, color[1], color[2], color[3])
    outputDebugString(message)
end

local function runChecks()
    local playerX, playerY, playerZ = getElementPosition(localPlayer)
    report("position joueur", true, ("%.1f, %.1f, %.1f"):format(playerX, playerY, playerZ))

    local level = getWaterLevel(testX, testY, 10, true)
    report("ocean conserve", type(level) == "number" and math.abs(level) < 0.75,
        type(level) == "number" and ("niveau %.2f a %.0f,%.0f; seabed=%s"):format(level, testX, testY, currentBoundary)
            or ("aucun niveau a %.0f,%.0f"):format(testX, testY))

    local hit, _, _, hitZ = testLineAgainstWater(testX, testY, 20, testX, testY, -100)
    report("line-of-sight water", hit and math.abs(hitZ) < 0.75,
        hit and ("impact z=%.2f a %.0f,%.0f"):format(hitZ, testX, testY) or ("aucun impact a %.0f,%.0f"):format(testX, testY))
end

addEvent("seaBedBoundaryRunChecks", true)
addEventHandler("seaBedBoundaryRunChecks", resourceRoot, function(boundary)
    currentBoundary = boundary
    setTimer(runChecks, 500, 1)
end)

addCommandHandler("seabedcheck", runChecks)
