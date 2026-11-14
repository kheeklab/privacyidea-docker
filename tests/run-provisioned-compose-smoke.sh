#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose --file docker-compose-test.yml)
"${compose[@]}" up --no-build --detach pi-app

ready=false
for ((attempt = 1; attempt <= 120; attempt++)); do
    body=$("${compose[@]}" exec -T pi-app curl --silent --fail --max-time 3 \
        http://127.0.0.1:8080/healthz/readyz 2>/dev/null || true)
    if grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"' <<<"$body"; then
        ready=true
        break
    fi
    sleep 1
done

if [ "$ready" != true ]; then
    echo "Provisioned privacyIDEA fixture did not become ready within 120 seconds." >&2
    exit 1
fi

"${compose[@]}" run --no-deps --rm sut
