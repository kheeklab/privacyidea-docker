#!/usr/bin/env bash
# Verify that the privacyIDEA 3.14 English redirect correction is applied in the image.
# Usage: IMAGE=<image-id> bash tests/test-ui-package.sh
set -eo pipefail

IMAGE="${IMAGE:?IMAGE is required}"

result=$(docker run --rm -i --network none --entrypoint /opt/privacyidea/bin/python \
  "$IMAGE" - <<'PY'
import importlib.util
from pathlib import Path
spec = importlib.util.find_spec('privacyidea.webui.login')
src = Path(spec.origin).read_bytes()
old = b'return redirect(f"{request.script_root}/app/v2/")'
new = b'return redirect(f"{request.script_root}/app/v2/en/")'
assert old not in src, "FAIL: original broken redirect still present"
assert new in src, "FAIL: corrected redirect not found"
print("PASS: English UI redirect correction applied")
PY
)
echo "$result"
[[ "$result" == *"PASS"* ]] || { echo "FAIL: UI package check"; exit 1; }
