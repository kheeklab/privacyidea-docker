#!/usr/bin/env sh
apk --no-cache add curl

# Check that the database is available
echo "Waiting for PI to be ready"
while ! nc -w 1 pi-app 8080; do
    # Show some progress
    echo -n '.';
    sleep 1;
done
echo "PI is ready"
# Give it another 3 seconds.
sleep 3;

curl --silent --fail http://pi-app:8080 | grep '<title idle-disabled="true">pivacyIDEA</title>'
