# Native ped leave-car test

This resource isolates GTA's native vehicle-exit task from the Tagging Up Turf
mission state machine.

## API under test

```text
setPedExitVehicle(ped)
```

For a synchronized server ped, this existing client API uses MTA's authoritative
vehicle request/confirmation protocol. Once the server accepts the request, the
current syncer constructs `CTaskComplexLeaveCar`, assigns it to the primary task
slot, and reports the ordinary synchronized vehicle-exit lifecycle. This harness
does not create a second direct-task API because doing so could leave the ped
visually outside while the server still records it as a vehicle occupant.

## Commands

- `/nativeleave` creates a Greenwood near the player, seats Sweet as passenger,
  assigns the player as syncer, and requests the native exit after one second.
- `/nativeleavecancel` removes the primary task during an active test.
- `/nativeleavecleanup` destroys the test ped and vehicle.

A normal run only prints `PASS` after the client has observed
`TASK_COMPLEX_LEAVE_CAR`, the native task has ended outside the vehicle, and the
server has received `onVehicleExit` for the same ped, vehicle, and session.

## Assembly gate

The gate used `/Users/salimtrouve/Documents/GTA-SanAndreas/GTA_SA.EXE`, SHA-256
`72ae59e44c761389e354a50dc6215e964fe771121e2f4b1877273a493ceecc9b`.
Opcode `05CD TASK_LEAVE_CAR` dispatches through `0x490554`, allocates exactly
`0x34` bytes at `0x490574`, and calls the constructor at `0x63B8C0`. Clone
`0x63D9E0` also allocates `0x34`; destructor `0x63B970` accesses and destroys the
`CTaskUtilityLineUpPedWithCar*` stored at offset `+0x1C`.

The old Neon/MTA interface omitted that pointer and described a `0x30` layout,
shifting every trailing field. The corrected interface restores the pointer and
asserts `sizeof(CTaskComplexLeaveCarSAInterface) == 0x34` at compile time.

The candidate `gta-reversed-dryxio` reconstruction also differs in
`ControlSubTask`: the executable preserves `DIE` (`0xD4`), while the reverse
preserves `PAUSE`. Neon does not copy that lifecycle implementation; it invokes
the original GTA constructor and vtable.

Native raw door `0` means automatic door selection. The MTA task factory's
default `0xFF` deliberately reaches that automatic path through its wrapper;
the harness therefore does not force a front-left door for passenger Sweet.

## Manual protocol

1. Start this resource on the local test server.
2. Stand on open, level ground and run `/nativeleave`.
3. Confirm Sweet exits naturally from the passenger side without teleporting.
4. Confirm the chat reports the native task observation, server
   `onVehicleExit`, and exactly one green `PASS`.
5. Run `/nativeleave` again followed quickly by `/nativeleavecancel`; Sweet must
   stop the active primary task and the resource must report `cancelled` once.
6. Run `/nativeleavecleanup` and confirm both spawned elements disappear.

Gameplay testing is intentionally manual; Codex only builds and deploys this
resource, then asks the user to perform this protocol in-game.
