#!/bin/bash

set -e

function main {

    if [ -f /app/nginx.conf ]; then
        cp /app/nginx.conf /etc/nginx/nginx.conf
    else
        envsubst < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf
        envsubst < /etc/nginx/templates/pi.conf.template > /etc/nginx/conf.d/pi.conf
    fi
}

main
