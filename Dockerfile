ARG BASE_IMAGE_TAG=3.12.7-slim-bullseye
ARG PI_VERSION=3.10
ARG PI_HOME=/opt/privacyidea

FROM python:$BASE_IMAGE_TAG AS builder
ARG PI_HOME
ARG PI_VERSION
RUN apt-get update && apt-get install -y python3-dev gcc libpq-dev libkrb5-dev
COPY requirements.txt requirements.txt
RUN python3 -m venv "$PI_HOME" && . "$PI_HOME/bin/activate" \
    && pip3 install --upgrade pip \
    && pip3 install wheel \
    && pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v"$PI_VERSION"/requirements.txt \
    && pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v"$PI_VERSION"/requirements-kerberos.txt \
    && pip3 install privacyidea=="$PI_VERSION" \
    && pip3 install -r requirements.txt

FROM python:$BASE_IMAGE_TAG
ARG PI_HOME
LABEL maintainer="Sida Say <sida@kheek.com>"
ENV PI_SKIP_BOOTSTRAP=false \
    PI_DB_VENDOR=sqlite \
    PI_DATA_DIR=/data/privacyidea \
    PI_CFG_DIR=/etc/privacyidea \
    PI_CFG_FILE=pi.cfg \
    PATH="$PI_HOME/bin:$PATH"

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN install_packages ca-certificates gettext-base tini tree jq libpq5 realmd krb5-user curl && \
    mkdir -p "$PI_DATA_DIR" "$PI_CFG_DIR" && \
    chown -R nobody:nogroup "$PI_DATA_DIR" "$PI_CFG_DIR"
USER nobody
WORKDIR "$PI_HOME"
COPY --from=builder /opt/privacyidea .
COPY --chown=nobody:nogroup rootfs /
EXPOSE 8080/tcp
VOLUME [ "$PI_DATA_DIR" ]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/privacyidea_entrypoint.sh"]
