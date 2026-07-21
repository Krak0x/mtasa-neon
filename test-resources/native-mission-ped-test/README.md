# Native mission ped simulation test

This resource isolates the first generic native mission-ped checkpoint from
Drive-Thru. It validates GTA decision-maker identity, authoritative simulation,
and one stock event response without implementing that response in Lua.

## Command protocol

1. Run `/nativemissionped`.
2. A violet Voodoo appears with one Ballas passenger and a frozen Grove target.
3. The harness acquires the profile once, disables the ped syncer, observes the
   profile become inactive, then restores the same syncer and requires the same
   token to reactivate without a second acquisition.
4. The Voodoo is set to `249` health. The Ballas must urgently leave, run at
   least eight metres away from it, then resume `TASK_KILL_CHAR_ON_FOOT` and
   damage the Grove target.
5. Wait for the green `PASS`. A Ballas who merely exits and stands still is a
   failure. Immediate combat without the intermediate flee is also a failure.
6. Run `/nativemissionpedcleanup` to restore the player's previous position.

The harness repairs the Voodoo only after the native flee response is observed.
That prevents the later explosion from hiding whether the underlying kill task
resumed. The server independently checks the syncer, passenger exit and target
health before accepting the client verdict.

## Native contract under test

`setPedMissionActor(ped, true)` remains the persistent classification and
weapon-target policy. The harness then acquires the separate
`acquirePedNativeEventProfile(ped, "mission")` lease and requires
`isPedNativeEventProfileActive` before igniting the vehicle.

Only the client currently synchronizing the ped activates the leased native
event profile. The initial adapter selects GTA's default mission decision for
`EVENT_VEHICLE_ON_FIRE` during event admission and presents the MTA-backed
`CPlayerPed` as a non-player only inside that event's `AffectsPed` call. Normal
movement, vehicle entry, combat, allocation, player data and pad processing
retain their ordinary MTA identity. The logical lease survives stream and
syncer generations, while resource stop releases it automatically.

This checkpoint intentionally does not serialize active event tasks across a
syncer migration and does not expose custom SCM decision-maker files yet.

## Validation record

The 2026-07-21 run retained the original token while deliberately removing and
restoring the ped syncer. The client observed the profile inactive off-syncer,
active again for the new authoritative generation, then
`TASK_SIMPLE_CAR_GET_OUT` and the native smart-flee subtree after the Voodoo
reached `249` health. The tester manually cleaned the harness before the Ballas
crossed the eight-metre gate and resumed its underlying kill task, so the final
green `PASS` remains pending. The same build subsequently completed the
integrated Drive-Thru chase without regressing protagonist vehicle entry.

## Reverse evidence

The target is compact GTA SA 1.0 with SHA-256
`72ae59e44c761389e354a50dc6215e964fe771121e2f4b1877273a493ceecc9b`.
`CPed::SetPedDefaultDecisionMaker` at `0x5E06E0` selects `-2` for ped types `0`
and `1`, but selects `-1` for a non-player whose created-by byte at `+0x484` is
`PED_MISSION`. `CPedIntelligence::SetPedDecisionMakerType` at `0x600B50` reads
and writes the normal and group indices at `+0xB4` and `+0xB8`.

`CPed::SetCharCreatedBy` at `0x5E47E0` applies the same decision, sets mission
hearing and seeing ranges to `30`, and zeroes scanner count/radius only for a
non-player. MTA's former wrapper called this setter on a `CPlayerPed`, so it
retained `DM_PLAYER` and the player scanner despite changing the created-by
byte.

`CPlayerPed::ProcessControl` at `0x60EA90` already calls the common
`CPed::ProcessControl`, so native intelligence and event responses advance
without replacing MTA's allocation-specific control loop.
`CEventVehicleOnFire::AffectsPed` at `0x4B4FD0` rejects players before accepting
a living occupant. Event `79` in the stock
`m_norm.ped` decision data selects `TASK_COMPLEX_LEAVE_CAR_AND_FLEE`; the
handler at `0x4BB2E0` constructs immediate leave followed by smart flee from
the vehicle with safe distance `15.0`. Once this priority-54 response ends, the
priority-53 scripted kill task remains available underneath it.

The corresponding gta-reversed-dryxio implementations match these decisive
instructions. No reverse correction or gta-reversed build is required.
