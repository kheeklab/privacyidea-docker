#!/bin/bash
set -e

# This script sets up and starts PrivacyIDEA within a Docker container.

# Source the common functions used by PrivacyIDEA scripts.
source /usr/local/bin/_privacyidea_common.sh

function main {
    # Print a message indicating how to SSH into the container.
    echo "[PrivacyIDEA] To SSH into this container, run: \"docker exec -it ${HOSTNAME} /bin/bash\"."
    echo ""

    # Set the mount directory for configuration files.
    if [ -d /etc/privacyidea/mount ]
    then
        PI_MOUNT_DIR=/etc/privacyidea/mount
    else
        PI_MOUNT_DIR=/mnt/privacyidea
    fi
    export PI_MOUNT_DIR

    # Execute any pre-configuration scripts.
    execute_scripts /usr/local/privacyidea/scripts/pre-configure

    # Execute any pre-startup scripts.
    execute_scripts /usr/local/privacyidea/scripts/pre-startup

    # Configure and start PrivacyIDEA.
    # Source configure_privacyidea.sh which sets up config, DB, keys, and admin.
    . configure_privacyidea.sh

    echo "[PrivacyIDEA] Starting privacyIDEA. To stop the container with CTRL-C, run this container with the option \"-it\"."
    echo ""

    # After configure_privacyidea.sh returns, we exec into gunicorn.
    # This replaces the shell with gunicorn as a direct child of tini (PID 1),
    # so Docker's SIGTERM is received directly by gunicorn, enabling graceful shutdown.
    if [ -f /etc/privacyidea/server.key -a -f /etc/privacyidea/server.crt ]; then
        exec /opt/privacyidea/bin/gunicorn \
            --certfile=/etc/privacyidea/server.crt \
            --keyfile=/etc/privacyidea/server.key \
            --bind 0.0.0.0:${PI_SSLPORT:-8443} \
            -c /opt/privacyidea/gunicorn_conf.py \
            "privacyidea.app:create_app(config_name='production', config_file='$PI_CFG_DIR/$PI_CFG_FILE')"
    else
        exec /opt/privacyidea/bin/gunicorn \
            -c /opt/privacyidea/gunicorn_conf.py \
            "privacyidea.app:create_app(config_name='production', config_file='$PI_CFG_DIR/$PI_CFG_FILE')"
    fi
}

# Call the main function.
main
