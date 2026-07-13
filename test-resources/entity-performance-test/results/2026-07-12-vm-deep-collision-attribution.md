# 2026-07-12 deep collision attribution and rejected AABB prefilter

This pass followed the earlier entity-level native attribution with counters
inside `CPhysical::ProcessCollision` and its narrow phase. It used the Windows
VM, GTA SA 1.0 US, the Neon `Release|Win32` client, origin
`(-689.37, 957.25, 12.17)`, five-second warm-ups, five-second samples, and
`timingdebug on`. The entities are client-local and the client remained in the
foreground.

Timing mode adds diagnostic overhead. The distributions below are useful for
paired scenario comparisons, while authoritative optimization benchmarks must
also be repeated with timing disabled.

## Instrumentation boundary

The aggregate detail line records, separately for automobiles and player peds:

- collision calls, unique entities, and retries;
- entities still unsafe after attempts one through six;
- collision-step average and maximum;
- normal and shift sector scans plus total shift time;
- broad-phase candidates, sphere tests, and sphere passes;
- `ProcessEntityCollision` calls, time, and returned contacts;
- `CCollision::ProcessColModels` calls and time;
- exact repeated `ProcessColModels` queries in the same world frame.

The verified GTA SA 1.0 US boundaries include `CWorld::Process` at `0x5684A0`,
`CPhysical::ProcessCollision` at `0x54DFB0`, sector-list calls at `0x54DA84`
and `0x54DDA4`, the broad sphere test call at `0x54BBD2`, automobile
`ProcessEntityCollision` at `0x6ACE70`, player-ped `ProcessEntityCollision` at
`0x5E2530`, and `CCollision::ProcessColModels` at `0x4185C0`.

An initial run was discarded for internal `ProcessColModels` attribution:
MTA's existing per-vehicle suspension hook later replaced the automobile call
site at `0x6AD053`, so the new direct timing call was not active there. The fix
routed that existing hook through `EntityPerformanceProcessColModels` instead
of installing a competing call-site hook. A 16-vehicle smoke test then showed
18 `ProcessEntityCollision` and 18 `ProcessColModels` calls in a representative
frame, confirming that automobile attribution was live before the paired runs
below.

## Homogeneous collision profile

All test vehicles used model 411.

| Stage | FPS | avg ms | p95 ms | p99 ms | worst ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline | 100.9 | 9.91 | 11.08 | 11.79 | 13.50 |
| vehicle 64 moving/visible/separate | 47.9 | 20.87 | 22.58 | 25.00 | 26.70 |
| vehicle 64 moving/visible/touching | 16.8 | 59.69 | 66.50 | 74.63 | 74.63 |
| vehicle 16 moving/visible/deep-contact | 7.5 | 133.91 | 151.85 | 152.47 | 152.47 |
| vehicle 16 deep-contact, collision off | 77.1 | 12.97 | 14.85 | 15.88 | 17.24 |
| ped 110 moving/visible/separate | 37.3 | 26.77 | 28.46 | 32.59 | 33.19 |

Representative measured touching frames contained 59 native automobiles,
173-209 collision calls, and 114-150 retries. Eight to fourteen automobiles
remained unsafe after attempt six. `ProcessColModels` ran 1,939-2,598 times and
consumed approximately 28-35 ms per frame.

The steady deep-contact frames contained 23 native automobiles: the 16 test
vehicles plus seven existing world vehicles. They produced 80-88 collision
calls and 57-65 retries. Eleven to thirteen automobiles remained unsafe after
attempt six. `ProcessColModels` ran 1,700-2,008 times, consumed approximately
93-116 ms, and returned roughly 27,700-33,400 contacts per logged frame. Exact
repeated queries were normally zero and never exceeded seven in those steady
samples. The dominant work was therefore real model/contact processing under
changing collision state, not identical whole-function inputs suitable for a
simple result cache.

## Varied collision profile

This profile used the deterministic built-in model cycles.

| Stage | FPS | avg ms | p95 ms | p99 ms | worst ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline | 100.3 | 9.97 | 11.06 | 16.82 | 23.50 |
| vehicle 64 moving/visible/separate | 37.0 | 27.01 | 29.91 | 34.72 | 35.87 |
| vehicle 64 moving/visible/touching | 20.7 | 48.43 | 55.77 | 59.29 | 59.97 |
| vehicle 16 moving/visible/deep-contact | 44.7 | 22.38 | 31.53 | 35.77 | 54.11 |
| vehicle 16 deep-contact, collision off | 71.9 | 13.92 | 16.53 | 17.54 | 18.85 |
| ped 110 moving/visible/separate | 36.0 | 27.77 | 30.21 | 33.79 | 35.51 |

Representative measured touching frames contained 59 native automobiles,
128-163 collision calls, and 69-104 retries. Four to twelve automobiles
remained unsafe after attempt six. `ProcessColModels` ran 1,335-1,914 times and
consumed approximately 16-24 ms per frame.

Unlike the homogeneous stack, the varied deep-contact population separated
during warm-up and measurement. Representative frames fell from 46 collision
calls and 23 retries to 31 calls and eight retries. The unsafe-after-six count
fell from four to zero, while `ProcessColModels` fell from 659 calls and about
13 ms to 135 calls and about 2 ms. This confirms that the pathological
homogeneous result is a persistent collision-geometry state rather than a
count-only cost.

The 110-ped stage produced 119-149 collision calls for 110 test peds,
approximately 953-1,213 `ProcessColModels` calls, and roughly 4-7 ms inside
`ProcessColModels` in representative frames. Collision remains the leading
native ped cost, but its contact volume is much lower than the unresolved
homogeneous vehicle stack.

## Rejected optimization: world-AABB prefilter

The first optimization candidate added a conservative world-space AABB test
before body-collision `ProcessColModels` calls. It excluded calls with line or
suspension outputs, cached transformed bounds, and kept a 0.05-unit boundary
margin. Ambiguous or invalid bounds always fell through to GTA's original
narrow phase. The go/no-go requirement was a useful rejection rate with no
change to contacts or stability.

A five-second homogeneous smoke test used 64 moving, visible, separated
vehicles:

| FPS | avg ms | p95 ms | p99 ms | worst ms |
| ---: | ---: | ---: | ---: | ---: |
| 46.8 | 21.38 | 23.95 | 26.93 | 29.37 |

The client remained stable, but every logged frame reported
`aabb-reject=0`. The active frames contained between 108 and 739
`ProcessColModels` calls, so the prefilter eliminated none of them. The smoke
distribution must not be treated as a precise before/after comparison because
the visible high-water differed from the earlier profile and each row has only
one sample. The zero rejection count is nevertheless decisive: this layer
could not save narrow-phase work and added its own matrix/cache cost.

The candidate failed its go/no-go gate, was removed from the source, and the
rollback DLL was rebuilt successfully. No AABB prefilter remains active.

## Next attribution gate

The next pass should split `ProcessColModels` itself rather than adding another
outer broad-phase test. Required dimensions are body versus suspension calls,
identical versus different model pairs, primitive counts and time for
sphere/box/triangle work, and cost by collision retry ordinal. A retry reduction
must remain a separate higher-risk experiment because it can alter physical
response, safe/stuck transitions, and multiplayer synchronization.
