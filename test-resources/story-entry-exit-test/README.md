# Story entry-exit regression test

This harness exercises the generic story entry-exit runtime without playing a complete mission.

```text
start story-entry-exit-runtime
start story-entry-exit-test
/enextest
```

The command snapshots the player, moves them just outside the Los Santos Binco in dimension `4104` and leases `cschp_ls`. Walk into the exact doorway on foot, observe the one-second fade into area 15, then walk back through the interior doorway and observe the exterior heading. `/enexteststop` releases the lease and restores the snapshot.

Validation should also attempt the exterior trigger from a vehicle, restart either resource during fade-out, black hold and fade-in, and repeat the pair several times. The player must never remain frozen or behind a black camera after cleanup.
