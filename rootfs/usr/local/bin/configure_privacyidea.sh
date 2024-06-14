#!/bin/bash
set -e

source /usr/local/bin/_privacyidea_common.sh

function main {
    echo ""
    echo "             _                    _______  _______ "
    echo "   ___  ____(_)  _____ _______ __/  _/ _ \/ __/ _ |"
    echo '  / _ \/ __/ / |/ / _ `/ __/ // // // // / _// __ |'
    echo " / .__/_/ /_/|___/\_,_/\__/\_, /___/____/___/_/ |_|"
    echo "/_/                       /___/                    "
    echo ""
    echo "[PrivacyIDEA] Starting ${PrivacyIDEA}. To stop the container with CTRL-C, run this container with the option \"-it\"."
    echo ""

    generate_pi_config
    prestart_privacyidea
    exec /opt/privacyidea/bin/gunicorn -c /opt/privacyidea/gunicorn_conf.py "privacyidea.app:create_app(config_name='production', config_file='$PI_CFG_DIR/$PI_CFG_FILE')"
}

function generate_pi_config {

    # Common logic for checking and setting default values
    check_and_set_defaults() {
        [ -z "$PI_DB_HOST" ] && echo "[ERROR] PI_DB_HOST should be defined" && return 1
        [ -z "$PI_DB_USER" ] && echo "[ERROR] PI_DB_USER should be defined" && return 1
        [ -z "$PI_DB_PASSWORD" ] && echo "[ERROR] PI_DB_PASSWORD should be defined" && return 1
        [ -z "$PI_DB_NAME" ] && echo "[ERROR] PI_DB_NAME should be defined" && return 1

        # URL encode the password
        encoded_password=$(printf "%s" "$PI_DB_PASSWORD" | jq -s -R -r @uri)
    }

    # Check the selected database vendor
    case $PI_DB_VENDOR in
        "mariadb" | "mysql")
            echo "[INFO] Using $PI_DB_VENDOR ..."

            check_and_set_defaults

            # Define the SQLAlchemy database URI using the necessary variables
            if [ -z "$PI_DB_ARGS" ]; then
                export SQLALCHEMY_DATABASE_URI=${PI_DB_VENDOR}+pymysql://${PI_DB_USER}:${encoded_password}@${PI_DB_HOST}:${PI_DB_PORT:-3306}/${PI_DB_NAME}
            else
                export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+pymysql://${PI_DB_USER}:${encoded_password}@${PI_DB_HOST}:${PI_DB_PORT:-3306}/${PI_DB_NAME}?${PI_DB_ARGS//,/&}"
            fi
            ;;

        "postgresql")
            echo "Using $PI_DB_VENDOR..."

            check_and_set_defaults

            # Define the SQLAlchemy database URI using the necessary variables
            if [ -z "$PI_DB_ARGS" ]; then
                export SQLALCHEMY_DATABASE_URI=${PI_DB_VENDOR}+psycopg2://${PI_DB_USER}:${encoded_password}@/${PI_DB_NAME}?host=${PI_DB_HOST}&port=${PI_DB_HOST//[!,]/}
            else
                PI_DB_ARGS = ${PI_DB_ARGS// /}
                export SQLALCHEMY_DATABASE_URI="${PI_DB_VENDOR}+psycopg2://${PI_DB_USER}:${encoded_password}@/${PI_DB_NAME}?host=${PI_DB_HOST// /}&port=${PI_DB_PORT:-${PI_DB_HOST//[!,]/}}&${PI_DB_ARGS//,/&}"
            fi
            ;;

        *)
            echo ""
            echo "[WARNING] PI_DB_VENDOR environment variable is not set. Using default SQLite..."
            echo ""

            # Define the SQLAlchemy database URI for SQLite
            export SQLALCHEMY_DATABASE_URI=sqlite:////${PI_DATA_DIR}/privacyidea.db
            ;;
    esac

    # Check if the configuration file already exists
    if [ ! -f ${PI_CFG_DIR}/pi.cfg ]; then

        # Check if SQLALCHEMY_DATABASE_URI is defined
        if [ -z "$SQLALCHEMY_DATABASE_URI" ]; then
            echo ""
            echo "[WARNING] SQLALCHEMY_DATABASE_URI is undefined"
            echo ""
        else
            # Use the pi-config.template file as a template and substitute the necessary variables
            envsubst < /opt/templates/pi-config.template > ${PI_CFG_DIR}/pi.cfg
        fi
    fi

}

function prestart_privacyidea {

    # Copy files from mounted directory to PI_HOME
    if [ -d "${PI_MOUNT_DIR}/files" ] && [ "$(ls -A "${PI_MOUNT_DIR}/files")" ]; then
        echo ""
        echo "[privacyIDEA] Copying files from ${PI_MOUNT_DIR}/files:"
        echo ""
        tree --noreport "${PI_MOUNT_DIR}/files"
        echo ""
        echo "[privacyIDEA] ... into ${PI_HOME}."
        cp -r "${PI_MOUNT_DIR}/files"/* "${PI_HOME}"
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

        # Create keys directory if not exists
        if [ ! -d ${PI_DATA_DIR}/keys ]; then
            echo ""
            echo "[INFO] Creating keys directory..."
            echo ""
            mkdir ${PI_DATA_DIR}/keys
        fi

        # Create encryption key file if not exists
        if [ ! -f ${PI_DATA_DIR}/keys/encfile ]; then
            echo ""
            echo "[INFO]  Encryption key file not found, creating a new one..."
            echo ""
            pi-manage create_enckey
        fi

        # Create audit keys if not exists
        if [ ! -f ${PI_DATA_DIR}/keys/private.pem ]; then
            echo ""
            echo "[INFO] Creating audit keys..."
            echo ""
            pi-manage create_audit_keys
        fi

        # Create database tables
        echo ""
        echo "[INFO] Generating privacyIDEA database tables..."
        echo ""
        pi-manage create_tables

        # Create admin user if not specified through environment variables
        if [ -z "${PI_ADMIN_USER}" ] || [ -z "${PI_ADMIN_PASSWORD}" ]; then
            echo ""
            echo "[INFO]  Creating default admin user. [WARNING]: This is not recommended for production environments. Please set PI_ADMIN_USER and PI_ADMIN_PASSWORD environment variables to specify the admin user in production."
            echo ""
            pi-manage admin add admin -p privacyidea
        else
            echo ""
            echo "[INFO] Creating admin user from specified environment variables..."
            echo ""
            pi-manage admin add "${PI_ADMIN_USER}" -p "${PI_ADMIN_PASSWORD}"
        fi
    else
        echo ""
        echo "[INFO] Skipping key generation, table creation, and admin user creation."
        echo ""
    fi
}

main
