#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="${repo_root}/scripts/resolve-pypi-artifact-hashes.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'fixture wheel for privacyIDEA 3.14\n' > "$tmp/3.14.whl"
printf 'fixture wheel for privacyIDEA 3.14.1\n' > "$tmp/3.14.1.whl"
hash_314="$(sha256sum "$tmp/3.14.whl" | cut -d' ' -f1)"
hash_3141="$(sha256sum "$tmp/3.14.1.whl" | cut -d' ' -f1)"

python3 - "$tmp" "$hash_314" "$hash_3141" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
for version, digest in zip(("3.14", "3.14.1"), sys.argv[2:]):
    metadata = {
        "info": {"version": version},
        "urls": [{
            "filename": f"privacyidea-{version}-py3-none-any.whl",
            "packagetype": "bdist_wheel",
            "digests": {"sha256": digest},
        }],
    }
    (root / f"{version}.json").write_text(json.dumps(metadata), encoding="utf-8")
PY

resolved_314="$(python3 "$resolver" 3.14 "$tmp/3.14.json")"
resolved_3141="$(python3 "$resolver" 3.14.1 "$tmp/3.14.1.json")"
[[ "$resolved_314" == "$hash_314" ]]
[[ "$resolved_3141" == "$hash_3141" ]]
[[ "$resolved_3141" != "$resolved_314" ]]
[[ "$resolved_3141" != 86a24cbffa8a7316eab93eb220b4d8710ea68af2390990d0dddd58d7bd6947b1 ]]

printf '%s  %s\n' "$resolved_3141" "$tmp/3.14.1.whl" | sha256sum -c - >/dev/null
printf 'tampered fixture\n' >> "$tmp/3.14.1.whl"
if printf '%s  %s\n' "$resolved_3141" "$tmp/3.14.1.whl" | sha256sum -c - >/dev/null 2>&1; then
  echo 'tampered artifact unexpectedly passed hash validation' >&2
  exit 1
fi

if python3 "$resolver" 3.14.1 "$tmp/3.14.json" >/dev/null 2>&1; then
  echo 'mismatched PyPI version metadata unexpectedly passed' >&2
  exit 1
fi

echo 'privacyIDEA artifact hash mapping and tamper checks passed'
