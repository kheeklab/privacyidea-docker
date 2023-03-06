#!/bin/bash

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

    # Configure Nginx.
    . configure_nginx.sh

    # Execute any pre-startup scripts.
    execute_scripts /usr/local/privacyidea/scripts/pre-startup

    # Start PrivacyIDEA.
    start_privacyidea

    # Execute any post-shutdown scripts.
    execute_scripts /usr/local/privacyidea/scripts/post-shutdown
}

# Define the function to start PrivacyIDEA.
function start_privacyidea {
    . start_privacyidea.sh
}

# Call the main function.
main
