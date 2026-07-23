# Canonical static-world v3 packs

Static-world v3 is the deterministic multi-IMG transport and admission format
for large native-world payloads. This checkpoint deliberately stops before GTA
registration: an accepted v3 resource is audited and published into the
content-addressed cache with `activation=no` and `lease=no`. It cannot request
a startup ticket, select a native registrar policy, or mutate GTA stores.

That separation proves the expensive byte pipeline and Carcer City corpus
before the later aggregate planner and multi-city registrar introduce
irreversible native mutations.

## Closed transport format

A v3 resource contains one descriptor without a `startup` attribute:

```xml
<native_world format="3"
              policy="static-world-v3"
              manifest="native/native-world.json" />
```

The exact tagged group is:

- `native-world.json`;
- `world.ide`;
- one through 32 contiguous archives named `w000.img`, `w001.img`, and so on.

The manifest has an exact schema and ordered `files.images` array. Every file
name, byte length, and lowercase SHA-256 is bound before publication. The
content ID additionally binds the format, policy, pack ID, IDE identity, and
the ordered name/length/hash tuple of every IMG. Reordering archives therefore
creates a different semantic object.

Each IMG is a standard `VER2` archive capped at 131,072 sectors (256 MiB). The
payload cap is 8 GiB, with all aggregate arithmetic performed as checked
64-bit values. The transport cache retains at most four v3 objects under a
32 GiB cap and requires free space for the new object plus the greater of
512 MiB or 12.5 percent of that object.

Publication uses a private same-volume quarantine. Source files, quarantine
files, and the final object are opened as regular non-reparse files, checked by
length and SHA-256, and constrained to an exact file set. The semantic audit is
repeated inside the locked quarantine before its atomic rename.

## Deterministic native identities

Each pack receives a two-character lowercase namespace. Generated names are:

- models: `<ns>m` plus four base-36 digits;
- TXDs: `<ns>t` plus three base-36 digits;
- spatial COLs: `<ns>c` plus two base-36 digits;
- spatial IPLs: `<ns>i` plus two base-36 digits.

The builder checks GTA's uppercase key for every generated model name and
rejects collisions. Model IDs form one contiguous source-first range. A source
model used by more than one spatial IPL receives a stable primary ID first;
additional spatial variants are appended deterministically. This keeps each
collision record owned by exactly one streamed spatial group.

The runtime transport envelope derives the inventory from IDE and IMG bytes. It
checks the ID/name mapping, cross-IMG uniqueness, DFF/TXD RenderWare roots,
COL3 model mappings, paired spatial ordinals, and every binary IPL instance.
Stock placement IDs are allowed only below the custom range. Custom placement
IDs must exist in the IDE. Coordinates and quaternions are finite and bounded.
Generated models may belong to only one spatial IPL, and a supplied COL record
must belong to the paired IPL ordinal.

This transport envelope does not replace the full DFF/TXD/COL semantic audit
performed by the offline builder. In particular, a cached v3 object is not
directly activable by a future registrar. Activation must repeat the complete
payload grammar, stock-key collision, pool, and native-state preflight under
an activation lease.

Standalone streamed IPLs have no entry in GTA's static IPL entity-index array,
so v3 currently requires `lodIndex = -1`. A non-negative LOD link is rejected
instead of risking an access through static index `-1`. Native LOD linkage
requires a later registrar-owned entity-index bootstrap; the transport format
does not pretend that larger limits solve it.

Models explicitly lacking source collision keep no collision record; no
synthetic geometry is created. Models explicitly lacking a source TXD use one
builder-generated, shared, canonical empty dictionary. Both cases are recorded
in the validation report and are not generalized to arbitrary missing files.

## Conversion and admission boundary

`audit_native_world_v3_admission.py` scans the four local catalogs without
mutating them. `build_native_world_v3.py` applies only closed, reported
conversions:

- the single pinned Vice City RenderWare 3.4 DFF is deserialized and serialized
  through the pinned local librw null backend;
- two pinned malformed Carcer 2DFX extensions are reduced to empty extensions
  because their claimed 12 effects have no bytes before the next clump child;
- all 57 COL2 records are validated, converted to COL3, and revalidated;
- TXD native-texture tuples, mip chains, anisotropy plugins, dimensions, and
  64-bit GPU/decoded budgets are checked;
- case-insensitive TXD duplicates use a deterministic first-wins policy and
  later unreachable entries are removed;
- known extractor defects in timed-object fields are repaired only by exact
  source fingerprint, prefix, source ID, and raw value tuples.

COL admission validates complete record boundaries, counts, offsets, primitive
arrays, face groups, core and shadow indices, finite bounds, flags, and zero
padding before conversion, after conversion, and after model remap. Pack
verification re-reads the emitted DFF/TXD/COL/IPL members rather than trusting
source validation or manifest claims.

No generic "repair malformed data" mode exists. A source or converter identity
change fails closed and requires a reviewed new conversion vector.

## Reproduction

Build the local librw converter:

```sh
clang++ -std=c++17 \
  -I../librw -I../librw/src -DRW_NULL \
  utils/extended-world/librw_dff_upgrade.cpp \
  ../librw/lib/macos-arm64-null/Release/librw.a \
  -o /tmp/librw_dff_upgrade_v3
```

Audit all local source catalogs:

```sh
python3 utils/extended-world/audit_native_world_v3_admission.py \
  --librw-dff-upgrader /tmp/librw_dff_upgrade_v3 \
  --output /tmp/native-world-v3-admission.json
```

Build the Carcer proof into a new empty directory:

```sh
python3 utils/extended-world/build_native_world_v3.py \
  --resource test-resources/carcer-city-test \
  --output /tmp/carcer-v3 \
  --prefix CARCER_CITY \
  --pack-id carcer-city \
  --namespace cc \
  --model-id-start 26099 \
  --librw-dff-upgrader /tmp/librw_dff_upgrade_v3
```

Run the same command into a second empty directory and compare
`native-world.json`, `world.ide`, every IMG, and `validation.json` by SHA-256.
The deterministic proof is valid only when every digest matches.

## Carcer proof envelope

The reviewed Carcer input produces:

- 3,450 source models and 3,493 spatial model variants;
- model IDs 26,099 through 29,591;
- 106 TXDs;
- 12 COL/IPL spatial pairs;
- 12,475 placements, including 56 stock-model placements;
- four IMG archives;
- two pinned malformed-DFF repairs;
- four COL2-to-COL3 conversions;
- 70 removed later TXD duplicates.

The generated payload is approximately 789 MiB. Its first three archives are
exactly 256 MiB and the fourth is 21,321,728 bytes. Two clean builds from the
frozen local inputs produced byte-identical outputs on 2026-07-23:

| File | SHA-256 |
| --- | --- |
| `native-world.json` | `3468a1995adb549144f5f37dc3cd46e7e88040ab84b4df2dc2ce1a4207554b17` |
| `world.ide` | `25581a22aadcc445a8351c7a534713bbc4ec3fefd6f6d23193166085970ffdb5` |
| `w000.img` | `0bfda1c9e27bec8c3269fe3aca449f1b56d454407a50a7e7ff81cdecf923f71a` |
| `w001.img` | `6f089020124fa76b62e0d42731fe7c883ea1994a06268bc0e37b6e0eeaeecd0f` |
| `w002.img` | `a2ac3414b836fcd18297b7f129b3227e7778cb71cbd1e4aa9fd152145b7d6f52` |
| `w003.img` | `25fac738e7888b5e98dda330631f754df6f1a5a3b759ac661b40b7bedc9678c2` |
| `validation.json` | `74b2870c2720fb966a9ce9d85c8ac9dc7e4142f89102abddf35aec9b842c2708` |

The exact hashes are also bound by the generated manifest and must be
reproduced from the current source fingerprints before each deployment.

`test-resources/native-world-v3-transport-test` contains only the tracked
descriptor. Deploy the generated payload separately into its runtime `native`
directory. A successful client gate must report:

- `format=3`, six files for the Carcer proof;
- `audit=static-world-v3-transport-envelope-v1`;
- `publish=atomic`;
- first run `disposition=published`, second run `disposition=hit`;
- `activation=no`, `lease=no`, and no restart request.

The game must remain stock because v3 activation is intentionally unavailable
at this checkpoint. Seeing Carcer in GTA would indicate an architectural
violation, not success.
