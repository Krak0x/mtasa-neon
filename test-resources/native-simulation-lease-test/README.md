# Native simulation streaming lease test

This resource isolates the first simulation-island checkpoint. It proves that
a resource-owned client lease can keep a native GTA ped and vehicle alive after
their simulation owner moves outside normal MTA streaming distance. It also
proves that persistent ped and vehicle sync ownership is stored per element,
not in one manager-global boolean.

## Commands

1. Run `/nativesimlease` while on foot. Wait for `ACCEPT=true` and confirm both
   lease tokens, both streamed states, and both syncer states are reported.
2. Run `/nativesimfar`. The harness moves only the player to Las Venturas. Do
   not move or issue another command for 15 seconds.
3. A pass requires the ped and vehicle to remain streamed on the owner, both
   server syncers to remain that owner, a valid road-height Z throughout the
   observation, and at least 20 metres of synchronized horizontal native
   vehicle movement while the player is far away. Falling or bouncing can
   never satisfy the distance verdict.
4. Run `/nativesimnear` to return beside the current Voodoo position and
   visually confirm that it did not disappear and recreate. The tested model
   412 Voodoo is violet with plate `VOODOO`; the stationary model 410 Manana
   probe is yellow with plate `MANANA`.
5. Optional lifecycle proof: run `/nativesimfar` again, then
   `/nativesimrelease`. `RELEASE ped=true vehicle=true` and subsequent
   `STREAM OUT attendu` reports are the expected result. This intentionally
   destroys the local GTA task and is not a resume test.
6. Run `/nativesimcleanup` to destroy the harness and restore the original
   player position.

The harness creates a second non-persistent ped and vehicle after assigning the
primary island persistently. Before this checkpoint, those unrelated
assignments reset the manager-global persistence flag and the primary island
lost its syncer after `/nativesimfar`.

## API contract

`acquireElementStreamingLease(element)` returns a non-zero token owned by the
calling client resource. Each token holds one independent streaming reference.
`releaseElementStreamingLease(token)` accepts only a live token owned by the
same resource. Element destruction invalidates the generation-safe target
reference, and resource shutdown releases every surviving token automatically.
The older `setElementStreamable` boolean owns a separate legacy reference and
cannot consume another resource's lease.

This checkpoint preserves an already-running native task. It does not yet
reconstruct a task after owner migration, disconnection, or an intentional
lease release. That work belongs to the task-handoff checkpoint.

## Reverse and SCM boundary

The installed `main.scm` SHA-256 is
`601def3baae766ce6a23e2f0b9b48f6b33c9a64e2fc32eb4f22ddea8b868b0fa`.
SWEET3 contains opcode `0587 SET_LOAD_COLLISION_FOR_CAR_FLAG drive_by_car1
FALSE` at file offset `0x829F5`. The target handler starts at `0x48EBF4`.
Argument `TRUE` clears physical bit `0x4000` at `0x48EC19`; argument `FALSE`
sets it at `0x48EC50`. `setVehicleLoadCollisionFlag(vehicle, loadCollision)`
exposes that exact polarity and persists it across local native vehicle
recreation. It remains independent of MTA's ordinary element collision toggle.

The target executable remains compact GTA SA 1.0 SHA-256
`72ae59e44c761389e354a50dc6215e964fe771121e2f4b1877273a493ceecc9b`.
The audited client path is MTA `CClientPed::StreamOut` to `_DestroyModel`, which
removes the GTA ped from the pool and nulls its task manager. The lease prevents
that MTA lifecycle transition. The related gta-reversed collision audit shows
that physical flag `b15` (target mask `0x4000`) excludes a mission entity from
`CColStore`'s reduced collision requests and lets
`CCarCtrl::SwitchBetweenPhysicsAndGhost` ghost a mission vehicle when collision
is absent. No gta-reversed correction is needed; the new vehicle primitive
writes the audited flag through the existing GTA vehicle interface.
