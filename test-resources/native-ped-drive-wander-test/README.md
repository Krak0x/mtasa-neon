# Native ped drive-wander test

This resource isolates GTA's indefinite `CTaskComplexCarDriveWander` from the
Tagging Up Turf mission.

## API under test

```text
setPedDriveWander(ped, vehicle, speed [, drivingStyle = "stop_for_cars"])
setPedMissionActor(ped, enabled)
isPedMissionActor(ped)
```

The ped is first marked as a native GTA mission actor, matching SCM-created
characters and preventing ambient passenger abandonment. It must already occupy the streamed vehicle, its driver seat must be empty
or occupied by that ped, and the calling client must own synchronization for
both elements. Driving styles accept integers `0..6` or the names documented by
the Neon README. The OOP alias is `ped:setDriveWander(...)`.

## Commands and protocol

1. Stand on an open road and run `/nativedrivewander`.
2. Confirm the Greenwood starts driving while Sweet remains visibly in the
   passenger seat and no driver is created or warped in.
3. Wait at least 15 seconds for the green `PASS`, which requires native task
   persistence plus at least four metres of server-observed synchronized movement.
4. Run `/nativedrivewandercancel`; the client must report cancellation without
   crashing or switching Sweet into another vehicle.
5. Run `/nativedrivewandercleanup`.

The task is indefinite, so disappearance before or after the 15-second gate is
a failure rather than completion. Cancellation restores Sweet's previous
mission-actor and AI state.
Gameplay verification remains manual; Codex builds and deploys, then asks the
user to run this protocol.

## Assembly gate

The compact US executable with SHA-256
`72ae59e44c761389e354a50dc6215e964fe771121e2f4b1877273a493ceecc9b` was
checked through the auto-re-agent/Ghidra workflow. Opcode `05D2` dispatches at
`0x490762`, collects ped, vehicle, float speed and driving style, allocates
exactly `0x24` bytes, and calls constructor `0x63CB10`.

The verified layout stores vehicle `+0x0C`, speed `+0x10`, desired model `+0x14`,
style `+0x18`, driver flag `+0x1C`, original autopilot bytes `+0x1D..+0x1F`, and
setup flag `+0x20`. Neon calls the original GTA constructor and lifecycle; it
does not copy the reconstructed implementation. SWEET1 passes speed `20.0` and
style `2` (`avoid_cars`) directly from Sweet's passenger seat after CJ exits.

The same ASM gate locks `CPed::m_nCreatedBy` at `+0x484`. `PED_GAME=1` first
passengers with no driver receive an automatic leave-and-retask sequence after
four seconds; SCM `CREATE_CHAR` instead calls `SetCharCreatedBy` with
`PED_MISSION=2`. The test therefore exercises the public mission-actor policy
and proves Wander remains active beyond that ambient timeout.
