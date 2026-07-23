#!/usr/bin/env python3
"""Prove deterministic v3 source canonicalization without building city packs."""

from __future__ import annotations

import argparse
import json
import struct
from collections import Counter
from pathlib import Path

from audit_native_world_catalog import DEFAULT_CITIES, parse_generated_map
from build_native_world_v3 import (
    MAX_AGGREGATE_DECODED_BYTES,
    MAX_AGGREGATE_GPU_BYTES,
    MAX_CITY_DECODED_BYTES,
    MAX_CITY_GPU_BYTES,
    RW_LIBRARY_ID,
    canonicalize_rw_version,
    canonicalize_txd_duplicates,
    convert_col2_to_col3,
    merge_profile,
    normalize_dff_uvs,
    sha256_file,
    upgrade_legacy_dff,
    validate_static_col_record_v3,
    validate_static_txd_v3_grammar,
)


EXPECTED_COL2 = 57
EXPECTED_LEGACY_DFF = 1
EXPECTED_CARCER_REPAIRS = 2
EXPECTED_ZERO_TRIANGLE_DFFS = 2


def prove_col_equivalence(source: bytes, converted: bytes, name: str) -> None:
    if source[:4] != b"COL2":
        if converted != source:
            raise ValueError(f"{name}: non-COL2 bytes changed")
        return
    if (
        converted[:4] != b"COL3"
        or len(converted) != len(source) + 12
        or converted[8:80] != source[8:80]
        or converted[120:] != source[108:]
        or converted[108:120] != b"\0" * 12
    ):
        raise ValueError(f"{name}: COL2/COL3 semantic body equivalence failed")
    source_flags = struct.unpack_from("<I", source, 80)[0]
    converted_flags = struct.unpack_from("<I", converted, 80)[0]
    if converted_flags != (source_flags & ~0x10):
        raise ValueError(f"{name}: legacy shadow flag was not canonicalized")
    for offset in range(84, 108, 4):
        old = struct.unpack_from("<I", source, offset)[0]
        new = struct.unpack_from("<I", converted, offset)[0]
        if new != (old + 12 if old else 0):
            raise ValueError(f"{name}: COL section offset equivalence failed at {offset}")


def audit(repository: Path, upgrader: Path) -> dict[str, object]:
    aggregate = Counter()
    aggregate_texture: Counter[str] = Counter()
    aggregate_collision: Counter[str] = Counter()
    reports = []
    for city in DEFAULT_CITIES:
        resource = repository / city.resource
        parsed = parse_generated_map(resource / "map_data.lua", city.prefix)
        conversions = Counter()
        duplicate_records = 0
        texture = Counter()
        collision = Counter()

        for relative in sorted(set(parsed["assets"]["dff"]), key=str.casefold):
            path = resource / relative
            source, upgrade = upgrade_legacy_dff(path, upgrader)
            canonical, _, repairs = canonicalize_rw_version(source, relative)
            _, _, zero_triangles = normalize_dff_uvs(
                canonical,
                relative,
                source_sha256=sha256_file(path),
            )
            if struct.unpack_from("<I", canonical, 8)[0] != RW_LIBRARY_ID:
                raise ValueError(f"{relative}: canonical DFF version is not SA 3.6")
            conversions["legacy_dff"] += int(upgrade is not None)
            conversions["dff_source_repairs"] += int(bool(repairs))
            conversions["zero_triangle_dffs"] += int(bool(zero_triangles))

        for relative in sorted(set(parsed["assets"]["txd"]), key=str.casefold):
            path = resource / relative
            canonical, duplicates = canonicalize_txd_duplicates(path.read_bytes(), relative)
            duplicate_records += sum(record.get("kind") == "first-wins-duplicate" for record in duplicates)
            member_texture = validate_static_txd_v3_grammar(canonical, relative)
            if not member_texture["textures"]:
                raise ValueError(f"{relative}: empty source TXD is not admitted by static-world-v3")
            merge_profile(
                texture,
                member_texture,
                context=f"{city.pack_id} texture profile",
                byte_limits={
                    "serialized_gpu_bytes": MAX_CITY_GPU_BYTES,
                    "decoded_rgba_bytes": MAX_CITY_DECODED_BYTES,
                },
            )

        for relative in sorted(set(parsed["assets"]["col"]), key=str.casefold):
            path = resource / relative
            source = path.read_bytes()
            converted, changed = convert_col2_to_col3(source, relative)
            prove_col_equivalence(source, converted, relative)
            merge_profile(
                collision,
                validate_static_col_record_v3(converted, relative),
                context=f"{city.pack_id} collision profile",
            )
            conversions["col2_to_col3"] += int(changed)

        aggregate.update(conversions)
        aggregate["txd_duplicates_removed"] += duplicate_records
        merge_profile(
            aggregate_texture,
            texture,
            context="aggregate texture profile",
            byte_limits={
                "serialized_gpu_bytes": MAX_AGGREGATE_GPU_BYTES,
                "decoded_rgba_bytes": MAX_AGGREGATE_DECODED_BYTES,
            },
        )
        merge_profile(aggregate_collision, collision, context="aggregate collision profile")
        reports.append(
            {
                "pack_id": city.pack_id,
                "source_fingerprint": sha256_file(resource / "map_data.lua"),
                "conversions": dict(sorted(conversions.items())),
                "txd_duplicates_removed": duplicate_records,
                "texture_profile": dict(sorted(texture.items())),
                "collision_profile": dict(sorted(collision.items())),
            }
        )

    if aggregate["col2_to_col3"] != EXPECTED_COL2:
        raise ValueError(f"expected {EXPECTED_COL2} COL2 conversions, got {aggregate['col2_to_col3']}")
    if aggregate["legacy_dff"] != EXPECTED_LEGACY_DFF:
        raise ValueError(f"expected {EXPECTED_LEGACY_DFF} legacy DFF conversion, got {aggregate['legacy_dff']}")
    if aggregate["dff_source_repairs"] != EXPECTED_CARCER_REPAIRS:
        raise ValueError(f"expected {EXPECTED_CARCER_REPAIRS} closed Carcer repairs, got {aggregate['dff_source_repairs']}")
    if aggregate["zero_triangle_dffs"] != EXPECTED_ZERO_TRIANGLE_DFFS:
        raise ValueError(
            f"expected {EXPECTED_ZERO_TRIANGLE_DFFS} closed zero-triangle DFFs, got {aggregate['zero_triangle_dffs']}"
        )
    return {
        "schema": 1,
        "generated_by": "utils/extended-world/audit_native_world_v3_admission.py",
        "cities": reports,
        "aggregate": dict(sorted(aggregate.items())),
        "aggregate_texture_profile": dict(sorted(aggregate_texture.items())),
        "aggregate_collision_profile": dict(sorted(aggregate_collision.items())),
        "postconditions": {
            "legacy_dff": "pinned librw deserialize/serialize identity and round-trip shape",
            "col2": "full canonical COL grammar and indices validate before remap; payload arrays and shifted offsets are equivalent",
            "txd_duplicates": "closed D3D9 tuple/mip grammar validates; first lookup winner preserved; unreachable later names removed",
            "budgets": "all byte sums use checked uint64 arithmetic and compiled per-texture/TXD/city/aggregate limits",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--librw-dff-upgrader", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = audit(args.repository.resolve(), args.librw_dff_upgrader.resolve())
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")


if __name__ == "__main__":
    main()
