/*****************************************************************************
 *
 *  PROJECT:     MTA Neon
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CWorldSectorLimits.cpp
 *  PURPOSE:     Extended GTA SA world-sector installation
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CWorldSectorLimits.h"
#include "CWorldSectorCodeMover.h"

#include <CVector.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

#if 1
namespace
{
    constexpr int WORLD_MAP_SIZE = 20000;
    constexpr int WORLD_SECTOR_SIZE = 50;
    constexpr int WORLD_LOD_SECTOR_SIZE = 200;
    constexpr int WORLD_SECTORS_PER_DIMENSION = WORLD_MAP_SIZE / WORLD_SECTOR_SIZE;
    constexpr int WORLD_LOD_SECTORS_PER_DIMENSION = WORLD_MAP_SIZE / WORLD_LOD_SECTOR_SIZE;
    constexpr int TOTAL_WORLD_SECTORS = WORLD_SECTORS_PER_DIMENSION * WORLD_SECTORS_PER_DIMENSION;
    constexpr int TOTAL_WORLD_LOD_SECTORS = WORLD_LOD_SECTORS_PER_DIMENSION * WORLD_LOD_SECTORS_PER_DIMENSION;
    constexpr int TOTAL_REPEAT_SECTORS = 16 * 16;
    constexpr std::size_t MOVED_CODE_CAPACITY = 150000;
    constexpr bool EXTENDED_WORLD_PATCH_DRY_RUN = false;
    constexpr bool EXTENDED_WORLD_PATCH_DISABLED = false;

    struct SWorldSector
    {
        void* buildingList;
        void* dummyList;
    };

    struct SRepeatSector
    {
        void* vehicleList;
        void* pedList;
        void* objectList;
    };

    static_assert(sizeof(SWorldSector) == 8);
    static_assert(sizeof(SRepeatSector) == 12);

    float g_worldMapMinCoord = -10000.0f;
    float g_worldMapMaxCoord = 10000.0f;
    float g_worldMapMaxCoordMinusOne = 9999.0f;
    float g_worldSectorSize = 50.0f;
    float g_worldSectorSizeHalf = 25.0f;
    float g_worldSectorSizeInversed = 1.0f / 50.0f;
    float g_worldSectorSizeDoubledThenSquared = 10000.0f;
    float g_worldSectorCountHalf = 200.0f;
    float g_worldLodSectorSize = 200.0f;
    float g_worldLodSectorSizeHalf = 100.0f;
    float g_worldLodSectorSizeInversed = 1.0f / 200.0f;
    float g_worldLodSectorSizeTimesSqrtTwoSquared = 80000.0f;
    float g_worldLodSectorCountHalf = 50.0f;
    int   g_worldSectorCountHalfInteger = 200;

    SWorldSector*  g_worldSectors{};
    void**         g_worldLodSectors{};
    std::uint8_t*  g_movedCode{};
    bool           g_extendedWorldSectorsInstalled{};
    bool           g_vanillaWorldSectorsMigrated{};
    SRepeatSector* const g_repeatSectors = reinterpret_cast<SRepeatSector*>(0xB992B8);

    void MigrateVanillaSectorLists()
    {
        constexpr int VANILLA_WORLD_SECTORS_PER_DIMENSION = 120;
        constexpr int VANILLA_LOD_SECTORS_PER_DIMENSION = 30;
        constexpr int worldOffset = (WORLD_SECTORS_PER_DIMENSION - VANILLA_WORLD_SECTORS_PER_DIMENSION) / 2;
        constexpr int lodOffset = (WORLD_LOD_SECTORS_PER_DIMENSION - VANILLA_LOD_SECTORS_PER_DIMENSION) / 2;

        const auto* vanillaWorldSectors = reinterpret_cast<const SWorldSector*>(0xB7D0B8);
        for (int y = 0; y < VANILLA_WORLD_SECTORS_PER_DIMENSION; ++y)
        {
            for (int x = 0; x < VANILLA_WORLD_SECTORS_PER_DIMENSION; ++x)
            {
                SWorldSector& destination = g_worldSectors[(y + worldOffset) * WORLD_SECTORS_PER_DIMENSION + x + worldOffset];
                const SWorldSector& source = vanillaWorldSectors[y * VANILLA_WORLD_SECTORS_PER_DIMENSION + x];
                if (!destination.buildingList)
                    destination.buildingList = source.buildingList;
                if (!destination.dummyList)
                    destination.dummyList = source.dummyList;
            }
        }

        auto* const* vanillaLodSectors = reinterpret_cast<void* const*>(0xB99EB8);
        for (int y = 0; y < VANILLA_LOD_SECTORS_PER_DIMENSION; ++y)
        {
            for (int x = 0; x < VANILLA_LOD_SECTORS_PER_DIMENSION; ++x)
            {
                void*& destination = g_worldLodSectors[(y + lodOffset) * WORLD_LOD_SECTORS_PER_DIMENSION + x + lodOffset];
                if (!destination)
                    destination = vanillaLodSectors[y * VANILLA_LOD_SECTORS_PER_DIMENSION + x];
            }
        }
    }

    SWorldSector* __cdecl GetExtendedWorldSector(int x, int y)
    {
        // SetupScanLists calls GTA's out-of-line CWorld::GetSector helper.
        // Fastman92's address manifest does not cover this function, so leaving
        // it vanilla clamps extended indices to 119 and returns the old grid.
        x = std::clamp(x, 0, WORLD_SECTORS_PER_DIMENSION - 1);
        y = std::clamp(y, 0, WORLD_SECTORS_PER_DIMENSION - 1);
        return &g_worldSectors[y * WORLD_SECTORS_PER_DIMENSION + x];
    }

    void __cdecl LimitCameraCoordinates(CVector& position)
    {
        constexpr float minAllowedCoord = 250.0f;
        const float     maxAllowedCoord = g_worldMapMaxCoord - minAllowedCoord;
        while (position.fX > maxAllowedCoord)
            position.fX -= 1.0f;
        while (position.fX < minAllowedCoord)
            position.fX += 1.0f;
        while (position.fY > maxAllowedCoord)
            position.fY -= 1.0f;
        while (position.fY < minAllowedCoord)
            position.fY += 1.0f;
    }

    __declspec(naked) void PatchCameraEditor()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            push edi
            call LimitCameraCoordinates
            add esp, 4
            mov eax, 0x50F847
            jmp eax
        }
    }

    __declspec(naked) void PatchLosClearStartX()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            mov ecx, ebx
            sub ecx, g_worldSectorCountHalfInteger
            mov [esp + 0x78], ecx
            push 0x56B02C
            retn
        }
    }

    __declspec(naked) void PatchLosClearEndX()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            mov edx, [esp + 0x74]
            sub edx, g_worldSectorCountHalfInteger
            push 0x56B1C7
            retn
        }
    }

    __declspec(naked) void PatchLosClearStartY()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            lea edx, [ebx + 1]
            sub edx, g_worldSectorCountHalfInteger
            mov [esp + 0x78], edx
            push 0x56AA16
            retn
        }
    }

    __declspec(naked) void PatchLosClearEndY()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            mov eax, [esp + 0x74]
            inc eax
            sub eax, g_worldSectorCountHalfInteger
            push 0x56ABA7
            retn
        }
    }

    __declspec(naked) void PatchProcessLosStartX()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            sub ebp, g_worldSectorCountHalfInteger
            mov [esp + 0x34], ebp
            push 0x56C71B
            retn
        }
    }

    __declspec(naked) void PatchProcessLosEndX()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            sub ecx, g_worldSectorCountHalfInteger
            mov [esp + 0x2C], ecx
            push 0x56C92B
            retn
        }
    }

    __declspec(naked) void PatchProcessLosStartY()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            inc ebp
            sub ebp, g_worldSectorCountHalfInteger
            mov [esp + 0x30], ebp
            push 0x56C027
            retn
        }
    }

    __declspec(naked) void PatchProcessLosEndY()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            inc ecx
            sub ecx, g_worldSectorCountHalfInteger
            mov [esp + 0x28], ecx
            push 0x56C21F
            retn
        }
    }

    __declspec(naked) void PatchRendererStart()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            mov esi, [esp + 0x1C]
            mov eax, esi
            sub eax, g_worldSectorCountHalfInteger
            push 0x55484D
            retn
        }
    }

    __declspec(naked) void PatchRendererEnd()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        __asm
        {
            mov edi, [esp + 0x24]
            mov ecx, edi
            sub ecx, g_worldSectorCountHalfInteger
            push 0x55485D
            retn
        }
    }

    enum class EWorldSectorDirectPatchKind : std::uint8_t
    {
        POINTER,
        UINT32,
        FLOAT,
        REDIRECT,
    };

    enum class EWorldSectorPatchValue : std::uint8_t;

    struct SWorldSectorDirectPatchEntry
    {
        std::uintptr_t               address;
        EWorldSectorDirectPatchKind kind;
        EWorldSectorPatchValue      value;
    };

    // The generated enum is stored as uint8_t in the entry to keep this struct
    // independent of its declaration order.
#include "CWorldSectorDirectPatchManifest.inc"

    struct SWorldSectorManifestEntry
    {
        std::uintptr_t     address;
        std::size_t        originalSize;
        const std::uint8_t* bytecode;
        std::size_t        bytecodeSize;
        std::uintptr_t     continueAt;
    };

#include "CWorldSectorManifest.inc"

    struct SDirectPatch
    {
        std::uintptr_t          address;
        std::vector<std::uint8_t> expected;
        std::vector<std::uint8_t> replacement;
    };

    std::uint32_t FloatBits(float value)
    {
        std::uint32_t bits{};
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    }

    std::uint32_t ResolvePatchValue(EWorldSectorPatchValue value)
    {
        switch (value)
        {
            case EWorldSectorPatchValue::VALUE_0: return reinterpret_cast<std::uint32_t>(&g_worldMapMinCoord);
            case EWorldSectorPatchValue::VALUE_1: return reinterpret_cast<std::uint32_t>(&g_worldMapMaxCoord);
            case EWorldSectorPatchValue::VALUE_2: return FloatBits(g_worldMapMinCoord);
            case EWorldSectorPatchValue::VALUE_3: return FloatBits(g_worldMapMaxCoord);
            case EWorldSectorPatchValue::VALUE_4: return FloatBits(g_worldMapMaxCoordMinusOne);
            case EWorldSectorPatchValue::VALUE_5: return reinterpret_cast<std::uint32_t>(g_worldSectors);
            case EWorldSectorPatchValue::VALUE_6: return reinterpret_cast<std::uint32_t>(&g_worldSectors->dummyList);
            case EWorldSectorPatchValue::VALUE_7: return reinterpret_cast<std::uint32_t>(g_worldSectors + TOTAL_WORLD_SECTORS);
            case EWorldSectorPatchValue::VALUE_8: return TOTAL_WORLD_SECTORS;
            case EWorldSectorPatchValue::VALUE_9: return reinterpret_cast<std::uint32_t>(&g_worldSectorSize);
            case EWorldSectorPatchValue::VALUE_10: return reinterpret_cast<std::uint32_t>(&g_worldSectorSizeHalf);
            case EWorldSectorPatchValue::VALUE_11: return reinterpret_cast<std::uint32_t>(&g_worldSectorSizeDoubledThenSquared);
            case EWorldSectorPatchValue::VALUE_12: return reinterpret_cast<std::uint32_t>(&g_worldSectorSizeInversed);
            case EWorldSectorPatchValue::VALUE_13: return reinterpret_cast<std::uint32_t>(&g_worldSectorCountHalf);
            case EWorldSectorPatchValue::VALUE_14: return reinterpret_cast<std::uint32_t>(&PatchLosClearStartX);
            case EWorldSectorPatchValue::VALUE_15: return reinterpret_cast<std::uint32_t>(&PatchLosClearEndX);
            case EWorldSectorPatchValue::VALUE_16: return reinterpret_cast<std::uint32_t>(&PatchLosClearStartY);
            case EWorldSectorPatchValue::VALUE_17: return reinterpret_cast<std::uint32_t>(&PatchLosClearEndY);
            case EWorldSectorPatchValue::VALUE_18: return reinterpret_cast<std::uint32_t>(&PatchProcessLosStartX);
            case EWorldSectorPatchValue::VALUE_19: return reinterpret_cast<std::uint32_t>(&PatchProcessLosEndX);
            case EWorldSectorPatchValue::VALUE_20: return reinterpret_cast<std::uint32_t>(&PatchProcessLosStartY);
            case EWorldSectorPatchValue::VALUE_21: return reinterpret_cast<std::uint32_t>(&PatchProcessLosEndY);
            case EWorldSectorPatchValue::VALUE_22: return reinterpret_cast<std::uint32_t>(&PatchRendererStart);
            case EWorldSectorPatchValue::VALUE_23: return reinterpret_cast<std::uint32_t>(&PatchRendererEnd);
            case EWorldSectorPatchValue::VALUE_24: return WORLD_SECTORS_PER_DIMENSION - 1;
            case EWorldSectorPatchValue::VALUE_25: return WORLD_SECTORS_PER_DIMENSION;
            case EWorldSectorPatchValue::VALUE_26: return FloatBits(g_worldSectorSizeInversed);
            case EWorldSectorPatchValue::VALUE_27: return FloatBits(g_worldSectorCountHalf);
            case EWorldSectorPatchValue::VALUE_28: return reinterpret_cast<std::uint32_t>(g_repeatSectors);
            case EWorldSectorPatchValue::VALUE_29: return reinterpret_cast<std::uint32_t>(&g_repeatSectors->objectList);
            case EWorldSectorPatchValue::VALUE_30: return reinterpret_cast<std::uint32_t>(&g_repeatSectors->pedList);
            case EWorldSectorPatchValue::VALUE_31: return reinterpret_cast<std::uint32_t>(g_repeatSectors + TOTAL_REPEAT_SECTORS);
            case EWorldSectorPatchValue::VALUE_32: return reinterpret_cast<std::uint32_t>(&g_repeatSectors[TOTAL_REPEAT_SECTORS].objectList);
            case EWorldSectorPatchValue::VALUE_33: return TOTAL_REPEAT_SECTORS;
            case EWorldSectorPatchValue::VALUE_34: return reinterpret_cast<std::uint32_t>(g_worldLodSectors);
            case EWorldSectorPatchValue::VALUE_35: return reinterpret_cast<std::uint32_t>(g_worldLodSectors + TOTAL_WORLD_LOD_SECTORS);
            case EWorldSectorPatchValue::VALUE_36: return TOTAL_WORLD_LOD_SECTORS;
            case EWorldSectorPatchValue::VALUE_37: return reinterpret_cast<std::uint32_t>(&g_worldLodSectorSize);
            case EWorldSectorPatchValue::VALUE_38: return reinterpret_cast<std::uint32_t>(&g_worldLodSectorSizeHalf);
            case EWorldSectorPatchValue::VALUE_39: return reinterpret_cast<std::uint32_t>(&g_worldLodSectorSizeTimesSqrtTwoSquared);
            case EWorldSectorPatchValue::VALUE_40: return reinterpret_cast<std::uint32_t>(&g_worldLodSectorCountHalf);
            case EWorldSectorPatchValue::VALUE_41: return reinterpret_cast<std::uint32_t>(&g_worldLodSectorSizeInversed);
            case EWorldSectorPatchValue::VALUE_42: return reinterpret_cast<std::uint32_t>(&PatchCameraEditor);
            case EWorldSectorPatchValue::VALUE_43: return reinterpret_cast<std::uint32_t>(&GetExtendedWorldSector);
        }
        return 0;
    }

    bool ReadMemory(std::uintptr_t address, void* output, std::size_t size)
    {
        MEMORY_BASIC_INFORMATION memory{};
        if (VirtualQuery(reinterpret_cast<const void*>(address), &memory, sizeof(memory)) != sizeof(memory) || memory.State != MEM_COMMIT ||
            (memory.Protect & (PAGE_NOACCESS | PAGE_GUARD)) != 0 || address + size > reinterpret_cast<std::uintptr_t>(memory.BaseAddress) + memory.RegionSize)
        {
            return false;
        }
        std::memcpy(output, reinterpret_cast<const void*>(address), size);
        return true;
    }

    bool WriteMemory(std::uintptr_t address, const void* bytes, std::size_t size)
    {
        DWORD oldProtection{};
        if (!VirtualProtect(reinterpret_cast<void*>(address), size, PAGE_EXECUTE_READWRITE, &oldProtection))
            return false;
        std::memcpy(reinterpret_cast<void*>(address), bytes, size);
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address), size);
        DWORD ignored{};
        return VirtualProtect(reinterpret_cast<void*>(address), size, oldProtection, &ignored) != FALSE;
    }

    bool PrepareDirectPatches(std::vector<SDirectPatch>& patches)
    {
        patches.reserve(std::size(WORLD_SECTOR_DIRECT_PATCHES));
        for (const SWorldSectorDirectPatchEntry& entry : WORLD_SECTOR_DIRECT_PATCHES)
        {
            const auto value = entry.value;
            SDirectPatch patch;
            patch.address = entry.address;
            const std::size_t size = entry.kind == EWorldSectorDirectPatchKind::REDIRECT ? 5 : 4;
            patch.expected.resize(size);
            patch.replacement.resize(size);
            if (!ReadMemory(entry.address, patch.expected.data(), size))
                return false;

            const std::uint32_t resolved = ResolvePatchValue(value);
            if (entry.kind == EWorldSectorDirectPatchKind::REDIRECT)
            {
                patch.replacement[0] = 0xE9;
                const std::int64_t displacement = static_cast<std::int64_t>(resolved) - static_cast<std::int64_t>(entry.address + 5);
                if (displacement < std::numeric_limits<std::int32_t>::min() || displacement > std::numeric_limits<std::int32_t>::max())
                    return false;
                const std::int32_t relative = static_cast<std::int32_t>(displacement);
                std::memcpy(patch.replacement.data() + 1, &relative, sizeof(relative));
            }
            else
            {
                std::memcpy(patch.replacement.data(), &resolved, sizeof(resolved));
            }
            patches.push_back(std::move(patch));
        }
        return true;
    }
}

bool InstallExtendedWorldSectorPatch()
{
    if (EXTENDED_WORLD_PATCH_DISABLED)
        return false;

    if (g_extendedWorldSectorsInstalled)
        return true;

    g_worldSectors = static_cast<SWorldSector*>(VirtualAlloc(nullptr, sizeof(SWorldSector) * TOTAL_WORLD_SECTORS, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    g_worldLodSectors = static_cast<void**>(VirtualAlloc(nullptr, sizeof(void*) * TOTAL_WORLD_LOD_SECTORS, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    g_movedCode = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, MOVED_CODE_CAPACITY, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!g_worldSectors || !g_worldLodSectors || !g_movedCode)
        return false;
    MigrateVanillaSectorLists();

    std::vector<SDirectPatch> directPatches;
    if (!PrepareDirectPatches(directPatches))
        return false;

    CWorldSectorCodeMover mover(reinterpret_cast<std::uintptr_t>(g_movedCode), MOVED_CODE_CAPACITY, ReadMemory);
    mover.SetVariable("NUMBER_OF_WORLD_SECTORS_PER_DIMENSION", WORLD_SECTORS_PER_DIMENSION);
    mover.SetVariable("NUMBER_OF_WORLD_SECTORS_PER_DIMENSION_MINUS_ONE", WORLD_SECTORS_PER_DIMENSION - 1);
    mover.SetVariable("NUMBER_OF_WORLD_LOD_SECTORS_PER_DIMENSION", WORLD_LOD_SECTORS_PER_DIMENSION);
    mover.SetVariable("NUMBER_OF_WORLD_LOD_SECTORS_PER_DIMENSION_MINUS_ONE", WORLD_LOD_SECTORS_PER_DIMENSION - 1);
    mover.SetVariable("SIZE_OF_WORLD_LOD_SECTORS_FOR_ONE_DIMENSION", WORLD_LOD_SECTORS_PER_DIMENSION * sizeof(void*));
    mover.SetVariable("MINUS_NUMBER_OF_WORLD_LOD_SECTORS_PER_DIMENSION_HALF", -WORLD_LOD_SECTORS_PER_DIMENSION / 2);

    for (const SWorldSectorManifestEntry& entry : WORLD_SECTOR_MANIFEST)
    {
        if (!mover.Prepare(entry.address, entry.originalSize, entry.bytecode, entry.bytecodeSize, entry.continueAt))
            return false;
    }

    // Validate every direct patch before the code mover performs its first write.
    for (const SDirectPatch& patch : directPatches)
    {
        std::vector<std::uint8_t> current(patch.expected.size());
        if (!ReadMemory(patch.address, current.data(), current.size()) || current != patch.expected)
            return false;
    }

    if (EXTENDED_WORLD_PATCH_DRY_RUN)
        return false;

    if (!mover.Commit(WriteMemory))
        return false;
    for (const SDirectPatch& patch : directPatches)
    {
        if (!WriteMemory(patch.address, patch.replacement.data(), patch.replacement.size()))
            return false;
    }

    g_extendedWorldSectorsInstalled = true;
    return true;
}

void* GetActiveWorldSectorArray()
{
    return g_extendedWorldSectorsInstalled ? g_worldSectors : reinterpret_cast<void*>(0xB7D0B8);
}

int GetActiveWorldSectorCount()
{
    return g_extendedWorldSectorsInstalled ? TOTAL_WORLD_SECTORS : 120 * 120;
}

int GetActiveWorldSectorDimension()
{
    return g_extendedWorldSectorsInstalled ? WORLD_SECTORS_PER_DIMENSION : 120;
}

void EnsureVanillaWorldSectorsMigrated()
{
    if (g_extendedWorldSectorsInstalled && !g_vanillaWorldSectorsMigrated)
    {
        MigrateVanillaSectorLists();
        g_vanillaWorldSectorsMigrated = true;
    }
}
#else
bool InstallExtendedWorldSectorPatch()
{
    return false;
}

void* GetActiveWorldSectorArray()
{
    return reinterpret_cast<void*>(0xB7D0B8);
}

int GetActiveWorldSectorCount()
{
    return 120 * 120;
}

int GetActiveWorldSectorDimension()
{
    return 120;
}
void EnsureVanillaWorldSectorsMigrated()
{
}
#endif
