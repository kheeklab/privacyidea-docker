#!/usr/bin/env bash
#
# Regression tests for .github/scripts/resolve-release-input.sh
#
# No network, GitHub, or Docker needed: the edge version lookup is stubbed with
# PYPI_VERSION and the GITHUB_* values are fixed. Every case asserts both the
# exit code and the operator-facing guidance, because the rejection message is
# the replacement for the ref dropdown GitHub does not let us restrict.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/.github/scripts/resolve-release-input.sh"
[[ -x "$script" ]] || { echo "missing or non-executable: ${script}" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

test_sha="5e31c9a28ebd033a23997c907690ec8014654bc2"
test_run_id="43178109188"
test_attempt="1"

passed=0
failed=0

report_failure() {
  local label="$1" detail="$2"
  failed=$((failed + 1))
  echo "FAIL: ${label}" >&2
  echo "      ${detail}" >&2
  echo "----- stdout -----" >&2
  cat "$tmp/stdout" >&2
  echo "----- stderr -----" >&2
  cat "$tmp/stderr" >&2
  echo "------------------" >&2
}

# assert_case <label> <expected-exit> <expected-stderr-substrings> <expected-output-lines> [ENV=VALUE ...]
#
# <expected-stderr-substrings> and <expected-output-lines> are newline separated;
# every non-empty line must appear verbatim.
assert_case() {
  local label="$1" expected_exit="$2" expected_error="$3" expected_output="$4"
  shift 4

  local output_file="$tmp/github-output" status=0
  : > "$output_file"

  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    GITHUB_OUTPUT="$output_file" \
    GITHUB_SHA="$test_sha" \
    GITHUB_RUN_ID="$test_run_id" \
    GITHUB_RUN_ATTEMPT="$test_attempt" \
    PI_MIN_SUPPORTED_VERSION="3.14" \
    "$@" \
    bash "$script" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?

  if [[ "$status" -ne "$expected_exit" ]]; then
    report_failure "$label" "expected exit ${expected_exit}, got ${status}"
    return
  fi

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if ! grep -Fq -- "$line" "$tmp/stderr"; then
      report_failure "$label" "stderr is missing: ${line}"
      return
    fi
  done <<< "$expected_error"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if ! grep -Fqx -- "$line" "$output_file"; then
      report_failure "$label" "GITHUB_OUTPUT is missing: ${line}"
      return
    fi
  done <<< "$expected_output"

  if [[ "$expected_exit" -ne 0 && -s "$output_file" ]]; then
    report_failure "$label" "a rejected dispatch must not publish outputs"
    return
  fi

  passed=$((passed + 1))
  echo "ok: ${label}"
}

assert_case "release dispatch on a v* tag succeeds" 0 "" \
  $'channel=release\nversion=3.14.1\nstaging_tag=stg-43178109188-1-3.14.1\nsha_short=5e31c9a28ebd' \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1 \
  INPUT_CHANNEL=release INPUT_VERSION=3.14.1

assert_case "release dispatch without a channel input defaults to release" 0 "" \
  $'channel=release\nversion=3.14.1' \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1 \
  INPUT_VERSION=3.14.1

assert_case "release dispatch without pi_version is rejected" 1 \
  "pi_version input is required for release dispatch and must equal 3.14.1" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1 \
  INPUT_CHANNEL=release

assert_case "release dispatch with a mismatched pi_version is rejected" 1 \
  "pi_version 3.14.0 does not match ref v3.14.1" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1 \
  INPUT_CHANNEL=release INPUT_VERSION=3.14.0

assert_case "release dispatch on a pre-release tag is rejected" 1 \
  "ref v3.14.1-rc1 is not a release tag" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1-rc1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1-rc1 \
  INPUT_CHANNEL=release INPUT_VERSION=3.14.1-rc1

assert_case "release dispatch below the supported floor is rejected" 1 \
  "version 3.13.0 is below the supported floor 3.14" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.13.0 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.13.0 \
  INPUT_CHANNEL=release INPUT_VERSION=3.13.0

assert_case "default release dispatch on main names both corrective commands" 1 \
  $'release dispatch must target a release tag, got refs/heads/main\n--ref v<version> -f pi_version=<version>\n--ref main -f channel=edge' "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/heads/main EVENT_REF_TYPE=branch EVENT_REF_NAME=main

assert_case "explicit edge dispatch on main succeeds and resolves the PyPI version" 0 "" \
  $'channel=edge\nversion=3.14.2\nstaging_tag=stg-43178109188-1-3.14.2' \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/heads/main EVENT_REF_TYPE=branch EVENT_REF_NAME=main \
  INPUT_CHANNEL=edge PYPI_VERSION=3.14.2

assert_case "edge dispatch rejects a pi_version input" 1 \
  "pi_version must be omitted for channel=edge" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/heads/main EVENT_REF_TYPE=branch EVENT_REF_NAME=main \
  INPUT_CHANNEL=edge INPUT_VERSION=3.14.2 PYPI_VERSION=3.14.2

assert_case "edge dispatch rejects a non-release PyPI version" 1 \
  "resolved PyPI version main is not a release version" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/heads/main EVENT_REF_TYPE=branch EVENT_REF_NAME=main \
  INPUT_CHANNEL=edge PYPI_VERSION=main

assert_case "edge dispatch on a tag ref is rejected" 1 \
  "edge dispatch must target the main branch, got refs/tags/v3.14.1" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1 \
  INPUT_CHANNEL=edge PYPI_VERSION=3.14.1

assert_case "edge dispatch on a feature branch is rejected" 1 \
  "edge dispatch must target the main branch, got refs/heads/feature/x" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/heads/feature/x EVENT_REF_TYPE=branch EVENT_REF_NAME=feature/x \
  INPUT_CHANNEL=edge PYPI_VERSION=3.14.1

assert_case "default release dispatch on a feature branch is rejected with guidance" 1 \
  $'release dispatch must target a release tag, got refs/heads/feature/x\n--ref main -f channel=edge' "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/heads/feature/x EVENT_REF_TYPE=branch EVENT_REF_NAME=feature/x

assert_case "unknown channel value is rejected" 1 \
  "unsupported channel input 'stable'" "" \
  EVENT_NAME=workflow_dispatch EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1 \
  INPUT_CHANNEL=stable INPUT_VERSION=3.14.1

assert_case "push of a v* tag is a release" 0 "" \
  $'channel=release\nversion=3.14.1' \
  EVENT_NAME=push EVENT_REF=refs/tags/v3.14.1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1

assert_case "push of a non-release tag is rejected" 1 \
  "ref v3.14.1-rc1 is not a release tag" "" \
  EVENT_NAME=push EVENT_REF=refs/tags/v3.14.1-rc1 EVENT_REF_TYPE=tag EVENT_REF_NAME=v3.14.1-rc1

assert_case "push to main is an edge build" 0 "" \
  $'channel=edge\nversion=3.15.0' \
  EVENT_NAME=push EVENT_REF=refs/heads/main EVENT_REF_TYPE=branch EVENT_REF_NAME=main \
  PYPI_VERSION=3.15.0

assert_case "push to a feature branch is rejected" 1 \
  "unsupported event/ref: push refs/heads/feature/x" "" \
  EVENT_NAME=push EVENT_REF=refs/heads/feature/x EVENT_REF_TYPE=branch EVENT_REF_NAME=feature/x

echo
if [[ "$failed" -gt 0 ]]; then
  echo "${failed} case(s) failed, ${passed} passed" >&2
  exit 1
fi

# Wiring guard: release.yml must pass every input the script reads and keep the
# script as the validate step. Renaming one side alone would silently turn a
# validated dispatch back into an unvalidated one.
workflow="${repo_root}/.github/workflows/release.yml"
wiring_failed=0
while IFS= read -r needle; do
  if ! grep -Fq -- "$needle" "$workflow"; then
    echo "FAIL: release.yml is missing: ${needle}" >&2
    wiring_failed=1
  fi
done <<'EOF'
INPUT_CHANNEL: ${{ github.event.inputs.channel }}
INPUT_VERSION: ${{ github.event.inputs.pi_version }}
EVENT_REF_TYPE: ${{ github.ref_type }}
EVENT_REF_NAME: ${{ github.ref_name }}
run: .github/scripts/resolve-release-input.sh
        default: release
          - edge
EOF

if [[ "$wiring_failed" -ne 0 ]]; then
  echo "release.yml wiring check failed, ${passed} case(s) passed" >&2
  exit 1
fi

echo "all ${passed} release input cases passed"
