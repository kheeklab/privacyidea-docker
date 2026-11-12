#!/usr/bin/env bash
#
# Resolve and validate a release.yml invocation into one publication channel.
#
# One place decides what a run is allowed to publish:
#   - push of a v* tag            -> release
#   - push to main                -> edge
#   - workflow_dispatch, channel=release on a v* tag ref -> release
#   - workflow_dispatch, channel=edge on the main branch -> edge
#
# Everything else fails closed with the exact command that would have worked.
# GitHub offers no way to restrict the ref dropdown of a workflow_dispatch, so
# the rejection message is the guard rail; see docs/release-runbook.md.
#
# Inputs (environment):
#   EVENT_NAME, EVENT_REF, EVENT_REF_TYPE, EVENT_REF_NAME  GitHub event context
#   INPUT_CHANNEL      workflow_dispatch channel input (release|edge), default release
#   INPUT_VERSION      workflow_dispatch pi_version input, release channel only
#   PI_MIN_SUPPORTED_VERSION  release floor, defaults to 3.14
#   GITHUB_SHA, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT
#   GITHUB_OUTPUT      when set, key=value outputs are appended there
#   PYPI_VERSION       test-only override for the edge version lookup; the
#                      workflow never sets it, so a real edge run reads PyPI
#
# Outputs: version, channel, staging_tag, sha_short
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

event_name="${EVENT_NAME:?EVENT_NAME is required}"
event_ref="${EVENT_REF:?EVENT_REF is required}"
ref_type="${EVENT_REF_TYPE:?EVENT_REF_TYPE is required}"
ref_name="${EVENT_REF_NAME:?EVENT_REF_NAME is required}"
input_channel="${INPUT_CHANNEL:-}"
input_version="${INPUT_VERSION:-}"
min_version="${PI_MIN_SUPPORTED_VERSION:-3.14}"

release_example='release: gh workflow run release.yml --ref v<version> -f pi_version=<version> (or pick the v<version> tag in the "Use workflow from" dropdown)'
edge_example='edge: gh workflow run release.yml --ref main -f channel=edge (or pick the main branch in the "Use workflow from" dropdown)'

version_regex='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
tag_regex='^v[0-9]+\.[0-9]+(\.[0-9]+)?$'

# Edge builds install whatever privacyIDEA release PyPI currently serves, so
# the version is resolved, never supplied by the operator.
resolve_edge_version() {
  local resolved="${PYPI_VERSION:-}"
  if [[ -z "$resolved" ]]; then
    resolved=$(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
      https://pypi.org/pypi/privacyIDEA/json | jq -r '.info.version')
  fi
  [[ "$resolved" =~ $version_regex ]] || fail "resolved PyPI version ${resolved} is not a release version; retry once PyPI serves a release version"
  printf '%s\n' "$resolved"
}

if [[ "$event_name" == "workflow_dispatch" ]]; then
  # Default matches the workflow input default, so a dispatch that omits
  # channel is treated as a release attempt and rejected on a branch ref.
  channel="${input_channel:-release}"

  case "$channel" in
    release)
      if [[ "$ref_type" != "tag" ]]; then
        fail "release dispatch must target a release tag, got ${event_ref}. ${release_example}. To rebuild the edge channel from main instead, use: ${edge_example}"
      fi
      [[ "$ref_name" =~ $tag_regex ]] || fail "ref ${ref_name} is not a release tag (expected v<major>.<minor>[.<patch>]). ${release_example}"
      version="${ref_name#v}"
      [[ -n "$input_version" ]] || fail "pi_version input is required for release dispatch and must equal ${version}. ${release_example}"
      [[ "$input_version" == "$version" ]] || fail "pi_version ${input_version} does not match ref v${version}. ${release_example}"
      ;;
    edge)
      [[ "$event_ref" == "refs/heads/main" ]] || fail "edge dispatch must target the main branch, got ${event_ref}. ${edge_example}"
      [[ -z "$input_version" ]] || fail "pi_version must be omitted for channel=edge: an edge build installs the current PyPI release and cannot honour a requested version. ${edge_example}"
      version=$(resolve_edge_version)
      ;;
    *)
      fail "unsupported channel input '${channel}'; supported values are release and edge. ${release_example}. ${edge_example}"
      ;;
  esac
elif [[ "$event_name" == "push" && "$ref_type" == "tag" ]]; then
  [[ "$ref_name" =~ $tag_regex ]] || fail "ref ${ref_name} is not a release tag (expected v<major>.<minor>[.<patch>])"
  version="${ref_name#v}"
  channel=release
elif [[ "$event_name" == "push" && "$event_ref" == "refs/heads/main" ]]; then
  channel=edge
  version=$(resolve_edge_version)
else
  fail "unsupported event/ref: ${event_name} ${event_ref}. Supported: push to main (edge), push of a v* tag (release), workflow_dispatch with channel=release on a v* tag or channel=edge on main. ${release_example}. ${edge_example}"
fi

if [[ "$channel" == "release" ]]; then
  [[ "$version" =~ $version_regex ]] || fail "version ${version} is not a valid release version"
  highest=$(printf '%s\n%s\n' "$min_version" "$version" | sort -V | tail -1)
  [[ "$highest" == "$version" ]] || fail "version ${version} is below the supported floor ${min_version}"
fi

sha_full="${GITHUB_SHA:?GITHUB_SHA is required}"
sha_short="${sha_full:0:12}"
[[ "$sha_short" =~ ^[0-9a-f]{12}$ ]] || fail "unexpected SHA ${sha_full}"

# One commit can build several versions (the feeder creates more than one v*
# ref at the same HEAD) and main resolves a moving PyPI version. A sha-only
# staging tag could be overwritten between build and promotion, so the staging
# identity carries the run and the version. sha-<12> remains a mutable
# consumer alias only.
staging_tag="stg-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}-${version}"
[[ "$staging_tag" =~ ^stg-[0-9]+-[0-9]+-[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "unexpected staging tag ${staging_tag}"

outputs=$(
  printf 'version=%s\n' "$version"
  printf 'channel=%s\n' "$channel"
  printf 'staging_tag=%s\n' "$staging_tag"
  printf 'sha_short=%s\n' "$sha_short"
)
printf '%s\n' "$outputs"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf '%s\n' "$outputs" >> "$GITHUB_OUTPUT"
fi

echo "channel=${channel} version=${version} staging_tag=${staging_tag}"
