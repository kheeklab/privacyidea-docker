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
                echo "[ERROR] Unsupported PI_DB_VENDOR '${PI_DB_VENDOR}'. Supported values: mariadb, mysql, postgresql, sqlite."
                echo ""
                exit 1
                ;;
        esac
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

        # Create admin user if not specified through environment variables
        if [ -z "${PI_ADMIN_USER}" ] || [ -z "${PI_ADMIN_PASSWORD}" ]; then
            if [[ "${SQLALCHEMY_DATABASE_URI}" == sqlite:* ]] || [ "${PI_DB_VENDOR}" = "sqlite" ]; then
                echo ""
                echo "[INFO] Creating default admin user for local SQLite setup."
                echo ""
                pi-manage admin add admin --password privacyidea
            else
                echo ""
                echo "[ERROR] PI_ADMIN_USER and PI_ADMIN_PASSWORD must be set for non-SQLite databases."
                echo ""
                exit 1
            fi
        else
            echo ""
            echo "[INFO] Creating admin user from specified environment variables..."
            echo ""
            pi-manage admin add "${PI_ADMIN_USER}" --password "${PI_ADMIN_PASSWORD}"
        fi

        touch "${PI_DATA_DIR}/.privacyidea_initialized"
        initialized=1
    fi

    if [ "${PI_AUTO_UPDATE}" = true ] && [ "$initialized" = 1 ]; then
        echo "Auto updating privacyIDEA..."
        if ! privacyidea-schema-upgrade -d /opt/privacyidea/lib/privacyidea/migrations; then
            echo "[ERROR] Schema upgrade failed. Check database connectivity and try again."
            exit 1
        fi
        echo "privacyIDEA successfully updated."
    fi
}

# Run configuration and setup
generate_pi_config
prestart_privacyidea
