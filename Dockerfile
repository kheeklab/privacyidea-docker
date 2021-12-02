FROM python:3.8.11-buster

LABEL maintainer="Sida Say <sida.say@khalibre.com>"

ENV PI_SKIP_BOOTSTRAP=false \
    DB_VENDOR=sqlite \
    PI_VERSION=3.6.2

COPY ./configs/install-nginx-debian.sh /

RUN bash /install-nginx-debian.sh

EXPOSE 80

# Expose 443, in case of LTS / HTTPS
EXPOSE 443


# COPY PI configuration
COPY ./configs/config.py /etc/privacyidea/pi.cfg

# Remove default configuration from Nginx
RUN rm /etc/nginx/conf.d/default.conf
# Copy the base uWSGI ini file to enable default dynamic uwsgi process number
COPY ./configs/uwsgi.ini /etc/uwsgi/

# Install Supervisord
RUN set -xe; \
    apt-get update && apt-get install -y ca-certificates; \
    pip install supervisor uwsgi pymysql-sa PyMySQL;\
    pip install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${PI_VERSION}/requirements.txt; \
    pip install git+https://github.com/privacyidea/privacyidea.git@v${PI_VERSION}; \
    apt-get remove --purge --auto-remove -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Custom Supervisord config
COPY ./configs/supervisord-debian.conf /etc/supervisor/supervisord.conf

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
    # Copy start.sh script that will check for a /app/prestart.sh script and run it before starting the app
COPY ./configs/start.sh /start.sh
RUN chmod +x /start.sh

# Copy the entrypoint that will generate Nginx additional configs
COPY ./configs/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

# Add demo app
COPY ./configs/app /app
WORKDIR /app
VOLUME [ "/data/privacyidea" ]

# Run the start script, it will check for an /app/prestart.sh script (e.g. for migrations)
# And then will start Supervisor, which in turn will start Nginx and uWSGI
CMD ["/start.sh"]
