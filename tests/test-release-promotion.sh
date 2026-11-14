#!/usr/bin/env bash
# Exercise durable reservation and promotion without network or registry writes.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/registry"
git init --bare --quiet "$tmp/remote.git"
cat > "$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$3" in
  inspect)
    key="${4//\//_}"
    if [[ -f "$REGISTRY_DIR/$key" ]]; then
      cat "$REGISTRY_DIR/$key"
    else
      echo 'manifest unknown' >&2
      exit 1
    fi
    ;;
  create)
    key="${5//\//_}"
    printf '%s\n' "${6##*@}" > "$REGISTRY_DIR/$key"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" REGISTRY_DIR="$tmp/registry"
export GHCR_REPO=ghcr.io/example/privacyidea HUB_ENABLED=true HUB_REPO=example/privacyidea
export REQUIREMENTS_REF=v3.14 REQUIREMENTS_COMMIT=0123456789abcdef0123456789abcdef01234567
export REQUIREMENTS_SHA256=89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567
export ARTIFACT_HASHES=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export INTENTS_REMOTE_URL="$tmp/remote.git" INTENT_STORE_DIR="$tmp/store"
export TODAY_UTC=20261112 VERSION=3.14 ROUTE=rebuild IDENTITY=3.14-20261112-003 REF_NAME=v3.14-20261112-003
export JOURNAL="$tmp/nested/journal.md" GITHUB_OUTPUT="$tmp/output" LEDGER_FILE="$tmp/ledger"
TESTED_DIGEST="sha256:$(printf '%064d' 1)"
export TESTED_DIGEST SHA_SHORT=123456789abc
export HUB_DIGEST="$TESTED_DIGEST"
printf '3.14\n' > "$LEDGER_FILE"
bash "$root/.github/scripts/promote-release.sh" reserve
jq -e '.status == "reserved"' "$INTENT_STORE_DIR/intents/$VERSION/$IDENTITY.json" >/dev/null
jq -e --arg commit "$REQUIREMENTS_COMMIT" --arg sha "$REQUIREMENTS_SHA256" '.requirements_commit == $commit and .requirements_sha256 == $sha' "$INTENT_STORE_DIR/intents/$VERSION/$IDENTITY.json" >/dev/null
jq -e --arg hashes "$ARTIFACT_HASHES" '.artifact_hashes == $hashes' "$INTENT_STORE_DIR/intents/$VERSION/$IDENTITY.json" >/dev/null
if ARTIFACT_HASHES=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  bash "$root/.github/scripts/promote-release.sh" reserve >/dev/null 2>&1; then
  echo 'changed artifact hashes unexpectedly reused a reserved intent' >&2
  exit 1
fi
bash "$root/.github/scripts/promote-release.sh" promote
jq -e --arg digest "$TESTED_DIGEST" '.status == "promoted" and .tested_digest == $digest' "$INTENT_STORE_DIR/intents/$VERSION/$IDENTITY.json" >/dev/null
test -s "$JOURNAL"
if git --git-dir="$tmp/remote.git" ls-tree -r --name-only release-intents | grep -q '\.git-err'; then
  echo 'push error file leaked into intent ledger' >&2
  exit 1
fi
export ROUTE=numeric VERSION=3.14.1 IDENTITY='' REF_NAME=v3.14.1
export REQUIREMENTS_REF=v3.14.1
bash "$root/.github/scripts/promote-release.sh" reserve
export IDENTITY=3.14.1-20261112
jq -e '.status == "reserved"' "$INTENT_STORE_DIR/intents/$VERSION/$IDENTITY.json" >/dev/null
bash "$root/.github/scripts/promote-release.sh" promote
jq -e '.status == "promoted"' "$INTENT_STORE_DIR/intents/$VERSION/$IDENTITY.json" >/dev/null
echo 'release promotion integration tests passed'
