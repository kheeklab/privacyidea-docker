#!/usr/bin/env bash
set -eo pipefail

# This provisions disposable CI state with explicit upstream setup commands.
# It tests PI_SKIP_BOOTSTRAP startup only; it does not qualify automatic bootstrap.
export SQLALCHEMY_DATABASE_URI=
source /usr/local/bin/configure_privacyidea.sh

# Compose may rerun a completed one-shot service when the stack is restarted.
# Reuse, validate, and never overwrite its persistent database or keys.
if [ -f "${PI_DATA_DIR}/.privacyidea_initialized" ]; then
    test -s "$PI_ENCFILE" && test -s "$PI_AUDIT_KEY_PRIVATE_PATH" && test -s "$PI_AUDIT_KEY_PUBLIC_PATH" || {
        echo "Existing disposable fixture marker has missing key files; preserve and inspect its volumes." >&2
        exit 1
    }
    /opt/privacyidea/bin/python - "$PI_DATA_DIR/privacyidea.db" "$PI_ADMIN_USER" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
if not {"admin", "alembic_version"}.issubset(tables):
    raise SystemExit("Existing disposable fixture database lacks required tables")
if connection.execute("SELECT 1 FROM admin WHERE username = ?", (sys.argv[2],)).fetchone() is None:
    raise SystemExit("Existing disposable fixture does not contain the requested admin")
PY
    echo "Existing disposable fixture database and keys validated; preserved."
    exit 0
fi

echo "Provisioning disposable SQLite schema"
pi-manage setup create_tables
mkdir -p "$(dirname "$PI_ENCFILE")" "$(dirname "$PI_AUDIT_KEY_PRIVATE_PATH")"
echo "Provisioning disposable encryption key"
pi-manage setup create_enckey
echo "Provisioning disposable audit keys"
pi-manage setup create_audit_keys
echo "Provisioning disposable administrator"
pi-manage admin add "$PI_ADMIN_USER" --password "$PI_ADMIN_PASSWORD"
touch "${PI_DATA_DIR}/.privacyidea_initialized"
echo "Disposable fixture provisioning complete"
