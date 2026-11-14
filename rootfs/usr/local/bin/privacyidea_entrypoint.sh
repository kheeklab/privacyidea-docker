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

    if [ "${PI_SKIP_BOOTSTRAP:-false}" = true ] && [ "${PI_AUTO_UPDATE:-false}" = true ]; then
        echo "[ERROR] PI_AUTO_UPDATE cannot be used with PI_SKIP_BOOTSTRAP." >&2
        return 1
    fi

    # Validate before invoking hooks or writing configuration on a fresh start.
    if [ "${PI_SKIP_BOOTSTRAP:-false}" != true ] && [ ! -f "${PI_DATA_DIR}/.privacyidea_initialized" ]; then
        if [ -z "${PI_ADMIN_USER:-}" ] || [ -z "${PI_ADMIN_PASSWORD:-}" ]; then
            echo "[ERROR] PI_ADMIN_USER and PI_ADMIN_PASSWORD must both be set for initial bootstrap." >&2
            return 1
        fi
        echo "[ERROR] Automatic bootstrap is unavailable: no backend and topology combination is qualified." >&2
        return 1
    fi

    # Inspect marked installations before any image-controlled hook can mutate state.
    if [ "${PI_SKIP_BOOTSTRAP:-false}" != true ]; then
        /usr/local/bin/configure_privacyidea.sh --check-initialized
    fi

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
        TLS_BIND="${GUNICORN_BIND:-0.0.0.0:${PI_SSLPORT:-8443}}"
        exec /opt/privacyidea/bin/gunicorn \
            --certfile=/etc/privacyidea/server.crt \
            --keyfile=/etc/privacyidea/server.key \
            --bind "${TLS_BIND}" \
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
