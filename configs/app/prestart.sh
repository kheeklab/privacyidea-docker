#!/bin/bash

if [ "${DB_VENDOR}" = "mariadb" ]; then
    echo "Using $DB_VENDOR..."
    [ -z "$DB_HOST" ] && echo "DB_HOST should be defined" && return 1
    [ -z "$DB_USER" ] && echo "DB_USER should be defined" && return 1
    [ -z "$DB_PASSWORD" ] && echo "DB_PASSWORD should be defined" && return 1
    [ -z "$DB_NAME" ] && echo "DB_NAME should be defined" && return 1
    export SQLALCHEMY_DATABASE_URI=pymysql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}
else
    echo "DB_VENDOR enviroment varaible is not set. Using default SQLite..."
fi
if [ "${PI_SKIP_BOOTSTRAP}" = false ]; then
    if [ ! -f /data/privacyidea/encfile ]; then
        pi-manage create_enckey
    fi
    if [ ! -d /data/privacyidea/keys ]; then
        mkdir /data/privacyidea/keys
    fi
    if [ ! -f /data/privacyidea/keys/private.pem ]; then
        pi-manage create_audit_keys
    fi
    pi-manage createdb
    pi-manage db stamp head -d /usr/local/lib/privacyidea//migrations/
    pi-manage admin add admin -p privacyidea
fi
