# World sync regression test

This resource reproduces and guards against corruption of version-dependent
position payloads that were serialized into an intermediate bitstream before
being copied into a recipient-versioned packet.

It intentionally tests the four live server RPC paths currently under audit:

- `moveObject`;
- `setColPolygonPointPosition`;
- `addColPolygonPoint` without an index;
- `addColPolygonPoint` with an index.

Each polygon mutation uses a separate polygon so one malformed payload cannot
contaminate the next check. Initial polygon creation is not part of the failure:
it uses the recipient-versioned entity-add path.

## Commands

- `/worldsynctest` creates the test elements near the player and starts one run.
- `/worldsynccleanup` destroys the current run's elements.

Starting a new run automatically cleans up the previous one.

## Manual regression protocol

1. Start this resource on the local custom server.
2. Join with the current Neon client and stand somewhere in ordinary San
   Andreas coordinates.
3. Run `/worldsynctest` once and keep the client open for seven seconds.
4. Copy the four verdict lines from chat or the matching client/server log
   lines.
5. Run `/worldsynccleanup`.

On the affected pre-fix build, `MOVE` is expected to fail with zero or very few
intermediate samples, usually followed by the object snapping to its final
position. `COL SET`, `COL ADD`, and `COL ADD INDEX` are expected to report a
point-count or coordinate mismatch. The exact corrupted values are not used as
the oracle because they are an implementation detail of the malformed payload.

After the protocol fix, all four checks must report `PASS`. Repeat the same
command at X=+9500 via `/ewtest 9500` and at the negative boundary via
`/watertest -9990`.

## Recorded validation

On 2026-07-17 the affected build failed all four checks at ordinary San Andreas
coordinates: polygon coordinates or indices were corrupted and `moveObject`
had no intermediate movement before its final snap. After the semantic packet
fix, all four checks passed in three runs:

- ordinary San Andreas coordinates;
- X=+9500 via `/ewtest 9500`;
- X=-9990 via `/watertest -9990`.

The fixed movement runs reported 35-36 intermediate samples, no regression or
overshoot, and a final error of zero.

Gameplay execution is intentionally manual. Codex may prepare and deploy this
resource, but the user runs the command and reports the in-game verdicts.
