FROM tiangolo/meinheld-gunicorn:python3.8
LABEL maintainer="Sida Say <sida.say@khalibre.com>"

ENV PI_SKIP_BOOTSTRAP=false \
    DB_VENDOR=sqlite
ENV PI_VERSION=3.5.1

RUN pip3 install -r https://raw.githubusercontent.com/privacyidea/privacyidea/v${PI_VERSION}/requirements.txt; \
    pip3 install git+https://github.com/privacyidea/privacyidea.git@v${PI_VERSION}; \
    pip3 install pymysql-sa; \
    pip3 install PyMySQL


COPY configs/config.py /etc/privacyidea/pi.cfg
COPY configs/main.py /app/main.py
COPY configs/prestart.sh /app/prestart.sh

VOLUME [ "/data/privacyidea" ]
