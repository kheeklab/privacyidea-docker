FROM python:3.8.8

LABEL maintainer="Sida Say <sida.say@khalibre.com>"

ENV PYTHONPATH=/app \
    PI_SKIP_BOOTSTRAP=false \
    DB_VENDOR=sqlite \
    PI_VERSION=3.5.1

RUN apt-get update; \
    pip install meinheld gunicorn pymysql-sa PyMySQL; \
    pip install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${PI_VERSION}/requirements.txt; \
    pip install git+https://github.com/privacyidea/privacyidea.git@v${PI_VERSION}

COPY ./configs/gunicorn_conf.py /gunicorn_conf.py
COPY ./configs/config.py /etc/privacyidea/pi.cfg
COPY ./configs/app /app
COPY ./configs/entrypoint.sh /entrypoint.sh
COPY ./configs/start.sh /start.sh
RUN chmod +x /start.sh; \
    chmod +x /entrypoint.sh

WORKDIR /app/
VOLUME [ "/data/privacyidea" ]

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]

# Run the start script, it will check for an /app/prestart.sh script (e.g. for migrations)
# And then will start Gunicorn with Meinheld
CMD ["/start.sh"]
