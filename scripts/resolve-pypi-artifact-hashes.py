#!/usr/bin/env python3
"""Print the PyPI SHA-256 hashes for privacyIDEA's platform-independent wheel."""
import json
import re
import sys
from pathlib import Path

version, metadata_path = sys.argv[1:]
metadata = json.loads(Path(metadata_path).read_text(encoding="utf-8"))
if metadata.get("info", {}).get("version") != version:
    raise SystemExit(f"PyPI metadata version does not match requested {version}")

hashes = sorted(
    {
        item.get("digests", {}).get("sha256", "")
        for item in metadata.get("urls", [])
        if item.get("packagetype") == "bdist_wheel"
        and item.get("filename", "").endswith("-py3-none-any.whl")
    }
)
if not hashes or any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in hashes):
    raise SystemExit(f"PyPI has no valid py3-none-any wheel hash for privacyIDEA {version}")
print(",".join(hashes))
