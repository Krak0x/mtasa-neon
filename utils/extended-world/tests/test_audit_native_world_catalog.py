#!/usr/bin/env python3
"""Tests for the read-only static multi-city catalog."""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from audit_native_world_catalog import (  # noqa: E402
    EXCLUDED_COMPONENTS,
    STATIC_COMPONENTS,
    _asset_fingerprint,
    audit_col,
    audit_img,
    audit_rw,
    baseline_projection,
    parse_generated_map,
)


MAP_FIXTURE = """-- Generated fixture.
FIXTURE_STATS = { placements = 2, models = 2, customModels = 1, nativeModels = 1 }
FIXTURE_MODELS = {
    [100] = { name = "fixture", modelType = "object", txd = false, dff = "assets/models/100.dff", col = "assets/collisions/100.col", lodDistance = 100, ideFlags = 0 },
}
FIXTURE_PLACEMENTS = {
    { model = 100, native = false, x = -2, y = 3, z = 4, qx = 0, qy = 0, qz = 0, qw = 1, lod = false, isLod = false, source = "a.ipl", sourceIndex = 0 },
    { model = 615, native = true, x = 8, y = -5, z = 6, qx = 0, qy = 0, qz = 0, qw = 1, lod = false, isLod = false, source = "b.ipl", sourceIndex = 0 },
}
"""


class GeneratedMapInventoryTest(unittest.TestCase):
    def test_parser_keeps_only_static_custom_assets_and_counts_native_placements(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-world-audit-") as temporary:
            path = Path(temporary) / "map_data.lua"
            path.write_text(MAP_FIXTURE, encoding="utf-8")
            result = parse_generated_map(path, "FIXTURE")

        self.assertEqual(1, result["models_custom"])
        self.assertEqual(1, result["models_native"])
        self.assertEqual(2, result["placements"])
        self.assertEqual(1, result["placements_native"])
        self.assertEqual(2, result["source_ipls"])
        self.assertEqual({"x": [-2.0, 8.0], "y": [-5.0, 3.0], "z": [4.0, 6.0]}, result["bounds"])
        self.assertEqual([], result["assets"]["txd"])
        self.assertEqual(["assets/models/100.dff"], result["assets"]["dff"])

    def test_scope_excludes_runtime_gameplay_data(self) -> None:
        self.assertEqual(("dff", "txd", "col", "ipl"), STATIC_COMPONENTS)
        self.assertIn("path-nodes", EXCLUDED_COMPONENTS)
        self.assertIn("streamed-scm", EXCLUDED_COMPONENTS)
        self.assertIn("dat-expansion", EXCLUDED_COMPONENTS)


class FingerprintTest(unittest.TestCase):
    def test_fingerprint_is_order_independent_and_reports_missing_assets(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-world-fingerprint-") as temporary:
            root = Path(temporary)
            (root / "a.bin").write_bytes(b"a")
            (root / "b.bin").write_bytes(b"bb")
            first = _asset_fingerprint(root, ["b.bin", "a.bin", "missing.bin"])
            second = _asset_fingerprint(root, ["a.bin", "b.bin", "missing.bin"])
        self.assertEqual(first, second)
        self.assertEqual((2, 3, ["missing.bin"]), first[1:])

    def test_baseline_omits_diagnostics_but_keeps_source_identity(self) -> None:
        catalog = {
            "schema": 1,
            "scope": {"core": ["dff"]},
            "aggregate": {"placements": 1},
            "cities": [
                {
                    "pack_id": "fixture",
                    "map": {
                        "models_custom": 1,
                        "models_native": 0,
                        "placements": 1,
                        "placements_native": 0,
                        "source_ipls": 1,
                        "model_types": {"object": 1},
                    },
                    "fingerprints": {"dff": {"sha256": "abc"}},
                    "img": [
                        {
                            "path": "fixture.img",
                            "sha256": "def",
                            "bytes": 2048,
                            "sectors": 1,
                            "entries": 1,
                            "extensions": {"dff": 1},
                            "largest_member": {"name": "ignored"},
                        }
                    ],
                    "dff": {"current_neon_policy": {"rejected": {"count": 1}}},
                }
            ],
        }
        baseline = baseline_projection(catalog)
        self.assertNotIn("dff", baseline["cities"][0])
        self.assertNotIn("largest_member", baseline["cities"][0]["img"][0])
        self.assertEqual("abc", baseline["cities"][0]["fingerprints"]["dff"]["sha256"])


class PolicyClassificationTest(unittest.TestCase):
    def test_col2_is_inventory_data_not_a_false_engine_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-world-col2-") as temporary:
            root = Path(temporary)
            relative = "fixture.col"
            (root / relative).write_bytes(struct.pack("<4sI", b"COL2", 24) + b"\0" * 24)
            result = audit_col(root, [relative])
        self.assertEqual({"COL2": 1}, result["magics"])
        rejection = result["current_neon_policy"]["rejected"]
        self.assertEqual(1, rejection["count"])
        self.assertEqual({"canonicalization-required": 1}, rejection["by_bucket"])

    def test_invalid_rw_is_classified_without_rewriting_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-world-rw-") as temporary:
            root = Path(temporary)
            relative = "fixture.dff"
            source = b"not a renderware clump"
            (root / relative).write_bytes(source)
            result = audit_rw(root, [relative], "dff")
            self.assertEqual(source, (root / relative).read_bytes())
        self.assertEqual(0, result["current_neon_policy"]["accepted"])
        self.assertEqual(1, result["current_neon_policy"]["rejected"]["count"])

    def test_img_measurements_expose_serialized_field_limits(self) -> None:
        with tempfile.TemporaryDirectory(prefix="native-world-img-") as temporary:
            path = Path(temporary) / "fixture.img"
            directory = struct.pack("<4sI", b"VER2", 1)
            directory += struct.pack("<IHH24s", 1, 1, 1, b"fixture.dff".ljust(24, b"\0"))
            path.write_bytes(directory.ljust(2048, b"\0") + b"payload".ljust(2048, b"\0"))
            result = audit_img(path)
        self.assertEqual(1, result["entries"])
        self.assertEqual({"dff": 1}, result["extensions"])
        self.assertEqual(65_535, result["format_constraints"]["member_sectors_max"])


if __name__ == "__main__":
    unittest.main()
