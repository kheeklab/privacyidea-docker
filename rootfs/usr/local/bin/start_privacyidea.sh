#!/bin/bash
set -e

source /usr/local/bin/_privacyidea_common.sh

function main {
    echo ""
    echo "[PrivacyIDEA] Starting ${PrivacyIDEA}. To stop the container with CTRL-C, run this container with the option \"-it\"."
    echo ""

    generate_pi_config
    prestart_privacyidea
    exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
}

function generate_pi_config {

    # Check the selected database vendor
    if [ "${DB_VENDOR}" = "mariadb" ] || [ "${DB_VENDOR}" = "mysql" ]; then
        echo "Using $DB_VENDOR..."

        # Ensure that the necessary variables are defined
        [ -z "$DB_HOST" ] && echo "DB_HOST should be defined" && return 1
        [ -z "$DB_USER" ] && echo "DB_USER should be defined" && return 1
        [ -z "$DB_PASSWORD" ] && echo "DB_PASSWORD should be defined" && return 1
        [ -z "$DB_NAME" ] && echo "DB_NAME should be defined" && return 1

        # Set the default port if it is not defined
        if [ -z "$DB_PORT" ]; then
            echo DB_PORT is not defined using default port
            export DB_PORT=3306
        fi

        # Define the SQLAlchemy database URI using the necessary variables
        export SQLALCHEMY_DATABASE_URI=pymysql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}

    elif [ "${DB_VENDOR}" = "postgresql" ]; then
        echo "Using $DB_VENDOR..."

        # Ensure that the necessary variables are defined
        [ -z "$DB_HOST" ] && echo "DB_HOST should be defined" && return 1
        [ -z "$DB_USER" ] && echo "DB_USER should be defined" && return 1
        [ -z "$DB_PASSWORD" ] && echo "DB_PASSWORD should be defined" && return 1
        [ -z "$DB_NAME" ] && echo "DB_NAME should be defined" && return 1

        # Set the default port if it is not defined
        if [ -z "$DB_PORT" ]; then
            echo DB_PORT is not defined using default port
            export DB_PORT=5432
        fi

        # Define the SQLAlchemy database URI using the necessary variables
        export SQLALCHEMY_DATABASE_URI=postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}

    else
        echo "DB_VENDOR environment variable is not set. Using default SQLite..."
        echo ""

        # Define the SQLAlchemy database URI for SQLite
        export SQLALCHEMY_DATABASE_URI=sqlite://///data/privacyidea/privacyidea.db
    fi

    # Check if the configuration file already exists
    if [ ! -f /etc/privacyidea/pi.cfg ]; then

        # Check if SQLALCHEMY_DATABASE_URI is defined
        if [ -z "$SQLALCHEMY_DATABASE_URI" ]; then
            echo "SQLALCHEMY_DATABASE_URI is undefined"
        else
            # Use the pi-config.template file as a template and substitute the necessary variables
            envsubst < /opt/templates/pi-config.template > /etc/privacyidea/pi.cfg
        fi
    fi

}

function prestart_privacyidea {

    # Copy files from mounted directory to PI_HOME
    if [ -d "${PI_MOUNT_DIR}/files" ] && [ "$(ls -A "${PI_MOUNT_DIR}/files")" ]; then
        echo "[privacyIDEA] Copying files from ${PI_MOUNT_DIR}/files:"
        echo ""
        tree --noreport "${PI_MOUNT_DIR}/files"
        echo ""
        echo "[privacyIDEA] ... into ${PI_HOME}."
        cp -r "${PI_MOUNT_DIR}/files"/* "${PI_HOME}"
        echo ""
    else
        echo "[privacyIDEA] The directory ${PI_MOUNT_DIR}/files does not exist or is empty. Copy any files to this directory to have them copied to ${PI_HOME} before privacyIDEA starts."
        echo ""
    fi

    # Execute scripts from mounted directory
    if [ -d "${PI_MOUNT_DIR}/scripts" ]; then
        execute_scripts "${PI_MOUNT_DIR}/scripts"
    else
        echo "[privacyIDEA] The directory ${PI_MOUNT_DIR}/scripts does not exist. Copy any scripts to this directory to have them executed, in alphabetical order, before privacyIDEA starts."
        echo ""
    fi

    # Generate keys, create tables, and admin user
    if [ "${PI_SKIP_BOOTSTRAP}" = false ]; then

        # Create keys directory if not exists
        if [ ! -d /data/privacyidea/keys ]; then
            echo "Creating keys directory..."
            mkdir /data/privacyidea/keys
        fi

        # Create encryption key file if not exists
        if [ ! -f /data/privacyidea/keys/encfile ]; then
            echo "Encryption key file not found, creating a new one..."
            pi-manage create_enckey
        fi

        # Create audit keys if not exists
        if [ ! -f /data/privacyidea/keys/private.pem ]; then
            echo "Creating audit keys..."
            pi-manage create_audit_keys
        fi

        # Create database tables
        echo "Generating privacyIDEA database tables..."
        pi-manage create_tables

        # Create admin user if not specified through environment variables
        if [ -z "${PI_ADMIN_USER}" ] || [ -z "${PI_ADMIN_PASSWORD}" ]; then
            echo "Creating default admin user. WARNING: This is not recommended for production environments. Please set PI_ADMIN_USER and PI_ADMIN_PASSWORD environment variables to specify the admin user in production."
            pi-manage admin add admin -p privacyidea
        else
            echo "Creating admin user from specified environment variables..."
            pi-manage admin add "${PI_ADMIN_USER}" -p "${PI_ADMIN_PASSWORD}"
        fi
    else
        echo "Skipping key generation, table creation, and admin user creation."
    fi
}


main
