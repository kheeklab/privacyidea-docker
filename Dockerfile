# python:3.14-slim pinned by index digest; Dependabot bumps this weekly.
ARG PI_VERSION=main
# Upstream ref that carries requirements.txt. release.yml resolves it from the
# upstream tags (v<V>, falling back to v<major.minor>) so a patch release never
# assumes the upstream tag equals the installed package version. Empty keeps
# the local-build default of v<PI_VERSION>.
ARG PI_REQUIREMENTS_REF=
ARG PI_REQUIREMENTS_COMMIT=
ARG PI_REQUIREMENTS_SHA256=
ARG PI_ARTIFACT_HASHES=
ARG PI_HOME=/opt/privacyidea

FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f AS builder
ARG PI_HOME
ARG PI_VERSION
ARG PI_REQUIREMENTS_REF
ARG PI_REQUIREMENTS_COMMIT
ARG PI_REQUIREMENTS_SHA256
ARG PI_ARTIFACT_HASHES
RUN apt-get update && apt-get install -y curl jq git python3-dev gcc libpq-dev libxslt-dev --no-install-recommends && \
    dpkg-query -W -f='${binary:Package}=${Version}\n' | sort > /tmp/builder-os-packages.txt
COPY requirements.txt /tmp/requirements.txt
COPY requirements-build.lock /tmp/requirements-build.lock
COPY scripts/filter-requirement-overrides.py /tmp/filter-requirement-overrides.py
COPY scripts/resolve-pypi-artifact-hashes.py /tmp/resolve-pypi-artifact-hashes.py
RUN set -eux; \
    VERSION="$PI_VERSION"; \
    if [ -z "$VERSION" ] || [ "$VERSION" = "main" ]; then \
    curl -fsSL -o /tmp/privacyidea-pypi.json https://pypi.org/pypi/privacyIDEA/json; \
    VERSION=$(jq -r '.info.version' /tmp/privacyidea-pypi.json); \
    rm -f /tmp/privacyidea-pypi.json; \
    fi; \
    test -n "$VERSION"; \
    VERSION="${VERSION#v}"; \
    artifact_hashes="$PI_ARTIFACT_HASHES"; \
    if [ -z "$artifact_hashes" ]; then \
      curl -fsSL "https://pypi.org/pypi/privacyIDEA/${VERSION}/json" -o /tmp/privacyidea-artifact.json; \
      artifact_hashes=$(python3 /tmp/resolve-pypi-artifact-hashes.py "$VERSION" /tmp/privacyidea-artifact.json); \
    fi; \
    printf '%s' "$artifact_hashes" | tr ',' '\n' | grep -Eq '^[0-9a-f]{64}$'; \
    echo "Using privacyIDEA version: ${VERSION}"; \
    major_minor=$(printf '%s' "$VERSION" | cut -d. -f1-2); \
    requirements_ref="${PI_REQUIREMENTS_REF:-v${VERSION}}"; \
    requirements_commit="${PI_REQUIREMENTS_COMMIT:-}"; \
    requirements_sha256="${PI_REQUIREMENTS_SHA256:-}"; \
    if [ -z "$requirements_commit" ]; then \
      for candidate in "$requirements_ref" "v${major_minor}"; do \
        tag_ref="refs/tags/${candidate}"; \
        refs=$(git ls-remote --tags https://github.com/privacyidea/privacyidea.git "$tag_ref" "${tag_ref}^{}"); \
        requirements_commit=$(printf '%s\n' "$refs" | awk -v peeled="${tag_ref}^{}" '$2 == peeled {print $1; found=1; exit} END {if (!found) exit 1}' || true); \
        if [ -z "$requirements_commit" ]; then requirements_commit=$(printf '%s\n' "$refs" | awk -v direct="$tag_ref" '$2 == direct {print $1; exit}'); fi; \
        if [ -n "$requirements_commit" ] && curl -fsSL -o /tmp/pi-requirements.txt "https://raw.githubusercontent.com/privacyidea/privacyidea/${requirements_commit}/requirements.txt"; then \
          requirements_ref="$candidate"; \
          break; \
        fi; \
        requirements_commit=""; \
      done; \
    else \
      echo "$requirements_commit" | grep -Eq '^[0-9a-f]{40}$'; \
      curl -fsSL -o /tmp/pi-requirements.txt "https://raw.githubusercontent.com/privacyidea/privacyidea/${requirements_commit}/requirements.txt"; \
    fi; \
    test -s /tmp/pi-requirements.txt; \
    actual_requirements_sha256=$(sha256sum /tmp/pi-requirements.txt | cut -d' ' -f1); \
    if [ -n "$requirements_sha256" ]; then \
      echo "${requirements_sha256}  /tmp/pi-requirements.txt" | sha256sum -c -; \
    else \
      requirements_sha256="$actual_requirements_sha256"; \
    fi; \
    echo "Using privacyIDEA requirements ref=${requirements_ref} commit=${requirements_commit} sha256=${requirements_sha256}"; \
    printf 'requirements_ref=%s\nrequirements_commit=%s\nrequirements_sha256=%s\nprivacyidea_artifact_hashes=%s\n' "$requirements_ref" "$requirements_commit" "$requirements_sha256" "$artifact_hashes" > /tmp/build-inputs.txt; \
    python3 -m venv "/opt/privacyidea"; \
    . "/opt/privacyidea/bin/activate"; \
    pip3 install --no-deps --require-hashes -r /tmp/requirements-build.lock; \
    python /tmp/filter-requirement-overrides.py /tmp/pi-requirements.txt /tmp/requirements.txt /tmp/pi-requirements-filtered.txt; \
    { \
      printf 'privacyidea==%s \\\n' "$VERSION"; \
      printf '%s\n' "$artifact_hashes" | tr ',' '\n' | while IFS= read -r hash; do printf '    --hash=sha256:%s \\\n' "$hash"; done; \
      cat /tmp/pi-requirements-filtered.txt /tmp/requirements.txt; \
    } > /tmp/requirements.lock; \
    sed -i "1i# Upstream ${requirements_ref} commit ${requirements_commit} requirements.txt sha256 ${requirements_sha256}" /tmp/requirements.lock; \
    pip3 install --no-deps --no-build-isolation --require-hashes -r /tmp/requirements.lock; \
    pip3 check


FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f
ARG PI_HOME
ARG PI_REQUIREMENTS_COMMIT
ARG PI_REQUIREMENTS_SHA256
ARG PI_ARTIFACT_HASHES
LABEL maintainer="Sida Say <sida@kheek.com>"
LABEL org.opencontainers.image.requirements.commit="$PI_REQUIREMENTS_COMMIT" \
      org.opencontainers.image.requirements.sha256="$PI_REQUIREMENTS_SHA256" \
      org.opencontainers.image.privacyidea.artifact.hashes="$PI_ARTIFACT_HASHES"
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
    mkdir -p "$PI_DATA_DIR" "$PI_CFG_DIR" /var/log/privacyidea /usr/share/privacyidea && \
    dpkg-query -W -f='${binary:Package}=${Version}\n' | sort > /usr/share/privacyidea/runtime-os-packages.txt && \
    chown -R nobody:nogroup "$PI_DATA_DIR" "$PI_CFG_DIR" /var/log/privacyidea
USER nobody
WORKDIR "$PI_HOME"
COPY --from=builder /opt/privacyidea .
COPY --from=builder /tmp/requirements.lock /usr/share/privacyidea/requirements.lock
COPY --from=builder /tmp/requirements-build.lock /usr/share/privacyidea/requirements-build.lock
COPY --from=builder /tmp/build-inputs.txt /usr/share/privacyidea/build-inputs.txt
COPY --from=builder /tmp/builder-os-packages.txt /usr/share/privacyidea/builder-os-packages.txt
COPY --chown=nobody:nogroup rootfs /
# Apply the privacyIDEA 3.14 English redirect correction at build time.
# Scoped to 3.14 and a known source hash; exits 0 on other versions.
COPY scripts/patch-default-ui.py /tmp/patch-default-ui.py
USER root
RUN /opt/privacyidea/bin/python /tmp/patch-default-ui.py && rm /tmp/patch-default-ui.py
USER nobody
EXPOSE 8080/tcp
VOLUME [ "$PI_DATA_DIR" ]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/privacyidea_entrypoint.sh"]
