#!/usr/bin/env bash
set -eu
: "${FIXTURE_DIR:?Set FIXTURE_DIR to the disposable provisioned data directory}"
image=${IMAGE:?Set IMAGE to the exact fixture image}
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'chmod -R u+w "$tmp_dir" 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT
chmod 777 "$tmp_dir"
docker run --rm --network none --user 0:0 -e "COPY_UID=$(id -u)" -e "COPY_GID=$(id -g)" \
    -v "$FIXTURE_DIR:/fixture:ro" -v "$tmp_dir:/copy" --entrypoint /bin/sh "$image" \
    -c 'cp -a /fixture/. /copy/; chown -R "$COPY_UID:$COPY_GID" /copy; chown 65534:65534 /copy/privacyidea.db /copy/keys /copy/keys/*; touch -a -d @1000000000 /copy/keys/*; chmod -R a+rX /copy; chmod 777 /copy/keys; chmod a+w /copy/privacyidea.db'
chmod 777 "$tmp_dir"
printf 'touch /data/privacyidea/hook-ran\n' > "$tmp_dir/hook.sh"
printf '#!/bin/sh\ntouch /data/privacyidea/server-ran\n' > "$tmp_dir/server.sh"
printf '#!/bin/sh\ntouch /data/privacyidea/upgrade-ran\n' > "$tmp_dir/upgrade.sh"
chmod 755 "$tmp_dir/server.sh" "$tmp_dir/upgrade.sh"
run_entrypoint() {
    docker run --rm --network none -e SQLALCHEMY_DATABASE_URI=sqlite:////data/privacyidea/privacyidea.db -e PI_SKIP_BOOTSTRAP=false -e PI_AUTO_UPDATE="${auto:-false}" \
        -e PI_SECRET_KEY=distinctive-test-secret -e PI_PEPPER=distinctive-test-pepper \
        -e PI_ADMIN_USER="${admin_user:-}" -e PI_ADMIN_PASSWORD="${admin_password:-}" \
        -v "$tmp_dir:/data/privacyidea" \
        -v "$tmp_dir/hook.sh:/usr/local/privacyidea/scripts/pre-configure/test.sh:ro" \
        -v "$tmp_dir/server.sh:/opt/privacyidea/bin/gunicorn:ro" \
        -v "$tmp_dir/upgrade.sh:/opt/privacyidea/bin/privacyidea-schema-upgrade:ro" \
        -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
        -v "$repo_dir/rootfs/usr/local/bin/privacyidea_entrypoint.sh:/usr/local/bin/privacyidea_entrypoint.sh:ro" \
        "$image" > "$tmp_dir/log" 2>&1
}
run_check() {
    docker run --rm --network none -e SQLALCHEMY_DATABASE_URI=sqlite:////data/privacyidea/privacyidea.db -e PI_SKIP_BOOTSTRAP=false -e PI_AUTO_UPDATE="${auto:-false}" \
        -e PI_ADMIN_PASSWORD=distinctive-test-secret \
        -v "$tmp_dir:/data/privacyidea" \
        -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
        --entrypoint /bin/bash "$image" /usr/local/bin/configure_privacyidea.sh "$@" > "$tmp_dir/log" 2>&1
}
state_snapshot() {
    find "$tmp_dir/keys" "$tmp_dir/privacyidea.db" "$tmp_dir/.privacyidea_initialized" -type f \
        -printf '%p %m %u %g %s %A@ %T@ %C@\n' | sort
}
metadata_before=$(state_snapshot)
if ! run_check --check-initialized; then
    echo 'FAIL: real initialized fixture rejected' >&2
    exit 1
fi
metadata_after=$(state_snapshot)
if [ "$metadata_before" != "$metadata_after" ]; then
    diff -u <(printf '%s\n' "$metadata_before") <(printf '%s\n' "$metadata_after") >&2 || true
    echo 'FAIL: preflight changed fixture metadata, including key atime' >&2
    exit 1
fi
before=$(sha256sum "$tmp_dir/privacyidea.db" "$tmp_dir/keys/"*)
for auto in false true; do
    admin_user='' admin_password=''
    if [ "$auto" = true ]; then admin_user=changed admin_password=distinctive-test-secret; fi
    if ! run_entrypoint; then
        echo "FAIL: initialized head entrypoint rejected with auto=$auto" >&2
        exit 1
    fi
    [ -e "$tmp_dir/hook-ran" ] && [ -e "$tmp_dir/server-ran" ] && [ ! -e "$tmp_dir/upgrade-ran" ] || {
        echo 'FAIL: head path missed hook/server or invoked upgrade' >&2; exit 1;
    }
    [ "$before" = "$(sha256sum "$tmp_dir/privacyidea.db" "$tmp_dir/keys/"*)" ] || {
        echo 'FAIL: head startup changed database or keys' >&2; exit 1;
    }
    rm "$tmp_dir/hook-ran" "$tmp_dir/server-ran"
done
cp "$tmp_dir/privacyidea.db" "$tmp_dir/original.db"
python3 - "$tmp_dir/privacyidea.db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute('DROP TABLE realm')
PY
if run_check --check-initialized; then
    echo 'FAIL: missing privacyIDEA table accepted' >&2
    exit 1
fi
for state in old missing malformed multiple duplicate; do
    cp "$tmp_dir/original.db" "$tmp_dir/privacyidea.db"
    python3 - "$tmp_dir/privacyidea.db" "$state" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    state = sys.argv[2]
    if state == 'old':
        db.execute("UPDATE alembic_version SET version_num = 'old_revision'")
    elif state == 'missing':
        db.execute('DELETE FROM alembic_version')
    elif state == 'malformed':
        db.execute("UPDATE alembic_version SET version_num = ''")
    elif state == 'multiple':
        db.execute("INSERT INTO alembic_version VALUES ('unexpected')")
    else:
        # The stock table has a primary key; rebuild it to simulate malformed duplicate state.
        db.execute('CREATE TABLE revision_copy AS SELECT * FROM alembic_version')
        db.execute('DROP TABLE alembic_version')
        db.execute('CREATE TABLE alembic_version (version_num VARCHAR(32))')
        db.execute('INSERT INTO alembic_version SELECT version_num FROM revision_copy')
        db.execute('INSERT INTO alembic_version SELECT version_num FROM revision_copy')
        db.execute('DROP TABLE revision_copy')
PY
    state_before=$(sha256sum "$tmp_dir/privacyidea.db" "$tmp_dir/keys/"*)
    for auto in false true; do
        for invocation in check direct; do
            args=()
            [ "$invocation" = direct ] || args=(--check-initialized)
            if run_check "${args[@]}"; then
                echo "FAIL: $state revision accepted with auto=$auto ($invocation)" >&2
                exit 1
            fi
            if grep -q 'distinctive-test-secret' "$tmp_dir/log"; then
                echo 'FAIL: secret in failure log' >&2
                exit 1
            fi
            [ "$state_before" = "$(sha256sum "$tmp_dir/privacyidea.db" "$tmp_dir/keys/"*)" ] || {
                echo 'FAIL: rejected revision changed state' >&2; exit 1;
            }
        done
        if run_entrypoint; then
            echo "FAIL: $state revision reached server with auto=$auto" >&2
            exit 1
        fi
        if [ -e "$tmp_dir/hook-ran" ] || [ -e "$tmp_dir/server-ran" ] || [ -e "$tmp_dir/upgrade-ran" ]; then
            echo 'FAIL: rejected revision reached hook, server, or upgrade' >&2
            exit 1
        fi
        if grep -Eq 'distinctive-test-secret|distinctive-test-pepper' "$tmp_dir/log"; then
            echo 'FAIL: secret in entrypoint failure log' >&2
            exit 1
        fi
    done
done
echo 'PASS: real fixture preserved; incomplete and invalid revision states rejected'
