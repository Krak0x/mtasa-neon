# Native task handoff test

This isolated harness proves that a server-owned native route survives loss of
the machine currently materializing its GTA tasks. It uses the same eight-point
SWEET3 Ballas route as the earlier lease test, but the route descriptor and its
logical progress now live in `native-task-runtime`.

## Test commands

Start both resources in this order:

```text
start native-task-runtime
start native-task-handoff-test
```

Then run:

```text
/nativehandoff
/nativehandofffar
/nativehandoffcycle
/nativehandoffnear
/nativehandoffcleanup
```

1. Wait for `ACTIVE epoch=1` after `/nativehandoff`.
2. Move far away with `/nativehandofffar`; the server logs must keep advancing.
3. Use `/nativehandoffcycle` only while still far away.
4. The old epoch must report native stream-out for both the ped and vehicle.
5. Epoch 2 must become active without a logical-index regression or a position
   discontinuity above 15 metres.
6. Use `/nativehandoffnear` to inspect the current vehicle. A PASS requires at
   least 20 metres of newly server-observed horizontal movement, valid road Z,
   and the same authoritative syncer for ped and vehicle.

The spawned car is a violet model 412 Voodoo with plate `HANDOFF`. Seeing a
different vehicle is ambient traffic, not harness evidence.

Failure signs include a missing half of the stream-out pair, epoch 2 restarting
at route index zero after later progress, a large position jump, invalid Z,
split ped/vehicle ownership, or movement that exists only in client visuals.

## Validation evidence

Manual validation on 21 July 2026 revoked epoch `1` at route index `3` while the
owner was more than three kilometres away. Both elements produced native
stream-out evidence before epoch `2` was assigned. The new epoch resumed at
index `3` with `0.00 m` discontinuity and synchronized another `22.2 m` at
Z `13.21`; cleanup later observed index `5`. No Lua error, resource failure or
client crash was recorded.
