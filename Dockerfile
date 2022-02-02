FROM nginx:1.21

LABEL maintainer="michimau <mauro.michielon@eea.europa.eu>"
#forked from https://github.com/Khalibre/privacyidea-docker
#original maintainer="Sida Say <sida.say@khalibre.com>"

RUN set -xe; \
    apt-get -y update && \
    apt-get install -y ca-certificates \
    pip \
    python3 \
    python3-venv \
    python3-wheel \
    git \
    supervisor

RUN mkdir -p mkdir /etc/privacyidea/data/keys \
    /opt/privacyidea \
    /var/log/privacyidea && \
    useradd -r -M -d /opt/privacyidea privacyidea && \
    chown -R privacyidea:privacyidea /opt/privacyidea /etc/privacyidea /var/log/privacyidea

#    apt-get remove --purge --auto-remove -y ca-certificates && rm -rf /var/lib/apt/lists/*

# COPY PI configuration
COPY ./configs/config.py /etc/privacyidea/pi.cfg

# Remove default configuration from Nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copy the base uWSGI ini file to enable default dynamic uwsgi process number
COPY ./configs/uwsgi.ini /etc/uwsgi/

# Custom Supervisord config
COPY ./configs/supervisord-debian.conf /etc/supervisor/supervisord.conf

# Add demo app
COPY ./configs/app /app

COPY ["configs/start.sh", "configs/entrypoint.sh", "/"]

RUN chmod +x /entrypoint.sh /start.sh \
    && apt-get clean autoclean \
    && apt-get autoremove --yes \
    && rm -rf /var/lib/{apt,dpkg,cache,log}/ \
    && rm -rf /tmp/*

# Which uWSGI .ini file should be used, to make it customizable
ENV UWSGI_INI /app/uwsgi.ini

# By default, run 2 processes
ENV UWSGI_CHEAPER 2

# By default, when on demand, run up to 16 processes
ENV UWSGI_PROCESSES 16

# By default, allow unlimited file sizes, modify it to limit the file sizes
# To have a maximum of 1 MB (Nginx's default) change the line to:
# ENV NGINX_MAX_UPLOAD 1m
ENV NGINX_MAX_UPLOAD 0

# By default, Nginx will run a single worker process, setting it to auto
# will create a worker for each CPU core
ENV NGINX_WORKER_PROCESSES 1

# By default, NGINX show NGINX version on error page and HTTP header
ENV NGINX_SERVER_TOKENS 'off'

# By default, Nginx listens on port 80.
# To modify this, change LISTEN_PORT environment variable.
# (in a Dockerfile or with an option for `docker run`)
ENV LISTEN_PORT 80

#USER privacyidea

ENV PI_SKIP_BOOTSTRAP=false \
    DB_VENDOR=sqlite \
    PI_VERSION=3.6.3

ENV VIRTUAL_ENV=/opt/privacyidea
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN pip install wheel && \
    pip install supervisor uwsgi pymysql-sa PyMySQL pg8000 && \
    pip install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${PI_VERSION}/requirements.txt && \
    pip install git+https://github.com/privacyidea/privacyidea.git@v${PI_VERSION}

# Copy start.sh script that will check for a /app/prestart.sh script and run it before starting the app
# Copy the entrypoint that will generate Nginx additional configs
# Make sure scripts can be executed and do some cleanup

EXPOSE 80/tcp
EXPOSE 443/tcp

#USER privacyidea 
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /app
VOLUME [ "/data/privacyidea" ]

# Run the start script, it will check for an /app/prestart.sh script (e.g. for migrations)
# And then will start Supervisor, which in turn will start Nginx and uWSGI
CMD ["/start.sh"]
