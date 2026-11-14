#!/usr/bin/env python3
"""Correct the known privacyIDEA 3.14 English UI redirect at image build time.

The bundled login.py at 3.14 redirects the root path (/) to /app/v2/ (no locale
segment), but the route handler only exists for /app/v2/<locale>/. This causes
a 404 for the default English entry point. The correction targets /app/v2/en/.

Scoped strictly to privacyIDEA 3.14 and a known source hash. Refusing to apply
on any other version or unknown source content to prevent blind upstream patching.
"""
import hashlib
import importlib.metadata
import importlib.util
from pathlib import Path

if importlib.metadata.version('privacyidea') != '3.14':
    print('Default UI packaging correction is scoped to privacyIDEA 3.14; skipping.')
    raise SystemExit(0)

spec = importlib.util.find_spec('privacyidea.webui.login')
if spec is None or spec.origin is None:
    raise SystemExit('Cannot locate privacyIDEA UI entrypoint.')
path = Path(spec.origin)
original = path.read_bytes()
# SHA-256 of the unmodified privacyIDEA 3.14 login.py
expected_sha256 = '3c6509a88c1e34515e8f0ccade3866f4747340acf567dba9b0092b108c1df6a8'
old = b'return redirect(f"{request.script_root}/app/v2/")'
new = b'return redirect(f"{request.script_root}/app/v2/en/")'
if hashlib.sha256(original).hexdigest() != expected_sha256 or original.count(old) != 1:
    raise SystemExit('Unsupported privacyIDEA 3.14 UI source; refusing to patch.')
path.write_bytes(original.replace(old, new, 1))
print('Applied the privacyIDEA 3.14 English UI redirect correction.')
