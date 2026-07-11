# Perry Island extended-world test

The current generated resource loads the complete WOSA `novailhb` Perry Island
zone: 286 custom building placements and 1045 stock GTA objects. It includes
terrain, roads, industrial geometry, vegetation, street furniture, textures,
collisions, and LODs. The original placements are translated by
`+8409.370117` on X, placing `perry_land_22` at X=9000 while leaving San Andreas
untouched.

Commands:

- `/perrytest` teleports the player in a vehicle above the slice.
- `/perryback` returns the player to San Andreas.

The test still excludes native IPL loading, water, radar, paths, and population.
Custom assets are copied unchanged from WOSA's `novailha` zone. Regenerate the
complete resource with:

```sh
python3 utils/extended-world/build_perry_slice.py --wosa /path/to/wosa \
    --output test-resources/perry-island-slice --full
```

The generated `assets/`, `meta.xml`, and `slice_data.lua` are intentionally
ignored by Git. They remain local test artifacts so the MTA Neon repository
does not permanently duplicate approximately 22 MB of WOSA DFF/COL/TXD files.
The committed client/server scripts and generator are the reproducible source
of the test resource.
