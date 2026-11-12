#!/usr/bin/env bash
#
# Resolve and validate a release.yml invocation into one publication route.
#
# Three routes are supported. One place decides what a run is allowed to
# publish:
#   - push of a numeric v<V> tag, or workflow_dispatch channel=release on it
#         -> route=numeric, image release identity <V>-<YYYYMMDD>[-NNN]
#   - push of a rebuild ref v<V>-<YYYYMMDD>[-NNN], or workflow_dispatch
#     channel=release on it
#         -> route=rebuild, image release identity <V>-<YYYYMMDD>[-NNN]
#   - push to main, or workflow_dispatch channel=edge on main
#         -> route=edge, no dated identity
#
# Everything else fails closed with the exact command that would have worked.
# GitHub offers no way to restrict the ref dropdown of a workflow_dispatch, so
# the rejection message is the guard rail; see docs/release-runbook.md.
#
# Inputs (environment):
#   EVENT_NAME, EVENT_REF, EVENT_REF_TYPE, EVENT_REF_NAME  GitHub event context
#   INPUT_CHANNEL      workflow_dispatch channel input (release|edge), default release
#   INPUT_VERSION      workflow_dispatch pi_version input. Numeric route: required
#                      and equal to the ref version. Rebuild route: optional, but
#                      when supplied it must equal the ref version.
#   PI_MIN_SUPPORTED_VERSION  release floor, defaults to 3.14
#   REBUILD_INTENT_MAX_AGE_DAYS  backdating guard for a new rebuild intent,
#                      defaults to 7; a retry inside the window keeps its date
#   PI_UPSTREAM_GIT_URL  upstream repository used to confirm the rebuild ref
#   UPSTREAM_TAGS_FILE  test-only override: newline list of upstream v* tags.
#                       The workflow never sets it, so a real run asks upstream.
#   PYPI_VERSION       test-only override for the edge version lookup; the
#                      workflow never sets it, so a real edge run reads PyPI
#   PYPI_VERSIONS_FILE test-only override: newline list of PyPI versions,
#                      used for the rebuild route's exact-package check
#   GITHUB_SHA, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT
#   GITHUB_OUTPUT      when set, key=value outputs are appended there
#
# Outputs: route, version, identity, requirements_ref, channel, staging_tag,
#          sha_short, ref_date, sequence
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/release-refs.sh
. "${script_dir}/release-refs.sh"

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
upstream_git_url="${PI_UPSTREAM_GIT_URL:-https://github.com/privacyidea/privacyidea.git}"

release_example='release: gh workflow run release.yml --ref v<version> -f pi_version=<version> (or pick the v<version> tag in the "Use workflow from" dropdown)'
rebuild_example='rebuild: gh workflow run release.yml --ref v<version>-<YYYYMMDD> (pick the rebuild tag in the "Use workflow from" dropdown; pi_version may be omitted)'
edge_example='edge: gh workflow run release.yml --ref main -f channel=edge (or pick the main branch in the "Use workflow from" dropdown)'

# Edge builds install whatever privacyIDEA release PyPI currently serves, so
# the version is resolved, never supplied by the operator.
resolve_edge_version() {
  local resolved="${PYPI_VERSION:-}"
  if [[ -z "$resolved" ]]; then
    resolved=$(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
      https://pypi.org/pypi/privacyIDEA/json | jq -r '.info.version')
  fi
  [[ "$resolved" =~ $NUMERIC_VERSION_RE ]] || fail "resolved PyPI version ${resolved} is not a release version; retry once PyPI serves a release version"
  printf '%s\n' "$resolved"
}

list_upstream_tags() {
  if [[ -n "${UPSTREAM_TAGS_FILE:-}" ]]; then
    [[ -s "$UPSTREAM_TAGS_FILE" ]] || fail "UPSTREAM_TAGS_FILE ${UPSTREAM_TAGS_FILE} is empty or missing"
    cat "$UPSTREAM_TAGS_FILE"
    return 0
  fi
  local tags
  tags=$(git ls-remote --tags --refs "$upstream_git_url" 2>/dev/null \
    | sed 's|.*refs/tags/||' | sort -u) || fail "could not read upstream tags from ${upstream_git_url}; a rebuild needs the upstream tag that carries its requirements.txt"
  printf '%s\n' "$tags"
}

# Resolve the upstream ref that carries requirements.txt for an installed
# version. The installer pins the exact package (privacyidea==V), so the
# requirements file only has to come from the closest real upstream tag:
# v<V> when that tag exists, otherwise v<major.minor>.
resolve_requirements_ref() {
  local version="$1" upstream_tags major_minor
  upstream_tags=$(list_upstream_tags)
  major_minor=$(version_major_minor "$version") || fail "version ${version} has no major.minor form"

  if grep -qxF "v${version}" <<< "$upstream_tags"; then
    printf 'v%s\n' "$version"
    return 0
  fi
  if grep -qxF "v${major_minor}" <<< "$upstream_tags"; then
    echo "::warning::upstream tag v${version} does not exist; using v${major_minor} requirements.txt while installing privacyidea==${version}"
    printf 'v%s\n' "$major_minor"
    return 0
  fi
  fail "upstream has neither v${version} nor v${major_minor} in the 3.14 line; refusing to build an image whose requirements ref cannot be resolved"
}

assert_pypi_version_exists() {
  local version="$1"
  if [[ -n "${PYPI_VERSIONS_FILE:-}" ]]; then
    grep -qxF "$version" "$PYPI_VERSIONS_FILE" || fail "privacyIDEA ${version} is not on PyPI (checked PYPI_VERSIONS_FILE); refusing a rebuild that cannot install privacyidea==${version}"
    return 0
  fi
  if ! curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
    -o /dev/null "https://pypi.org/pypi/privacyIDEA/${version}/json"; then
    fail "privacyIDEA ${version} is not on PyPI; refusing a rebuild that cannot install privacyidea==${version}"
  fi
}

validate_floor() {
  local version="$1" highest
  highest=$(printf '%s\n%s\n' "$min_version" "$version" | sort -V | tail -1)
  [[ "$highest" == "$version" ]] || fail "version ${version} is below the supported floor ${min_version}"
}

# Rebuild route validation shared by the tag push and the dispatch path.
validate_rebuild_ref() {
  local ref="$1" upstream_tags
  is_rebuild_tag "$ref" || fail "ref ${ref} is not a rebuild tag (expected v<major>.<minor>[.<patch>]-<YYYYMMDD>[-NNN]). ${rebuild_example}"
  parse_rebuild_ref "$ref" || fail "ref ${ref} is not a rebuild tag; sequence 000 is ambiguous and not allowed (use 001-999). ${rebuild_example}"

  version="$PARSED_VERSION"
  ref_date="$PARSED_DATE"
  sequence="$PARSED_SEQUENCE"

  validate_floor "$version"

  is_calendar_date "$ref_date" || fail "rebuild ref ${ref} carries ${ref_date}, which is not a real UTC calendar date"
  if is_future_date "$ref_date"; then
    fail "rebuild ref ${ref} carries ${ref_date}, which is in the future relative to the UTC date. A new intent must carry today's UTC date"
  fi
  if [[ -n "$sequence" ]]; then
    [[ "$sequence" =~ ^[0-9]{3}$ && "$sequence" != "000" ]] \
      || fail "rebuild ref ${ref} has sequence '${sequence}'; only 001-999 is allowed"
  fi

  upstream_tags=$(list_upstream_tags)
  grep -qxF "v${version}" <<< "$upstream_tags" \
    || fail "upstream privacyIDEA has no v${version} tag; refusing a rebuild that cannot resolve its requirements.txt"
  assert_pypi_version_exists "$version"

  identity=$(route_identity "$version" "$ref_date" "$sequence")
  requirements_ref="v${version}"
}

if [[ "$event_name" == "workflow_dispatch" ]]; then
  # Default matches the workflow input default, so a dispatch that omits
  # channel is treated as a release attempt and rejected on a branch ref.
  channel="${input_channel:-release}"

  case "$channel" in
    release)
      if [[ "$ref_type" != "tag" ]]; then
        fail "release dispatch must target a release tag or rebuild tag, got ${event_ref}. ${release_example}. ${rebuild_example}. To rebuild the edge channel from main instead, use: ${edge_example}"
      fi
      if is_rebuild_tag "$ref_name"; then
        validate_rebuild_ref "$ref_name"
        route=rebuild
        if [[ -n "$input_version" && "$input_version" != "$version" ]]; then
          fail "pi_version ${input_version} does not match rebuild ref ${ref_name} (the installed version is ${version}). ${rebuild_example}"
        fi
      else
        [[ "$ref_name" =~ $NUMERIC_TAG_RE ]] \
          || fail "ref ${ref_name} is not a release or rebuild tag (expected v<major>.<minor>[.<patch>] or v<version>-<YYYYMMDD>[-NNN]). ${release_example}. ${rebuild_example}"
        route=numeric
        version="${ref_name#v}"
        [[ -n "$input_version" ]] || fail "pi_version input is required for numeric release dispatch and must equal ${version}. ${release_example}"
        [[ "$input_version" == "$version" ]] || fail "pi_version ${input_version} does not match ref v${version}. ${release_example}"
        identity=""
        requirements_ref="v${version}"
      fi
      ;;
    edge)
      [[ "$event_ref" == "refs/heads/main" ]] || fail "edge dispatch must target the main branch, got ${event_ref}. ${edge_example}"
      [[ -z "$input_version" ]] || fail "pi_version must be omitted for channel=edge: an edge build installs the current PyPI release and cannot honour a requested version. ${edge_example}"
      route=edge
      version=$(resolve_edge_version)
      identity=""
      requirements_ref="v${version}"
      ;;
    *)
      fail "unsupported channel input '${channel}'; supported values are release and edge. ${release_example}. ${rebuild_example}. ${edge_example}"
      ;;
  esac
elif [[ "$event_name" == "push" && "$ref_type" == "tag" ]]; then
  channel=release
  if is_rebuild_tag "$ref_name"; then
    validate_rebuild_ref "$ref_name"
    route=rebuild
  elif [[ "$ref_name" =~ $NUMERIC_TAG_RE ]]; then
    route=numeric
    version="${ref_name#v}"
    identity=""
    requirements_ref="v${version}"
  else
    fail "ref ${ref_name} is not a release or rebuild tag (expected v<major>.<minor>[.<patch>] or v<version>-<YYYYMMDD>[-NNN]); dated mirror identities are produced by release.yml and never tagged by hand"
  fi
elif [[ "$event_name" == "push" && "$event_ref" == "refs/heads/main" ]]; then
  channel=edge
  route=edge
  version=$(resolve_edge_version)
  identity=""
  requirements_ref="v${version}"
else
  fail "unsupported event/ref: ${event_name} ${event_ref}. Supported: push to main (edge), push of a v* numeric or rebuild tag (release), workflow_dispatch with channel=release on such a tag or channel=edge on main. ${release_example}. ${rebuild_example}. ${edge_example}"
fi

if [[ "$route" == "numeric" || "$route" == "rebuild" ]]; then
  validate_floor "$version"
  [[ "$version" =~ $NUMERIC_VERSION_RE ]] || fail "version ${version} is not a valid release version"
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
  printf 'route=%s\n' "$route"
  printf 'version=%s\n' "$version"
  printf 'identity=%s\n' "${identity:-}"
  printf 'requirements_ref=%s\n' "$requirements_ref"
  printf 'channel=%s\n' "$channel"
  printf 'staging_tag=%s\n' "$staging_tag"
  printf 'sha_short=%s\n' "$sha_short"
  printf 'ref_date=%s\n' "${ref_date:-}"
  printf 'sequence=%s\n' "${sequence:-}"
)
printf '%s\n' "$outputs"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf '%s\n' "$outputs" >> "$GITHUB_OUTPUT"
fi

echo "route=${route} channel=${channel} version=${version} identity=${identity:-none} requirements_ref=${requirements_ref} staging_tag=${staging_tag}"
