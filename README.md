# MTA:SA Neon Engine

MTA:SA Neon is an experimental fork of [Multi Theft Auto: San Andreas](https://github.com/multitheftauto/mtasa-blue), focused on prototyping advanced engine features and exploring changes that may be too early or too specialized for the upstream project.

The repository preserves the complete upstream history and adds proof-of-concept work on top of it. Neon is not affiliated with or endorsed by the Multi Theft Auto team.

## MTA:SA vs MTA:SA Neon

Neon keeps MTA:SA's resource model and default gameplay behavior while lifting selected GTA:SA engine limits and exposing new opt-in features to servers. The figures below describe the currently implemented Windows client patches.

| Area | MTA:SA | MTA:SA Neon |
| --- | ---: | ---: |
| GTA corona pool | 64 | 4,096 (4,094 available to scripted MTA coronas) |
| GTA 3D marker pool | 32 | 4,096 |
| GTA checkpoint pool | 32 | 4,096 |
| GTA checkpoint direction arrows | 5 | 4,096 |
| GTA attribute CULL zones | 1,300 | 4,096 |
| GTA tunnel CULL zones | 40 | 256 |
| GTA mirror CULL zones | 72 | 256 |
| Native CULL-zone editing | Not exposed to Lua | Client Lua CRUD with stable IDs, resource-scoped cleanup, and 3D diagnostics |
| Visible entity pointers | 1,000 | 8,192 |
| Visible LOD pointers | 1,000 | 8,192 |
| Streaming RenderWare object instances | 2,500 | 30,000 |
| Main world-sector grid | 120 x 120 | 400 x 400 |
| LOD world-sector grid | 30 x 30 | 100 x 100 |
| Supported extended-world XY | Approximately -3,000 to +3,000 | -10,000 to +9,999 |
| Native minimap tiles | Fixed 12 x 12 stock grid, approximately -3,000 to +3,000 | Sparse 40 x 40 logical grid covering -10,000 to +9,999, with resource-owned TXDs and protected stock tiles |
| MTA pickup visual XY | -4,096 to +4,095.875 | -10,000 to +9,999 |
| Low-precision networked XY | Approximately -8,192 to +8,192 | -10,000 to +10,000 for Neon-capable connections |
| Absolute networked camera range | Approximately -8,192 to +8,192 | Approximately -16,384 to +16,384 for Neon-capable connections |
| Custom-water block grid | 12 x 12 (144 blocks) | 40 x 40 (1,600 blocks) |
| Custom-water XY | Approximately -3,000 to +3,000 | -10,000 to +9,999 |
| Procedural seabed boundary | Unlimited | Server-configurable from 3,000 to 10,000, or unlimited |
| Project2DFX distant static lights | Not integrated | Native, resource-controlled implementation with a 300-5,000 draw-distance range |
| Local ped-skin preview workflow | Build a resource and load the replacement | Experimental drag-and-drop DFF/TXD preview for developers |
| Model-native ped walking styles | No explicit synchronized model-native mode | Server/client Lua opt-in that follows skin changes and ped recreation |
| SA-MP-style fast weapon strafe | Not available as a synchronized glitch | Optional `fastweaponstrafe` glitch, server-synchronized and disabled by default |
| Neon diagnostics and stress tests | Not included | Reproducible resources for coronas, markers, rendering, Project2DFX, extended world, radar, pickups, water, seabed, CULL zones, native mirrors, and dense-entity profiling |
| Extended-world demonstration | Not included | Perry Island slice generator and an in-game test around X=9,000 |

These are capacity increases, not forced visual defaults. Distant lights are disabled by default, ordinary draw distances remain unchanged, and servers or client resources decide when to use the extended features. Legacy network connections retain MTA:SA's original position formats. The CULL relocation and Lua lifecycle have been exercised in game; dedicated tunnel and mirror capacity-boundary tests remain follow-up validation.

Project2DFX support currently covers distant static coronas and timed traffic lights using `SALodLights.dat`. Searchlight cones are recorded for future work; distant cars, static shadows, and the other Project2DFX modules are not included. The drag-and-drop skin preview is an intentionally insecure local development prototype, not a production or competitive-client feature. Technical design, executable address inventories, validation results, and reproducible limit-test resources are documented in [LIMIT_PATCHING.md](./LIMIT_PATCHING.md). Dense-entity profiling methodology and results are documented separately in [ENTITY_PERFORMANCE.md](./ENTITY_PERFORMANCE.md). The extended native minimap design and Lua API are documented in [EXTENDED_RADAR.md](./EXTENDED_RADAR.md).

## Neon Lua API additions

The 21 functions below are the Lua APIs added by Neon since its fork point at `ab2313ddc3fef299e34217465f8a2f3ef1806c6a`. Client functions run in downloaded client resources, server functions run in server resources, and client/server functions are available on both sides. Limit increases that do not introduce a callable Lua function remain documented in the comparison table above.

### Extended native radar

| Function | Side | Description |
| --- | --- | --- |
| `engineSetRadarMapTile(column, row, txd)` | Client | Registers or replaces a resource-owned TXD in one extended 40 x 40 radar cell. Stock San Andreas cells are protected. |
| `engineResetRadarMapTile(column, row)` | Client | Removes a radar tile owned by the calling resource and restores the native ocean fallback for that cell. |
| `engineGetRadarMapStats()` | Client | Returns hook status and registered, loaded, failed, and compressed-source tile statistics. |

Radar tile registrations are resource-scoped: destroying their TXD or stopping the owning resource removes them automatically. See [EXTENDED_RADAR.md](./EXTENDED_RADAR.md) for coordinates, streaming behavior, and current constraints.

### Renderer and distant lights

| Function | Side | Description |
| --- | --- | --- |
| `engineGetRendererStats()` | Client | Returns current usage, session high-water values, and capacities for visible entities, visible LODs, and streaming RenderWare objects. |
| `engineResetRendererStats()` | Client | Resets the renderer high-water measurement window without changing renderer capacities. |
| `engineSetDistantLightsEnabled(enabled)` | Client | Enables or disables Neon's native Project2DFX distant static lights. The feature is disabled by default. |
| `engineSetDistantLightsDrawDistance(distance)` | Client | Sets the distant-light draw distance from 300 to 5,000 world units. |
| `engineRebuildDistantLights()` | Client | Rebuilds the distant-light cache from the currently streamed world. |
| `engineGetDistantLightStats()` | Client | Returns enabled state, definition count, active corona count, corona capacity, and draw distance. |

### Native CULL zones

| Function | Side | Description |
| --- | --- | --- |
| `engineGetCullZones([type])` | Client | Lists adopted native and custom CULL zones, optionally filtered by `attribute`, `tunnel`, or `mirror`. |
| `engineCreateCullZone(type, x, y, z, width, depth, height, flags, ...)` | Client | Creates a resource-owned CULL zone and returns its stable ID; optional arguments cover rotation and mirror-plane data. |
| `engineSetCullZone(id, type, x, y, z, width, depth, height, flags, ...)` | Client | Replaces an owned or claimed zone definition while retaining its stable ID. |
| `engineSetCullZoneEnabled(id, enabled)` | Client | Enables or disables a custom zone or a vanilla zone claimed by the calling resource. |
| `engineRemoveCullZone(id)` | Client | Removes a custom zone or temporarily removes a claimed vanilla zone. |
| `engineRestoreCullZone(id)` | Client | Restores a claimed vanilla zone to its original definition and releases the resource's edit state. |

Custom zones are deleted and edited vanilla zones are restored when their owning resource stops. Coordinates use GTA's signed 16-bit whole-unit representation, so fractional inputs are truncated.

### Marker diagnostics

| Function | Side | Description |
| --- | --- | --- |
| `getMarkerLimitStats()` | Client | Returns streamed-marker usage and limits plus allocated 3D-marker, checkpoint, and direction-arrow capacities. |

### Procedural seabed

| Function | Side | Description |
| --- | --- | --- |
| `setWorldSeaBedOuterBoundary(boundary)` | Server | Sets and synchronizes the square procedural-seabed boundary from 3,000 to 10,000 units; values are rounded up to GTA's 500-unit blocks. |
| `resetWorldSeaBedOuterBoundary()` | Server | Restores GTA's unlimited procedural seabed and synchronizes the reset to clients. |
| `getWorldSeaBedOuterBoundary()` | Server | Returns the applied boundary, or `false` while the seabed is unlimited. |

These functions affect only the rendered procedural seabed. They do not remove the infinite ocean or change water physics.

### Model-native ped walking styles

| Function | Side | Description |
| --- | --- | --- |
| `setPedUseNativeWalkingStyle(ped, enabled)` | Client/server | Makes a ped use the current skin model's native motion group, or disables native selection and restores the default walking style. |
| `isPedUsingNativeWalkingStyle(ped)` | Client/server | Reports whether model-native walking-style selection is enabled for the ped. |

The mode follows skin changes, entity recreation, joins, and streaming. The OOP equivalents are `ped:setUseNativeWalkingStyle(enabled)`, `ped:isUsingNativeWalkingStyle()`, and the `ped.usingNativeWalkingStyle` property.

### Existing API extensions

Neon adds `fastweaponstrafe` as a server-synchronized, disabled-by-default option accepted by the existing `setGlitchEnabled` and `isGlitchEnabled` server functions:

```lua
setGlitchEnabled("fastweaponstrafe", true)
local enabled = isGlitchEnabled("fastweaponstrafe")
```

## Upstream relationship

Neon is built on [Multi Theft Auto: San Andreas](https://github.com/multitheftauto/mtasa-blue) and preserves its complete history and GPLv3 licensing. Neon-specific experiments and builds are maintained independently; use the upstream project for official MTA:SA downloads, documentation, and support.

## Build instructions

### Windows

Prerequisites
- [Visual Studio 2026](https://visualstudio.microsoft.com/vs/) with:
  - Desktop development with C++
  - Optional component *C++ MFC for latest v145 build tools (x86 & x64)* or if that's missing *C++ MFC for x64/x86 (Latest MSVC)*
- [Microsoft DirectX SDK](https://wiki.multitheftauto.com/wiki/Compiling_MTASA#Microsoft_DirectX_SDK)
- [Git for Windows](https://git-scm.com/download/win) (Optional)

1. Execute `win-create-projects.bat`
2. Open `MTASA.sln` in the `Build` directory
3. Compile
4. Execute: `win-install-data.bat`

Visit the wiki article ["Compiling MTASA"](https://wiki.multitheftauto.com/wiki/Compiling_MTASA) for additional information and error troubleshooting.

### GNU/Linux

The MTA:SA server can be built on GNU/Linux for x86, x86_64, armhf, and arm64. ARM configurations are experimental; x86_64 is the primary build environment and can be used to cross-compile the other architectures.

**Build dependencies**

*Please always read the utils/docker/Dockerfile for up-to-date build dependencies.*

- make
- GNU GCC compiler (version 10 or newer)
- libncurses-dev
- libmysqlclient-dev

**Build instructions: Script**

**Note:** This script always deletes `Build/` and `Bin/` directories and does a clean build.

```sh
$ ./linux-build.sh [--arch=x86|x64|arm|arm64] [--config=debug|release] [--cores=<n>]
$ ./linux-install-data.sh  # optional step
```

If build architecture `--arch` is not provided, then it's taken from the environment variable `BUILD_ARCHITECTURE` (defaults to: x64).

If build configuration `--config` is not provided, then it's taken from the environment variable `BUILD_CONFIG` (defaults to: release).

If the number of jobs `--cores` is not provided, then the build will default to the amount of CPU cores.

If you are trying to **cross-compile** to another architecture, then set `AR`, `CC`, `CXX`, `GCC_PREFIX` environment variables accordingly (see `utils/docker/Dockerfile` for an example).

**Build instructions: Manual**

```sh
$ ./utils/premake5 gmake
$ make -C Build/ config=release_x64 all
$ ./linux-install-data.sh  # optional step
```

If you don't want to build the release configuration for the x86_64 architecture, you can instead pick another build configuration from: `{debug|release}_{x86|x64|arm|arm64}`.

#### GNU/Linux: Docker Build Environment

If you have problems resolving the required dependencies or want maximum compatibility, you can use the upstream MTA:SA Docker image, which contains the required build dependencies.

**Pulling the Docker image**

```sh
$ docker pull ghcr.io/multitheftauto/mtasa-blue-build:latest
```

**Building with Docker**

These examples assume that your current directory is the Neon checkout. The image expects the source tree at `/build` inside the container. After compiling, you will find the resulting binaries in `./Bin`. To build the unoptimised debug build, add `--config=debug` to the Docker arguments.

```sh
# x86_64
docker run --rm -v `pwd`:/build ghcr.io/multitheftauto/mtasa-blue-build:latest --arch=x64

# x86
docker run --rm -v `pwd`:/build ghcr.io/multitheftauto/mtasa-blue-build:latest --arch=x86

# arm
docker run --rm -v `pwd`:/build ghcr.io/multitheftauto/mtasa-blue-build:latest --arch=arm

# arm64
docker run --rm -v `pwd`:/build ghcr.io/multitheftauto/mtasa-blue-build:latest --arch=arm64
```

### Premake FAQ

#### How to add new C++ source files?

Execute `win-create-projects.bat`

## License

Unless otherwise specified, all source code hosted on this repository is licensed under the GPLv3 license. See the [LICENSE](./LICENSE) file for more details.

Grand Theft Auto and all related trademarks are © Rockstar North 1997–2026.
