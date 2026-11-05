#!/usr/bin/env sh
set -e

apk --no-cache add curl

readyz_body=$(mktemp)
trap 'rm -f "$readyz_body" /tmp/pi_ui_body' 0

echo "Waiting for PI to be ready"
attempt=0
while [ "$attempt" -lt 30 ]; do
    readyz_status=$(curl --silent --max-time 5 --output "$readyz_body" --write-out '%{http_code}' http://pi-app:8080/healthz/readyz 2>/dev/null || true)
    if [ "$readyz_status" = "200" ] && grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"' "$readyz_body"; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done

if [ "$readyz_status" != "200" ] || ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"' "$readyz_body"; then
    echo "/healthz/readyz did not return HTTP 200 with status \"ready\"" >&2
    exit 1
fi
echo "PI is ready"

effective_url=$(curl -sSL --fail -w "%{url_effective}" -o /tmp/pi_ui_body http://pi-app:8080/)
case "$effective_url" in
    */app/v2/*|*/app/v2/|*/app/v2)
        ;;
    *)
        echo "Expected URL to reach /app/v2/, got: $effective_url" >&2
        exit 1
        ;;
esac

if ! grep -Fq '<title i18n="@@common.privacyideaAuthentication">privacyIDEA Authentication System</title>' /tmp/pi_ui_body; then
    echo "Web UI body does not contain expected title" >&2
    exit 1
fi
