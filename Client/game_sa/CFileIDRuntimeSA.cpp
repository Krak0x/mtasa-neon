/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CFileIDRuntimeSA.cpp
 *  PURPOSE:     Validated process-lifetime GTA SA FileID relocation
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CFileIDRuntimeSA.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <vector>

namespace
{
    constexpr DWORD EXPECTED_IMAGE_BASE = 0x00400000;
    constexpr DWORD STOCK_STREAMING_INFO_COUNT = 26316;
    constexpr DWORD STOCK_MODEL_INFO_COUNT = 20000;
    constexpr DWORD TARGET_MODEL_INFO_COUNT = 32000;
    constexpr DWORD TARGET_STREAMING_INFO_COUNT = 42341;

    constexpr SFileIDLayout STOCK_LAYOUT = {0, 20000, 25000, 25255, 25511, 25575, 25755, 26230, 26312, 26314, 26316};
    // FileID partition spans are also native loop bounds for the TXD, COL and
    // IPL pools. Keep those spans equal to the currently installed pool sizes;
    // widening the namespace before relocating the pools makes GTA walk past
    // their allocations (CStreaming::Update crashed this way at 0x410B57).
    constexpr SFileIDLayout TARGET_LAYOUT = {0, 32000, 40000, 40512, 41536, 41600, 41780, 42255, 42337, 42339, 42341};

    static_assert(sizeof(SFileIDLayout) == 11 * sizeof(std::uint32_t));
    static_assert(TARGET_LAYOUT.txd - TARGET_LAYOUT.dff == 32000);
    static_assert(TARGET_LAYOUT.col - TARGET_LAYOUT.txd == 8000);
    static_assert(TARGET_LAYOUT.ipl - TARGET_LAYOUT.col == 512);
    static_assert(TARGET_LAYOUT.dat - TARGET_LAYOUT.ipl == 1024);
    static_assert(TARGET_LAYOUT.ifp - TARGET_LAYOUT.dat == 64);
    static_assert(TARGET_LAYOUT.rrr - TARGET_LAYOUT.ifp == 180);
    static_assert(TARGET_LAYOUT.scm - TARGET_LAYOUT.rrr == 475);
    static_assert(TARGET_LAYOUT.loadedList - TARGET_LAYOUT.scm == 82);
    static_assert(TARGET_LAYOUT.total - TARGET_LAYOUT.requestedList == 2);
    static_assert(TARGET_LAYOUT.total <= std::numeric_limits<std::uint16_t>::max());
    static_assert(TARGET_LAYOUT.txd <= static_cast<std::uint32_t>(std::numeric_limits<std::int16_t>::max()) + 1);

    enum class EAnchor
    {
        TxdBase,
        ColBase,
        IplBase,
        DatBase,
        IfpBase,
        RrrBase,
        ScmBase,
        StreamingBegin,
        StreamingEnd,
        ModelInfoBegin,
    };

    struct SAnchor
    {
        EAnchor              kind;
        const char*          name;
        DWORD                instructionAddress;
        BYTE                 operandOffset;
        DWORD                stockValue;
        BYTE                 instructionSize;
        std::array<BYTE, 10> expected;
    };

    constexpr SAnchor ANCHORS[] = {
#define NATIVE_FILE_ID_ANCHOR(kind, address, operand, stock, size, ...) {EAnchor::kind, #kind, address, operand, stock, size, {__VA_ARGS__}},
#include "CFileIDRuntimeSA.Manifest.inc"
#undef NATIVE_FILE_ID_ANCHOR
    };

    enum class ERelocationPatchKind : BYTE
    {
        ModelPointer,
        StreamingPointer,
        Value32,
        Movzx,
        Value16,
        RedirectNextOnCd,
        RedirectSave,
        RedirectLoad,
    };

    struct SRelocationPatch
    {
        ERelocationPatchKind kind;
        DWORD                address;
        DWORD                expected;
        DWORD                replacement;
        std::array<BYTE, 5>  expectedBytes;
    };

    constexpr SRelocationPatch RELOCATION_PATCHES[] = {
#define NATIVE_FILE_ID_POINTER(kind, address, expected, offset) {ERelocationPatchKind::kind##Pointer, address, expected, offset, {}},
#define NATIVE_FILE_ID_VALUE(address, expected, replacement)    {ERelocationPatchKind::Value32, address, expected, replacement, {}},
#define NATIVE_FILE_ID_MOVZX(address)                           {ERelocationPatchKind::Movzx, address, 0x0000BF0F, 0x0000B70F, {}},
#define NATIVE_FILE_ID_UINT16(address, expected, replacement)   {ERelocationPatchKind::Value16, address, expected, replacement, {}},
#define NATIVE_FILE_ID_REDIRECT(kind, address, ...)             {ERelocationPatchKind::Redirect##kind, address, 0, 0, {__VA_ARGS__}},
#include "CFileIDRelocationSA.Manifest.inc"
#undef NATIVE_FILE_ID_POINTER
#undef NATIVE_FILE_ID_VALUE
#undef NATIVE_FILE_ID_MOVZX
#undef NATIVE_FILE_ID_UINT16
#undef NATIVE_FILE_ID_REDIRECT
    };
    static_assert(std::size(RELOCATION_PATCHES) == 1427);

    struct SStockPartition
    {
        DWORD stockBase;
        DWORD targetBase;
        DWORD count;
    };

    constexpr SStockPartition STOCK_PARTITIONS[] = {
        {STOCK_LAYOUT.dff, TARGET_LAYOUT.dff, STOCK_LAYOUT.txd - STOCK_LAYOUT.dff},
        {STOCK_LAYOUT.txd, TARGET_LAYOUT.txd, STOCK_LAYOUT.col - STOCK_LAYOUT.txd},
        {STOCK_LAYOUT.col, TARGET_LAYOUT.col, STOCK_LAYOUT.ipl - STOCK_LAYOUT.col},
        {STOCK_LAYOUT.ipl, TARGET_LAYOUT.ipl, STOCK_LAYOUT.dat - STOCK_LAYOUT.ipl},
        {STOCK_LAYOUT.dat, TARGET_LAYOUT.dat, STOCK_LAYOUT.ifp - STOCK_LAYOUT.dat},
        {STOCK_LAYOUT.ifp, TARGET_LAYOUT.ifp, STOCK_LAYOUT.rrr - STOCK_LAYOUT.ifp},
        {STOCK_LAYOUT.rrr, TARGET_LAYOUT.rrr, STOCK_LAYOUT.scm - STOCK_LAYOUT.rrr},
        {STOCK_LAYOUT.scm, TARGET_LAYOUT.scm, STOCK_LAYOUT.loadedList - STOCK_LAYOUT.scm},
        {STOCK_LAYOUT.loadedList, TARGET_LAYOUT.loadedList, STOCK_LAYOUT.total - STOCK_LAYOUT.loadedList},
    };

    constexpr DWORD STOCK_SAVED_FILE_COUNT = 26316;
    static_assert(STOCK_SAVED_FILE_COUNT == STOCK_LAYOUT.total);

    CStreamingInfo* g_relocatedStreamingInfo{};
    void**          g_relocatedModelInfo{};

    constexpr size_t EXTENDED_BYTE_CAPACITY = 1u << 17;
    constexpr size_t COL_MODEL_SLOT_OFFSET = 0x28;
    constexpr size_t ENTITY_IPL_INDEX_OFFSET = 0x2E;

    struct SExtendedByteEntry
    {
        const void*  key{};
        std::int32_t value{};
    };

    SExtendedByteEntry* g_extendedBytes{};
    SRWLOCK             g_extendedBytesLock = SRWLOCK_INIT;
    volatile LONG       g_extendedBytesOverflow{};
    SExtendedByteEntry* g_extendedBytesTestSnapshot{};
    LONG                g_extendedBytesTestOverflow{};

    size_t HashExtendedByte(const void* key)
    {
        const auto value = reinterpret_cast<uintptr_t>(key);
        return ((value >> 3) * 2654435761u) & (EXTENDED_BYTE_CAPACITY - 1);
    }

    SExtendedByteEntry* FindExtendedByte(const void* key, bool insert)
    {
        SExtendedByteEntry* firstDeleted{};
        size_t              index = HashExtendedByte(key);
        for (size_t probe = 0; probe < EXTENDED_BYTE_CAPACITY; ++probe)
        {
            SExtendedByteEntry& entry = g_extendedBytes[index];
            if (entry.key == key)
                return &entry;
            if (!entry.key)
                return insert ? (firstDeleted ? firstDeleted : &entry) : nullptr;
            if (entry.key == reinterpret_cast<const void*>(1) && !firstDeleted)
                firstDeleted = &entry;
            index = (index + 1) & (EXTENDED_BYTE_CAPACITY - 1);
        }
        return insert ? firstDeleted : nullptr;
    }

    BYTE EncodeLegacyByte(std::int32_t value)
    {
        // Unpatched boolean readers must never see a high valid IPL as zero.
        // 0xFF is also GTA's legacy invalid sentinel, while the side table
        // remains authoritative for every patched equality/indexing reader.
        return value >= 0 && value < 0xFF ? static_cast<BYTE>(value) : 0xFF;
    }

    std::int32_t GetExtendedByte(const void* field)
    {
        if (g_extendedBytes)
        {
            AcquireSRWLockShared(&g_extendedBytesLock);
            const SExtendedByteEntry* entry = FindExtendedByte(field, false);
            const std::int32_t        value = entry ? entry->value : (*static_cast<const BYTE*>(field) == 0xFF ? -1 : *static_cast<const BYTE*>(field));
            ReleaseSRWLockShared(&g_extendedBytesLock);
            return value;
        }
        return *static_cast<const BYTE*>(field) == 0xFF ? -1 : *static_cast<const BYTE*>(field);
    }

    void SetExtendedByte(void* field, std::int32_t value)
    {
        if (!g_extendedBytes)
        {
            *static_cast<BYTE*>(field) = EncodeLegacyByte(value);
            return;
        }

        AcquireSRWLockExclusive(&g_extendedBytesLock);
        SExtendedByteEntry* entry = FindExtendedByte(field, true);
        if (entry)
        {
            entry->key = field;
            entry->value = value;
            // Publish the compatibility byte only after the authoritative
            // full-width entry exists. An exhausted side table must never
            // leave a plausible 0xFF value without matching side storage.
            *static_cast<BYTE*>(field) = EncodeLegacyByte(value);
        }
        else
            InterlockedExchange(&g_extendedBytesOverflow, 1);
        ReleaseSRWLockExclusive(&g_extendedBytesLock);
    }

    void ForgetExtendedByte(const void* field)
    {
        if (!g_extendedBytes)
            return;

        AcquireSRWLockExclusive(&g_extendedBytesLock);
        if (SExtendedByteEntry* entry = FindExtendedByte(field, false))
            entry->key = reinterpret_cast<const void*>(1);
        ReleaseSRWLockExclusive(&g_extendedBytesLock);
    }

    std::int32_t GetColModelSlotInternal(const void* colModel)
    {
        return GetExtendedByte(static_cast<const BYTE*>(colModel) + COL_MODEL_SLOT_OFFSET);
    }

    void SetColModelSlotInternal(void* colModel, std::int32_t slot)
    {
        SetExtendedByte(static_cast<BYTE*>(colModel) + COL_MODEL_SLOT_OFFSET, slot);
    }

    std::int32_t GetEntityIplIndexInternal(const void* entity)
    {
        return GetExtendedByte(static_cast<const BYTE*>(entity) + ENTITY_IPL_INDEX_OFFSET);
    }

    void SetEntityIplIndexInternal(void* entity, std::int32_t index)
    {
        SetExtendedByte(static_cast<BYTE*>(entity) + ENTITY_IPL_INDEX_OFFSET, index);
    }

    void ForgetEntityIplIndexInternal(const void* entity)
    {
        ForgetExtendedByte(static_cast<const BYTE*>(entity) + ENTITY_IPL_INDEX_OFFSET);
    }

    void __cdecl RegisterEntityExtension(void* entity)
    {
        SetEntityIplIndexInternal(entity, 0);
    }

    void __cdecl UnregisterEntityExtension(const void* entity)
    {
        ForgetEntityIplIndexInternal(entity);
    }

    void __cdecl RegisterColModelExtension(void* colModel)
    {
        SetColModelSlotInternal(colModel, 0);
    }

    void __cdecl UnregisterColModelExtension(const void* colModel)
    {
        ForgetExtendedByte(static_cast<const BYTE*>(colModel) + COL_MODEL_SLOT_OFFSET);
    }

    constexpr DWORD CONTINUE_ENTITY_CONSTRUCTOR = 0x00532AAC;
    constexpr DWORD CONTINUE_LOAD_COLLISION_FILE = 0x005B4FC4;
    constexpr DWORD CONTINUE_LOAD_OBJECT_INSTANCE_SLOT = 0x005383DA;
    constexpr DWORD CONTINUE_LOAD_OBJECT_INSTANCE_PUSH = 0x005383ED;
    constexpr DWORD CONTINUE_LOAD_COLLISION_MODEL = 0x00538627;
    constexpr DWORD CONTINUE_LOAD_COLLISION_FIRST_TIME = 0x005B5195;
    constexpr DWORD CONTINUE_CREATE_HIT_COL_MODEL = 0x004C6F4D;
    constexpr DWORD CONTINUE_REMOVE_COL = 0x01564EE4;
    constexpr DWORD CONTINUE_REMOVE_IPL_BUILDINGS = 0x00404B8D;
    constexpr DWORD CONTINUE_REMOVE_IPL_OBJECTS = 0x00404BD7;
    constexpr DWORD CONTINUE_REMOVE_IPL_DUMMIES = 0x00404C3B;
    constexpr DWORD CONTINUE_LOAD_IPL_TEXT = 0x004061FF;
    constexpr DWORD CONTINUE_LOAD_IPL_BINARY = 0x00406305;
    constexpr DWORD CONTINUE_LOAD_IPL_BOUNDS_TEXT = 0x00405E21;
    constexpr DWORD CONTINUE_LOAD_IPL_BOUNDS_BINARY = 0x00405CB0;
    constexpr DWORD CONTINUE_REGISTER_REFERENCE = 0x00571B8A;
    constexpr DWORD CONTINUE_DUMMY_UPDATE = 0x0059EBCF;
    constexpr DWORD CONTINUE_OBJECT_FROM_DUMMY = 0x005A1E7D;
    constexpr DWORD CONTINUE_DUMMY_FROM_OBJECT = 0x0059EA82;

    void __cdecl RemoveStaticWorldCarGenerators(std::int32_t iplSlot)
    {
        // The admitted native-world grammar contains no car generators. GTA's
        // stock cleanup narrows the IPL slot to a byte, so forwarding an
        // extended slot would instead delete generators owned by an aliased
        // stock IPL (256 would target IPL 0). Preserve cleanup for the exact
        // contiguous stock IPL range and make the static-world-owned range
        // inert; the closed payload validator rejects every cargen section.
        constexpr std::int32_t STOCK_IPL_COUNT = 191;
        if (iplSlot >= 0 && iplSlot < STOCK_IPL_COUNT)
            reinterpret_cast<void(__cdecl*)(BYTE)>(0x006F3240)(static_cast<BYTE>(iplSlot));
    }

    void __declspec(naked) ExtendEntityConstructor()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push esi
            call RegisterEntityExtension
            add esp, 4
            mov dword ptr [esi + 1Ch], 08000080h
            jmp CONTINUE_ENTITY_CONSTRUCTOR
        }
        // clang-format on
    }

    void __declspec(naked) ExtendEntityDestructor()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov fs:[0], ecx
            push esi
            call UnregisterEntityExtension
            add esp, 4
            pop esi
            add esp, 10h
            ret
        }
        // clang-format on
    }

    void __declspec(naked) ExtendColModelConstructor()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push esi
            call RegisterColModelExtension
            add esp, 4
            mov eax, esi
            pop esi
            ret
        }
        // clang-format on
    }

    void __declspec(naked) ExtendColModelDestructor()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push esi
            call UnregisterColModelExtension
            add esp, 4
            pop esi
            ret
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadCollisionFile()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov edx, [esp + 48h]
            push edx
            push edi
            call SetColModelSlotInternal
            add esp, 8
            jmp CONTINUE_LOAD_COLLISION_FILE
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadObjectInstanceColSlot()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push eax
            call GetColModelSlotInternal
            add esp, 4
            mov ebx, eax
            test ebx, ebx
            jmp CONTINUE_LOAD_OBJECT_INSTANCE_SLOT
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadObjectInstanceColPush()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push eax
            push ebx
            jmp CONTINUE_LOAD_OBJECT_INSTANCE_PUSH
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadCollisionModel()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov eax, [esp + 50h]
            push eax
            push esi
            call SetColModelSlotInternal
            add esp, 8
            jmp CONTINUE_LOAD_COLLISION_MODEL
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadCollisionFirstTime()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov edx, [esp + 54h]
            push edx
            push esi
            call SetColModelSlotInternal
            add esp, 8
            push 1
            push esi
            mov ecx, edi
            jmp CONTINUE_LOAD_COLLISION_FIRST_TIME
        }
        // clang-format on
    }

    void __declspec(naked) ExtendCreateHitColModel()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push ecx
            push 0
            push esi
            call SetColModelSlotInternal
            add esp, 8
            pop ecx
            pop edi
            jmp CONTINUE_CREATE_HIT_COL_MODEL
        }
        // clang-format on
    }

    void __declspec(naked) ExtendRemoveCol()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push ecx
            push ecx
            call GetColModelSlotInternal
            add esp, 4
            cmp eax, ebx
            pop ecx
            jmp CONTINUE_REMOVE_COL
        }
        // clang-format on
    }

    void __declspec(naked) ExtendRemoveIplBuildings()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            lea eax, [esi + 2Eh]
            push eax
            call GetExtendedByte
            add esp, 4
            mov edx, eax
            cmp edx, [esp + 20h]
            mov eax, [esp + 10h]
            mov ecx, [esp + 14h]
            jmp CONTINUE_REMOVE_IPL_BUILDINGS
        }
        // clang-format on
    }

    void __declspec(naked) ExtendRemoveIplObjects()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            lea eax, [esi + 2Eh]
            push eax
            call GetExtendedByte
            add esp, 4
            mov edx, eax
            cmp edx, [esp + 20h]
            mov eax, [esp + 10h]
            jmp CONTINUE_REMOVE_IPL_OBJECTS
        }
        // clang-format on
    }

    void __declspec(naked) ExtendRemoveIplDummies()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            lea eax, [esi + 2Eh]
            push eax
            call GetExtendedByte
            add esp, 4
            cmp eax, [esp + 20h]
            jmp CONTINUE_REMOVE_IPL_DUMMIES
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadIplText()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov esi, eax
            add esp, 8
            mov edx, [esp + 1Ch]
            push edx
            push esi
            call SetEntityIplIndexInternal
            add esp, 8
            mov eax, [esi + 30h]
            cmp eax, -1
            jmp CONTINUE_LOAD_IPL_TEXT
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadIplBinary()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov esi, eax
            add esp, 4
            push ebx
            push esi
            call SetEntityIplIndexInternal
            add esp, 8
            mov eax, [esi + 30h]
            cmp eax, -1
            jmp CONTINUE_LOAD_IPL_BINARY
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadIplBoundsText()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov esi, eax
            add esp, 4
            mov ecx, [esp + 28h]
            push ecx
            push esi
            call SetEntityIplIndexInternal
            add esp, 8
            mov eax, [esi + 30h]
            cmp eax, -1
            jmp CONTINUE_LOAD_IPL_BOUNDS_TEXT
        }
        // clang-format on
    }

    void __declspec(naked) ExtendLoadIplBoundsBinary()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            mov esi, eax
            add esp, 8
            mov ecx, [esp + 2Ch]
            push ecx
            push esi
            call SetEntityIplIndexInternal
            add esp, 8
            mov eax, [esi + 30h]
            cmp eax, -1
            jmp CONTINUE_LOAD_IPL_BOUNDS_BINARY
        }
        // clang-format on
    }

    void __declspec(naked) ExtendRegisterReference()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push ebp
            call GetEntityIplIndexInternal
            add esp, 4
            test eax, eax
            jmp CONTINUE_REGISTER_REFERENCE
        }
        // clang-format on
    }

    void __declspec(naked) ExtendDummyUpdate()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push edi
            call GetEntityIplIndexInternal
            add esp, 4
            test eax, eax
            jmp CONTINUE_DUMMY_UPDATE
        }
        // clang-format on
    }

    void __declspec(naked) ExtendObjectFromDummy()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push edi
            call GetEntityIplIndexInternal
            add esp, 4
            push eax
            push esi
            call SetEntityIplIndexInternal
            add esp, 8
            jmp CONTINUE_OBJECT_FROM_DUMMY
        }
        // clang-format on
    }

    void __declspec(naked) ExtendDummyFromObject()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            push edi
            call GetEntityIplIndexInternal
            add esp, 4
            push eax
            push eax
            push esi
            call SetEntityIplIndexInternal
            add esp, 8
            pop ecx
            jmp CONTINUE_DUMMY_FROM_OBJECT
        }
        // clang-format on
    }

    constexpr DWORD CONTINUE_COL_ACCEL_START_CACHE = 0x005B31A5;

    void __declspec(naked) ForceColAccelCacheMiss()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            // CINFO.BIN serializes fixed-size IPL/COL arrays. Force the
            // neutral state so an old cache is neither consumed nor rebuilt
            // after those stores have been expanded.
            mov dword ptr ds:[0BC40A0h], 0
            mov eax, dword ptr ds:[0B744A4h]
            jmp CONTINUE_COL_ACCEL_START_CACHE
        }
        // clang-format on
    }

    enum class ENativeStorePatchKind : BYTE
    {
        Redirect,
        Bytes,
    };

    struct SNativeStorePatch
    {
        ENativeStorePatchKind kind;
        DWORD                 address;
        BYTE                  size;
        DWORD                 handler;
        std::array<BYTE, 32>  expected;
        std::array<BYTE, 32>  replacement;
    };

    const SNativeStorePatch NATIVE_STORE_PATCHES[] = {
        {ENativeStorePatchKind::Bytes, 0x0055105F, 4, 0, {0xC8, 0x32, 0x00, 0x00}, {0x00, 0x7D, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x00551107, 4, 0, {0xA6, 0x27, 0x00, 0x00}, {0x30, 0x75, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x00552C3F, 4, 0, {0x90, 0x01, 0x00, 0x00}, {0x00, 0x08, 0x00, 0x00}},

        {ENativeStorePatchKind::Redirect, 0x00532AA5, 7, reinterpret_cast<DWORD>(&ExtendEntityConstructor), {0xC7, 0x46, 0x1C, 0x80, 0x00, 0x00, 0x08}},
        {ENativeStorePatchKind::Redirect,
         0x00535EE6,
         12,
         reinterpret_cast<DWORD>(&ExtendEntityDestructor),
         {0x5E, 0x64, 0x89, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x83, 0xC4, 0x10, 0xC3}},
        // FLA hooks the HOODLUM constructor epilogue, after the legacy byte
        // and flags are initialized, so the wrapper only adds side storage.
        {ENativeStorePatchKind::Redirect, 0x0156C6AA, 5, reinterpret_cast<DWORD>(&ExtendColModelConstructor), {0x8B, 0xC6, 0x5E, 0xC3, 0xEB}},
        {ENativeStorePatchKind::Redirect, 0x0040F73A, 5, reinterpret_cast<DWORD>(&ExtendColModelDestructor), {0x5E, 0xC3, 0x90, 0x90, 0x90}},

        {ENativeStorePatchKind::Redirect, 0x005B4FBD, 7, reinterpret_cast<DWORD>(&ExtendLoadCollisionFile), {0x8A, 0x54, 0x24, 0x48, 0x88, 0x57, 0x28}},
        {ENativeStorePatchKind::Redirect, 0x005383D5, 5, reinterpret_cast<DWORD>(&ExtendLoadObjectInstanceColSlot), {0x8A, 0x58, 0x28, 0x84, 0xDB}},
        {ENativeStorePatchKind::Redirect, 0x005383E8, 5, reinterpret_cast<DWORD>(&ExtendLoadObjectInstanceColPush), {0x0F, 0xB6, 0xCB, 0x50, 0x51}},
        {ENativeStorePatchKind::Bytes, 0x0053851E, 5, 0, {0x0F, 0xB6, 0x44, 0x24, 0x50}, {0x8B, 0x44, 0x24, 0x50, 0x90}},
        {ENativeStorePatchKind::Redirect, 0x00538620, 7, reinterpret_cast<DWORD>(&ExtendLoadCollisionModel), {0x8A, 0x44, 0x24, 0x50, 0x88, 0x46, 0x28}},
        {ENativeStorePatchKind::Bytes, 0x005B50F4, 5, 0, {0x0F, 0xB6, 0x4C, 0x24, 0x54}, {0x8B, 0x4C, 0x24, 0x54, 0x90}},
        {ENativeStorePatchKind::Redirect,
         0x005B5189,
         12,
         reinterpret_cast<DWORD>(&ExtendLoadCollisionFirstTime),
         {0x8A, 0x54, 0x24, 0x54, 0x6A, 0x01, 0x56, 0x8B, 0xCF, 0x88, 0x56, 0x28}},
        {ENativeStorePatchKind::Redirect, 0x004C6F48, 5, reinterpret_cast<DWORD>(&ExtendCreateHitColModel), {0xC6, 0x46, 0x28, 0x00, 0x5F}},
        {ENativeStorePatchKind::Redirect, 0x01564EDE, 6, reinterpret_cast<DWORD>(&ExtendRemoveCol), {0x0F, 0xB6, 0x51, 0x28, 0x3B, 0xD3}},

        {ENativeStorePatchKind::Redirect, 0x00404B85, 8, reinterpret_cast<DWORD>(&ExtendRemoveIplBuildings), {0x0F, 0xB6, 0x56, 0x2E, 0x3B, 0x54, 0x24, 0x20}},
        {ENativeStorePatchKind::Redirect, 0x00404BCF, 8, reinterpret_cast<DWORD>(&ExtendRemoveIplObjects), {0x0F, 0xB6, 0x56, 0x2E, 0x3B, 0x54, 0x24, 0x20}},
        {ENativeStorePatchKind::Redirect, 0x00404C33, 8, reinterpret_cast<DWORD>(&ExtendRemoveIplDummies), {0x0F, 0xB6, 0x46, 0x2E, 0x3B, 0x44, 0x24, 0x20}},
        {ENativeStorePatchKind::Redirect,
         0x004061ED,
         18,
         reinterpret_cast<DWORD>(&ExtendLoadIplText),
         {0x8A, 0x54, 0x24, 0x24, 0x8B, 0xF0, 0x8B, 0x46, 0x30, 0x83, 0xC4, 0x08, 0x83, 0xF8, 0xFF, 0x88, 0x56, 0x2E}},
        {ENativeStorePatchKind::Redirect,
         0x004062F9,
         12,
         reinterpret_cast<DWORD>(&ExtendLoadIplBinary),
         {0x8B, 0x46, 0x30, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0xFF, 0x88, 0x5E, 0x2E}},
        {ENativeStorePatchKind::Redirect,
         0x00405E0F,
         18,
         reinterpret_cast<DWORD>(&ExtendLoadIplBoundsText),
         {0x8A, 0x4C, 0x24, 0x2C, 0x8B, 0xF0, 0x8B, 0x46, 0x30, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0xFF, 0x88, 0x4E, 0x2E}},
        {ENativeStorePatchKind::Redirect,
         0x00405C9E,
         18,
         reinterpret_cast<DWORD>(&ExtendLoadIplBoundsBinary),
         {0x8B, 0xF0, 0x8A, 0x44, 0x24, 0x34, 0x88, 0x46, 0x2E, 0x8B, 0x46, 0x30, 0x83, 0xC4, 0x08, 0x83, 0xF8, 0xFF}},
        {ENativeStorePatchKind::Redirect, 0x00571B85, 5, reinterpret_cast<DWORD>(&ExtendRegisterReference), {0x8A, 0x45, 0x2E, 0x84, 0xC0}},
        {ENativeStorePatchKind::Redirect, 0x0059EBCA, 5, reinterpret_cast<DWORD>(&ExtendDummyUpdate), {0x8A, 0x47, 0x2E, 0x84, 0xC0}},
        {ENativeStorePatchKind::Redirect, 0x005A1E77, 6, reinterpret_cast<DWORD>(&ExtendObjectFromDummy), {0x8A, 0x47, 0x2E, 0x88, 0x46, 0x2E}},
        {ENativeStorePatchKind::Redirect,
         0x0059EA79,
         9,
         reinterpret_cast<DWORD>(&ExtendDummyFromObject),
         {0x8A, 0x4F, 0x2E, 0x0F, 0xB6, 0xC1, 0x88, 0x4E, 0x2E}},
        {ENativeStorePatchKind::Redirect, 0x00404C61, 5, reinterpret_cast<DWORD>(&RemoveStaticWorldCarGenerators), {0xE9, 0xDA, 0xE5, 0x2E, 0x00}},

        // FLA invalidates both accelerator files when their serialized
        // layouts can no longer match. Neon does it without mutating the GTA
        // installation: CINFO is forced to a neutral state, while MINFO's
        // open and write paths are bypassed. MINFO still accumulates one
        // uint16 ID per DFF at runtime, so both the standalone allocator and
        // its inlined copy must cover the complete 32,000-model store even
        // though their disk paths are disabled.
        {ENativeStorePatchKind::Redirect, 0x005B31A0, 5, reinterpret_cast<DWORD>(&ForceColAccelCacheMiss), {0xA1, 0xA4, 0x44, 0xB7, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x004C6AE3, 4, 0, {0x8C, 0xA0, 0x00, 0x00}, {0x00, 0xFA, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x004C6AF6, 4, 0, {0x23, 0x28, 0x00, 0x00}, {0x80, 0x3E, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x004C6B7E, 5, 0, {0xE8, 0x7D, 0x1D, 0x07, 0x00}, {0x33, 0xC0, 0x90, 0x90, 0x90}},
        {ENativeStorePatchKind::Bytes, 0x004C6B8B, 4, 0, {0x8C, 0xA0, 0x00, 0x00}, {0x00, 0xFA, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x004C6B9C, 4, 0, {0x23, 0x28, 0x00, 0x00}, {0x80, 0x3E, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x004C6BB1, 4, 0, {0x8C, 0xA0, 0x00, 0x00}, {0x00, 0xFA, 0x00, 0x00}},
        {ENativeStorePatchKind::Bytes, 0x004C6BD3, 7, 0, {0x8A, 0x46, 0x1B, 0x84, 0xC0, 0x75, 0x2B}, {0xE9, 0x2D, 0x00, 0x00, 0x00, 0x90, 0x90}},
        {ENativeStorePatchKind::Bytes, 0x004C6BF0, 4, 0, {0x8C, 0xA0, 0x00, 0x00}, {0x00, 0xFA, 0x00, 0x00}},
    };

    bool IsReadable(const void* pointer, size_t size)
    {
        if (!pointer || !size)
            return false;

        uintptr_t current = reinterpret_cast<uintptr_t>(pointer);
        if (current > std::numeric_limits<uintptr_t>::max() - size)
            return false;
        const uintptr_t end = current + size;

        while (current < end)
        {
            MEMORY_BASIC_INFORMATION memory{};
            if (VirtualQuery(reinterpret_cast<const void*>(current), &memory, sizeof(memory)) != sizeof(memory) || memory.State != MEM_COMMIT ||
                memory.Protect & (PAGE_GUARD | PAGE_NOACCESS))
                return false;

            const uintptr_t regionEnd = reinterpret_cast<uintptr_t>(memory.BaseAddress) + memory.RegionSize;
            if (regionEnd <= current)
                return false;
            current = regionEnd;
        }
        return true;
    }

    bool IsInImage(DWORD address, size_t size, DWORD imageSize)
    {
        if (address < EXPECTED_IMAGE_BASE || size > imageSize)
            return false;
        return address - EXPECTED_IMAGE_BASE <= imageSize - size;
    }

    bool ReadMemory(DWORD address, void* output, size_t size)
    {
        if (!IsReadable(reinterpret_cast<const void*>(address), size))
            return false;
        std::memcpy(output, reinterpret_cast<const void*>(address), size);
        return true;
    }

    bool WriteMemory(DWORD address, const void* bytes, size_t size)
    {
        DWORD oldProtection{};
        if (!VirtualProtect(reinterpret_cast<void*>(address), size, PAGE_EXECUTE_READWRITE, &oldProtection))
            return false;
        std::memcpy(reinterpret_cast<void*>(address), bytes, size);
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address), size);
        DWORD ignored{};
        return VirtualProtect(reinterpret_cast<void*>(address), size, oldProtection, &ignored) != FALSE;
    }

    DWORD ReadAnchor(EAnchor kind)
    {
        for (const SAnchor& anchor : ANCHORS)
        {
            if (anchor.kind == kind)
                return *reinterpret_cast<const DWORD*>(anchor.instructionAddress + anchor.operandOffset);
        }
        return 0;
    }

    size_t GetPatchSize(ERelocationPatchKind kind)
    {
        switch (kind)
        {
            case ERelocationPatchKind::ModelPointer:
            case ERelocationPatchKind::StreamingPointer:
            case ERelocationPatchKind::Value32:
                return sizeof(DWORD);
            case ERelocationPatchKind::Movzx:
            case ERelocationPatchKind::Value16:
                return sizeof(WORD);
            case ERelocationPatchKind::RedirectSave:
            case ERelocationPatchKind::RedirectLoad:
            case ERelocationPatchKind::RedirectNextOnCd:
                return 5;
        }
        return 0;
    }

    bool ValidateNativeStorePatches(DWORD imageSize, std::string& error)
    {
        struct SRange
        {
            DWORD  begin;
            DWORD  end;
            size_t index;
        };

        std::vector<SRange> ranges;
        ranges.reserve(std::size(NATIVE_STORE_PATCHES));
        for (size_t index = 0; index < std::size(NATIVE_STORE_PATCHES); ++index)
        {
            const SNativeStorePatch& patch = NATIVE_STORE_PATCHES[index];
            if (!patch.size || patch.size > patch.expected.size() || !IsInImage(patch.address, patch.size, imageSize))
            {
                error = SString("native store patch %u has an invalid range", static_cast<unsigned int>(index));
                return false;
            }
            if (patch.kind == ENativeStorePatchKind::Redirect)
            {
                if (patch.size < 5 || !patch.handler)
                {
                    error = SString("native store hook %u has an invalid target or span", static_cast<unsigned int>(index));
                    return false;
                }
                const int64_t displacement = static_cast<int64_t>(patch.handler) - static_cast<int64_t>(patch.address + 5);
                if (displacement < std::numeric_limits<std::int32_t>::min() || displacement > std::numeric_limits<std::int32_t>::max())
                {
                    error = SString("native store hook is out of relative-jump range at 0x%08X", patch.address);
                    return false;
                }
            }

            std::array<BYTE, 32> current{};
            if (!ReadMemory(patch.address, current.data(), patch.size) || !std::equal(current.begin(), current.begin() + patch.size, patch.expected.begin()))
            {
                error = SString("native store patch failed byte validation at 0x%08X", patch.address);
                return false;
            }
            ranges.push_back({patch.address, patch.address + patch.size, index});
        }

        std::sort(ranges.begin(), ranges.end(), [](const SRange& left, const SRange& right) { return left.begin < right.begin; });
        for (size_t index = 1; index < ranges.size(); ++index)
        {
            if (ranges[index].begin < ranges[index - 1].end)
            {
                error = SString("native store patches %u and %u overlap", static_cast<unsigned int>(ranges[index - 1].index),
                                static_cast<unsigned int>(ranges[index].index));
                return false;
            }
        }

        for (const SRange& nativeRange : ranges)
        {
            for (size_t index = 0; index < std::size(RELOCATION_PATCHES); ++index)
            {
                const SRelocationPatch& relocation = RELOCATION_PATCHES[index];
                const DWORD             relocationEnd = relocation.address + static_cast<DWORD>(GetPatchSize(relocation.kind));
                if (nativeRange.begin < relocationEnd && relocation.address < nativeRange.end)
                {
                    error = SString("native store patch %u overlaps FileID relocation patch %u", static_cast<unsigned int>(nativeRange.index),
                                    static_cast<unsigned int>(index));
                    return false;
                }
            }
        }
        return true;
    }

    bool ValidateRelocationManifest(DWORD imageSize, std::string& error)
    {
        struct SRange
        {
            DWORD  begin;
            DWORD  end;
            size_t index;
        };

        std::vector<SRange> ranges;
        ranges.reserve(std::size(RELOCATION_PATCHES));
        for (size_t index = 0; index < std::size(RELOCATION_PATCHES); ++index)
        {
            const SRelocationPatch& patch = RELOCATION_PATCHES[index];
            const size_t            size = GetPatchSize(patch.kind);
            if (!size || !IsInImage(patch.address, size, imageSize))
            {
                error = SString("FileID relocation patch %u is outside the executable image", static_cast<unsigned int>(index));
                return false;
            }

            if (patch.kind == ERelocationPatchKind::ModelPointer && patch.replacement > TARGET_MODEL_INFO_COUNT * sizeof(void*))
            {
                error = SString("FileID model-pointer displacement is invalid at 0x%08X", patch.address);
                return false;
            }
            if (patch.kind == ERelocationPatchKind::StreamingPointer && patch.replacement > (TARGET_STREAMING_INFO_COUNT + 1) * sizeof(CStreamingInfo))
            {
                error = SString("FileID streaming-pointer displacement is invalid at 0x%08X", patch.address);
                return false;
            }

            std::array<BYTE, 5> current{};
            if (!ReadMemory(patch.address, current.data(), size))
            {
                error = SString("FileID relocation patch is unreadable at 0x%08X", patch.address);
                return false;
            }
            if (patch.kind == ERelocationPatchKind::RedirectNextOnCd || patch.kind == ERelocationPatchKind::RedirectSave ||
                patch.kind == ERelocationPatchKind::RedirectLoad)
            {
                if (!std::equal(current.begin(), current.begin() + size, patch.expectedBytes.begin()))
                {
                    error = SString("FileID relocation hook failed byte validation at 0x%08X", patch.address);
                    return false;
                }
            }
            else if (std::memcmp(current.data(), &patch.expected, size) != 0)
            {
                DWORD actual{};
                std::memcpy(&actual, current.data(), size);
                error = SString("FileID relocation operand failed validation at 0x%08X: expected 0x%08X, got 0x%08X", patch.address, patch.expected, actual);
                return false;
            }
            ranges.push_back({patch.address, patch.address + static_cast<DWORD>(size), index});
        }

        std::sort(ranges.begin(), ranges.end(), [](const SRange& left, const SRange& right) { return left.begin < right.begin; });
        for (size_t index = 1; index < ranges.size(); ++index)
        {
            if (ranges[index].begin < ranges[index - 1].end)
            {
                error = SString("FileID relocation patches %u and %u overlap", static_cast<unsigned int>(ranges[index - 1].index),
                                static_cast<unsigned int>(ranges[index].index));
                return false;
            }
        }
        return true;
    }

    using BufferTransfer = bool(__cdecl*)(void*, int);

    constexpr DWORD CONTINUE_NEXT_MODEL_ON_CD = 0x0040CD19;
    constexpr DWORD END_NEXT_MODEL_ON_CD = 0x0040CEF8;

    // GTA compares the sign-extended next IMG ID with -1. Once IDs above
    // 32767 are valid, the load must be unsigned, but 0xFFFF must still end
    // the chain instead of being used as streaming-table index 65535.
    void __declspec(naked) CompareNextModelOnCdUnsigned()
    {
        MTA_VERIFY_HOOK_LOCAL_SIZE;
        // clang-format off
        __asm
        {
            cmp esi, 0FFFFh
            je  endOfChain
            jmp CONTINUE_NEXT_MODEL_ON_CD

        endOfChain:
            jmp END_NEXT_MODEL_ON_CD
        }
        // clang-format on
    }

    bool __cdecl SaveStockStreamingFlags()
    {
        if (!g_relocatedStreamingInfo)
            return false;

        std::array<BYTE, STOCK_SAVED_FILE_COUNT> flags{};
        size_t                                   output = 0;
        for (const SStockPartition& partition : STOCK_PARTITIONS)
        {
            for (DWORD index = 0; index < partition.count; ++index)
            {
                const CStreamingInfo& info = g_relocatedStreamingInfo[partition.targetBase + index];
                flags[output++] = info.loadState == eModelLoadState::LOADSTATE_LOADED ? info.flg : 0xFF;
            }
        }
        return output == flags.size() && reinterpret_cast<BufferTransfer>(0x005D1270)(flags.data(), static_cast<int>(flags.size()));
    }

    bool __cdecl LoadStockStreamingFlags()
    {
        if (!g_relocatedStreamingInfo)
            return false;

        std::array<BYTE, STOCK_SAVED_FILE_COUNT> flags{};
        if (!reinterpret_cast<BufferTransfer>(0x005D1300)(flags.data(), static_cast<int>(flags.size())))
            return false;

        size_t input = 0;
        for (const SStockPartition& partition : STOCK_PARTITIONS)
        {
            for (DWORD index = 0; index < partition.count; ++index)
            {
                CStreamingInfo& info = g_relocatedStreamingInfo[partition.targetBase + index];
                const BYTE      savedFlags = flags[input++];
                if (info.loadState == eModelLoadState::LOADSTATE_LOADED && savedFlags != 0xFF)
                    info.flg |= savedFlags;
            }
        }
        return input == flags.size();
    }

    bool ResolveReplacement(const SRelocationPatch& patch, DWORD& replacement, std::string& error)
    {
        switch (patch.kind)
        {
            case ERelocationPatchKind::ModelPointer:
                replacement = reinterpret_cast<DWORD>(g_relocatedModelInfo) + patch.replacement;
                return true;
            case ERelocationPatchKind::StreamingPointer:
                replacement = reinterpret_cast<DWORD>(g_relocatedStreamingInfo) + patch.replacement;
                return true;
            case ERelocationPatchKind::Value32:
            case ERelocationPatchKind::Movzx:
            case ERelocationPatchKind::Value16:
                replacement = patch.replacement;
                return true;
            case ERelocationPatchKind::RedirectNextOnCd:
            case ERelocationPatchKind::RedirectSave:
            case ERelocationPatchKind::RedirectLoad:
            {
                DWORD target{};
                if (patch.kind == ERelocationPatchKind::RedirectNextOnCd)
                    target = reinterpret_cast<DWORD>(&CompareNextModelOnCdUnsigned);
                else if (patch.kind == ERelocationPatchKind::RedirectSave)
                    target = reinterpret_cast<DWORD>(&SaveStockStreamingFlags);
                else
                    target = reinterpret_cast<DWORD>(&LoadStockStreamingFlags);
                const int64_t displacement = static_cast<int64_t>(target) - static_cast<int64_t>(patch.address + 5);
                if (displacement < std::numeric_limits<std::int32_t>::min() || displacement > std::numeric_limits<std::int32_t>::max())
                {
                    error = SString("FileID relocation hook is out of relative-jump range at 0x%08X", patch.address);
                    return false;
                }
                replacement = static_cast<DWORD>(static_cast<std::int32_t>(displacement));
                return true;
            }
        }
        return false;
    }
}  // namespace

bool CFileIDRuntimeSA::CaptureStockLayout(eGameVersion gameVersion, std::string& error)
{
    if (gameVersion != VERSION_US_10)
    {
        error = "unsupported executable version for FileID runtime anchors";
        return false;
    }

    const HMODULE module = GetModuleHandle(nullptr);
    if (reinterpret_cast<uintptr_t>(module) != EXPECTED_IMAGE_BASE)
    {
        error = "unexpected executable image base for FileID runtime anchors";
        return false;
    }

    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(module);
    if (!IsReadable(dos, sizeof(*dos)) || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x100000)
    {
        error = "invalid executable DOS header for FileID runtime anchors";
        return false;
    }

    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(reinterpret_cast<const BYTE*>(module) + dos->e_lfanew);
    if (!IsReadable(nt, sizeof(*nt)) || nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC)
    {
        error = "invalid executable PE32 header for FileID runtime anchors";
        return false;
    }

    const DWORD imageSize = nt->OptionalHeader.SizeOfImage;
    for (const SAnchor& anchor : ANCHORS)
    {
        const uint64_t end = static_cast<uint64_t>(anchor.instructionAddress) + anchor.instructionSize;
        if (anchor.instructionAddress < EXPECTED_IMAGE_BASE || end > static_cast<uint64_t>(EXPECTED_IMAGE_BASE) + imageSize ||
            anchor.operandOffset + sizeof(DWORD) > anchor.instructionSize ||
            std::memcmp(reinterpret_cast<const void*>(anchor.instructionAddress), anchor.expected.data(), anchor.instructionSize) != 0)
        {
            error = SString("FileID runtime anchor %s failed read-only byte validation at 0x%08X", anchor.name, anchor.instructionAddress);
            return false;
        }

        if (*reinterpret_cast<const DWORD*>(anchor.instructionAddress + anchor.operandOffset) != anchor.stockValue)
        {
            error = SString("FileID runtime anchor %s has an unexpected stock operand", anchor.name);
            return false;
        }
    }

    SFileIDLayout layout{};
    layout.dff = 0;
    layout.txd = ReadAnchor(EAnchor::TxdBase);
    layout.col = ReadAnchor(EAnchor::ColBase);
    layout.ipl = ReadAnchor(EAnchor::IplBase);
    layout.dat = ReadAnchor(EAnchor::DatBase);
    layout.ifp = ReadAnchor(EAnchor::IfpBase);
    layout.rrr = ReadAnchor(EAnchor::RrrBase);
    layout.scm = ReadAnchor(EAnchor::ScmBase);

    const uintptr_t streamingBegin = ReadAnchor(EAnchor::StreamingBegin);
    const uintptr_t streamingEnd = ReadAnchor(EAnchor::StreamingEnd);
    if (streamingEnd <= streamingBegin || (streamingEnd - streamingBegin) % sizeof(CStreamingInfo) != 0)
    {
        error = "FileID streaming table endpoints do not form a whole CStreamingInfo array";
        return false;
    }

    layout.total = static_cast<std::uint32_t>((streamingEnd - streamingBegin) / sizeof(CStreamingInfo));
    if (layout.total != STOCK_STREAMING_INFO_COUNT || layout.total < 4 || layout.scm > layout.total - 4)
    {
        error = "FileID stock streaming table count or sentinel layout is invalid";
        return false;
    }
    layout.loadedList = layout.total - 4;
    layout.requestedList = layout.total - 2;

    if (std::memcmp(&layout, &STOCK_LAYOUT, sizeof(layout)) != 0)
    {
        error = "FileID stock partitions differ from the relocation contract";
        return false;
    }

    auto* streamingInfoArray = reinterpret_cast<CStreamingInfo*>(streamingBegin);
    void* modelInfoArray = reinterpret_cast<void*>(ReadAnchor(EAnchor::ModelInfoBegin));
    if (!IsReadable(streamingInfoArray, static_cast<size_t>(layout.total) * sizeof(CStreamingInfo)) ||
        !IsReadable(modelInfoArray, static_cast<size_t>(layout.txd) * sizeof(void*)))
    {
        error = "FileID runtime arrays are not fully readable";
        return false;
    }
    if (!ValidateRelocationManifest(imageSize, error))
        return false;
    if (!ValidateNativeStorePatches(imageSize, error))
        return false;

    m_layout = layout;
    m_streamingInfoArray = streamingInfoArray;
    m_modelInfoArray = modelInfoArray;
    m_imageSize = imageSize;
    m_relocationPrepared = true;
    SharedUtil::WriteDebugEvent(SString(
        "[NativeFileID] state=prepared layout=stock dff=%u txd=%u col=%u ipl=%u dat=%u ifp=%u rrr=%u scm=%u loaded=%u requested=%u "
        "total=%u streaming=%p models=%p patchSites=%u nativeWrites=no",
        layout.dff, layout.txd, layout.col, layout.ipl, layout.dat, layout.ifp, layout.rrr, layout.scm, layout.loadedList, layout.requestedList, layout.total,
        m_streamingInfoArray, m_modelInfoArray, static_cast<unsigned int>(std::size(RELOCATION_PATCHES) + std::size(NATIVE_STORE_PATCHES))));
    return true;
}

bool CFileIDRuntimeSA::InstallStockRelocation(std::string& error)
{
    if (m_relocationInstalled)
        return true;
    if (!m_relocationPrepared || m_installStarted)
    {
        error = m_installStarted ? "a previous FileID relocation commit did not complete" : "FileID relocation was not prepared";
        return false;
    }
    if (!ValidateRelocationManifest(m_imageSize, error))
        return false;
    if (!ValidateNativeStorePatches(m_imageSize, error))
        return false;

    g_relocatedModelInfo =
        static_cast<void**>(VirtualAlloc(nullptr, static_cast<size_t>(TARGET_MODEL_INFO_COUNT + 1) * sizeof(void*), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    g_relocatedStreamingInfo = static_cast<CStreamingInfo*>(
        VirtualAlloc(nullptr, static_cast<size_t>(TARGET_STREAMING_INFO_COUNT + 1) * sizeof(CStreamingInfo), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    g_extendedBytes =
        static_cast<SExtendedByteEntry*>(VirtualAlloc(nullptr, EXTENDED_BYTE_CAPACITY * sizeof(SExtendedByteEntry), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    InterlockedExchange(&g_extendedBytesOverflow, 0);
    if (!g_relocatedModelInfo || !g_relocatedStreamingInfo || !g_extendedBytes)
    {
        if (g_relocatedModelInfo)
            VirtualFree(g_relocatedModelInfo, 0, MEM_RELEASE);
        if (g_relocatedStreamingInfo)
            VirtualFree(g_relocatedStreamingInfo, 0, MEM_RELEASE);
        if (g_extendedBytes)
            VirtualFree(g_extendedBytes, 0, MEM_RELEASE);
        g_relocatedModelInfo = nullptr;
        g_relocatedStreamingInfo = nullptr;
        g_extendedBytes = nullptr;
        error = "unable to allocate process-lifetime FileID/store-extension tables";
        return false;
    }
    const auto releasePreparedTables = []()
    {
        VirtualFree(g_relocatedModelInfo, 0, MEM_RELEASE);
        VirtualFree(g_relocatedStreamingInfo, 0, MEM_RELEASE);
        VirtualFree(g_extendedBytes, 0, MEM_RELEASE);
        g_relocatedModelInfo = nullptr;
        g_relocatedStreamingInfo = nullptr;
        g_extendedBytes = nullptr;
    };

    std::memcpy(g_relocatedModelInfo, m_modelInfoArray, static_cast<size_t>(STOCK_MODEL_INFO_COUNT) * sizeof(void*));
    for (const SStockPartition& partition : STOCK_PARTITIONS)
    {
        std::memcpy(g_relocatedStreamingInfo + partition.targetBase, m_streamingInfoArray + partition.stockBase,
                    static_cast<size_t>(partition.count) * sizeof(CStreamingInfo));
    }
    std::memcpy(g_relocatedStreamingInfo + TARGET_LAYOUT.loadedList, m_streamingInfoArray + STOCK_LAYOUT.loadedList,
                static_cast<size_t>(4) * sizeof(CStreamingInfo));

    struct SPreparedWrite
    {
        DWORD                address;
        std::array<BYTE, 32> bytes;
        size_t               size;
    };
    std::vector<SPreparedWrite> writes;
    writes.reserve(std::size(RELOCATION_PATCHES) + std::size(NATIVE_STORE_PATCHES));
    for (const SRelocationPatch& patch : RELOCATION_PATCHES)
    {
        DWORD replacement{};
        if (!ResolveReplacement(patch, replacement, error))
        {
            releasePreparedTables();
            return false;
        }

        SPreparedWrite write{};
        write.address = patch.address;
        write.size = GetPatchSize(patch.kind);
        if (patch.kind == ERelocationPatchKind::RedirectNextOnCd || patch.kind == ERelocationPatchKind::RedirectSave ||
            patch.kind == ERelocationPatchKind::RedirectLoad)
        {
            write.bytes[0] = 0xE9;
            std::memcpy(write.bytes.data() + 1, &replacement, sizeof(replacement));
        }
        else
            std::memcpy(write.bytes.data(), &replacement, write.size);
        writes.push_back(write);
    }

    for (const SNativeStorePatch& patch : NATIVE_STORE_PATCHES)
    {
        SPreparedWrite write{};
        write.address = patch.address;
        write.size = patch.size;
        if (patch.kind == ENativeStorePatchKind::Redirect)
        {
            const int64_t displacement64 = static_cast<int64_t>(patch.handler) - static_cast<int64_t>(patch.address + 5);
            if (displacement64 < std::numeric_limits<std::int32_t>::min() || displacement64 > std::numeric_limits<std::int32_t>::max())
            {
                releasePreparedTables();
                error = SString("native store hook is out of relative-jump range at 0x%08X", patch.address);
                return false;
            }
            const std::int32_t displacement = static_cast<std::int32_t>(displacement64);
            std::fill(write.bytes.begin(), write.bytes.begin() + write.size, 0x90);
            write.bytes[0] = 0xE9;
            std::memcpy(write.bytes.data() + 1, &displacement, sizeof(displacement));
        }
        else
            std::copy(patch.replacement.begin(), patch.replacement.begin() + patch.size, write.bytes.begin());
        writes.push_back(write);
    }

    // Recheck every operand after allocation and preparation, directly before
    // the first native write. Startup is single-threaded, but this also catches
    // any earlier installer that changed a shared instruction unexpectedly.
    if (!ValidateRelocationManifest(m_imageSize, error))
    {
        releasePreparedTables();
        return false;
    }
    if (!ValidateNativeStorePatches(m_imageSize, error))
    {
        releasePreparedTables();
        return false;
    }

    // From this point onward any failed native write is fatal to this process;
    // rolling back a partially observed table relocation would be less safe.
    m_installStarted = true;
    for (const SPreparedWrite& write : writes)
    {
        if (!WriteMemory(write.address, write.bytes.data(), write.size))
        {
            error = SString("fatal partial FileID relocation write failure at 0x%08X", write.address);
            return false;
        }
    }

    m_layout = TARGET_LAYOUT;
    m_streamingInfoArray = g_relocatedStreamingInfo;
    m_modelInfoArray = g_relocatedModelInfo;
    m_relocationInstalled = true;
    SharedUtil::WriteDebugEvent(
        SString("[NativeFileID] state=installed layout=stock-only dff=%u txd=%u col=%u ipl=%u dat=%u ifp=%u rrr=%u scm=%u loaded=%u "
                "requested=%u total=%u streaming=%p models=%p patchSites=%u fileIDPatchSites=%u storePatchSites=%u nativeWrites=yes "
                "txdCapacity=8000 colCapacity=512 iplCapacity=1024 buildingCapacity=32000 colModelCapacity=30000 quadTreeNodeCapacity=2048 "
                "extendedCOLIPL=yes cacheAccelerators=disabled datExpansion=no pathsExpansion=no",
                m_layout.dff, m_layout.txd, m_layout.col, m_layout.ipl, m_layout.dat, m_layout.ifp, m_layout.rrr, m_layout.scm, m_layout.loadedList,
                m_layout.requestedList, m_layout.total, m_streamingInfoArray, m_modelInfoArray,
                static_cast<unsigned int>(std::size(RELOCATION_PATCHES) + std::size(NATIVE_STORE_PATCHES)),
                static_cast<unsigned int>(std::size(RELOCATION_PATCHES)), static_cast<unsigned int>(std::size(NATIVE_STORE_PATCHES))));
    return true;
}

std::int32_t CFileIDRuntimeSA::GetColModelSlot(const void* colModel)
{
    return GetColModelSlotInternal(colModel);
}

void CFileIDRuntimeSA::SetColModelSlot(void* colModel, std::int32_t slot)
{
    SetColModelSlotInternal(colModel, slot);
}

std::int32_t CFileIDRuntimeSA::GetEntityIplIndex(const void* entity)
{
    return GetEntityIplIndexInternal(entity);
}

void CFileIDRuntimeSA::SetEntityIplIndex(void* entity, std::int32_t index)
{
    SetEntityIplIndexInternal(entity, index);
}

void CFileIDRuntimeSA::ForgetEntityIplIndex(const void* entity)
{
    ForgetEntityIplIndexInternal(entity);
}

bool CFileIDRuntimeSA::HasStoreExtensionOverflow()
{
    return InterlockedCompareExchange(&g_extendedBytesOverflow, 0, 0) != 0;
}

bool CFileIDRuntimeSA::BeginStoreExtensionTestSnapshot(std::string& error)
{
    if (!g_extendedBytes)
    {
        error = "store-extension table is unavailable for the boundary harness";
        return false;
    }

    auto* snapshot =
        static_cast<SExtendedByteEntry*>(VirtualAlloc(nullptr, EXTENDED_BYTE_CAPACITY * sizeof(SExtendedByteEntry), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (!snapshot)
    {
        error = "unable to allocate the boundary-harness store-extension snapshot";
        return false;
    }

    AcquireSRWLockExclusive(&g_extendedBytesLock);
    if (g_extendedBytesTestSnapshot)
    {
        ReleaseSRWLockExclusive(&g_extendedBytesLock);
        VirtualFree(snapshot, 0, MEM_RELEASE);
        error = "a store-extension boundary-harness snapshot is already active";
        return false;
    }
    std::memcpy(snapshot, g_extendedBytes, EXTENDED_BYTE_CAPACITY * sizeof(SExtendedByteEntry));
    g_extendedBytesTestOverflow = InterlockedCompareExchange(&g_extendedBytesOverflow, 0, 0);
    g_extendedBytesTestSnapshot = snapshot;
    ReleaseSRWLockExclusive(&g_extendedBytesLock);
    return true;
}

bool CFileIDRuntimeSA::RestoreStoreExtensionTestSnapshot(std::string& error)
{
    AcquireSRWLockExclusive(&g_extendedBytesLock);
    SExtendedByteEntry* snapshot = g_extendedBytesTestSnapshot;
    if (!g_extendedBytes || !snapshot)
    {
        ReleaseSRWLockExclusive(&g_extendedBytesLock);
        error = "no store-extension boundary-harness snapshot is active";
        return false;
    }
    std::memcpy(g_extendedBytes, snapshot, EXTENDED_BYTE_CAPACITY * sizeof(SExtendedByteEntry));
    InterlockedExchange(&g_extendedBytesOverflow, g_extendedBytesTestOverflow);
    g_extendedBytesTestSnapshot = nullptr;
    ReleaseSRWLockExclusive(&g_extendedBytesLock);
    VirtualFree(snapshot, 0, MEM_RELEASE);
    return true;
}
