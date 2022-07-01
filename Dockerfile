FROM python:3.8.13-bullseye

ARG LABEL_BUILD_DATE
ARG LABEL_VCS_REF
ARG LABEL_VERSION

LABEL maintainer="Sida Say <sida.say@khalibre.com>"

COPY prebuildfs /

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN install_packages ca-certificates git supervisor gettext-base nginx

RUN mkdir -p mkdir /etc/privacyidea/data/keys \
    /var/log/privacyidea && \
    adduser --gecos "PrivacyIdea User" --disabled-password --home /home/privacyidea privacyidea --uid 1001 && \
    addgroup privacyidea privacyidea && \
    usermod -g 1001 privacyidea && \
    chown -R privacyidea:privacyidea /etc/privacyidea /var/log/privacyidea

COPY rootfs /

# Which uWSGI .ini file should be used, to make it customizable
ENV UWSGI_INI /etc/uwsgi/uwsgi.ini

# By default, run 2 processes
ENV UWSGI_CHEAPER 2

# By default, when on demand, run up to 16 processes
ENV UWSGI_PROCESSES 16

# By default, allow unlimited file sizes, modify it to limit the file sizes
# To have a maximum of 1 MB (Nginx's default) change the line to:
# ENV NGINX_MAX_UPLOAD 1m
ENV NGINX_MAX_UPLOAD 100m

# By default, Nginx will run a single worker process, setting it to auto
# will create a worker for each CPU core
ENV NGINX_WORKER_PROCESSES 1

# By default, NGINX show NGINX version on error page and HTTP header
ENV NGINX_SERVER_TOKENS 'off'

ENV NGINX_WORKER_CONNECTIONS 1024

# By default, Nginx listens on port 80.
# To modify this, change LISTEN_PORT environment variable.
# (in a Dockerfile or with an option for `docker run`)
ENV NGINX_LISTEN_PORT 80
ENV NGINX_LISTEN_SSL_PORT 443

ENV NGINX_SSL_ENABLED true

ENV PI_SKIP_BOOTSTRAP=false \
    DB_VENDOR=sqlite \
    PI_HOME=/opt/privacyidea \
    VIRTUAL_ENV=/opt/privacyidea

RUN python3 -m venv $VIRTUAL_ENV

ENV PATH="$VIRTUAL_ENV/bin:$PATH"

ARG PI_VERSION=3.7.1

RUN pip3 install wheel && \
    pip3 install uwsgi pymysql-sa PyMySQL psycopg2-binary && \
    pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${PI_VERSION}/requirements.txt && \
    pip3 install git+https://github.com/privacyidea/privacyidea.git@v${PI_VERSION}

EXPOSE 80/tcp
EXPOSE 443/tcp

ENTRYPOINT ["/usr/local/bin/privacyidea_entrypoint.sh"]

WORKDIR /opt/privacyidea

VOLUME [ "/data/privacyidea" ]

LABEL org.label-schema.build-date="${LABEL_BUILD_DATE}"
LABEL org.label-schema.description = "The docker image is a self-contained Debian with privacyIDEA and NGINX installed, which will run on every distribution."
LABEL org.label-schema.name="PrivacyIDEA Docker"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.url="https://github.com/privacyidea/privacyidea"
LABEL org.label-schema.usage="https://github.com/Khalibre/privacyidea-docker#readme"
LABEL org.label-schema.vcs-ref="${LABEL_VCS_REF}"
LABEL org.label-schema.vcs-url="https://github.com/Khalibre/privacyidea-docker"
LABEL org.label-schema.vendor="Khalibre"
LABEL org.label-schema.version="${LABEL_VERSION}"
