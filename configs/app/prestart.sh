#!/bin/bash

if { [ "${DB_VENDOR}" = "mariadb" ] || [ "${DB_VENDOR}" = "mysql" ]; } then
    echo "Using $DB_VENDOR..."
    [ -z "$DB_HOST" ] && echo "DB_HOST should be defined" && return 1
    [ -z "$DB_USER" ] && echo "DB_USER should be defined" && return 1
    [ -z "$DB_PASSWORD" ] && echo "DB_PASSWORD should be defined" && return 1
    [ -z "$DB_NAME" ] && echo "DB_NAME should be defined" && return 1
    export SQLALCHEMY_DATABASE_URI=pymysql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}
elif { [ "${DB_VENDOR}" = "postgresql" ]; } then
    export SQLALCHEMY_DATABASE_URI=postgresql+pg8000://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}
else
    echo "DB_VENDOR enviroment varaible is not set. Using default SQLite..."
fi
if [ "${PI_SKIP_BOOTSTRAP}" = false ]; then
    if [ ! -f /etc/privacyidea/encfile ]; then
        pi-manage create_enckey
    fi
    if [ ! -d /etc/privacyidea/keys ]; then
        mkdir /etc/privacyidea/keys
    fi
    if [ ! -f /etc/privacyidea/keys/private.pem ]; then
        pi-manage create_audit_keys
    fi
    pi-manage createdb
    pi-manage db stamp head -d /opt/privacyidea/lib/privacyidea/migrations/
    #pi-manage db stamp head -d /usr/local/lib/privacyidea/migrations/
    if { [ "${PI_SKIP_BOOTSTRAP}" = false ] && [ -z ${PI_ADMIN_USER} ] && [ -z ${PI_ADMIN_PASSWORD} ]; } then
        echo "Create deafult admin user. Not recommented in production. Please set PI_ADMIN_USER and PI_ADMIN_PASSWORD in production enviroment."
        pi-manage admin add admin -p privacyidea
    else
        echo "Create admin user from definded enviroment variables."
        pi-manage admin add ${PI_ADMIN_USER} -p ${PI_ADMIN_PASSWORD}
    fi
fi
