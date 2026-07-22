#!/usr/bin/env python3
"""Static tests for the native FileID capture and stock-only relocation."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
REPOSITORY = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))

from validate_native_file_id_runtime import (  # noqa: E402
    EXPECTED_RELOCATION_COUNTS,
    EXPECTED_STOCK_LAYOUT,
    STOCK_LAYOUT,
    TARGET_LAYOUT,
    PeImage,
    parse_manifest,
    parse_relocation_manifest,
    validate_executable,
    validate_manifest,
    validate_relocation_executable,
    validate_relocation_manifest,
)


class NativeFileIDRuntimeTest(unittest.TestCase):
    @staticmethod
    def parse_native_store_patches() -> list[tuple[int, int, bytes]]:
        source = (REPOSITORY / "Client/game_sa/CFileIDRuntimeSA.cpp").read_text(encoding="utf-8")
        table = source[source.index("const SNativeStorePatch NATIVE_STORE_PATCHES[]"):]
        table = table[: table.index("\n    };")]
        pattern = re.compile(
            r"\{ENativeStorePatchKind::(?:Redirect|Bytes),\s*(0x[0-9A-Fa-f]+),\s*(\d+),.*?,\s*\{([^{}]+)\}",
            re.DOTALL,
        )
        patches: list[tuple[int, int, bytes]] = []
        for match in pattern.finditer(table):
            address, size, expected = match.groups()
            values = bytes(int(value.strip(), 0) for value in expected.split(",") if value.strip())
            patches.append((int(address, 0), int(size), values))
        return patches

    def test_manifests_cover_capture_and_relocation(self) -> None:
        anchors = parse_manifest()
        relocation = parse_relocation_manifest()
        validate_manifest(anchors)
        validate_relocation_manifest(relocation)
        self.assertEqual(10, len(anchors))
        self.assertEqual(EXPECTED_STOCK_LAYOUT, {anchor.kind: anchor.stock_value for anchor in anchors})
        self.assertEqual(EXPECTED_RELOCATION_COUNTS, Counter(patch.kind for patch in relocation))
        self.assertEqual(1_427, len(relocation))
        next_on_cd = [patch for patch in relocation if patch.kind == "RedirectNextOnCd"]
        self.assertEqual(1, len(next_on_cd))
        self.assertEqual(0x0040CD10, next_on_cd[0].address)
        self.assertEqual(b"\x83\xfe\xff\x0f\x84", next_on_cd[0].expected)
        high_movzx = [patch for patch in relocation if patch.address == 0x01567506]
        self.assertEqual(1, len(high_movzx))
        self.assertEqual("Movzx", high_movzx[0].kind)
        high_patches = [patch for patch in relocation if patch.address >= 0x01000000]
        self.assertEqual(
            {"ModelPointer": 28, "StreamingPointer": 51, "Value32": 37, "Movzx": 7},
            dict(Counter(patch.kind for patch in high_patches)),
        )
        self.assertEqual(123, len(high_patches))

    def test_target_layout_matches_current_store_loop_bounds(self) -> None:
        self.assertEqual((31_999, 32_000), (TARGET_LAYOUT["txd"] - 1, TARGET_LAYOUT["txd"]))
        self.assertEqual((39_999, 40_000), (TARGET_LAYOUT["col"] - 1, TARGET_LAYOUT["col"]))
        self.assertEqual((40_511, 40_512), (TARGET_LAYOUT["ipl"] - 1, TARGET_LAYOUT["ipl"]))
        self.assertEqual(8_000, TARGET_LAYOUT["col"] - TARGET_LAYOUT["txd"])
        self.assertEqual(512, TARGET_LAYOUT["ipl"] - TARGET_LAYOUT["col"])
        self.assertEqual(1_024, TARGET_LAYOUT["dat"] - TARGET_LAYOUT["ipl"])
        self.assertEqual(42_341, TARGET_LAYOUT["total"])
        self.assertLessEqual(TARGET_LAYOUT["total"], 0xFFFF)
        self.assertLessEqual(TARGET_LAYOUT["txd"] - 1, 0x7FFF)
        for left, right in (("dat", "ifp"), ("ifp", "rrr"), ("rrr", "scm"), ("scm", "loaded")):
            self.assertEqual(STOCK_LAYOUT[right] - STOCK_LAYOUT[left], TARGET_LAYOUT[right] - TARGET_LAYOUT[left])

        # CStreaming::Update uses these relocated streaming pointers as its
        # CColStore loop bounds while indexing the separate stock pool. Pin the
        # exact relationship that prevents another read past slot 254.
        relocation = {patch.address: patch for patch in parse_relocation_manifest()}
        col_slot_one_status = relocation[0x00410B32]
        ipl_begin_status = relocation[0x00410BE0]
        self.assertEqual("StreamingPointer", col_slot_one_status.kind)
        self.assertEqual("StreamingPointer", ipl_begin_status.kind)
        self.assertEqual((512 - 1) * 20, ipl_begin_status.replacement - col_slot_one_status.replacement)

    def test_named_gta_sa_model_operands_use_sa_ids(self) -> None:
        relocation = {patch.address: patch for patch in parse_relocation_manifest()}
        model_base = EXPECTED_STOCK_LAYOUT["ModelInfoBegin"]
        for address, model_id in ((0x006B2187, 460), (0x006CC3DD, 425)):
            patch = relocation[address]
            self.assertEqual("ModelPointer", patch.kind)
            self.assertEqual(model_base + model_id * 4, patch.expected)
            self.assertEqual(model_id * 4, patch.replacement)

    def test_mta_consumers_have_no_legacy_static_file_id_captures(self) -> None:
        roots = (
            REPOSITORY / "Client/core",
            REPOSITORY / "Client/game_sa",
            REPOSITORY / "Client/mods/deathmatch",
            REPOSITORY / "Client/multiplayer_sa",
        )
        implementation = REPOSITORY / "Client/game_sa/CFileIDRuntimeSA.cpp"
        forbidden = (
            "ARRAY_ModelInfo",
            "CStreaming__ms_aInfoForModel",
            "*(char**)(0x5B8B08 + 6)",
            "0xA9B0C8",
            "0A9B0C8h",
        )
        offenders: list[str] = []
        for root in roots:
            for source in (*root.rglob("*.cpp"), *root.rglob("*.h")):
                if source == implementation:
                    continue
                text = source.read_text(encoding="utf-8", errors="replace")
                for token in forbidden:
                    if token in text:
                        offenders.append(f"{source.relative_to(REPOSITORY)}: {token}")
        self.assertEqual([], offenders)

    def test_extended_col_and_ipl_fields_are_only_used_through_runtime_accessors(self) -> None:
        allowed_declarations = {
            REPOSITORY / "Client/game_sa/CColModelSA.h",
            REPOSITORY / "Client/game_sa/CEntitySA.h",
        }
        offenders: list[str] = []
        for root in (REPOSITORY / "Client/game_sa", REPOSITORY / "Client/multiplayer_sa"):
            for source in (*root.rglob("*.cpp"), *root.rglob("*.h")):
                if source in allowed_declarations:
                    continue
                text = source.read_text(encoding="utf-8", errors="replace")
                for token in ("m_collisionSlot", "m_iplIndex"):
                    if token in text:
                        offenders.append(f"{source.relative_to(REPOSITORY)}: {token}")
        self.assertEqual([], offenders)

    def test_install_is_preflighted_and_process_lifetime(self) -> None:
        source = (REPOSITORY / "Client/game_sa/CFileIDRuntimeSA.cpp").read_text(encoding="utf-8")
        self.assertIn("ValidateRelocationManifest", source)
        self.assertIn("ValidateNativeStorePatches", source)
        self.assertIn("VirtualQuery", source)
        self.assertIn("VirtualAlloc", source)
        self.assertIn("VirtualProtect", source)
        self.assertIn("FlushInstructionCache", source)
        self.assertIn("nativeWrites=no", source)
        self.assertIn("nativeWrites=yes", source)
        self.assertIn("datExpansion=no pathsExpansion=no", source)
        self.assertIn("std::array<BYTE, STOCK_SAVED_FILE_COUNT>", source)
        self.assertIn("STOCK_SAVED_FILE_COUNT = 26316", source)
        self.assertIn("CompareNextModelOnCdUnsigned", source)
        self.assertIn("ForceColAccelCacheMiss", source)
        self.assertIn("HasStoreExtensionOverflow", source)
        self.assertIn("RemoveStaticWorldCarGenerators", source)
        self.assertIn("STOCK_IPL_COUNT = 191", source)
        self.assertIn("info.flg |= savedFlags", source)
        prepare = source.index("std::vector<SPreparedWrite> writes")
        commit = source.index("m_installStarted = true", prepare)
        native_write = source.index("WriteMemory(write.address", commit)
        self.assertLess(prepare, commit)
        self.assertLess(commit, native_write)

    def test_boundary_harness_exercises_full_width_native_lifecycle(self) -> None:
        source = (REPOSITORY / "Client/game_sa/CNativeWorldPackSA.cpp").read_text(encoding="utf-8")
        for token in (
            "MTA_NATIVE_WORLD_STORE_BOUNDARY_TEST",
            "colTargets[] = {255, 256, 511}",
            "iplTargets[] = {255, 256, 1023}",
            "LOAD_COL_BUFFER = 0x4106D0",
            "REMOVE_COL = 0x410730",
            "LOAD_IPL_BUFFER = 0x406080",
            "REMOVE_IPL = 0x404B20",
            "CPtrNodeSingleLinkPoolSA::GetPoolInstance()",
            "ptrNodePool->CaptureTestSnapshot",
            "ptrNodePool->RestoreTestSnapshot",
            "COL-255-canary",
            "IPL did not restrict target COL slot",
            "CFileIDRuntimeSA::GetColModelSlot",
            "CFileIDRuntimeSA::GetEntityIplIndex",
            "candidate->eSpecialModelType == eModelSpecialType::NONE",
            "BeginStoreExtensionTestSnapshot",
            "RestoreStoreExtensionTestSnapshot",
            "ownedPoolRollback=exact streamingRollback=exact",
            "sideTableRollback=exact",
            "rngDraws=3 intentional=yes",
        ):
            self.assertIn(token, source)

        runtime = (REPOSITORY / "Client/game_sa/CFileIDRuntimeSA.cpp").read_text(encoding="utf-8")
        self.assertIn("EXTENDED_BYTE_CAPACITY * sizeof(SExtendedByteEntry)", runtime)
        self.assertIn("g_extendedBytesTestSnapshot = snapshot", runtime)
        self.assertIn("g_extendedBytesTestSnapshot = nullptr", runtime)
        postconditions = source.index("ValidatePostconditions(ide, archiveId)")
        harness = source.index("RunNativeStoreBoundaryHarness(imgPath, ide, error)", postconditions)
        enable_ipls = source.index("EnableOwnedIplDynamicStreaming(ide)", harness)
        self.assertLess(postconditions, harness)
        self.assertLess(harness, enable_ipls)

    def test_native_store_patch_table_is_closed_and_non_overlapping(self) -> None:
        patches = self.parse_native_store_patches()
        self.assertEqual(37, len(patches))
        self.assertIn((0x00404C61, 5, b"\xE9\xDA\xE5\x2E\x00"), patches)
        ranges = sorted((address, address + size) for address, size, _ in patches)
        self.assertTrue(all(size <= len(expected) <= 32 for address, size, expected in patches))
        self.assertTrue(all(right[0] >= left[1] for left, right in zip(ranges, ranges[1:])))

        relocation_ranges = sorted((patch.address, patch.address + patch.size) for patch in parse_relocation_manifest())
        for begin, end in ranges:
            self.assertFalse(any(begin < relocation_end and relocation_begin < end for relocation_begin, relocation_end in relocation_ranges))

    def test_game_startup_orders_shared_instruction_preflights(self) -> None:
        source = (REPOSITORY / "Client/game_sa/CGameSA.cpp").read_text(encoding="utf-8")
        capture = source.index("m_fileIDs.CaptureStockLayout")
        stores = source.index("CNativeModelStoreSA::InstallFromEnvironment", capture)
        relocation = source.index("m_fileIDs.InstallStockRelocation", stores)
        publish = source.index("CModelInfoSAInterface::ms_modelInfoPtrs", relocation)
        self.assertLess(capture, stores)
        self.assertLess(stores, relocation)
        self.assertLess(relocation, publish)

    def test_building_pool_is_allocated_at_checkpoint_capacity_before_gta_initialises_pools(self) -> None:
        source = (REPOSITORY / "Client/game_sa/CGameSA.cpp").read_text(encoding="utf-8")
        resize = source.index("m_Pools->SetPoolCapacity(BUILDING_POOL, MAX_BUILDINGS)")
        hooks = source.index("CEntitySAInterface::StaticSetHooks()", resize)
        self.assertLess(resize, hooks)

        harness = (REPOSITORY / "Client/game_sa/CNativeWorldPackSA.cpp").read_text(encoding="utf-8")
        self.assertIn("boundaryHarness=preflight", harness)
        self.assertIn("buildingCapacity != 32000", harness)

    def test_manifest_is_reproducible_when_local_references_are_available(self) -> None:
        fla_root = Path(
            os.environ.get(
                "FLA_SOURCE_ROOT",
                "/Users/salimtrouve/Documents/GitHub/mta-misc/fastman/source code/fastman92 limit adjuster/"
                "fastman92 limit adjuster/Source files",
            )
        )
        file_id_limit = fla_root / "Modules/FileIDlimit.cpp"
        int32_header = (
            fla_root
            / "Modules/FileIDlimit/GTA SA 1.0 US HOODLUM WIN_X86/GTASA_int32_base_movsx_patches.h"
        )
        executable = Path(
            os.environ.get(
                "MTA_GTA_SA_RUNTIME_EXE",
                str(REPOSITORY / ".tmp/mta-programdata-gta_sa.exe"),
            )
        )
        if not all(path.is_file() for path in (file_id_limit, int32_header, executable)):
            self.skipTest("FLA source or expanded MTA HOODLUM executable is unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            generated = Path(temporary) / "CFileIDRelocationSA.Manifest.inc"
            subprocess.run(
                [
                    sys.executable,
                    str(TOOLS / "extract_file_id_relocation_manifest.py"),
                    str(file_id_limit),
                    str(int32_header),
                    str(executable),
                    str(generated),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            committed = REPOSITORY / "Client/game_sa/CFileIDRelocationSA.Manifest.inc"
            self.assertEqual(committed.read_bytes(), generated.read_bytes())

    def test_local_stock_executable_when_available(self) -> None:
        candidates = (
            Path(os.environ["MTA_GTA_SA_RUNTIME_EXE"]) if "MTA_GTA_SA_RUNTIME_EXE" in os.environ else None,
            REPOSITORY / ".tmp/mta-programdata-gta_sa.exe",
        )
        candidate = next((path for path in candidates if path is not None and path.is_file()), None)
        if candidate is None:
            self.skipTest("expanded MTA HOODLUM executable is unavailable")
        anchors = parse_manifest()
        relocation = parse_relocation_manifest()
        validate_manifest(anchors)
        validate_relocation_manifest(relocation)
        image = PeImage(candidate)
        validate_executable(image, anchors)
        validate_relocation_executable(image, relocation)
        for address, size, expected in self.parse_native_store_patches():
            self.assertEqual(expected[:size], image.read_va(address, size), f"native store patch mismatch at 0x{address:08X}")


if __name__ == "__main__":
    unittest.main()
