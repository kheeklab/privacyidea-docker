#!/bin/bash

set -e

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
    echo_server_cert_params() {
      echo_cert_params "$SERVER_DOMAIN" "$SERVER_EMAIL"
    }

    # [ main ]
    # generate certificates
    # - server
    echo_server_cert_params | \
      openssl req -newkey rsa:$RSA_STR_LEN -days $CERT_DAYS -nodes -keyout $KEY_DIR/${PREFIX}server-key.pem -out $CERT_DIR/${PREFIX}server-req.pem > /dev/null
    openssl rsa -in $KEY_DIR/${PREFIX}server-key.pem -out $KEY_DIR/${PREFIX}server-key.pem > /dev/null
    openssl x509 -req -in $CERT_DIR/${PREFIX}server-req.pem -days $CERT_DAYS -signkey $KEY_DIR/${PREFIX}server-key.pem -out $CERT_DIR/${PREFIX}server-cert.pem > /dev/null

    # clean up (before permission changed)
    rm $CERT_DIR/${PREFIX}server-req.pem > /dev/null

    # validate permission
    chmod 400 $KEY_DIR/${PREFIX}server-key.pem > /dev/null

    # verify certificate
    openssl x509 -in $CERT_DIR/${PREFIX}server-cert.pem -noout -text > /dev/null
}

function main {
  # Generate certificate if SSL is enabled and no certificate/key paths are provided
  if [ "$NGINX_SSL_ENABLED" = true ]; then
    if [ -z "$NGINX_SSL_CERT" ] && [ -z "$NGINX_SSL_KEY" ];
    then
      echo "SSL enabled but NGINX_SSL_CERT and NGINX_SSL_KEY are not defined, using generated certificate"
      generate_cert
      export NGINX_SSL_CERT=/etc/nginx/certs/pi-server-cert.pem
      export NGINX_SSL_KEY=/etc/nginx/certs/pi-server-key.pem
    fi
    envsubst < /opt/templates/nginx-pi-ssl.conf.template > /etc/nginx/conf.d/pi-ssl.conf
  fi

  # Substitute environment variables in nginx configuration files
  envsubst < /opt/templates/nginx.conf.template > /etc/nginx/nginx.conf
  envsubst < /opt/templates/nginx-pi.conf.template > /etc/nginx/conf.d/pi.conf
}

main
