# python:3.14-slim pinned by index digest; Dependabot bumps this weekly.
ARG PI_VERSION=main
# Upstream ref that carries requirements.txt. release.yml resolves it from the
# upstream tags (v<V>, falling back to v<major.minor>) so a patch release never
# assumes the upstream tag equals the installed package version. Empty keeps
# the local-build default of v<PI_VERSION>.
ARG PI_REQUIREMENTS_REF=
ARG PI_HOME=/opt/privacyidea

FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f AS builder
ARG PI_HOME
ARG PI_VERSION
ARG PI_REQUIREMENTS_REF
RUN apt-get update && apt-get install -y curl jq python3-dev gcc libpq-dev libxslt-dev --no-install-recommends
COPY requirements.txt /tmp/requirements.txt
RUN set -eux; \
    VERSION="$PI_VERSION"; \
    if [ -z "$VERSION" ] || [ "$VERSION" = "main" ]; then \
    curl -fsSL -o /tmp/privacyidea-pypi.json https://pypi.org/pypi/privacyIDEA/json; \
    VERSION=$(jq -r '.info.version' /tmp/privacyidea-pypi.json); \
    rm -f /tmp/privacyidea-pypi.json; \
    fi; \
    test -n "$VERSION"; \
    VERSION="${VERSION#v}"; \
    echo "Using privacyIDEA version: ${VERSION}"; \
    major_minor=$(printf '%s' "$VERSION" | cut -d. -f1-2); \
    requirements_ref="${PI_REQUIREMENTS_REF:-v${VERSION}}"; \
    if ! curl -fsSL -o /tmp/pi-requirements.txt \
      "https://raw.githubusercontent.com/privacyidea/privacyidea/${requirements_ref}/requirements.txt"; then \
    if [ "$requirements_ref" = "v${major_minor}" ]; then \
    echo "privacyIDEA upstream ref ${requirements_ref} has no requirements.txt" >&2; \
    exit 1; \
    fi; \
    echo "privacyIDEA upstream ref ${requirements_ref} has no requirements.txt; falling back to v${major_minor}" >&2; \
    curl -fsSL -o /tmp/pi-requirements.txt \
    "https://raw.githubusercontent.com/privacyidea/privacyidea/v${major_minor}/requirements.txt"; \
    requirements_ref="v${major_minor}"; \
    fi; \
    echo "Using privacyIDEA requirements from ${requirements_ref}"; \
    python3 -m venv "/opt/privacyidea"; \
    . "/opt/privacyidea/bin/activate"; \
    pip3 install --upgrade pip wheel; \
    pip3 install -r /tmp/pi-requirements.txt; \
    pip3 install "privacyidea==${VERSION}"; \
    pip3 install -r /tmp/requirements.txt


FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f
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
