#!/usr/bin/env python3
"""Tests for the read-only aggregate static-world v3 planner."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
REPOSITORY = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))

from plan_native_world_v3 import (  # noqa: E402
    FILE_ID_LAYOUT,
    FUTURE_CITY_MODEL_RESERVE,
    MODEL_ID_FIRST,
    MODEL_ID_LAST,
    SizedMember,
    baseline_projection,
    boundary_proofs,
    checked_sum,
    collisions,
    full_layout_proof,
    partition_sizes,
    plan,
    usage,
)


class ArithmeticAndFormatTest(unittest.TestCase):
    def test_checked_sum_refuses_uint64_overflow(self) -> None:
        with self.assertRaisesRegex(ValueError, "exceeds uint64"):
            checked_sum([(1 << 64) - 1, 1], "fixture")

    def test_img_partition_respects_member_sector_width(self) -> None:
        with self.assertRaisesRegex(ValueError, "16-bit sector"):
            partition_sizes([SizedMember("too-big.dff", (65_535 + 1) * 2_048)])

    def test_usage_does_not_hide_capacity_failure(self) -> None:
        report = usage(10, 8, 3)
        self.assertFalse(report["fits"])
        self.assertEqual(-1, report["remaining"])


class IdentityAndBoundaryTest(unittest.TestCase):
    def test_collision_report_requires_distinct_owners(self) -> None:
        report = collisions({"same-owner": ["a", "a"], "collision": ["a", "b"]})
        self.assertEqual([{"identity": "collision", "owners": ["a", "b"]}], report)

    def test_required_boundaries_have_exact_partition_owners(self) -> None:
        proofs = {report["file_id"]: report for report in boundary_proofs()}
        self.assertEqual("dff", proofs[31_999]["partition"])
        self.assertEqual("txd", proofs[32_000]["partition"])
        self.assertEqual("txd", proofs[39_999]["partition"])
        self.assertEqual("col", proofs[40_000]["partition"])
        self.assertEqual("col", proofs[40_511]["partition"])
        self.assertEqual("ipl", proofs[40_512]["partition"])
        self.assertTrue(all(report["owner_count"] == 1 for report in proofs.values()))
        self.assertEqual([0, MODEL_ID_LAST], FILE_ID_LAYOUT["dff"])
        layout = full_layout_proof()
        self.assertTrue(layout["valid"])
        self.assertEqual(42_340, layout["terminal_file_id"])
        self.assertEqual(42_341, layout["exclusive_end"])


class FrozenCorpusPlannerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = plan(REPOSITORY)

    def test_aggregate_remap_is_contiguous_source_first_and_deterministic(self) -> None:
        ranges = [city["model_id_range"] for city in self.report["cities"]]
        self.assertEqual(
            [[20_000, 21_053], [21_054, 24_855], [24_856, 28_343], [28_344, 31_836]],
            ranges,
        )
        self.assertEqual(MODEL_ID_FIRST, ranges[0][0])
        self.assertEqual(163, self.report["file_ids"]["remaining_custom_model_ids"])
        self.assertEqual(11_837, self.report["aggregate"]["model_variants"])
        self.assertEqual(919, self.report["aggregate"]["cross_spatial_variants"])
        self.assertEqual(13_404, self.report["aggregate"]["generated_identities"])
        self.assertTrue(all(len(city["remap_sha256"]) == 64 for city in self.report["cities"]))
        self.assertTrue(all(len(city["archive_assignment_sha256"]) == 64 for city in self.report["cities"]))

    def test_exact_store_and_pool_additions_include_spatial_variants(self) -> None:
        aggregate = self.report["aggregate"]
        self.assertEqual(11_217, aggregate["model_store_atomic"])
        self.assertEqual(136, aggregate["model_store_damage_atomic"])
        self.assertEqual(484, aggregate["model_store_timed"])
        self.assertEqual(1_325, aggregate["txd"])
        self.assertEqual(121, aggregate["col"])
        self.assertEqual(121, aggregate["ipl"])
        self.assertEqual(11_835, aggregate["col_model"])
        self.assertEqual(33_849, aggregate["building"])
        self.assertEqual(7, self.report["capacity"]["archive"]["additions"])
        self.assertEqual(23, self.report["capacity"]["stream_handle"]["projected"])
        self.assertEqual(21_815, self.report["capacity"]["col_model"]["projected"])
        self.assertEqual(43_015, self.report["capacity"]["building_all_city_resident"]["projected"])
        self.assertEqual(21_641, self.report["capacity"]["building_mutually_exclusive_city"]["projected"])

    def test_planner_fails_closed_on_known_activation_gaps(self) -> None:
        self.assertEqual("blocked", self.report["status"])
        blockers = {record["code"]: record for record in self.report["blockers"]}
        self.assertEqual(
            FUTURE_CITY_MODEL_RESERVE - 163,
            blockers["future-model-reserve"]["evidence"]["shortfall"],
        )
        self.assertEqual(3_038, blockers["streamed-ipl-lod-bootstrap"]["evidence"]["links"])
        self.assertIn("building-concurrency", blockers)
        self.assertIn("quad-tree-concurrency", blockers)
        self.assertIn("cache-rollover-capacity", blockers)
        self.assertIn("streaming-double-buffer-floor", blockers)
        self.assertIn("renderware-ram-high-water-unproved", blockers)
        self.assertIn("stock-identity-unproved", blockers)
        self.assertEqual(1_081, self.report["cities"][1]["lod_dependencies"]["cross_group_links"])
        self.assertEqual(1_956, self.report["cities"][2]["lod_dependencies"]["cross_group_links"])
        self.assertEqual(1, self.report["cities"][2]["lod_dependencies"]["same_group_links"])
        self.assertEqual(6, len(self.report["spatial"]["pairwise_city_bounds"]))
        self.assertTrue(all(city["spatial_group_bounds"] for city in self.report["cities"]))
        streaming = self.report["budgets"]["streaming"]
        self.assertEqual(
            streaming["minimum_per_channel_blocks"] * 2,
            streaming["minimum_total_double_buffer_blocks"],
        )

    def test_pack_scoped_archive_names_do_not_hide_global_member_collisions(self) -> None:
        self.assertEqual([], self.report["collisions"]["generated_identity"])
        self.assertEqual([], self.report["collisions"]["generated_gta_uppercase_key"])
        self.assertIn("(content_id, pack_id, filename)", self.report["collisions"]["archive_filename_policy"])

    def test_baseline_omits_large_source_collision_diagnostics(self) -> None:
        projection = baseline_projection(self.report)
        self.assertEqual(64, len(projection["cities"][1]["lod_group_edges_sha256"]))
        self.assertEqual(64, len(projection["reviewed_plan_sha256"]))
        self.assertNotIn("group_edges", projection["cities"][1]["lod_dependencies"])
        self.assertIn("future-model-reserve", projection["blocker_codes"])


if __name__ == "__main__":
    unittest.main()
