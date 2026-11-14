#!/usr/bin/env bash
set -eu
image=${IMAGE:-privacyidea:pers113-review}
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
chmod 755 "$test_dir"
mkdir "$test_dir/data"
chmod 777 "$test_dir/data"
touch "$test_dir/data/.privacyidea_initialized"
docker run --rm --network none -v "$test_dir/data:/data/privacyidea" \
    --entrypoint /opt/privacyidea/bin/python "$image" -c '
import os, sqlite3
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine
from privacyidea.models import db
import privacyidea
path = "/data/privacyidea/privacyidea.db"
db.metadata.create_all(create_engine("sqlite:////data/privacyidea/privacyidea.db"))
config = Config()
config.set_main_option("script_location", os.path.join(os.path.dirname(privacyidea.__file__), "migrations"))
with sqlite3.connect(path) as conn:
    conn.execute("CREATE TABLE alembic_version (version_num VARCHAR(32) NOT NULL)")
    conn.executemany("INSERT INTO alembic_version VALUES (?)", [(x,) for x in ScriptDirectory.from_config(config).get_heads()])
os.chmod(path, 0o666)
'
printf 'touch /data/privacyidea/hook-ran\n' > "$test_dir/hook.sh"
chmod 644 "$test_dir/hook.sh"
printf '#!/bin/sh\ntouch /data/privacyidea/upgrade-ran\n' > "$test_dir/upgrade.sh"
chmod 755 "$test_dir/upgrade.sh"
if docker run --rm --network none \
    -v "$test_dir/data:/data/privacyidea" \
    -v "$test_dir/hook.sh:/usr/local/privacyidea/scripts/pre-configure/test.sh:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/privacyidea_entrypoint.sh:/usr/local/bin/privacyidea_entrypoint.sh:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
    -v "$test_dir/upgrade.sh:/opt/privacyidea/bin/privacyidea-schema-upgrade:ro" \
    -e PI_SECRET_KEY=sentinel-secret -e PI_PEPPER=sentinel-pepper \
    "$image" > "$test_dir/log" 2>&1; then
    echo 'FAIL: entrypoint accepted initialized volume without keys' >&2
    exit 1
fi
if [ -e "$test_dir/data/hook-ran" ]; then
    echo 'FAIL: entrypoint ran a hook before checking initialized state' >&2
    exit 1
fi
run_config() {
    docker run --rm --network none \
    -v "$test_dir/data:/data/privacyidea" \
    -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
    -v "$test_dir/upgrade.sh:/opt/privacyidea/bin/privacyidea-schema-upgrade:ro" \
    -e PI_SECRET_KEY=sentinel-secret -e PI_PEPPER=sentinel-pepper \
    -e PI_SKIP_BOOTSTRAP="${skip:-false}" \
    -e PI_AUTO_UPDATE="${auto:-false}" \
    -e SQLALCHEMY_DATABASE_URI="${database_uri:-}" \
    --entrypoint /bin/bash "$image" /usr/local/bin/configure_privacyidea.sh > "$test_dir/log" 2>&1
}
if run_config; then
    echo 'FAIL: initialized volume with missing keys was accepted' >&2
    exit 1
fi
if grep -Eq 'sentinel-secret|sentinel-pepper' "$test_dir/log"; then
    echo 'FAIL: log contains secret' >&2
    exit 1
fi
test -e "$test_dir/data/privacyidea.db"
test -e "$test_dir/data/.privacyidea_initialized"
mkdir "$test_dir/data/keys"
printf 'enc' > "$test_dir/data/keys/encfile"
printf 'private' > "$test_dir/data/keys/private.pem"
printf 'public' > "$test_dir/data/keys/public.pem"
if run_config; then
    echo 'FAIL: malformed key material accepted' >&2
    exit 1
fi
chmod 777 "$test_dir/data/keys"
docker run --rm --network none --user 0:0 -v "$test_dir/data/keys:/keys" --entrypoint /opt/privacyidea/bin/python "$image" -c '
import os
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
open("/keys/encfile", "wb").write(os.urandom(96))
open("/keys/private.pem", "wb").write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))
open("/keys/public.pem", "wb").write(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
'
before=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
if ! run_config; then
    echo 'FAIL: accessible initialized database rejected' >&2
    sed -e 's/sentinel-secret/[redacted]/g' -e 's/sentinel-pepper/[redacted]/g' "$test_dir/log" >&2
    exit 1
fi
auto=true
if ! run_config; then
    echo 'FAIL: initialized head with auto-update rejected' >&2
    exit 1
fi
test ! -e "$test_dir/data/upgrade-ran" || { echo 'FAIL: head auto-update invoked upgrade' >&2; exit 1; }
auto=false
cp "$test_dir/data/keys/public.pem" "$test_dir/public.saved"
docker run --rm --network none --user 0:0 -v "$test_dir/data/keys:/keys" --entrypoint /opt/privacyidea/bin/python "$image" -c '
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
open("/keys/public.pem", "wb").write(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
'
if run_config; then
    echo 'FAIL: mismatched audit key pair accepted' >&2
    exit 1
fi
cp "$test_dir/public.saved" "$test_dir/data/keys/public.pem"
after=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
[ "$before" = "$after" ] || { echo 'FAIL: initialized state changed' >&2; exit 1; }
touch "$test_dir/data/.privacyidea_bootstrap_in_progress"
if docker run --rm --network none \
    -v "$test_dir/data:/data/privacyidea" \
    -v "$test_dir/hook.sh:/usr/local/privacyidea/scripts/pre-configure/test.sh:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/privacyidea_entrypoint.sh:/usr/local/bin/privacyidea_entrypoint.sh:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
    -e PI_SECRET_KEY=sentinel-secret -e PI_PEPPER=sentinel-pepper \
    "$image" > "$test_dir/log" 2>&1; then
    echo 'FAIL: entrypoint accepted conflicting local progress record' >&2
    exit 1
fi
if [ -e "$test_dir/data/hook-ran" ]; then
    echo 'FAIL: conflicting progress reached the hook' >&2
    exit 1
fi
if run_config; then
    echo 'FAIL: conflicting local progress record accepted' >&2
    exit 1
fi
rm "$test_dir/data/.privacyidea_bootstrap_in_progress"
touch "$test_dir/data/.privacyidea_bootstrap_complete"
if run_config; then
    echo 'FAIL: conflicting local completion record accepted' >&2
    exit 1
fi
rm "$test_dir/data/.privacyidea_bootstrap_complete"
python3 - "$test_dir/data/privacyidea.db" <<'PY'
import sqlite3
import sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute('CREATE TABLE privacyidea_bootstrap_state (id INTEGER)')
PY
if run_config; then
    echo 'FAIL: conflicting database progress record accepted' >&2
    exit 1
fi
python3 - "$test_dir/data/privacyidea.db" <<'PY'
import sqlite3
import sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute('DROP TABLE privacyidea_bootstrap_state')
PY
before=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
cp "$test_dir/data/privacyidea.db" "$test_dir/schema-original.db"
python3 - "$test_dir/data/privacyidea.db" <<'PY'
import sqlite3
import sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute('DROP TABLE token')
PY
if run_config; then
    echo 'FAIL: incomplete schema accepted' >&2
    exit 1
fi
cp "$test_dir/schema-original.db" "$test_dir/data/privacyidea.db"
before=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
database_uri='postgresql+psycopg2://user:sentinel-db-secret@127.0.0.1:1/test'
if run_config; then
    echo 'FAIL: inaccessible external database accepted' >&2
    exit 1
fi
if grep -Eq 'sentinel-secret|sentinel-pepper|sentinel-db-secret' "$test_dir/log"; then
    echo 'FAIL: database probe exposed a secret' >&2
    exit 1
fi
after=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
[ "$before" = "$after" ] || { echo 'FAIL: external probe changed local state' >&2; exit 1; }
database_uri=''
printf 'not a database' > "$test_dir/data/privacyidea.db"
before=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
if run_config; then
    echo 'FAIL: corrupt initialized database accepted' >&2
    exit 1
fi
after=$(sha256sum "$test_dir/data/keys/"* "$test_dir/data/privacyidea.db")
[ "$before" = "$after" ] || { echo 'FAIL: failed probe changed state' >&2; exit 1; }
skip=true
auto=true
if run_config; then
    echo 'FAIL: skip with auto-update was accepted' >&2
    exit 1
fi
test ! -e "$test_dir/data/upgrade-ran" || { echo 'FAIL: skip auto-update invoked upgrade' >&2; exit 1; }
if docker run --rm --network none \
    -v "$test_dir/data:/data/privacyidea" \
    -v "$test_dir/hook.sh:/usr/local/privacyidea/scripts/pre-configure/test.sh:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/privacyidea_entrypoint.sh:/usr/local/bin/privacyidea_entrypoint.sh:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
    -e PI_SKIP_BOOTSTRAP=true -e PI_AUTO_UPDATE=true \
    "$image" > "$test_dir/log" 2>&1; then
    echo 'FAIL: entrypoint accepted skip with auto-update' >&2
    exit 1
fi
test ! -e "$test_dir/data/hook-ran" || { echo 'FAIL: skip plus auto-update reached hook' >&2; exit 1; }
auto=false
if ! run_config; then
    echo 'FAIL: explicit skip without auto-update rejected' >&2
    exit 1
fi
if grep -Eq 'sentinel-secret|sentinel-pepper' "$test_dir/log"; then
    echo 'FAIL: log contains secret' >&2
    exit 1
fi
echo 'PASS: initialized key/database checks and skip override preserve state'
