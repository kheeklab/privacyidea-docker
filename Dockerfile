ARG BASE_IMAGE_TAG=3.12-slim
ARG PI_VERSION=main
ARG PI_HOME=/opt/privacyidea

FROM python:$BASE_IMAGE_TAG AS builder
ARG PI_HOME
ARG PI_VERSION
RUN apt-get update && apt-get install -y curl jq python3-dev gcc libpq-dev libkrb5-dev libxslt-dev --no-install-recommends
COPY requirements.txt /tmp/requirements.txt
RUN set -eux; \
    VERSION="$PI_VERSION"; \
    if [ -z "$VERSION" ] || [ "$VERSION" = "main" ]; then \
    curl -fsSL -o /tmp/privacyidea-pypi.json https://pypi.org/pypi/privacyIDEA/json; \
    VERSION=$(jq -r '.info.version' /tmp/privacyidea-pypi.json); \
    rm -f /tmp/privacyidea-pypi.json; \
    fi; \
    test -n "$VERSION"; \
    echo "Using privacyIDEA version: ${VERSION#v}"; \
    python3 -m venv "/opt/privacyidea"; \
    . "/opt/privacyidea/bin/activate"; \
    pip3 install --upgrade pip wheel; \
    pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${VERSION#v}/requirements.txt; \
    KERBEROS_URL="https://raw.githubusercontent.com/privacyidea/privacyidea/v${VERSION#v}/requirements-kerberos.txt"; \
    KERBEROS_HTTP=$(curl -sSL -o /tmp/requirements-kerberos.txt -w '%{http_code}' "$KERBEROS_URL") || KERBEROS_HTTP=000; \
    if [ "$KERBEROS_HTTP" = "404" ]; then \
        echo "No requirements-kerberos.txt for v${VERSION#v}; skipping kerberos extras"; \
        rm -f /tmp/requirements-kerberos.txt; \
    elif [ "$KERBEROS_HTTP" != "200" ]; then \
        echo "Failed to download requirements-kerberos.txt: HTTP $KERBEROS_HTTP" >&2; \
        exit 1; \
    elif [ ! -s /tmp/requirements-kerberos.txt ]; then \
        echo "requirements-kerberos.txt downloaded empty; aborting" >&2; \
        exit 1; \
    else \
        pip3 install -r /tmp/requirements-kerberos.txt; \
        rm -f /tmp/requirements-kerberos.txt; \
    fi; \
    pip3 install privacyidea==${VERSION#v}; \
    pip3 install -r /tmp/requirements.txt


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
RUN install_packages ca-certificates gettext-base tini tree jq libpq5 curl && \
    mkdir -p "$PI_DATA_DIR" "$PI_CFG_DIR" /var/log/privacyidea && \
    chown -R nobody:nogroup "$PI_DATA_DIR" "$PI_CFG_DIR" /var/log/privacyidea
USER nobody
WORKDIR "$PI_HOME"
COPY --from=builder /opt/privacyidea .
COPY --chown=nobody:nogroup rootfs /
EXPOSE 8080/tcp
VOLUME [ "$PI_DATA_DIR" ]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/privacyidea_entrypoint.sh"]
