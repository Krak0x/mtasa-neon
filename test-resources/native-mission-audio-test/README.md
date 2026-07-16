# Native mission audio test

This isolated resource exercises Neon's resource-owned wrapper around GTA San Andreas' four native mission-audio slots. It reads the original voice samples from the player's installed `audio/SFX/SCRIPT`; the resource contains no extracted Rockstar audio.

## Commands

- `/nativeaudio ar|ca|cb` loads, plays, observes natural completion, and releases one `SWEET1` line.
- `/nativeaudiosequence` preloads CA and AR together, then plays AR, CA, and CB in the mission order.
- `/nativeaudioguards` checks the supported event range, four-slot ceiling, and fifth-request refusal.
- `/nativeaudioclear` interrupts and releases every handle owned by this resource.
- `/nativeaudiorestart` starts AR and restarts the resource without a Lua release, validating native cleanup from `CResource` teardown.

The restart test needs the narrowly scoped ACL request:

```text
aclrequest allow native-mission-audio-test function.restartResource
```

After the resource returns to `ready`, `/nativeaudio ar` must work again. Report every `[native audio]` line and confirm audibly that AR, CA, and CB are the expected Sweet lines without overlap or repetition.

## API contract exercised

```lua
local handle = requestMissionAudio(eventId)
isMissionAudioLoaded(handle)
playMissionAudio(handle)
isMissionAudioFinished(handle)
releaseMissionAudio(handle)
```

Handles are generation tokens and implicitly belong to the calling resource. A resource cannot query, play, or release another resource's handle. Resource shutdown clears only slots whose native event still matches the owned request; unknown external slots are never preempted.
