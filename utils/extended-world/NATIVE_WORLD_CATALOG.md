# Static native-world catalog

Checkpoint 1 freezes the local source identity and produces a reproducible,
read-only inventory before any global GTA table is moved. It does not build a
native pack, rewrite an asset, patch the executable, or change runtime state.

## Scope

The multi-city capacity target is deliberately limited to static MTA world
content:

- DFF model payloads and the three static object model stores;
- TXD dictionaries and TXD slots;
- COL payloads and collision slots;
- IPL static placements, buildings, LOD links and IPL slots; and
- the IMG archives and streaming records needed to serve those payloads.

The capacity target excludes path nodes, vehicle/ped paths, DAT expansion,
streamed SCM, new IFP/RRR content, missions/savegames and ambient population.
This does not allow a future FileID relocation to delete or reinterpret the
stock DAT/IFP/RRR/SCM partitions: their existing ranges and every stock
reference still have to remain compatible. They receive no additional
multi-city capacity.

Radar, water, CULL/occlusion, audio, timecycle and interiors are optional,
separate follow-ups. They are not included in the checkpoint-1 totals.

## Reproducing the audit

The generated city resources are ignored local inputs. Point the branch
worktree at the canonical repository that contains them:

```sh
python3 utils/extended-world/audit_native_world_catalog.py \
  --repository /Users/salimtrouve/Documents/GitHub/mtasa-neon \
  --verify utils/extended-world/native_world_catalog_baseline.json \
  --output /tmp/native-world-catalog.json
```

`--verify` compares only the compact source identity: map counts, aggregate
asset-tree hashes and source IMG hashes. The detailed output also contains
bounds, largest source IPL/IMG member, serialized IMG field limits, missing
assets and per-file admission results.

The audit reads each referenced file and hashes it. It never opens a source in
write mode. Updating the baseline is an explicit review action after an
intentional source conversion; it must not be used to hide unexplained drift.

## Frozen measurements

The four optional cities add 10,918 custom models, 33,849 placements, 1,324
non-empty referenced TXDs and 121 source IPL groups. Their unique loose static
assets occupy 1,356,226,383 bytes; the eight existing source IMG containers
occupy 1,310,607,360 bytes.

San Andreas remains the stock baseline in the same process; it is not copied
into these extension hashes. Its occupied model-store counts are included
below so the exact requirements are stock SA plus all four optional cities.

Using the audited stock occupied counts, exact model-store requirements become:

| Store | Stock occupied | Additions | Exact required |
| --- | ---: | ---: | ---: |
| Atomic object | 13,984 | 10,355 | 24,339 |
| Damageable object | 69 | 83 | 152 |
| Timed object | 160 | 480 | 640 |

These are measured occupancy requirements, not recommended padded capacities.

The first runtime foundation checkpoint uses capacities `32,000 / 512 / 1,024`.
That leaves `7,661 / 360 / 384` slots after all four measured cities while
keeping allocation below roughly 1.1 MiB across the three stores. This is only
store headroom: the stock 20,000 DFF FileID partition and global streaming
table are deliberately unchanged and continue to reject higher IDs.

## How to read policy rejections

The semantic validator is the current closed Bullworth-v1 precommit profile.
It is intentionally stricter and narrower than GTA's general RenderWare
loader. The catalog therefore labels its results `current_neon_policy` and
sets `engine_limit` to false. In particular, VC/LC RenderWare plugin dialects
are mostly outside that closed grammar; those rejections do not prove that GTA
cannot load the files.

The first inventory establishes concrete conversion/review queues:

- Bullworth has nine DFFs with non-finite semantic UV values and one TXD with
  a case-insensitive duplicate texture. The existing Bullworth builder already
  canonicalizes those exact cases.
- Vice City model `642.dff` uses legacy RenderWare root version `0x1003FFFF`;
  its conversion must be reviewed rather than accepted by increasing a limit.
- Vice City contains 28 COL2 records, Liberty City 25 and Carcer City 4. A
  reviewed native COL2 reader or deterministic offline COL3 conversion is
  required before a closed multi-city admission policy can accept them.
- Carcer contains TXDs outside the current 1024/power-of-two/per-texture
  Bullworth profile, including the 51,322,104-byte `0078.txd` source member.
  Texture format support, upload memory and streaming residency must be
  decided separately; the catalog does not silently rescale textures.
- DFF/COL entries exceeding current geometry/count budgets remain visible as
  policy failures. Their measured maxima must drive the next profile instead
  of simply multiplying every existing constant.

Checkpoint 1 is an offline evidence gate. No in-game behavior or executable is
changed, so it requires no client build and has no meaningful in-game test.
