local restartTimer

addEvent("nativeMissionAudioTest:restart", true)
addEventHandler("nativeMissionAudioTest:restart", resourceRoot, function()
    if source ~= resourceRoot or not isElement(client) or isTimer(restartTimer) then
        return
    end

    if not hasObjectPermissionTo(getThisResource(), "function.restartResource", false) then
        outputChatBox("[native audio] ACL absente: aclrequest allow native-mission-audio-test function.restartResource", client, 255, 80, 80)
        return
    end

    outputChatBox("[native audio] Restart dans 2 s; le handle reste volontairement ouvert.", client, 255, 180, 80)
    restartTimer = setTimer(function()
        restartResource(getThisResource())
    end, 2000, 1)
end)
