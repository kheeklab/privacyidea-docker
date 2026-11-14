#!/bin/bash
set -e

# Source common functions and variables
source /usr/local/bin/_privacyidea_common.sh

# This script configures PrivacyIDEA: generates config, creates DB tables,
# encryption keys, audit keys, and admin user. Returns to entrypoint which
# then exec's into gunicorn.

echo ""
echo "             _                    _______  _______ "
echo "   ___  ____(_)  _____ _______ __/  _/ _ \/ __/ _ |"
echo '  / _ \/ __/ / |/ / _ `/ __/ // // // // / _// __ |'
echo " / .__/_/ /_/|___/\_,_/\__/\_, /___/____/___/_/ |_|"
echo "/_/                       /___/                    "
echo ""

# Function to generate PrivacyIDEA configuration
function generate_pi_config {
    check_and_set_defaults() {
        [ -z "$PI_DB_PASSWORD" ] && echo "[ERROR] PI_DB_PASSWORD should be defined" && exit 1
        check_and_clean_vars "PI_DB_HOST"
        check_and_clean_vars "PI_DB_USER"
        check_and_clean_vars "PI_DB_NAME"
        check_and_clean_vars "PI_DB_VENDOR"

        # PI_DB_PASSWORD is the plain password and must not be pre-encoded by the user.
        # Percent-encoding happens exactly once here, via jq @uri, so characters such as
        # '@', ':', '/', '%' and '+' are encoded correctly for the SQLAlchemy URI.
        encoded_password=$(printf "%s" "$PI_DB_PASSWORD" | jq -s -R -r @uri)
    }

    check_and_clean_vars() {
        local var_name="$1"
        local var_value="${!var_name}"

        if [ -z "$var_value" ]; then
            echo "[ERROR] $var_name should be defined"
            exit 1
        fi

        # Remove single, double quotes and spaces that would corrupt the URI.
        # Use printf -v instead of eval so the value is never executed.
        var_value=${var_value//\'/}
        var_value=${var_value//\"/}
        var_value=${var_value// /}
        printf -v "$var_name" '%s' "$var_value"
    }

    if [ -z "$SQLALCHEMY_DATABASE_URI" ]; then
        # Check the selected database vendor
        case $PI_DB_VENDOR in
            "mariadb" | "mysql")
                echo "[INFO] Using $PI_DB_VENDOR ..."
                check_and_set_defaults
                # Define the SQLAlchemy database URI using the necessary variables
                if [ -z "$PI_DB_ARGS" ]; then
                    export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+pymysql://${PI_DB_USER}:${encoded_password}@${PI_DB_HOST}:${PI_DB_PORT:-3306}/${PI_DB_NAME}"
                else
                    # Remove double quotes and spaces
                    check_and_clean_vars "PI_DB_ARGS"
                    export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+pymysql://${PI_DB_USER}:${encoded_password}@${PI_DB_HOST}:${PI_DB_PORT:-3306}/${PI_DB_NAME}?${PI_DB_ARGS//,/\&}"
                fi
                ;;

            "postgresql")
                echo "[INFO] Using $PI_DB_VENDOR..."
                check_and_set_defaults
                # Define the SQLAlchemy database URI using the necessary variables
                if [ -z "$PI_DB_ARGS" ]; then
                    export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+psycopg2://${PI_DB_USER}:${encoded_password}@/${PI_DB_NAME}?host=${PI_DB_HOST}&port=${PI_DB_PORT:-5432}"
                else
                    check_and_clean_vars "PI_DB_ARGS"
                    export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+psycopg2://${PI_DB_USER}:${encoded_password}@/${PI_DB_NAME}?host=${PI_DB_HOST}&port=${PI_DB_PORT:-5432}&${PI_DB_ARGS//,/\&}"
                fi
                ;;

            "sqlite" | "")
                echo ""
                echo "[INFO] Using SQLite database."
                echo ""

                # Validate PI_DATA_DIR exists and is writable before using SQLite
                if [ ! -d "$PI_DATA_DIR" ]; then
                    echo "[ERROR] PI_DATA_DIR ($PI_DATA_DIR) does not exist or is not a directory."
                    exit 1
                fi
                if [ ! -w "$PI_DATA_DIR" ]; then
                    echo "[ERROR] PI_DATA_DIR ($PI_DATA_DIR) is not writable."
                    exit 1
                fi

                # Define the SQLAlchemy database URI for SQLite
                export SQLALCHEMY_DATABASE_URI=sqlite:////${PI_DATA_DIR}/privacyidea.db
                ;;
            *)
                echo ""
                echo "[ERROR] Unsupported PI_DB_VENDOR. Supported values: mariadb, mysql, postgresql, sqlite."
                echo ""
                exit 1
                ;;
        esac
    fi

    # A legacy completion marker does not authorize replacing missing keys.
    # Skip mode is an explicit external-provisioning override.
    if [ "${PI_SKIP_BOOTSTRAP:-false}" != true ] && [ -f "${PI_DATA_DIR}/.privacyidea_initialized" ]; then
        for state_file in "${PI_DATA_DIR}/.privacyidea_bootstrap_in_progress" "${PI_DATA_DIR}/.privacyidea_bootstrap_complete"; do
            if [ -e "$state_file" ] || [ -L "$state_file" ]; then
                echo "[ERROR] Conflicting bootstrap state requires operator assessment." >&2
                exit 1
            fi
        done
        export PI_ENCFILE="${PI_ENCFILE:-${PI_DATA_DIR}/keys/encfile}"
        export PI_AUDIT_KEY_PRIVATE_PATH="${PI_AUDIT_KEY_PRIVATE_PATH:-${PI_DATA_DIR}/keys/private.pem}"
        export PI_AUDIT_KEY_PUBLIC_PATH="${PI_AUDIT_KEY_PUBLIC_PATH:-${PI_DATA_DIR}/keys/public.pem}"
        for key_file in "$PI_ENCFILE" "$PI_AUDIT_KEY_PRIVATE_PATH" "$PI_AUDIT_KEY_PUBLIC_PATH"; do
            if [ ! -f "$key_file" ] || [ ! -s "$key_file" ] || [ ! -r "$key_file" ]; then
                echo "[ERROR] Initialized installation has missing, empty, or unreadable key material; restore a consistent backup." >&2
                exit 1
            fi
        done
        # Do not leak URI, driver errors, or credentials from the probe.
        if ! /opt/privacyidea/bin/python - <<'PY'
import os
import sqlite3
import stat
from alembic.config import Config
from alembic.script import ScriptDirectory
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from privacyidea.models import db as privacyidea_db
import privacyidea
from sqlalchemy.engine import make_url

try:
    # The built-in 3.14 security module uses a 96-byte encryption key and
    # an RSA audit key pair. These checks do not establish DB/key identity.
    def _read_key_noatime(path, maximum_size):
        """Read one unchanged, unaliased key file without updating its atime."""
        before_path = os.stat(path, follow_symlinks=False)
        if (not stat.S_ISREG(before_path.st_mode) or before_path.st_nlink != 1
                or before_path.st_size <= 0 or before_path.st_size > maximum_size):
            raise ValueError('Unqualified key file')
        descriptor = os.open(path, os.O_RDONLY | os.O_NOATIME | os.O_NOFOLLOW)
        try:
            before = os.fstat(descriptor)
            identity = lambda value: (value.st_dev, value.st_ino, value.st_mode,
                                      value.st_nlink, value.st_uid, value.st_gid,
                                      value.st_size, value.st_mtime_ns, value.st_ctime_ns,
                                      value.st_atime_ns)
            if identity(before_path) != identity(before):
                raise ValueError('Key file changed before read')
            chunks = []
            total = 0
            while True:
                chunk = os.read(descriptor, min(65536, maximum_size + 1 - total))
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
                if total > maximum_size:
                    raise ValueError('Key file too large')
            after = os.fstat(descriptor)
            after_path = os.stat(path, follow_symlinks=False)
            if identity(before) != identity(after) or identity(before) != identity(after_path):
                raise ValueError('Key file changed during read')
        finally:
            os.close(descriptor)
        return b''.join(chunks)
    enc_data = _read_key_noatime(os.environ['PI_ENCFILE'], 96)
    if len(enc_data) != 96:
        raise ValueError('Invalid encryption key')
    private_key = serialization.load_pem_private_key(
        _read_key_noatime(os.environ['PI_AUDIT_KEY_PRIVATE_PATH'], 65536), password=None)
    public_key = serialization.load_pem_public_key(
        _read_key_noatime(os.environ['PI_AUDIT_KEY_PUBLIC_PATH'], 65536))
    if not isinstance(private_key, rsa.RSAPrivateKey) or not isinstance(public_key, rsa.RSAPublicKey):
        raise ValueError('Invalid audit key type')
    if private_key.public_key().public_numbers() != public_key.public_numbers():
        raise ValueError('Audit key pair mismatch')
    uri = os.environ['SQLALCHEMY_DATABASE_URI']
    url = make_url(uri)
    backend = url.get_backend_name()
    if backend == 'sqlite':
        path = url.database
        if url.query or not path or path == ':memory:' or not os.path.isfile(path):
            raise ValueError('SQLite database unavailable')
        # Never open the persistent database through SQLite: even mode=ro can
        # create or update WAL shared-memory files. WAL and hot-journal states
        # are unsupported; inspect only a stable, bounded in-memory snapshot.
        path = os.path.realpath(path)
        sidecars = tuple(path + suffix for suffix in ('-wal', '-shm', '-journal'))
        if any(os.path.lexists(sidecar) for sidecar in sidecars) or not hasattr(os, 'O_NOATIME'):
            raise ValueError('Unqualified SQLite sidecar state')
        path_before = os.stat(path, follow_symlinks=False)
        if not stat.S_ISREG(path_before.st_mode) or path_before.st_nlink != 1:
            raise ValueError('Unqualified SQLite file links or type')
        descriptor = os.open(path, os.O_RDONLY | os.O_NOATIME | os.O_NOFOLLOW)
        try:
            before = os.fstat(descriptor)
            if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1
                    or before.st_size < 100 or before.st_size > 64 * 1024 * 1024):
                raise ValueError('Unqualified SQLite snapshot size, links, or type')
            identity = lambda value: (value.st_dev, value.st_ino, value.st_nlink, value.st_size, value.st_mtime_ns, value.st_ctime_ns)
            if identity(path_before) != identity(before):
                raise ValueError('SQLite changed before snapshot')
            chunks = []
            remaining = before.st_size
            while remaining:
                chunk = os.read(descriptor, min(remaining, 1024 * 1024))
                if not chunk:
                    raise ValueError('Incomplete SQLite snapshot')
                chunks.append(chunk)
                remaining -= len(chunk)
            after = os.fstat(descriptor)
            current = os.stat(path, follow_symlinks=False)
            if (after.st_nlink != 1 or current.st_nlink != 1
                    or identity(before) != identity(after) or identity(before) != identity(current)):
                raise ValueError('SQLite changed during snapshot')
        finally:
            os.close(descriptor)
        if any(os.path.lexists(sidecar) for sidecar in sidecars):
            raise ValueError('Unqualified SQLite sidecar state')
        snapshot = b''.join(chunks)
        if snapshot[:16] != b'SQLite format 3\x00' or snapshot[18:20] != b'\x01\x01':
            raise ValueError('Unqualified SQLite journal mode')
        with sqlite3.connect(':memory:') as db:
            db.deserialize(snapshot)
            db.execute('PRAGMA temp_store=MEMORY')
            db.execute('SELECT 1').fetchone()
            if db.execute('PRAGMA quick_check').fetchone() != ('ok',):
                raise ValueError('Database integrity check failed')
            objects = {row[0].lower() for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view', 'trigger')"
            )}
            table_names = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            expected_tables = privacyidea_db.metadata.tables
            if not set(expected_tables).issubset(table_names):
                raise ValueError('Incomplete schema')
            for name, table in expected_tables.items():
                quoted_name = '"' + name.replace('"', '""') + '"'
                columns = {row[1] for row in db.execute('PRAGMA table_info(' + quoted_name + ')')}
                if not {column.name for column in table.columns}.issubset(columns):
                    raise ValueError('Incomplete schema')
            config = Config()
            config.set_main_option('script_location', os.path.join(os.path.dirname(privacyidea.__file__), 'migrations'))
            expected_revisions = set(ScriptDirectory.from_config(config).get_heads())
            rows = [row[0] for row in db.execute('SELECT version_num FROM alembic_version')]
            actual_revisions = set(rows)
            if not expected_revisions or len(rows) != len(actual_revisions) or actual_revisions != expected_revisions:
                raise ValueError('Unknown migration state')
    elif backend in ('postgresql', 'mysql', 'mariadb'):
        # Catalog visibility and cross-schema progress state are unqualified.
        raise ValueError('Database catalog visibility cannot be established')
    else:
        raise ValueError('Unsupported database')
    if not {'admin', 'config', 'token'} <= objects or 'privacyidea_bootstrap_state' in objects:
        raise ValueError('Incomplete or conflicting database state')
except Exception:
    raise SystemExit(1)
PY
        then
            echo "[ERROR] Initialized database could not be inspected; check connectivity and restore a consistent backup if needed." >&2
            exit 1
        fi
    fi

    if [ "${1:-}" = --check-initialized ]; then
        return 0
    fi

    # Always (re)generate the config from the template. pi.cfg is generated
    # output driven by environment variables, never hand-edited, so environment
    # changes must be reflected on every start. Use PI_CFG_FILE so the written
    # path matches what gunicorn loads.
    if [ -z "$SQLALCHEMY_DATABASE_URI" ]; then
        echo ""
        echo "[WARNING] SQLALCHEMY_DATABASE_URI is undefined"
        echo ""
    else
        # Use the pi-config.template file as a template and substitute the necessary variables
        envsubst < /opt/templates/pi-config.template > "${PI_CFG_DIR}/${PI_CFG_FILE}.tmp"
        mv "${PI_CFG_DIR}/${PI_CFG_FILE}.tmp" "${PI_CFG_DIR}/${PI_CFG_FILE}"
    fi
    
    # Normalize PI_LOGLEVEL to a valid logging level name before editing the
    # YAML; an unset or arbitrary value would corrupt the sed replacement.
    case "${PI_LOGLEVEL:-INFO}" in
        DEBUG|INFO|WARNING|ERROR|CRITICAL) ;;
        *) PI_LOGLEVEL=INFO ;;
    esac
    # Update the log level
    sed -i -e "s/level: .*/level: ${PI_LOGLEVEL}/g" /opt/privacyidea/pi-logging.yml

    # App logs go to stdout (console handler) by default. Setting PI_LOGFILE to a real
    # path switches the privacyidea logger to the rotating file handler instead. A pipe
    # (/dev/stdout, /dev/stderr) is never handed to RotatingFileHandler, which cannot seek.
    case "${PI_LOGFILE:-}" in
        "" | /dev/stdout | /dev/stderr)
            ;;
        *)
            python3 - <<'PY'
import json
import os
import re
from pathlib import Path

logging_config = Path("/opt/privacyidea/pi-logging.yml")
contents = logging_config.read_text()

contents, count = re.subn(
    r"(?m)^([ \t]*filename:[ \t]*).*$",
    lambda match: match.group(1) + json.dumps(os.environ["PI_LOGFILE"]),
    contents,
)
if count != 1:
    raise ValueError(f"Expected one log filename in {logging_config}, found {count}")

contents, count = re.subn(
    r"(?m)^([ \t]*handlers:[ \t]*\[)[^\]]*(\])",
    lambda match: match.group(1) + "file" + match.group(2),
    contents,
)
if count != 1:
    raise ValueError(f"Expected one logger handlers line in {logging_config}, found {count}")

logging_config.write_text(contents)
PY
            ;;
    esac
}

# Function to perform pre-start tasks for PrivacyIDEA
function prestart_privacyidea {
    # Copy files from mounted directory to PI_HOME
    PI_HOME=${PI_HOME:-/opt/privacyidea}

    export PI_HOME

    if [ -d "${PI_MOUNT_DIR}/files" ] && [ "$(ls -A "${PI_MOUNT_DIR}/files")" ]; then
        echo ""
        echo "[privacyIDEA] Copying files from ${PI_MOUNT_DIR}/files:"
        echo ""
        tree --noreport "${PI_MOUNT_DIR}/files"
        echo ""
        echo "[privacyIDEA] ... into ${PI_HOME}."
        cp -RL "${PI_MOUNT_DIR}/files/." "${PI_HOME}/"
        echo ""
    else
        echo ""
        echo "[privacyIDEA] The directory ${PI_MOUNT_DIR}/files does not exist or is empty. Copy any files to this directory to have them copied to ${PI_HOME} before privacyIDEA starts."
        echo ""
    fi

    # Execute scripts from mounted directory
    if [ -d "${PI_MOUNT_DIR}/scripts" ]; then
        execute_scripts "${PI_MOUNT_DIR}/scripts"
    else
        echo ""
        echo "[privacyIDEA] The directory ${PI_MOUNT_DIR}/scripts does not exist. Copy any scripts to this directory to have them executed, in alphabetical order, before privacyIDEA starts."
        echo ""
    fi

    # Resolve key file paths once, so the existence guards below and
    # privacyIDEA (which reads these via pi.cfg) always agree, even when
    # PI_DATA_DIR or the key path variables are overridden.
    export PI_ENCFILE="${PI_ENCFILE:-${PI_DATA_DIR}/keys/encfile}"
    export PI_AUDIT_KEY_PRIVATE_PATH="${PI_AUDIT_KEY_PRIVATE_PATH:-${PI_DATA_DIR}/keys/private.pem}"
    export PI_AUDIT_KEY_PUBLIC_PATH="${PI_AUDIT_KEY_PUBLIC_PATH:-${PI_DATA_DIR}/keys/public.pem}"

    # A marker records a completed bootstrap. Without it, every restart would
    # re-run `pi-manage admin add` (resetting the admin password) and
    # `create_tables`.
    initialized=0
    if [ -f "${PI_DATA_DIR}/.privacyidea_initialized" ]; then
        initialized=1
    fi

    if [ "${PI_SKIP_BOOTSTRAP}" = true ]; then
        echo ""
        echo "[INFO] Skipping key generation, table creation, and admin user creation."
        echo ""
        initialized=1
    elif [ "$initialized" = 1 ]; then
        echo ""
        echo "[INFO] privacyIDEA already initialized; skipping bootstrap."
        echo ""
    else
        # Fresh bootstrap: create tables, keys, and admin exactly once.

        # For a non-SQLite database, refuse to regenerate keys when the
        # database already contains privacyIDEA data but the key files are
        # missing. New keys cannot decrypt existing tokens; restore the key
        # volume instead.
        if [ -n "$SQLALCHEMY_DATABASE_URI" ] && [[ "$SQLALCHEMY_DATABASE_URI" != sqlite:* ]] && [ ! -f "$PI_ENCFILE" ]; then
            schema_present=$(/opt/privacyidea/bin/python - "$SQLALCHEMY_DATABASE_URI" <<'PY'
import sys
from sqlalchemy import create_engine, inspect
try:
    tables = set(inspect(create_engine(sys.argv[1])).get_table_names())
    if {"token", "admin", "alembic_version"} & tables:
        print("yes")
except Exception:
    pass
PY
)
            if [ "$schema_present" = "yes" ]; then
                echo "[ERROR] Database already contains privacyIDEA data, but the encryption key ($PI_ENCFILE) is missing." >&2
                echo "[ERROR] Refusing to regenerate keys: new keys cannot decrypt existing tokens. Restore your key volume." >&2
                exit 1
            fi
        fi

        # Create database tables
        echo ""
        echo "[INFO] Generating privacyIDEA database tables..."
        echo ""
        pi-manage setup create_tables

        # Create encryption key file if missing or empty
        if [ ! -f "$PI_ENCFILE" ] || [ ! -s "$PI_ENCFILE" ]; then
            echo ""
            echo "[INFO] Encryption key file not found or empty, creating a new one..."
            echo ""
            mkdir -p "$(dirname "$PI_ENCFILE")"
            pi-manage setup create_enckey
        fi

        # Create audit keys if missing
        if [ ! -f "$PI_AUDIT_KEY_PRIVATE_PATH" ]; then
            echo ""
            echo "[INFO] Creating audit keys..."
            echo ""
            mkdir -p "$(dirname "$PI_AUDIT_KEY_PRIVATE_PATH")"
            pi-manage setup create_audit_keys
        fi

        # Do not create an administrator without explicitly supplied credentials.
        if [ -z "${PI_ADMIN_USER}" ] || [ -z "${PI_ADMIN_PASSWORD}" ]; then
            echo "[ERROR] PI_ADMIN_USER and PI_ADMIN_PASSWORD must both be set for initial bootstrap." >&2
            exit 1
        else
            echo ""
            echo "[INFO] Creating admin user from specified environment variables..."
            echo ""
            pi-manage admin add "${PI_ADMIN_USER}" --password "${PI_ADMIN_PASSWORD}"
        fi

        touch "${PI_DATA_DIR}/.privacyidea_initialized"
        initialized=1
    fi

    if [ "${PI_AUTO_UPDATE:-false}" = true ] && [ "$initialized" = 1 ]; then
        echo "[INFO] Schema is already at the verified head; automatic migration is disabled."
    fi
}

# Defense in depth for direct invocation, before configuration or hooks mutate state.
if [ "${PI_SKIP_BOOTSTRAP:-false}" = true ] && [ "${PI_AUTO_UPDATE:-false}" = true ]; then
    echo "[ERROR] PI_AUTO_UPDATE cannot be used with PI_SKIP_BOOTSTRAP." >&2
    exit 1
fi
if [ "${PI_SKIP_BOOTSTRAP:-false}" != true ] && [ ! -f "${PI_DATA_DIR}/.privacyidea_initialized" ]; then
    echo "[ERROR] Automatic bootstrap is unavailable: no backend and topology combination is qualified." >&2
    exit 1
fi

# The entrypoint invokes this read-only path in a child before running hooks.
if [ "${1:-}" = --check-initialized ]; then
    generate_pi_config --check-initialized
    exit 0
fi

# Run configuration and setup
generate_pi_config
prestart_privacyidea
