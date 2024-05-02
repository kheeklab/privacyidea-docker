ARG BASE_IMAGE_TAG=3.8.18-slim-bookworm

FROM python:$BASE_IMAGE_TAG as builder
ENV VIRTUAL_ENV=/opt/privacyidea
WORKDIR $VIRTUAL_ENV
RUN apt-get update && apt-get install -y python3-dev gcc libpq-dev
COPY requirements.txt requirements.txt
RUN python3 -m venv "$VIRTUAL_ENV" && . $VIRTUAL_ENV/bin/activate && pip3 install wheel && pip3 install -r requirements.txt

FROM python:$BASE_IMAGE_TAG
LABEL maintainer="Sida Say <sida.say@khalibre.com>"
ENV PI_SKIP_BOOTSTRAP=false \
    PI_DB_VENDOR=sqlite \
    PI_HOME=/opt/privacyidea \
    PI_DATA_DIR=/data/privacyidea \
    PI_CFG_DIR=/etc/privacyidea \
    PI_CFG_FILE=pi.cfg

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN install_packages ca-certificates gettext-base tini tree jq libpq5 && \
    mkdir -p "$PI_DATA_DIR" "$PI_CFG_DIR" && \
    chown -R nobody:nogroup "$PI_DATA_DIR" "$PI_CFG_DIR"
USER nobody
WORKDIR "$PI_HOME"
COPY --from=builder /opt/privacyidea .
COPY --chown=nobody:nogroup rootfs /
ENV PATH="$PI_HOME/bin:$PATH"
EXPOSE 8080/tcp
VOLUME [ "$PI_DATA_DIR" ]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/privacyidea_entrypoint.sh"]
