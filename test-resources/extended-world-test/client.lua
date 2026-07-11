local function reportCheck(name, passed, details)
    local status = passed and "OK" or "ECHEC"
    local color = passed and { 80, 255, 160 } or { 255, 80, 80 }
    outputChatBox(("[Extended world] %s: %s%s"):format(name, status, details and (" (" .. details .. ")") or ""), color[1], color[2], color[3])
    outputDebugString(("[Extended world] %s: %s%s"):format(name, status, details and (" (" .. details .. ")") or ""))
end

addEvent("extendedWorldRunChecks", true)
addEventHandler("extendedWorldRunChecks", resourceRoot, function(x, y, z)
    setTimer(function()
        local px, py, pz = getElementPosition(localPlayer)
        reportCheck("teleport", math.abs(px - x) < 20 and math.abs(py - y) < 20, ("position %.1f, %.1f, %.1f"):format(px, py, pz))

        local hit, hitX, hitY, hitZ, hitElement = processLineOfSight(
            x + 3,
            y,
            z + 15,
            x + 3,
            y,
            z - 5,
            true,
            true,
            true,
            true,
            true,
            false,
            false,
            false,
            localPlayer
        )
        reportCheck("line-of-sight", hit and isElement(hitElement), hit and ("impact z=%.2f"):format(hitZ) or "aucun impact")

        local vehicle = getPedOccupiedVehicle(localPlayer)
        reportCheck("vehicule", isElement(vehicle), isElement(vehicle) and getElementType(vehicle) or "absent")
        local cameraTarget = getCameraTarget()
        local expectedCameraTarget = cameraTarget == localPlayer or cameraTarget == vehicle
        reportCheck("camera", expectedCameraTarget, isElement(cameraTarget) and getElementType(cameraTarget) or "aucune cible")
    end, 1500, 1)
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "object" then
        local x = getElementPosition(source)
        if math.abs(x) > 3000 then
            outputDebugString(("[Extended world] stream-in objet x=%.1f"):format(x))
        end
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "object" then
        local x = getElementPosition(source)
        if math.abs(x) > 3000 then
            outputDebugString(("[Extended world] stream-out objet x=%.1f"):format(x))
        end
    end
end)
