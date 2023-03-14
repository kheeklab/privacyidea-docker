FROM python:3.8.16-bullseye

LABEL maintainer="Sida Say <sida.say@khalibre.com>"

COPY prebuildfs /

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN install_packages ca-certificates git supervisor gettext-base nginx

# Create directories and user for PrivacyIdea and set ownership
RUN mkdir -p /data/privacyidea/keys \
    /var/log/privacyidea \
    /etc/privacyidea && \
    adduser --gecos "PrivacyIdea User" \
    --disabled-password \
    --home /home/privacyidea \
    --uid 1001 \
    privacyidea && \
    addgroup privacyidea privacyidea && \
    usermod -g 1001 privacyidea && \
    chown -R privacyidea:privacyidea /var/log/privacyidea /data/privacyidea /etc/privacyidea

# Set environment variables for uWSGI and Nginx
ENV UWSGI_INI=/etc/uwsgi/uwsgi.ini \
    UWSGI_CHEAPER=2 \
    UWSGI_PROCESSES=16 \
    NGINX_MAX_UPLOAD=1m \
    NGINX_WORKER_PROCESSES=auto \
    NGINX_SERVER_TOKENS=off \
    NGINX_WORKER_CONNECTIONS=1024 \
    NGINX_LISTEN_PORT=80 \
    NGINX_LISTEN_SSL_PORT=443 \
    NGINX_SSL_ENABLED=true \
    PI_SKIP_BOOTSTRAP=false \
    DB_VENDOR=sqlite \
    PI_HOME=/opt/privacyidea \
    VIRTUAL_ENV=/opt/privacyidea

# Set environment variables for Python
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Set the PrivacyIdea version to install
ARG PI_VERSION=3.8.1

# Create a virtual environment for PrivacyIdea and install its dependencies
RUN python3 -m venv $VIRTUAL_ENV && \
    pip3 install wheel && \
    pip3 install uwsgi pymysql-sa PyMySQL psycopg2-binary && \
    pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${PI_VERSION}/requirements.txt && \
    pip3 install git+https://github.com/privacyidea/privacyidea.git@v${PI_VERSION}

# Copy the rootfs directory to the root of the container filesystem
COPY rootfs /

# Expose ports 80 and 443
EXPOSE 80/tcp
EXPOSE 443/tcp

# Set the entrypoint to the privacyidea_entrypoint.sh script
ENTRYPOINT ["/usr/local/bin/privacyidea_entrypoint.sh"]

WORKDIR /opt/privacyidea

VOLUME [ "/data/privacyidea" ]
