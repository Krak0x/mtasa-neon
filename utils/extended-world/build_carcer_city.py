#!/usr/bin/env python3
"""Build the Clarksland exterior A/B resource from the Carcer City demo ZIP.

The resource intentionally uses the same generated data shape and client
runtime as ``ug-vc``.  Only text IPL instances in area zero are selected.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import shutil
import struct
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path


ARCHIVE_ROOT = "GTA Carcer City Demo/"
IMG_PATHS = ("models/gta3.img", "models/gta_int.img")
IDE_PATHS = (
    "data/maps/generic/vegepart.ide",
    "data/maps/generic/barriers.ide",
    "data/maps/generic/dynamic.ide",
    "data/maps/generic/dynamic2.ide",
    "data/maps/generic/multiobj.ide",
    "data/maps/generic/procobj.ide",
    "data/maps/clarksland/clark_gen.ide",
    "data/maps/clarksland/clark.ide",
    "data/maps/clarksland/clark_levels.ide",
    # GTA loads every exterior IDE before any IPL.  Keep the later Lac Point
    # definitions available even in a Clarksland-only placement test because
    # the two districts intentionally share a few model IDs.
    "data/maps/lacpoint/lacw.ide",
    "data/maps/lacpoint/lacwlevels.ide",
    "data/maps/lacpoint/lace.ide",
    "data/maps/lacpoint/lacelevels.ide",
    # Carcer reuses five models defined in its interior IDE as area-zero
    # exterior props.  Placement area, not the IDE's folder, determines
    # whether an instance belongs in this resource.
    "data/maps/ccinterior/cc_interiors.ide",
)
IPL_PATHS = (
    "data/maps/clarksland/clark_gen.ipl",
    "data/maps/clarksland/clark.ipl",
    "data/maps/clarksland/clark_levels.ipl",
    "data/maps/clarksland/clark_props.ipl",
    "data/maps/clarksland/clark_props2.ipl",
)
COL_MAGICS = {b"COLL", b"COL2", b"COL3", b"COL4"}


def load_shared_builder():
    path = Path(__file__).with_name("build_ug_map.py")
    spec = importlib.util.spec_from_file_location("mta_neon_build_ug_map", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load shared map builder from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


SHARED = load_shared_builder()
ModelDefinition = SHARED.ModelDefinition
Placement = SHARED.Placement


@dataclass(frozen=True)
class ImgEntry:
    name: str
    offset: int
    size: int


def split_fields(line: str) -> list[str]:
    return next(csv.reader([line], skipinitialspace=True))


def parse_ide_text(text: str, source: str) -> dict[int, ModelDefinition]:
    definitions: dict[int, ModelDefinition] = {}
    section: str | None = None
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.split("#", 1)[0].strip()
        lowered = line.casefold()
        if not line:
            continue
        if lowered in {"objs", "tobj", "anim"}:
            section = lowered
            continue
        if lowered == "end":
            section = None
            continue
        if section not in {"objs", "tobj", "anim"}:
            continue
        try:
            definition = SHARED.parse_model_definition(section, split_fields(line))
        except (IndexError, ValueError) as error:
            raise ValueError(f"invalid IDE row {source}:{line_number}: {line}") from error
        definitions[definition.source_id] = definition
    return definitions


def parse_ipl_text(text: str, source: str) -> list[Placement]:
    placements: list[Placement] = []
    in_instances = False
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.split("#", 1)[0].strip()
        lowered = line.casefold()
        if not line:
            continue
        if lowered == "inst":
            in_instances = True
            continue
        if lowered == "end":
            in_instances = False
            continue
        if not in_instances:
            continue
        fields = split_fields(line)
        if len(fields) < 11:
            raise ValueError(f"invalid IPL row {source}:{line_number}: {line}")
        try:
            placement = Placement(
                source_id=int(fields[0], 0),
                name=fields[1].strip(),
                area=int(fields[2], 0),
                x=float(fields[3]),
                y=float(fields[4]),
                z=float(fields[5]),
                qx=float(fields[6]),
                qy=float(fields[7]),
                qz=float(fields[8]),
                qw=float(fields[9]),
                lod_index=int(fields[10], 0),
                source_file=Path(source).name,
                source_index=len(placements),
            )
        except ValueError as error:
            raise ValueError(f"invalid IPL values {source}:{line_number}: {line}") from error
        placements.append(placement)
    return placements


def select_exterior(read_text) -> tuple[list[Placement], int, int]:
    selected: list[Placement] = []
    interiors_rejected = 0
    lod_links_rejected = 0
    for path in IPL_PATHS:
        source = parse_ipl_text(read_text(path), path)
        selected_by_source_index: dict[int, int] = {}
        file_selected: list[tuple[int, Placement]] = []
        for source_index, placement in enumerate(source):
            if placement.area != 0:
                interiors_rejected += 1
                continue
            selected_by_source_index[source_index] = len(selected) + len(file_selected)
            file_selected.append((source_index, placement))
        for _, placement in file_selected:
            if placement.lod_index >= 0:
                target = selected_by_source_index.get(placement.lod_index)
                if target is None:
                    lod_links_rejected += 1
                else:
                    placement.lod_global_index = target
            selected.append(placement)
    for placement in selected:
        if placement.lod_global_index is not None:
            selected[placement.lod_global_index].is_lod = True
    return selected, interiors_rejected, lod_links_rejected


def read_img_directory(stream) -> list[ImgEntry]:
    header = stream.read(8)
    if len(header) != 8 or header[:4] != b"VER2":
        raise ValueError("gta3.img is not an IMG v2 archive")
    count = struct.unpack_from("<I", header, 4)[0]
    directory = stream.read(count * 32)
    if len(directory) != count * 32:
        raise ValueError("truncated gta3.img directory")
    entries: list[ImgEntry] = []
    for index in range(count):
        sector, size, _, encoded_name = struct.unpack_from("<IHH24s", directory, index * 32)
        name = encoded_name.split(b"\0", 1)[0].decode("latin1").casefold()
        entries.append(ImgEntry(name=name, offset=sector * 2048, size=size * 2048))
    return entries


def trim_renderware_file(data: bytes) -> bytes:
    if len(data) < 12:
        return data
    payload_size = struct.unpack_from("<I", data, 4)[0]
    exact_size = 12 + payload_size
    if 12 <= exact_size <= len(data):
        return data[:exact_size]
    return data


def extract_img_members(archive: zipfile.ZipFile, member: str, wanted: set[str]) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    with archive.open(member) as stream:
        entries = read_img_directory(stream)
        selected = sorted((entry for entry in entries if entry.name in wanted), key=lambda entry: entry.offset)
        missing = wanted - {entry.name for entry in selected}
        if missing:
            preview = ", ".join(sorted(missing)[:20])
            raise FileNotFoundError(f"{len(missing)} IMG members are missing: {preview}")
        for entry in selected:
            stream.seek(entry.offset)
            data = stream.read(entry.size)
            if len(data) != entry.size:
                raise ValueError(f"truncated IMG member {entry.name}")
            result[entry.name] = data
    return result


def parse_col_bytes(data: bytes, source: str) -> tuple[dict[str, bytes], dict[int, bytes]]:
    by_name: dict[str, bytes] = {}
    by_id: dict[int, bytes] = {}
    offset = 0
    while offset < len(data):
        if not any(data[offset : min(len(data), offset + 32)]):
            break
        if offset + 32 > len(data):
            raise ValueError(f"truncated COL record in {source} at {offset}")
        magic = data[offset : offset + 4]
        if magic not in COL_MAGICS:
            raise ValueError(f"unknown COL magic {magic!r} in {source} at {offset}")
        payload_size = struct.unpack_from("<I", data, offset + 4)[0]
        end = offset + 8 + payload_size
        if payload_size < 24 or end > len(data):
            raise ValueError(f"invalid COL size {payload_size} in {source} at {offset}")
        record = data[offset:end]
        name = record[8:28].split(b"\0", 1)[0].decode("ascii", errors="replace").casefold()
        model_id = struct.unpack_from("<H", record, 28)[0]
        by_name[name] = record
        by_id[model_id] = record
        offset = end
    return by_name, by_id


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True, help="GTA_Carcer_City_Demo.zip")
    parser.add_argument("--output", type=Path, required=True, help="existing MTA resource directory")
    parser.add_argument("--translate-x", type=float, default=0.0)
    parser.add_argument("--translate-y", type=float, default=0.0)
    parser.add_argument("--translate-z", type=float, default=0.0)
    parser.add_argument("--analyze-only", action="store_true")
    args = parser.parse_args()

    if not args.archive.is_file():
        raise FileNotFoundError(args.archive)
    with zipfile.ZipFile(args.archive) as archive:
        members = {name.casefold(): name for name in archive.namelist()}

        def member_name(relative: str) -> str:
            key = (ARCHIVE_ROOT + relative).casefold()
            if key not in members:
                raise FileNotFoundError(f"archive member {relative}")
            return members[key]

        def read_text(relative: str) -> str:
            return archive.read(member_name(relative)).decode("latin1")

        definitions: dict[int, ModelDefinition] = {}
        for path in IDE_PATHS:
            # Later IDEs override earlier IDs, matching gta.dat load order.
            definitions.update(parse_ide_text(read_text(path), path))

        placements, interiors_rejected, lod_links_rejected = select_exterior(read_text)
        selected_ids = sorted({placement.source_id for placement in placements})
        native_ids: set[int] = set()
        missing_definitions = [source_id for source_id in selected_ids if source_id not in definitions]
        if missing_definitions:
            raise ValueError(f"models without IDE definitions: {missing_definitions[:20]}")
        models = [definitions[source_id] for source_id in selected_ids if source_id in definitions]
        for placement in placements:
            definition = definitions.get(placement.source_id)
            if definition:
                placement.name = definition.name

        xs = [placement.x + args.translate_x for placement in placements]
        ys = [placement.y + args.translate_y for placement in placements]
        summary = (
            f"carcer-clarksland: {len(placements)} area-0 placements, {len(models)} custom + "
            f"{len(native_ids)} native models, {interiors_rejected} interiors rejected, "
            f"{lod_links_rejected} LOD links rejected; X={min(xs):.1f}..{max(xs):.1f}, "
            f"Y={min(ys):.1f}..{max(ys):.1f}"
        )
        if args.analyze_only:
            print(summary)
            return

        directories: dict[str, dict[str, ImgEntry]] = {}
        for img_path in IMG_PATHS:
            with archive.open(member_name(img_path)) as stream:
                directories[img_path] = {entry.name: entry for entry in read_img_directory(stream)}

        model_sources: dict[int, tuple[str, str]] = {}
        wanted_by_img: dict[str, set[str]] = {img_path: set() for img_path in IMG_PATHS}
        for model in models:
            dff_name = model.name.casefold() + ".dff"
            txd_name = model.txd.casefold() + ".txd"
            txd_img = next((path for path in IMG_PATHS if txd_name in directories[path]), None)
            if txd_img is None:
                raise FileNotFoundError(f"missing TXD {txd_name} in Carcer IMG archives")
            # Prefer the DFF stored beside its TXD.  This is important for the
            # five exterior props sourced from gta_int.img, whose names can
            # also collide with different gta3.img variants.
            dff_img = txd_img if dff_name in directories[txd_img] else next(
                (path for path in IMG_PATHS if dff_name in directories[path]), None
            )
            if dff_img is None:
                raise FileNotFoundError(f"missing DFF {dff_name} in Carcer IMG archives")
            model_sources[model.source_id] = (dff_img, txd_img)
            wanted_by_img[dff_img].add(dff_name)
            wanted_by_img[txd_img].add(txd_name)

        col_names_by_img: dict[str, set[str]] = {}
        extracted_by_img: dict[str, dict[str, bytes]] = {}
        for img_path in IMG_PATHS:
            col_names = {name for name in directories[img_path] if name.endswith(".col")}
            col_names_by_img[img_path] = col_names
            wanted_by_img[img_path].update(col_names)
            extracted_by_img[img_path] = extract_img_members(
                archive, member_name(img_path), wanted_by_img[img_path]
            )

    args.output.mkdir(parents=True, exist_ok=True)
    assets_output = args.output / "assets"
    model_output = assets_output / "models"
    texture_output = assets_output / "textures"
    collision_output = assets_output / "collisions"
    # Radar artwork is generated separately from the same source archive. Keep
    # it when rebuilding geometry so the normal model regeneration workflow
    # cannot silently leave the resource without its extended-world minimap.
    for generated_directory in (model_output, texture_output, collision_output):
        if generated_directory.exists():
            shutil.rmtree(generated_directory)
    for packed_archive in (assets_output / "carcer_models.img", assets_output / "carcer_textures.img"):
        packed_archive.unlink(missing_ok=True)
    model_output.mkdir(parents=True)
    texture_output.mkdir(parents=True)
    collision_output.mkdir(parents=True)

    col_by_img: dict[str, tuple[dict[str, bytes], dict[int, bytes]]] = {}
    for img_path in IMG_PATHS:
        col_by_name: dict[str, bytes] = {}
        col_by_id: dict[int, bytes] = {}
        for col_name in sorted(col_names_by_img[img_path]):
            archive_by_name, archive_by_id = parse_col_bytes(extracted_by_img[img_path][col_name], col_name)
            for name, record in archive_by_name.items():
                col_by_name.setdefault(name, record)
            for source_id, record in archive_by_id.items():
                col_by_id.setdefault(source_id, record)
        col_by_img[img_path] = (col_by_name, col_by_id)

    asset_paths: list[str] = []
    texture_paths: dict[str, str] = {}
    for index, texture_name in enumerate(sorted({model.txd.casefold() for model in models}), start=1):
        model = next(model for model in models if model.txd.casefold() == texture_name)
        txd_img = model_sources[model.source_id][1]
        relative = f"assets/textures/{index:04d}.txd"
        (args.output / relative).write_bytes(
            trim_renderware_file(extracted_by_img[txd_img][texture_name + ".txd"])
        )
        texture_paths[texture_name] = relative
        asset_paths.append(relative)

    model_assets: dict[int, dict[str, str | None]] = {}
    missing_collisions = 0
    for model in models:
        dff_img, _ = model_sources[model.source_id]
        dff_relative = f"assets/models/{model.source_id}.dff"
        (args.output / dff_relative).write_bytes(
            trim_renderware_file(extracted_by_img[dff_img][model.name.casefold() + ".dff"])
        )
        asset_paths.append(dff_relative)
        preferred_names, preferred_ids = col_by_img[dff_img]
        fallback_img = next(path for path in IMG_PATHS if path != dff_img)
        fallback_names, fallback_ids = col_by_img[fallback_img]
        col_record = (
            preferred_names.get(model.name.casefold())
            or preferred_ids.get(model.source_id)
            or fallback_names.get(model.name.casefold())
            or fallback_ids.get(model.source_id)
        )
        col_relative: str | None = None
        if col_record is not None:
            col_relative = f"assets/collisions/{model.source_id}.col"
            (args.output / col_relative).write_bytes(col_record)
            asset_paths.append(col_relative)
        else:
            missing_collisions += 1
        model_assets[model.source_id] = {
            "txd": texture_paths[model.txd.casefold()],
            "dff": dff_relative,
            "col": col_relative,
        }

    SHARED.write_data(
        args.output,
        "CARCER_CITY",
        models,
        placements,
        model_assets,
        (args.translate_x, args.translate_y, args.translate_z),
        interiors_rejected,
        lod_links_rejected,
        native_ids,
        generated_by="utils/extended-world/build_carcer_city.py",
    )
    SHARED.write_meta(args.output, asset_paths, info_name="Carcer City Clarksland A/B test")
    total_bytes = sum((args.output / path).stat().st_size for path in asset_paths)
    print(summary)
    print(
        f"generated {len(texture_paths)} TXDs and {len(models) - missing_collisions}/{len(models)} COLs; "
        f"resource assets={total_bytes / (1024 * 1024):.1f} MiB"
    )


if __name__ == "__main__":
    main()
