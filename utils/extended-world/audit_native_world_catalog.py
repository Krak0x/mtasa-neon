#!/usr/bin/env python3
"""Inventory the static multi-city inputs without rewriting source assets.

The report deliberately separates immutable source measurements from Neon's
current Bullworth-v1 admission policy. A policy rejection is therefore not
reported as a GTA engine limit. The catalog scope is the static MTA world:
DFF, TXD, COL, IPL placements and their packed IMG containers.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from build_native_bw_pack import FIELD_PATTERN, MODEL_LINE, PLACEMENT_LINE, decode_lua_value
from pack_img import SECTOR_SIZE, sectors_for
from validate_native_world_payload import (
    COL_BUFFER_CAPACITY,
    RW_BUDGET,
    ColStats,
    RwStats,
    ValidationError,
    _validate_col3,
    _validate_coll,
    validate_rw_member,
)


SCHEMA = 1
MODEL_STORE_STOCK_OCCUPIED = {"object": 13_984, "object-damageable": 69, "timed-object": 160}
STATIC_MODEL_TYPES = frozenset(MODEL_STORE_STOCK_OCCUPIED)
STATIC_COMPONENTS = ("dff", "txd", "col", "ipl")
EXCLUDED_COMPONENTS = (
    "path-nodes",
    "traffic-and-ped-paths",
    "dat-expansion",
    "streamed-scm",
    "ifp-expansion",
    "rrr-expansion",
    "missions-and-savegames",
    "ambient-population",
)
OPTIONAL_COMPONENTS = ("radar", "water", "cull-and-occlusion", "audio", "timecycle", "interiors")


@dataclass(frozen=True)
class CitySpec:
    pack_id: str
    label: str
    resource: str
    prefix: str


DEFAULT_CITIES = (
    CitySpec("bullworth", "Bullworth", "test-resources/ug-bw", "UG_BW"),
    CitySpec("vice-city", "Vice City", "test-resources/ug-vc", "UG_VC"),
    CitySpec("liberty-city", "Liberty City", "test-resources/ug-lc", "UG_LC"),
    CitySpec("carcer-city", "Carcer City", "test-resources/carcer-city-test", "CARCER_CITY"),
)


def _fields(text: str) -> dict[str, object]:
    return {match.group(1): decode_lua_value(match.group(2)) for match in FIELD_PATTERN.finditer(text)}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _asset_fingerprint(resource: Path, paths: Iterable[str]) -> tuple[str, int, int, list[str]]:
    digest = hashlib.sha256()
    count = 0
    byte_count = 0
    missing: list[str] = []
    for relative in sorted(set(paths), key=str.casefold):
        path = resource / relative
        if not path.is_file():
            missing.append(relative)
            continue
        content_digest = _sha256(path)
        size = path.stat().st_size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\0")
        digest.update(content_digest.encode("ascii"))
        digest.update(b"\n")
        count += 1
        byte_count += size
    return digest.hexdigest(), count, byte_count, missing


def parse_generated_map(path: Path, prefix: str) -> dict[str, object]:
    """Parse the deliberately small schema emitted by the city builders."""

    model_open = f"{prefix}_MODELS = {{"
    placement_open = f"{prefix}_PLACEMENTS = {{"
    stat_prefix = f"{prefix}_STATS = {{"
    in_models = False
    in_placements = False
    models: dict[int, dict[str, object]] = {}
    placements: list[dict[str, object]] = []
    declared: dict[str, object] = {}

    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.startswith(stat_prefix):
            declared = _fields(line)
            continue
        if line == model_open:
            in_models = True
            continue
        if line == placement_open:
            in_placements = True
            continue
        if line == "}" and in_models:
            in_models = False
            continue
        if line == "}" and in_placements:
            in_placements = False
            continue
        if in_models:
            match = MODEL_LINE.match(line)
            if not match:
                raise ValueError(f"unrecognized model row at {path}:{line_number}")
            model_id = int(match.group(1))
            if model_id in models:
                raise ValueError(f"duplicate model ID {model_id} at {path}:{line_number}")
            values = _fields(match.group(2))
            required = {"name", "modelType", "dff", "txd", "col"}
            if missing := required - values.keys():
                raise ValueError(f"model {model_id} is missing {sorted(missing)}")
            models[model_id] = values
        elif in_placements:
            match = PLACEMENT_LINE.match(line)
            if not match:
                raise ValueError(f"unrecognized placement row at {path}:{line_number}")
            values = _fields(match.group(2))
            values["model"] = int(match.group(1))
            required = {"x", "y", "z", "source", "sourceIndex", "native"}
            if missing := required - values.keys():
                raise ValueError(f"placement {len(placements)} is missing {sorted(missing)}")
            placements.append(values)

    if not models or not placements or in_models or in_placements:
        raise ValueError(f"incomplete generated map in {path}")
    custom_ids = set(models)
    placed_custom_ids = {int(placement["model"]) for placement in placements if not placement["native"]}
    native_ids = {int(placement["model"]) for placement in placements if placement["native"]}
    unknown = sorted(
        placed_custom_ids - custom_ids
    )
    if unknown:
        raise ValueError(f"custom placements reference unknown models: {unknown[:10]}")
    if unused := sorted(custom_ids - placed_custom_ids):
        raise ValueError(f"custom models have no placements: {unused[:10]}")
    computed_counts = {
        "placements": len(placements),
        "customModels": len(models),
        "nativeModels": len(native_ids),
        "models": len(models) + len(native_ids),
    }
    for key, value in computed_counts.items():
        if key in declared and declared[key] != value:
            raise ValueError(f"declared {key}={declared[key]} differs from computed {value}")

    asset_paths: dict[str, list[str]] = {kind: [] for kind in ("dff", "txd", "col")}
    model_types: Counter[str] = Counter()
    for model in models.values():
        model_type = str(model["modelType"])
        if model_type not in STATIC_MODEL_TYPES:
            raise ValueError(f"unsupported static model type {model_type!r}")
        model_types[model_type] += 1
        for key in asset_paths:
            value = model[key]
            if value is not False:
                if not isinstance(value, str):
                    raise ValueError(f"non-string {key} path in {path}")
                asset_paths[key].append(value)

    axes = {axis: [float(row[axis]) for row in placements] for axis in ("x", "y", "z")}
    source_counts = Counter(str(row["source"]).casefold() for row in placements)
    return {
        "assets": asset_paths,
        "bounds": {axis: [min(values), max(values)] for axis, values in axes.items()},
        "declared": declared,
        "model_types": dict(sorted(model_types.items())),
        "models_custom": len(models),
        "models_native": len(native_ids),
        "placements": len(placements),
        "placements_native": sum(bool(row["native"]) for row in placements),
        "source_ipls": len(source_counts),
        "largest_source_ipl": (
            {"name": source_counts.most_common(1)[0][0], "placements": source_counts.most_common(1)[0][1]}
            if source_counts
            else None
        ),
    }


def _policy_bucket(error: str, extension: str) -> str:
    lowered = error.casefold()
    if extension == "col" and "col2" in lowered:
        return "canonicalization-required"
    if any(term in lowered for term in ("non-finite", "duplicate case-insensitive")):
        return "canonicalization-required"
    if any(term in lowered for term in ("wrong root version", "boundary", "bad magic", "truncated")):
        return "canonicalization-or-source-repair"
    if any(term in lowered for term in ("budget", "count", "exceed", "size", "header invalid")):
        return "current-neon-policy"
    return "compatibility-review"


def _summarize_failures(failures: list[dict[str, str]]) -> dict[str, object]:
    reasons = Counter(item["reason"] for item in failures)
    buckets = Counter(item["bucket"] for item in failures)
    return {
        "count": len(failures),
        "by_bucket": dict(sorted(buckets.items())),
        "by_reason": dict(sorted(reasons.items())),
        "examples": failures[:100],
        "examples_truncated": len(failures) > 100,
    }


def audit_rw(resource: Path, relative_paths: Iterable[str], extension: str) -> dict[str, object]:
    accepted = RwStats()
    failures: list[dict[str, str]] = []
    maximum_bytes = 0
    maximum_path = ""
    count = 0
    total_bytes = 0
    for relative in sorted(set(relative_paths), key=str.casefold):
        path = resource / relative
        if not path.is_file():
            continue
        data = path.read_bytes()
        count += 1
        total_bytes += len(data)
        if len(data) > maximum_bytes:
            maximum_bytes, maximum_path = len(data), relative
        member_stats = RwStats()
        try:
            validate_rw_member(data, extension, relative, member_stats)
        except (ValidationError, ValueError, struct.error) as error:
            reason = str(error).split(": ", 1)[-1]
            failures.append(
                {"path": relative, "bucket": _policy_bucket(reason, extension), "reason": reason}
            )
            continue
        for field in (
            "allocation_bytes",
            "geometry_vertices",
            "geometry_triangles",
            "geometry_materials",
            "bin_mesh_indices",
            "effects_2d",
            "breakable_vertices",
            "breakable_triangles",
            "breakable_materials",
            "native_textures",
            "texture_gpu_bytes",
            "texture_decoded_bytes",
        ):
            setattr(accepted, field, getattr(accepted, field) + getattr(member_stats, field))
        accepted.max_depth = max(accepted.max_depth, member_stats.max_depth)
        accepted.max_nodes = max(accepted.max_nodes, member_stats.max_nodes)
    return {
        "files": count,
        "bytes": total_bytes,
        "largest": {"path": maximum_path, "bytes": maximum_bytes},
        "current_neon_policy": {
            "accepted": count - len(failures),
            "rejected": _summarize_failures(failures),
            "accepted_only_metrics": {
                "geometry_vertices": accepted.geometry_vertices,
                "geometry_triangles": accepted.geometry_triangles,
                "geometry_materials": accepted.geometry_materials,
                "native_textures": accepted.native_textures,
                "texture_gpu_bytes": accepted.texture_gpu_bytes,
                "texture_decoded_bytes": accepted.texture_decoded_bytes,
                "max_chunk_depth": accepted.max_depth,
                "max_chunks_per_member": accepted.max_nodes,
            },
        },
    }


def audit_col(resource: Path, relative_paths: Iterable[str]) -> dict[str, object]:
    magics: Counter[str] = Counter()
    failures: list[dict[str, str]] = []
    accepted = ColStats()
    count = 0
    total_bytes = 0
    maximum_bytes = 0
    maximum_path = ""
    for relative in sorted(set(relative_paths), key=str.casefold):
        path = resource / relative
        if not path.is_file():
            continue
        data = path.read_bytes()
        count += 1
        total_bytes += len(data)
        if len(data) > maximum_bytes:
            maximum_bytes, maximum_path = len(data), relative
        magic = data[:4]
        magic_name = magic.decode("ascii", errors="replace")
        magics[magic_name] += 1
        try:
            if len(data) < 8:
                raise ValidationError("truncated COL record")
            record_size = 8 + struct.unpack_from("<I", data, 4)[0]
            if record_size > len(data) or any(data[record_size:]):
                raise ValidationError("COL record boundary or padding is invalid")
            if record_size > COL_BUFFER_CAPACITY:
                raise ValidationError(f"COL record exceeds current {COL_BUFFER_CAPACITY}-byte buffer")
            view = memoryview(data[:record_size])
            if magic == b"COLL":
                values = _validate_coll(view, relative)
            elif magic == b"COL3":
                values = _validate_col3(view, relative)
            elif magic == b"COL2":
                raise ValidationError("COL2 requires a reviewed native parser or offline COL3 conversion")
            else:
                raise ValidationError(f"bad magic {magic!r}")
        except (ValidationError, ValueError, struct.error) as error:
            reason = str(error).split(": ", 1)[-1]
            failures.append({"path": relative, "bucket": _policy_bucket(reason, "col"), "reason": reason})
            continue
        accepted.records += 1
        accepted.bytes += record_size
        for field, value in values.items():
            setattr(accepted, field, getattr(accepted, field) + value)
            if field in ("vertices", "faces", "face_groups"):
                maximum = f"max_{field}"
                setattr(accepted, maximum, max(getattr(accepted, maximum), value))
    return {
        "files": count,
        "bytes": total_bytes,
        "largest": {"path": maximum_path, "bytes": maximum_bytes},
        "magics": dict(sorted(magics.items())),
        "current_neon_policy": {
            "accepted": accepted.records,
            "rejected": _summarize_failures(failures),
            "accepted_only_metrics": {
                "bytes": accepted.bytes,
                "spheres": accepted.spheres,
                "boxes": accepted.boxes,
                "lines": accepted.lines,
                "vertices": accepted.vertices,
                "faces": accepted.faces,
                "face_groups": accepted.face_groups,
                "max_vertices": accepted.max_vertices,
                "max_faces": accepted.max_faces,
                "max_face_groups": accepted.max_face_groups,
            },
        },
    }


def audit_img(path: Path) -> dict[str, object]:
    byte_count = path.stat().st_size
    with path.open("rb") as stream:
        header = stream.read(8)
        if len(header) != 8:
            raise ValueError(f"truncated IMG header in {path}")
        magic, count = struct.unpack("<4sI", header)
        directory = stream.read(count * 32)
    if magic != b"VER2" or len(directory) != count * 32 or 8 + count * 32 > byte_count:
        raise ValueError(f"invalid IMG VER2 directory in {path}")
    extensions: Counter[str] = Counter()
    largest = {"name": "", "sectors": 0, "bytes_allocated": 0}
    previous_end = sectors_for(8 + count * 32)
    names: set[str] = set()
    for index in range(count):
        offset, size, stream_size, raw_name = struct.unpack_from("<IHH24s", directory, index * 32)
        name = raw_name.split(b"\0", 1)[0].decode("ascii").casefold()
        if not name or name in names or offset < previous_end or offset + size > sectors_for(byte_count):
            raise ValueError(f"invalid IMG member {name!r} in {path}")
        if stream_size < size:
            raise ValueError(f"IMG stream size is smaller than member size for {name}")
        names.add(name)
        previous_end = offset + size
        extensions[name.rsplit(".", 1)[-1]] += 1
        if size > largest["sectors"]:
            largest = {"name": name, "sectors": size, "bytes_allocated": size * SECTOR_SIZE}
    return {
        "path": path.name,
        "sha256": _sha256(path),
        "bytes": byte_count,
        "sectors": sectors_for(byte_count),
        "entries": count,
        "extensions": dict(sorted(extensions.items())),
        "largest_member": largest,
        "format_constraints": {
            "name_bytes_max": 23,
            "member_sectors_max": 65_535,
            "offset_field_bits": 32,
            "size_field_bits": 16,
        },
    }


def audit_city(repository: Path, spec: CitySpec) -> dict[str, object]:
    resource = repository / spec.resource
    map_path = resource / "map_data.lua"
    if not map_path.is_file():
        raise FileNotFoundError(map_path)
    parsed = parse_generated_map(map_path, spec.prefix)
    fingerprints: dict[str, object] = {}
    missing: list[str] = []
    for kind, paths in parsed["assets"].items():
        digest, count, byte_count, absent = _asset_fingerprint(resource, paths)
        fingerprints[kind] = {"sha256": digest, "files": count, "bytes": byte_count}
        missing.extend(absent)
    all_paths = [path for paths in parsed["assets"].values() for path in paths]
    digest, count, byte_count, absent = _asset_fingerprint(resource, all_paths)
    missing.extend(absent)
    fingerprints["all_static_assets"] = {"sha256": digest, "files": count, "bytes": byte_count}
    fingerprints["map_data.lua"] = {
        "sha256": _sha256(map_path),
        "bytes": map_path.stat().st_size,
    }
    img_reports = [audit_img(path) for path in sorted((resource / "assets").glob("*.img"))]
    return {
        "pack_id": spec.pack_id,
        "label": spec.label,
        "resource": spec.resource,
        "map": {key: value for key, value in parsed.items() if key != "assets"},
        "fingerprints": fingerprints,
        "missing_assets": sorted(set(missing), key=str.casefold),
        "img": img_reports,
        "dff": audit_rw(resource, parsed["assets"]["dff"], "dff"),
        "txd": audit_rw(resource, parsed["assets"]["txd"], "txd"),
        "col": audit_col(resource, parsed["assets"]["col"]),
    }


def build_catalog(repository: Path, cities: Iterable[CitySpec] = DEFAULT_CITIES) -> dict[str, object]:
    reports = [audit_city(repository, city) for city in cities]
    model_additions: Counter[str] = Counter()
    aggregate = Counter()
    for report in reports:
        model_additions.update(report["map"]["model_types"])
        aggregate["placements"] += int(report["map"]["placements"])
        aggregate["custom_models"] += int(report["map"]["models_custom"])
        aggregate["source_ipls"] += int(report["map"]["source_ipls"])
        aggregate["txds"] += int(report["fingerprints"]["txd"]["files"])
        aggregate["asset_bytes"] += int(report["fingerprints"]["all_static_assets"]["bytes"])
        aggregate["img_bytes"] += sum(int(img["bytes"]) for img in report["img"])
    exact_stores = {
        model_type: {
            "stock_occupied": MODEL_STORE_STOCK_OCCUPIED[model_type],
            "additions": model_additions[model_type],
            "exact_required": MODEL_STORE_STOCK_OCCUPIED[model_type] + model_additions[model_type],
        }
        for model_type in sorted(MODEL_STORE_STOCK_OCCUPIED)
    }
    return {
        "schema": SCHEMA,
        "scope": {
            "core": list(STATIC_COMPONENTS),
            "excluded_from_multi_city_capacity": list(EXCLUDED_COMPONENTS),
            "preserve_stock_layout_only": ["dat", "ifp", "rrr", "scm"],
            "optional_later": list(OPTIONAL_COMPONENTS),
            "note": "Excluded partitions still need stock-compatible relocation references when FileID is redesigned.",
        },
        "policy_provenance": {
            "name": "current Bullworth-v1 precommit profile",
            "engine_limit": False,
            "rw_budget": dict(sorted(RW_BUDGET.items())),
            "col_io_buffer_bytes": COL_BUFFER_CAPACITY,
        },
        "cities": reports,
        "aggregate": {
            **dict(sorted(aggregate.items())),
            "model_store_requirements": exact_stores,
        },
    }


def baseline_projection(catalog: dict[str, object]) -> dict[str, object]:
    """Return the compact source identity used to review intentional drift."""

    cities = []
    for report in catalog["cities"]:
        cities.append(
            {
                "pack_id": report["pack_id"],
                "map": {
                    key: report["map"][key]
                    for key in (
                        "models_custom",
                        "models_native",
                        "placements",
                        "placements_native",
                        "source_ipls",
                        "model_types",
                    )
                },
                "fingerprints": report["fingerprints"],
                "img": [
                    {
                        key: image[key]
                        for key in ("path", "sha256", "bytes", "sectors", "entries", "extensions")
                    }
                    for image in report["img"]
                ],
            }
        )
    return {
        "schema": catalog["schema"],
        "scope": catalog["scope"],
        "aggregate": catalog["aggregate"],
        "cities": cities,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, help="write the deterministic JSON report")
    parser.add_argument("--baseline-output", type=Path, help="write only the compact source-identity baseline")
    parser.add_argument("--verify", type=Path, help="fail if source identity differs from this compact baseline")
    args = parser.parse_args()
    result = build_catalog(args.repository.resolve())
    serialized = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.verify:
        expected = json.loads(args.verify.read_text(encoding="utf-8"))
        if baseline_projection(result) != expected:
            raise SystemExit(f"native-world catalog drifted from {args.verify}")
    if args.baseline_output:
        args.baseline_output.write_text(
            json.dumps(baseline_projection(result), indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    if args.output:
        args.output.write_text(serialized, encoding="utf-8")
    else:
        print(serialized, end="")


if __name__ == "__main__":
    main()
