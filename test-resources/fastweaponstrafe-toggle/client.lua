local function reportNativeWalkingStyle()
    local message = ("Client state: native=%s walkingStyle=%s model=%s"):format(
        tostring(isPedUsingNativeWalkingStyle(localPlayer)),
        tostring(getPedWalkingStyle(localPlayer)),
        tostring(getElementModel(localPlayer))
    )

    outputChatBox(message, 120, 220, 255)
    outputDebugString("[samp-movement] " .. message)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(reportNativeWalkingStyle, 1500, 1)
end)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    setTimer(reportNativeWalkingStyle, 500, 1)
end)

addCommandHandler("nativewalkclient", reportNativeWalkingStyle)
