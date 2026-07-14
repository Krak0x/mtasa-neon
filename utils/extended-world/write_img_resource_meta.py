#!/usr/bin/env python3
"""Write a compact MTA meta.xml for resources backed by IMG archives.

Generated map resources keep extracted DFF/TXD files on the developer machine
for reproducibility.  Shipping those files as individual MTA downloads defeats
the IMG streaming path, so this helper lists only the packed archives plus the
COL and radar files that still need ordinary resource access.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from xml.sax.saxutils import quoteattr


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--resource", type=Path, required=True)
    parser.add_argument("--info-name", required=True)
    parser.add_argument("--server-script", action="append", default=[])
    parser.add_argument("--client-script", action="append", default=[])
    parser.add_argument("--archive", action="append", default=[])
    parser.add_argument("--file-dir", action="append", default=[])
    args = parser.parse_args()

    resource = args.resource.resolve()
    lines = [
        "<meta>",
        f"    <info author={quoteattr('MTA Neon')} name={quoteattr(args.info_name)} type=\"script\" version=\"1.0.0\" />",
    ]
    for script in args.server_script:
        lines.append(f"    <script src={quoteattr(script)} type=\"server\" />")
    for script in args.client_script:
        lines.append(f"    <script src={quoteattr(script)} type=\"client\" cache=\"false\" />")

    files = set(args.archive)
    for directory_name in args.file_dir:
        directory = resource / directory_name
        if not directory.is_dir():
            raise FileNotFoundError(directory)
        files.update(path.relative_to(resource).as_posix() for path in directory.rglob("*") if path.is_file())
    for path in sorted(files):
        if not (resource / path).is_file():
            raise FileNotFoundError(resource / path)
        lines.append(f"    <file src={quoteattr(path)} />")
    lines.append("</meta>")

    (resource / "meta.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {resource / 'meta.xml'} with {len(files)} files")


if __name__ == "__main__":
    main()
