#!/bin/bash

set -e

function main {

    envsubst < /opt/templates/nginx.conf.template > /etc/nginx/nginx.conf
    envsubst < /opt/templates/nginx-pi.conf.template > /etc/nginx/conf.d/pi.conf
    if [ "$NGINX_SSL_ENABLED" = true ]; then
        if [ -z "$NGINX_SSL_CERT" ] && [ -z "$NGINX_SSL_CERT" ];
        then
            echo "SSL enabled but NGINX_SSL_CERT and NGINX_SSL_KEY are not defined, using generated certifiacate"
            echo "Generate self signed certificate"
            generate_cert
            echo ""
            echo "Finished generate certificates"

            export NGINX_SSL_CERT=/etc/nginx/certs/pi-server-cert.pem
            export NGINX_SSL_KEY=/etc/nginx/certs/pi-server-key.pem
        fi
        envsubst < /opt/templates/nginx-pi-ssl.conf.template > /etc/nginx/conf.d/pi-ssl.conf
    fi

}

function generate_cert {

    # Create certificate directory
    mkdir -p /etc/nginx/certs

    # [ global parameters ]
    # certificate configuration
    readonly CERT_DAYS=36500
    readonly RSA_STR_LEN=4096
    readonly PREFIX=pi-
    readonly CERT_DIR=/etc/nginx/certs
    readonly KEY_DIR=/etc/nginx/certs
    # certificate content definition
    readonly ADDRESS_COUNTRY_CODE=KH
    readonly ADDRESS_PREFECTURE=PI
    readonly ADDRESS_CITY='Phnom Penh'
    readonly COMPANY_NAME=Khalibre
    readonly COMPANY_SECTION=DevOps
    readonly CERT_PASSWORD= # no password
    # - ca
    readonly CA_DOMAIN='Khalibre DevOps'
    readonly CA_EMAIL=ca@email.address
    # - server
    readonly SERVER_DOMAIN=localhost
    readonly SERVER_EMAIL=server@email.address

    # [ functions ]
    echo_cert_params() {
        local company_domain="$1"
        local company_email="$2"

        echo $ADDRESS_COUNTRY_CODE
        echo $ADDRESS_PREFECTURE
        echo $ADDRESS_CITY
        echo $COMPANY_NAME
        echo $COMPANY_SECTION
        echo $company_domain
        echo $company_email
        echo $CERT_PASSWORD     # password
        echo $CERT_PASSWORD     # password (again)
        }
        echo_ca_cert_params() {
            echo_cert_params "$CA_DOMAIN" "$CA_EMAIL"
        }
        echo_server_cert_params() {
            echo_cert_params "$SERVER_DOMAIN" "$SERVER_EMAIL"
        }

        # [ main ]
        # generate certificates
        # - ca
        openssl genrsa $RSA_STR_LEN > $KEY_DIR/${PREFIX}ca-key.pem
        echo_ca_cert_params | \
            openssl req -new -x509 -nodes -days $CERT_DAYS -key $KEY_DIR/${PREFIX}ca-key.pem -out $CERT_DIR/${PREFIX}ca-cert.pem
        # - server
        echo_server_cert_params | \
            openssl req -newkey rsa:$RSA_STR_LEN -days $CERT_DAYS -nodes -keyout $KEY_DIR/${PREFIX}server-key.pem -out $CERT_DIR/${PREFIX}server-req.pem
        openssl rsa -in $KEY_DIR/${PREFIX}server-key.pem -out $KEY_DIR/${PREFIX}server-key.pem
        openssl x509 -req -in $CERT_DIR/${PREFIX}server-req.pem -days $CERT_DAYS -CA $CERT_DIR/${PREFIX}ca-cert.pem -CAkey $KEY_DIR/${PREFIX}ca-key.pem -set_serial 01 -out $CERT_DIR/${PREFIX}server-cert.pem

        # clean up (before permission changed)
        rm $KEY_DIR/${PREFIX}ca-key.pem
        rm $CERT_DIR/${PREFIX}server-req.pem

        # validate permission
        chmod 400 $KEY_DIR/${PREFIX}server-key.pem

        # verify relationship among certificates
        openssl verify -CAfile $CERT_DIR/${PREFIX}ca-cert.pem $CERT_DIR/${PREFIX}server-cert.pem
    }

main
