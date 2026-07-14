#!/usr/bin/env python3
"""Build a GTA IMG VER2 archive from extracted resource files."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


SECTOR_SIZE = 2048
HEADER = struct.Struct("<4sI")
DIRECTORY_ENTRY = struct.Struct("<IHH24s")


def sectors_for(size: int) -> int:
    return (size + SECTOR_SIZE - 1) // SECTOR_SIZE


def write_padding(output, size: int) -> None:
    padding = (-size) % SECTOR_SIZE
    if padding:
        output.write(b"\0" * padding)


def pack_img(output_path: Path, source_paths: list[Path]) -> None:
    if not source_paths:
        raise ValueError("an IMG archive needs at least one input file")

    entries: list[tuple[int, int, bytes, Path]] = []
    directory_size = HEADER.size + DIRECTORY_ENTRY.size * len(source_paths)
    next_sector = sectors_for(directory_size)
    seen_names: set[str] = set()

    for source_path in source_paths:
        if not source_path.is_file():
            raise FileNotFoundError(source_path)
        archive_name = source_path.name.casefold()
        encoded_name = archive_name.encode("ascii")
        if len(encoded_name) > 23:
            raise ValueError(f"IMG entry name is longer than 23 bytes: {archive_name}")
        if archive_name in seen_names:
            raise ValueError(f"duplicate IMG entry name: {archive_name}")
        seen_names.add(archive_name)

        size_sectors = sectors_for(source_path.stat().st_size)
        if size_sectors > 0xFFFF:
            raise ValueError(f"IMG entry is larger than 65535 sectors: {source_path}")
        entries.append((next_sector, size_sectors, encoded_name, source_path))
        next_sector += size_sectors

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as output:
        output.write(HEADER.pack(b"VER2", len(entries)))
        for offset, size_sectors, encoded_name, _ in entries:
            output.write(DIRECTORY_ENTRY.pack(offset, size_sectors, size_sectors, encoded_name.ljust(24, b"\0")))
        write_padding(output, output.tell())

        for offset, _, _, source_path in entries:
            expected_offset = offset * SECTOR_SIZE
            if output.tell() != expected_offset:
                raise RuntimeError(f"IMG offset mismatch for {source_path}")
            data = source_path.read_bytes()
            output.write(data)
            write_padding(output, len(data))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("inputs", type=Path, nargs="+")
    args = parser.parse_args()

    sources: list[Path] = []
    for value in args.inputs:
        if value.is_dir():
            sources.extend(path for path in value.iterdir() if path.is_file())
        else:
            sources.append(value)
    sources.sort(key=lambda path: path.name.casefold())
    pack_img(args.output, sources)
    print(
        f"packed {len(sources)} files into {args.output} "
        f"({args.output.stat().st_size / (1024 * 1024):.1f} MiB)"
    )


if __name__ == "__main__":
    main()
