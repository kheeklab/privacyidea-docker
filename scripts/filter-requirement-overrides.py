#!/usr/bin/env python3
"""Remove upstream pinned blocks superseded by this image's direct overrides."""

from pathlib import Path
import re
import sys

source, overrides, destination = map(Path, sys.argv[1:4])
override_names = set()
for line in overrides.read_text(encoding="utf-8").splitlines():
    value = line.strip()
    if value and not value.startswith("#"):
        value = value.split("\\", 1)[0].strip()
        match = re.match(r"^([A-Za-z0-9][A-Za-z0-9_.-]*)", value)
        if match:
            override_names.add(re.sub(r"[-_.]+", "-", match.group(1)).lower())


def package_name(line: str) -> str | None:
    if not line or line[0].isspace() or line.startswith(("#", "-")):
        return None
    value = line.rstrip().removesuffix("\\").strip()
    match = re.match(r"^([A-Za-z0-9][A-Za-z0-9_.-]*)", value)
    return re.sub(r"[-_.]+", "-", match.group(1)).lower() if match else None


blocks: list[tuple[str | None, list[str]]] = []
for line in source.read_text(encoding="utf-8").splitlines(keepends=True):
    name = package_name(line)
    if name is not None:
        blocks.append((name, [line]))
    elif blocks:
        blocks[-1][1].append(line)
    else:
        blocks.append((None, [line]))

with destination.open("w", encoding="utf-8") as output:
    for name, lines in blocks:
        if name not in override_names:
            output.writelines(lines)
