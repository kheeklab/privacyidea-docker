ARG BASE_IMAGE_TAG=3.12-slim
ARG PI_VERSION
ARG PI_HOME=/opt/privacyidea

FROM python:$BASE_IMAGE_TAG AS builder
ARG PI_HOME
ARG PI_VERSION
RUN apt-get update && apt-get install -y curl jq python3-dev gcc libpq-dev libkrb5-dev libxslt-dev libxslt-dev
COPY requirements.txt requirements.txt
RUN set -eux; \
    VERSION="$PI_VERSION"; \
    if [ "$PI_VERSION" = "main" ]; then \
    VERSION=$(curl -s https://pypi.org/pypi/privacyIDEA/json | jq -r '.info.version'); \
    fi; \
    echo "Using privacyIDEA version: $VERSION"; \
    python3 -m venv "/opt/privacyidea"; \
    . "/opt/privacyidea/bin/activate"; \
    pip3 install --upgrade pip wheel; \
    pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${VERSION}/requirements.txt; \
    pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${VERSION}/requirements-kerberos.txt; \
    pip3 install privacyidea==${VERSION}; \
    pip3 install -r requirements.txt


FROM python:$BASE_IMAGE_TAG
ARG PI_HOME
LABEL maintainer="Sida Say <sida@kheek.com>"
ENV PI_SKIP_BOOTSTRAP=false \
    PI_AUTO_UPDATE=false \
    PI_DB_VENDOR=sqlite \
    PI_DATA_DIR=/data/privacyidea \
    PI_CFG_DIR=/etc/privacyidea \
    PI_CFG_FILE=pi.cfg \
    PATH="$PI_HOME/bin:$PATH"

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN install_packages ca-certificates gettext-base tini tree jq libpq5 realmd krb5-user curl && \
    mkdir -p "$PI_DATA_DIR" "$PI_CFG_DIR" /var/log/privacyidea && \
    chown -R nobody:nogroup "$PI_DATA_DIR" "$PI_CFG_DIR" /var/log/privacyidea
USER nobody
WORKDIR "$PI_HOME"
COPY --from=builder /opt/privacyidea .
COPY --chown=nobody:nogroup rootfs /
EXPOSE 8080/tcp
VOLUME [ "$PI_DATA_DIR" ]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/privacyidea_entrypoint.sh"]
