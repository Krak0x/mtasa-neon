# Native ped enter-car test

This resource isolates Neon's existing `setPedEnterVehicle` API for a synchronized server ped. It verifies that the calling syncer observes GTA's `TASK_COMPLEX_ENTER_CAR_AS_PASSENGER`, while the server independently receives `onVehicleEnter` and sees Sweet in MTA passenger seat `1`.

Commands:

- `/nativeenter` creates Sweet and a Greenwood, then requests a natural passenger entry after one second.
- `/nativeentercancel` interrupts the active primary task.
- `/nativeentercleanup` removes the test elements.

The SCM opcode's passenger index `0` maps to MTA seat `1`, because MTA seat `0` is the driver. A pass requires both the client-side native-task observation and the server-side occupant transition; a visual warp or a client-only task is insufficient.
