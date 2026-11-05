#!/bin/bash
# Regression test for PI_DB_PASSWORD encoding in configure_privacyidea.sh.
#
# Contract: PI_DB_PASSWORD is the plain password and must not be pre-encoded by the
# user. configure_privacyidea.sh percent-encodes it exactly once with
# `jq -s -R -r @uri` (configure_privacyidea.sh:32), then embeds it in the SQLAlchemy
# URI (configure_privacyidea.sh:72 for postgresql). A value encoded twice would round
# trip to a mangled password and this test must then fail.
#
# Usage: IMAGE=privacyidea:test bash tests/test-db-uri-encoding.sh
set -eu

IMAGE="${IMAGE:-privacyidea:test}"

# The encoding and URI construction below mirror configure_privacyidea.sh.
docker run --rm -i \
  -e PI_DB_VENDOR=postgresql \
  -e PI_DB_USER=u \
  -e PI_DB_HOST=h \
  -e PI_DB_NAME=d \
  -e PI_DB_PASSWORD='p@ss:w/rd%+x' \
  -e PYTHONDONTWRITEBYTECODE=1 \
  --entrypoint /bin/bash \
  "$IMAGE" -s <<'SCRIPT'
set -eu

encoded_password=$(printf "%s" "$PI_DB_PASSWORD" | jq -s -R -r @uri)
export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+psycopg2://${PI_DB_USER}:${encoded_password}@/${PI_DB_NAME}?host=${PI_DB_HOST}&port=${PI_DB_PORT:-5432}"

/opt/privacyidea/bin/python3 - "$PI_DB_PASSWORD" <<'PY'
import os
import sys

from sqlalchemy.engine import make_url

expected = sys.argv[1]
actual = make_url(os.environ["SQLALCHEMY_DATABASE_URI"]).password
if actual != expected:
    print(f"FAIL: password round-trip mismatch: expected {expected!r}, got {actual!r}",
          file=sys.stderr)
    sys.exit(1)
print("PASS: PI_DB_PASSWORD round-trips through a single jq @uri encoding")
PY
SCRIPT
