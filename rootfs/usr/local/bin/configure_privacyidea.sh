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

        # URL encode the password
        # TODO: Fix double-encoding bug - if password contains '%', jq encodes to %25,
        # and if it already contains %25 (URL-encoded %), it becomes %2525. This needs
        # proper URL encoding that handles already-encoded characters.
        encoded_password=$(printf "%s" "$PI_DB_PASSWORD" | jq -s -R -r @uri)
    }

    check_and_clean_vars() {
        local var_name="$1"
        local var_value="${!var_name}"

        if [ -z "$var_value" ]; then
            echo "[ERROR] $var_name should be defined"
            exit 1
        else
            # Remove single, double quotes and spaces
            var_value=${var_value//\'/}
            var_value=${var_value//\"/}
            var_value=${var_value// /}
            eval "$var_name='$var_value'"
        fi
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

            *)
                echo ""
                echo "[WARNING] PI_DB_VENDOR environment variable is not set. Using default SQLite..."
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
        esac
    fi

    # Check if the configuration file already exists
    if [ ! -f "${PI_CFG_DIR}/pi.cfg" ]; then
        # Check if SQLALCHEMY_DATABASE_URI is defined
        if [ -z "$SQLALCHEMY_DATABASE_URI" ]; then
            echo ""
            echo "[WARNING] SQLALCHEMY_DATABASE_URI is undefined"
            echo ""
        else
            # Use the pi-config.template file as a template and substitute the necessary variables
            envsubst < /opt/templates/pi-config.template > "${PI_CFG_DIR}/pi.cfg"
        fi
    fi
    
    # Update the log level
    sed -i -e "s/level: .*/level: ${PI_LOGLEVEL}/g" /opt/privacyidea/pi-logging.yml
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
        cp -RL "${PI_MOUNT_DIR}/files/"* "${PI_HOME}"
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

    # Generate keys, create tables, and admin user
    if [ "${PI_SKIP_BOOTSTRAP}" = false ]; then

        # Create database tables
        echo ""
        echo "[INFO] Generating privacyIDEA database tables..."
        echo ""
        pi-manage setup create_tables

        # Create keys directory if not exists
        if [ ! -d "${PI_DATA_DIR}/keys" ]; then
            echo ""
            echo "[INFO] Creating keys directory..."
            echo ""
            mkdir -p "${PI_DATA_DIR}/keys"
        fi

        # Create encryption key file if not exists or invalid
        if [ ! -f "${PI_DATA_DIR}/keys/encfile" ]; then
            echo ""
            echo "[INFO] Encryption key file not found, creating a new one..."
            echo ""
            pi-manage setup create_enckey
        elif [ ! -s "${PI_DATA_DIR}/keys/encfile" ]; then
            echo ""
            echo "[WARNING] Encryption key file is empty, recreating..."
            echo ""
            pi-manage setup create_enckey
        fi

        # Create audit keys if not exists
        if [ ! -f "${PI_DATA_DIR}/keys/private.pem" ]; then
            echo ""
            echo "[INFO] Creating audit keys..."
            echo ""
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
    else
        echo ""
        echo "[INFO] Skipping key generation, table creation, and admin user creation."
        echo ""
    fi

    if [ "${PI_SKIP_BOOTSTRAP}" = true ] && [ "${PI_AUTO_UPDATE}" = true ] ; then
        echo "Auto updating privacyIDEA..."
        if ! privacyidea-schema-upgrade /opt/privacyidea/lib/privacyidea/migrations; then
            echo "[ERROR] Schema upgrade failed. Check database connectivity and try again."
            exit 1
        fi
        echo "privacyIDEA successfully updated."
    fi
}

# Run configuration and setup
generate_pi_config
prestart_privacyidea
