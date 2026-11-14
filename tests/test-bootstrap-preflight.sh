#!/usr/bin/env bash
set -eu

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/data" "$test_dir/hooks/pre-configure" "$test_dir/hooks/pre-startup"
printf 'touch "%s/hook-ran"\n' "$test_dir" > "$test_dir/hooks/pre-configure/test.sh"
sed -e "s|/usr/local/bin/_privacyidea_common.sh|$repo_dir/rootfs/usr/local/bin/_privacyidea_common.sh|" \
    -e "s|/usr/local/privacyidea/scripts|$test_dir/hooks|g" \
    -e 's|/usr/local/bin/configure_privacyidea.sh --check-initialized|true|' \
    -e "s|\. configure_privacyidea.sh|exit 0|" \
    "$repo_dir/rootfs/usr/local/bin/privacyidea_entrypoint.sh" > "$test_dir/entrypoint.sh"

for inputs in neither user password explicit; do
    case "$inputs" in
        neither) user='' password='' ;;
        user) user=example password='' ;;
        password) user='' password=distinctive-secret ;;
        explicit) user=example password=distinctive-secret ;;
    esac
    rm -f "$test_dir/hook-ran"
    if PI_DATA_DIR="$test_dir/data" PI_SKIP_BOOTSTRAP=false PI_ADMIN_USER="$user" \
        PI_ADMIN_PASSWORD="$password" bash "$test_dir/entrypoint.sh" > "$test_dir/log" 2>&1; then
        echo "FAIL: $inputs accepted" >&2
        exit 1
    fi
    if [ -e "$test_dir/hook-ran" ] || grep -q 'distinctive-secret' "$test_dir/log"; then
        echo "FAIL: $inputs ran a hook or exposed a secret" >&2
        exit 1
    fi
done
for mode in skip initialized; do
    rm -f "$test_dir/hook-ran" "$test_dir/data/.privacyidea_initialized"
    user='' password='' skip=false
    case "$mode" in
        skip) skip=true ;;
        initialized) touch "$test_dir/data/.privacyidea_initialized" ;;
    esac
    if ! PI_DATA_DIR="$test_dir/data" PI_SKIP_BOOTSTRAP="$skip" PI_ADMIN_USER="$user" \
        PI_ADMIN_PASSWORD="$password" bash "$test_dir/entrypoint.sh" > "$test_dir/log" 2>&1; then
        echo "FAIL: $mode rejected" >&2
        exit 1
    fi
    if [ ! -e "$test_dir/hook-ran" ] || grep -q 'distinctive-secret' "$test_dir/log"; then
        echo "FAIL: $mode did not run the hook or exposed a secret" >&2
        exit 1
    fi
done
for uri in sqlite:////nonexistent/path postgresql://example.invalid/db mysql://example.invalid/db custom://example.invalid/db; do
    rm -f "$test_dir/hook-ran" "$test_dir/data/.privacyidea_initialized"
    printf 'preserve' > "$test_dir/data/sentinel"
    if PI_DATA_DIR="$test_dir/data" PI_SKIP_BOOTSTRAP=false PI_ADMIN_USER=example \
        PI_ADMIN_PASSWORD=distinctive-secret SQLALCHEMY_DATABASE_URI="$uri" \
        bash "$test_dir/entrypoint.sh" > "$test_dir/log" 2>&1; then
        echo "FAIL: unqualified URI accepted" >&2
        exit 1
    fi
    if [ -e "$test_dir/hook-ran" ] || [ "$(cat "$test_dir/data/sentinel")" != preserve ] || \
        grep -q 'distinctive-secret' "$test_dir/log"; then
        echo "FAIL: unqualified URI caused mutation or exposed a secret" >&2
        exit 1
    fi
done
echo 'PASS: unqualified bootstrap rejected before hooks; skip and marker paths proceed'
