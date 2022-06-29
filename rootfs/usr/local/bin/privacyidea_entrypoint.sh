#!/bin/bash

source /usr/local/bin/_privacyidea_common.sh

function main {
    echo "[PrivacyIDEA] To SSH into this container, run: \"docker exec -it ${HOSTNAME} /bin/bash\"."
    echo ""

    if [ -d /etc/privacyidea/mount ]
    then
        PI_MOUNT_DIR=/etc/privacyidea/mount
    else
        PI_MOUNT_DIR=/mnt/privacyidea
    fi

    export PI_MOUNT_DIR

    execute_scripts /usr/local/privacyidea/scripts/pre-configure

    . configure_nginx.sh

    execute_scripts /usr/local/privacyidea/scripts/pre-startup

    start_privacyidea

    execute_scripts /usr/local/privacyidea/scripts/post-shutdown
}

function start_privacyidea {
    . start_privacyidea.sh
}

main
