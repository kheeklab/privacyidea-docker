#!/usr/bin/env bash
#
# Durable release identity reservation and digest-tested promotion.
#
# Invoked by .github/workflows/release.yml as
#
#   promote-release.sh reserve   before the build
#   promote-release.sh promote   after the build and tests passed
#
# Both modes run under the workflow's `release-publish` concurrency group, so
# they serialize with each other. The accepted-intent record lives on the
# `release-intents` orphan branch of this repository: one JSON file per
# identity under `intents/<version>/`, and one freeze marker per affected
# version under `freeze/<version>.json`. It is written with plain git commits,
# so a concurrent reservation loses the push and fails closed instead of
# overwriting another run's intent. Reading it needs no secrets beyond the
# workflow token, and it is retained with the repository.
#
# Nothing here may publish unless the caller already passed the member
# approval gate: `reserve` only records intent, `promote` writes registry tags.
#
# Inputs (environment):
#   ROUTE                 numeric | rebuild
#   VERSION               installed privacyIDEA version, e.g. 3.14 or 3.14.1
#   IDENTITY              rebuild only: <V>-<YYYYMMDD>[-NNN] from the ref
#   REF_NAME              git ref that triggered the run
#   GHCR_REPO             ghcr.io/<owner>/privacyidea
#   HUB_ENABLED           true when Docker Hub is a publication target
#   HUB_REPO              <namespace>/privacyidea (when HUB_ENABLED)
#   TESTED_DIGEST         promote only: tested multi-arch OCI index digest
#   HUB_DIGEST            promote only: Docker Hub staging digest (must equal tested)
#   SHA_SHORT             commit short SHA used for the numeric sha-<12> alias
#   INTENTS_REMOTE_URL    git URL with write access to the intents branch
#   INTENT_STORE_DIR      working clone of the intents branch
#   INTENTS_BRANCH        default release-intents
#   RUN_URL, COMMIT_SHA   evidence recorded in the journal
#   JOURNAL               promote only: journal output path
#   LEDGER_FILE           test-only override: newline list of released versions
#   REBUILD_INTENT_MAX_AGE_DAYS   default 7
#   GITHUB_OUTPUT         when set, key=value outputs are appended there
#
# Outputs:
#   reserve: identity, action (build|promote-only), tested_digest
#   promote: identity, move_latest, ghcr_dated, hub_dated, ghcr_alias, hub_alias
set -euo pipefail

mode="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/release-refs.sh
. "${script_dir}/release-refs.sh"

fail() {
  echo "::error::$*" >&2
  exit 1
}

warn() {
  echo "::warning::$*" >&2
}

emit_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}

route="${ROUTE:?ROUTE is required}"
version="${VERSION:?VERSION is required}"
identity="${IDENTITY:-}"
ref_name="${REF_NAME:-}"
ghcr_repo="${GHCR_REPO:?GHCR_REPO is required}"
hub_enabled="${HUB_ENABLED:-false}"
hub_repo="${HUB_REPO:-}"
tested_digest="${TESTED_DIGEST:-}"
hub_digest="${HUB_DIGEST:-}"
sha_short="${SHA_SHORT:-}"
store_dir="${INTENT_STORE_DIR:?INTENT_STORE_DIR is required}"
remote_url="${INTENTS_REMOTE_URL:?INTENTS_REMOTE_URL is required}"
intents_branch="${INTENTS_BRANCH:-release-intents}"
journal="${JOURNAL:-${RUNNER_TEMP:-/tmp}/promotion-journal.md}"
run_url="${RUN_URL:-}"
commit_sha="${COMMIT_SHA:-unknown}"
max_age_days="${REBUILD_INTENT_MAX_AGE_DAYS:-7}"
today="${TODAY_UTC:-$(utc_today)}"

[[ "$route" == "numeric" || "$route" == "rebuild" ]] || fail "unsupported route '${route}'"
is_numeric_version "$version" || fail "version '${version}' is not a numeric release version"

inspect_err="${TMPDIR:-/tmp}/release-inspect-$$.err"
git_err="${TMPDIR:-/tmp}/release-git-$$.err"
trap 'rm -f "$inspect_err" "$git_err" 2>/dev/null || true' EXIT

intent_dir() { printf '%s/intents/%s\n' "$store_dir" "$version"; }
intent_path() { printf '%s/%s.json\n' "$(intent_dir)" "$1"; }
freeze_path() { printf '%s/freeze/%s.json\n' "$store_dir" "$version"; }

# --- intents store ---------------------------------------------------------

store_git() { git -C "$store_dir" "$@"; }

store_init() {
  if [[ -d "$store_dir/.git" ]]; then
    store_git fetch --quiet --depth 1 origin "$intents_branch"
    store_git reset --hard --quiet "origin/${intents_branch}"
  else
    rm -rf "$store_dir"
    if git ls-remote --exit-code --heads "$remote_url" "$intents_branch" >/dev/null 2>&1; then
      git clone --quiet --depth 1 --branch "$intents_branch" "$remote_url" "$store_dir"
    else
      mkdir -p "$store_dir"
      git -C "$store_dir" init --quiet --initial-branch="$intents_branch"
      git -C "$store_dir" remote add origin "$remote_url"
      mkdir -p "$store_dir/intents" "$store_dir/freeze"
      {
        echo "# Release intents"
        echo
        echo "Durable accepted-intent and freeze records written by"
        echo "\`.github/scripts/promote-release.sh\` from \`.github/workflows/release.yml\`."
        echo "Never edit by hand: a manual edit invalidates the ordering assumption"
        echo "and requires human reconciliation (docs/release-runbook.md)."
      } > "$store_dir/README.md"
    fi
  fi
  mkdir -p "$(intent_dir)" "$store_dir/freeze"
  store_git config user.name "github-actions[bot]"
  store_git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
}

store_commit_push() {
  local message="$1"
  store_git add -A
  if store_git diff --cached --quiet; then
    return 0
  fi
  store_git commit --quiet -m "$message"
  if ! store_git push --quiet origin "HEAD:${intents_branch}" 2>"$git_err"; then
    cat "$git_err" >&2 || true
    fail "could not record the release intent on ${intents_branch}: another run reserved or updated an identity concurrently. Nothing was published; inspect the intent ledger and re-run."
  fi
}

freeze_marker() { # reason
  local reason="$1" path
  path=$(freeze_path)
  jq -n \
    --arg version "$version" \
    --arg route "$route" \
    --arg identity "$identity" \
    --arg digest "$tested_digest" \
    --arg reason "$reason" \
    --arg run "$run_url" \
    --arg at "$(utc_now)" \
    '{version: $version, route: $route, identity: $identity, tested_digest: $digest, reason: $reason, run: $run, frozen_at: $at}' > "$path"
  store_commit_push "freeze: halt ${version} promotions (${reason})" || true
}

freeze_and_fail() {
  local reason="$1"
  freeze_marker "$reason"
  fail "${reason}. Promotions for ${version} are frozen by freeze/${version}.json; preserve the evidence, investigate, and treat registry repair as a separately authorized action (docs/release-runbook.md)."
}

require_not_frozen() {
  local path
  path=$(freeze_path)
  if [[ -f "$path" ]]; then
    fail "promotions for ${version} are frozen by freeze/${version}.json ($(jq -r '.reason // "no reason recorded"' "$path")). Investigation and a separately authorized repair are required before any further promotion"
  fi
}

# Most recent intent recorded for this version, or non-zero when there is none.
# Used by the numeric route: a re-dispatch continues the accepted intent (and
# its retained tested digest) instead of reserving a second identity for the
# same upstream version.
choose_latest_intent() {
  local dir path name best="" best_date="" best_seq_num=-1 seq_num
  dir=$(intent_dir)
  [[ -d "$dir" ]] || return 1
  for path in "$dir"/*.json; do
    [[ -e "$path" ]] || continue
    name=$(basename "$path" .json)
    parse_dated_identity "$name" || continue
    seq_num=$((10#${PARSED_SEQUENCE:-0}))
    if [[ -z "$best" ]]; then
      best="$path" best_date="$PARSED_DATE" best_seq_num="$seq_num"
    elif [[ "$PARSED_DATE" > "$best_date" ]]; then
      best="$path" best_date="$PARSED_DATE" best_seq_num="$seq_num"
    elif [[ "$PARSED_DATE" == "$best_date" ]] && (( seq_num > best_seq_num )); then
      best="$path" best_date="$PARSED_DATE" best_seq_num="$seq_num"
    fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

# Number of the highest accepted sequence for a version and UTC date.
# -1 means the day is unused; 0 means only the bare date is accepted.
day_max_sequence() { # YYYYMMDD
  local day="$1" dir max=-1 path name
  dir=$(intent_dir)
  [[ -d "$dir" ]] || { echo -1; return 0; }
  for path in "$dir"/*.json; do
    [[ -e "$path" ]] || continue
    name=$(basename "$path" .json)
    parse_dated_identity "$name" || continue
    [[ "$PARSED_VERSION" == "$version" && "$PARSED_DATE" == "$day" ]] || continue
    if [[ -z "$PARSED_SEQUENCE" ]]; then
      [[ "$max" -lt 0 ]] && max=0
    else
      (( 10#${PARSED_SEQUENCE} > max )) && max=$((10#${PARSED_SEQUENCE}))
    fi
  done
  echo "$max"
}

# --- registry --------------------------------------------------------------

registry_inspect() {
  docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}'
}

# Prints a digest, ABSENT for an authenticated confirmed absence, or ERROR.
# An authorization, rate-limit or network failure is ERROR, never ABSENT.
inspect_outcome() {
  local ref="$1" out status=0
  out=$(registry_inspect "$ref" 2>"$inspect_err") || status=$?
  if (( status == 0 )); then
    if [[ "$out" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      printf '%s\n' "$out"
    else
      printf 'ERROR\n'
    fi
    return 0
  fi
  if grep -qiE 'manifest unknown|no such manifest|manifest[^ ]* not found|: not found|name unknown' "$inspect_err"; then
    printf 'ABSENT\n'
  else
    printf 'ERROR\n'
  fi
}

registry_copy() { # source_ref target_ref
  docker buildx imagetools create --tag "$2" "$1"
}

journal_row() { # registry tag class before after
  # Backticks are literal Markdown table delimiters.
  # shellcheck disable=SC2016
  printf '| %s | `%s` | %s | `%s` | `%s` |\n' "$1" "$2" "$3" "$4" "$5" >> "$journal"
}

journal_init() {
  mkdir -p "$(dirname "$journal")"
  {
    echo "# Promotion journal"
    echo
    echo "- version (installed privacyIDEA): ${version}"
    echo "- route: ${route}"
    echo "- image release identity: ${identity}"
    echo "- git ref: ${ref_name:-unknown}"
    echo "- commit: ${commit_sha}"
    echo "- tested multi-arch index digest: ${tested_digest:-not-yet-built}"
    echo "- run: ${run_url:-unknown}"
    echo "- requirements ref: ${REQUIREMENTS_REF:-unknown}"
    echo "- upstream numeric ledger highest at promotion: ${ledger_max:-unread}"
    echo "- newer numeric upstream release than this version detected: ${newer_numeric:-not-checked}"
    echo "- latest move: ${move_latest:-not-decided}"
    echo
    echo "| Registry | Tag | Class | Before | After |"
    echo "| :-- | :-- | :-- | :-- | :-- |"
  } > "$journal"
}

# --- ledger and pointer policy --------------------------------------------

read_ledger_versions() {
  if [[ -n "${LEDGER_FILE:-}" ]]; then
    grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' "$LEDGER_FILE" | sort -V || true
    return 0
  fi
  local raw
  raw=$(gh api --paginate --slurp "repos/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}/releases?per_page=100") \
    || fail "could not read the GitHub release ledger; refusing to compute pointer ordering"
  jq -e 'type == "array"' >/dev/null <<< "$raw" \
    || fail "release ledger response was not a JSON array"
  jq -r '.[][]? // empty | .tag_name' <<< "$raw" \
    | sed 's/^v//' \
    | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' \
    | sort -V || true
}

compute_pointer_policy() {
  local versions
  versions=$(read_ledger_versions)
  ledger_max=""
  if [[ -n "$versions" ]]; then
    ledger_max=$(printf '%s\n' "$versions" | tail -1)
  fi
  newer_numeric=false
  if [[ -n "$ledger_max" ]] && version_gt "$ledger_max" "$version"; then
    newer_numeric=true
  fi

  if [[ "$route" == "numeric" ]]; then
    # Only a normal numeric release may move latest, and only when it is the
    # highest numeric version in the ledger re-read under this lock.
    if [[ -z "$ledger_max" ]]; then
      move_latest=true
      local ghcr_latest hub_latest
      ghcr_latest=$(inspect_outcome "${ghcr_repo}:latest")
      [[ "$ghcr_latest" == "ERROR" ]] && fail "could not inspect ${ghcr_repo}:latest; refusing to decide the latest pointer on unreadable state"
      hub_latest="ABSENT"
      if [[ "$hub_enabled" == "true" ]]; then
        hub_latest=$(inspect_outcome "${hub_repo}:latest")
        [[ "$hub_latest" == "ERROR" ]] && fail "could not inspect ${hub_repo}:latest; refusing to decide the latest pointer on unreadable state"
      fi
      if [[ "$ghcr_latest" != "ABSENT" || "$hub_latest" != "ABSENT" ]]; then
        fail "no GitHub release exists but a latest tag is published (ghcr=${ghcr_latest}, dockerhub=${hub_latest}); establish the release-ledger baseline before the first release (see docs/release-runbook.md)"
      fi
    elif version_gt "$version" "$ledger_max"; then
      move_latest=true
    else
      move_latest=false
    fi
  else
    # Option A: a rebuild never moves latest, whatever the ledger says.
    move_latest=false
  fi
  export ledger_max newer_numeric move_latest
}

# --- reserve ---------------------------------------------------------------

identity_is_available_for_sequence() { # requested-sequence day-max
  local requested="$1" max="$2"
  if [[ -z "$requested" ]]; then
    (( max < 0 ))
  else
    (( 10#${requested} > max ))
  fi
}

reserve() {
  store_init
  require_not_frozen

  local action agent_digest path day max requested existing

  if [[ "$route" == "rebuild" ]]; then
    is_rebuild_tag "$ref_name" || fail "rebuild route requires a rebuild ref, got '${ref_name}'"
    parse_rebuild_ref "$ref_name" || fail "invalid rebuild ref '${ref_name}'"
    [[ "$PARSED_VERSION" == "$version" ]] || fail "rebuild ref ${ref_name} names version ${PARSED_VERSION}, not ${version}"
    [[ -n "$identity" ]] || fail "a rebuild needs its dated image identity"
    [[ "$identity" == "$(route_identity "$version" "$PARSED_DATE" "$PARSED_SEQUENCE")" ]] \
      || fail "image identity ${identity} does not match rebuild ref ${ref_name}"
    is_calendar_date "$PARSED_DATE" || fail "rebuild ref ${ref_name} carries ${PARSED_DATE}, which is not a real UTC calendar date"
    is_future_date "$PARSED_DATE" && fail "rebuild ref ${ref_name} carries ${PARSED_DATE}, which is in the future relative to the UTC date"
    (( $(date_age_days "$PARSED_DATE") > max_age_days )) \
      && fail "rebuild ref ${ref_name} is dated ${PARSED_DATE}, more than ${max_age_days} days before the UTC date; a new intent may not be backdated"

    day="$PARSED_DATE"
    requested="$PARSED_SEQUENCE"
    path=$(intent_path "$identity")
    if [[ -f "$path" ]]; then
      # An accepted identity remains retryable after its original date and
      # sequence become occupied. Its intent is the authority for reuse.
      [[ "$(jq -r '.version' "$path")" == "$version" && "$(jq -r '.identity' "$path")" == "$identity" ]] \
        || fail "existing intent at ${path} does not match ${version}/${identity}; refusing ambiguous identity reuse"
      agent_digest=$(jq -r '.tested_digest // ""' "$path")
      if [[ -n "$agent_digest" ]]; then
        action="promote-only"
        emit_output tested_digest "$agent_digest"
        echo "intent ${identity} already carries tested digest ${agent_digest}; resuming promotion without rebuilding"
      else
        action="build"
        echo "intent ${identity} exists without a tested digest; rebuilding the same identity"
      fi
    else
      (( $(date_age_days "$day") > max_age_days )) \
        && fail "new rebuild intent ${identity} is more than ${max_age_days} days old; choose today's UTC date"
      max=$(day_max_sequence "$day")
      if ! identity_is_available_for_sequence "$requested" "$max"; then
        if [[ -z "$requested" ]]; then
          fail "the bare date ${day} is already reserved for ${version} (highest accepted sequence: $(printf '%03d' "$max")); use v${version}-${day}-$(printf '%03d' $((max + 1))) or later"
        fi
        fail "sequence ${requested} for ${version} on ${day} is not greater than the highest accepted sequence $(printf '%03d' "$max"); use the next unused sequence"
      fi
      jq -n \
        --arg version "$version" \
        --arg route "$route" \
        --arg identity "$identity" \
        --arg ref "$ref_name" \
        --arg date "$day" \
        --arg sequence "$requested" \
        --arg requirements_ref "${REQUIREMENTS_REF:-}" \
        --arg commit "$commit_sha" \
        --arg run "$run_url" \
        --arg at "$(utc_now)" \
        '{
          version: $version,
          route: $route,
          identity: $identity,
          ref: $ref,
          date_utc: $date,
          sequence: $sequence,
          requirements_ref: $requirements_ref,
          status: "reserved",
          tested_digest: null,
          expected_previous: null,
          commit: $commit,
          run: $run,
          created_at: $at,
          updated_at: $at
        }' > "$path"
      store_commit_push "intent: reserve ${identity} for ${version} (${ref_name})"
      action="build"
    fi
  else
    # A numeric release reserves its dated identity before the build so the
    # identity and date are fixed in the accepted intent. A re-dispatch
    # continues the most recent unfinished intent instead of reserving a
    # second identity for the same upstream version.
    existing=""
    existing=$(choose_latest_intent) || existing=""
    if [[ -n "$existing" ]]; then
      identity=$(jq -r '.identity' "$existing")
      agent_digest=$(jq -r '.tested_digest // ""' "$existing")
      if [[ -n "$agent_digest" ]]; then
        action="promote-only"
        emit_output tested_digest "$agent_digest"
        echo "intent ${identity} already carries tested digest ${agent_digest}; resuming promotion without rebuilding"
      else
        action="build"
        echo "intent ${identity} exists without a tested digest; rebuilding the same identity"
      fi
    else
      day="$today"
      max=$(day_max_sequence "$day")
      if (( max < 0 )); then
        requested=""
      else
        (( max >= 999 )) && fail "all 999 sequences for ${version} on ${day} are reserved; promote a newer upstream version instead of reusing an exhausted day"
        requested=$(printf '%03d' $((max + 1)))
      fi
      identity=$(route_identity "$version" "$day" "$requested")
      path=$(intent_path "$identity")
      jq -n \
        --arg version "$version" \
        --arg route "$route" \
        --arg identity "$identity" \
        --arg ref "$ref_name" \
        --arg date "$day" \
        --arg sequence "$requested" \
        --arg requirements_ref "${REQUIREMENTS_REF:-}" \
        --arg commit "$commit_sha" \
        --arg run "$run_url" \
        --arg at "$(utc_now)" \
        '{
          version: $version,
          route: $route,
          identity: $identity,
          ref: $ref,
          date_utc: $date,
          sequence: $sequence,
          requirements_ref: $requirements_ref,
          status: "reserved",
          tested_digest: null,
          expected_previous: null,
          commit: $commit,
          run: $run,
          created_at: $at,
          updated_at: $at
        }' > "$path"
      store_commit_push "intent: reserve ${identity} for ${version} (${ref_name})"
      action="build"
    fi
  fi

  emit_output identity "$identity"
  emit_output action "$action"
  printf 'identity=%s action=%s\n' "$identity" "$action"
}

# --- promote ---------------------------------------------------------------

targets=()

add_target() { # class label repo tag
  targets+=("$1|$2|$3|$4")
}

build_targets() {
  targets=()
  add_target immutable GHCR "$ghcr_repo" "$identity"
  if [[ "$hub_enabled" == "true" ]]; then
    add_target immutable "Docker Hub" "$hub_repo" "$identity"
  fi
  add_target mutable GHCR "$ghcr_repo" "$version"
  if [[ "$hub_enabled" == "true" ]]; then
    add_target mutable "Docker Hub" "$hub_repo" "$version"
  fi
  if [[ "$route" == "numeric" ]]; then
    add_target mutable GHCR "$ghcr_repo" "v${version}"
    if [[ "$hub_enabled" == "true" ]]; then
      add_target mutable "Docker Hub" "$hub_repo" "v${version}"
    fi
    [[ -n "$sha_short" ]] || fail "numeric route needs SHA_SHORT for the sha-<12> alias"
    add_target mutable GHCR "$ghcr_repo" "sha-${sha_short}"
    if [[ "$hub_enabled" == "true" ]]; then
      add_target mutable "Docker Hub" "$hub_repo" "sha-${sha_short}"
    fi
  fi
}

# The write allowlist is the single source of truth; a target that is not on
# it is a bug and fails closed rather than being written.
assert_target_class() { # expected class label repo tag
  local expected="$1" label="$2" repo="$3" tag="$4" actual
  actual=$(classify_target_tag "$route" "$tag")
  [[ "$actual" == "$expected" ]] \
    || fail "refusing to write ${repo}:${tag}: classified '${actual}' for the ${route} route, expected '${expected}' (PERS-99 tag taxonomy)"
}

check_identity_target() { # label repo outcome
  local label="$1" repo="$2" outcome="$3" recorded
  [[ "$outcome" == "ERROR" ]] && fail "registry inspection failed for ${repo}:${identity}; a network or authorization error is not a confirmed absence, so promotion stops"
  if [[ "$outcome" != "ABSENT" && "$outcome" != "$tested_digest" ]]; then
    fail "immutable identity ${repo}:${identity} already exists with ${outcome}, not the tested ${tested_digest}; an identity is never reused for a different digest, allocate a new dated identity"
  fi
  recorded=$(jq -r --arg k "$label" '.expected_previous[$k] // ""' "$(intent_path "$identity")")
  if [[ -n "$recorded" && "$recorded" != "unknown" && "$outcome" != "$recorded" && "$outcome" != "$tested_digest" ]]; then
    fail "registry state for ${repo}:${identity} changed since the intent was accepted (recorded ${recorded}, now ${outcome}); refusing to promote"
  fi
}

check_alias_target() { # label repo outcome
  local label="$1" repo="$2" outcome="$3" recorded
  [[ "$outcome" == "ERROR" ]] && fail "registry inspection failed for ${repo}:${version}; a network or authorization error is not a confirmed absence, so promotion stops"
  recorded=$(jq -r --arg k "$label" '.expected_previous[$k] // ""' "$(intent_path "$identity")")
  [[ -n "$recorded" ]] || return 0
  [[ "$recorded" == "unknown" ]] && return 0
  if [[ "$recorded" == "absent" ]]; then
    [[ "$outcome" == "ABSENT" || "$outcome" == "$tested_digest" ]] \
      || fail "alias ${repo}:${version} was absent when the intent was accepted but is now ${outcome}; a rebuild never silently overwrites an unexpected alias value"
    return 0
  fi
  [[ "$outcome" == "$recorded" || "$outcome" == "$tested_digest" ]] \
    || fail "alias ${repo}:${version} changed from ${recorded} to ${outcome} since the intent was accepted; refusing the intended move"
}

write_target() { # class label repo tag
  local class="$1" label="$2" repo="$3" tag="$4" before after actual
  actual=$(classify_target_tag "$route" "$tag")
  [[ "$actual" == "$class" ]] \
    || fail "refusing to write ${repo}:${tag}: classified '${actual}' for the ${route} route, expected '${class}' (PERS-99 tag taxonomy)"

  before=$(inspect_outcome "${repo}:${tag}")
  [[ "$before" == "ERROR" ]] && freeze_and_fail "registry inspection failed for ${repo}:${tag} before writing"

  if [[ "$before" == "$tested_digest" ]]; then
    journal_row "$label" "$tag" "$class" "$before" "unchanged"
    echo "${repo}:${tag} already points at the tested digest"
    return 0
  fi

  if [[ "$class" == "immutable" && "$before" != "ABSENT" ]]; then
    fail "refusing to overwrite immutable identity ${repo}:${tag} (${before}) with the tested digest ${tested_digest}"
  fi

  registry_copy "${repo}@${tested_digest}" "${repo}:${tag}"
  after=$(inspect_outcome "${repo}:${tag}")
  if [[ "$after" != "$tested_digest" ]]; then
    journal_row "$label" "$tag" "$class" "$before" "${after:-no-digest}"
    freeze_and_fail "post-write readback for ${repo}:${tag} returned ${after:-no digest}, expected ${tested_digest}"
  fi
  journal_row "$label" "$tag" "$class" "$before" "$after"
  echo "promoted ${repo}:${tag} ${after}"
}

promote() {
  [[ -n "$tested_digest" ]] || fail "TESTED_DIGEST is required for promotion"
  [[ "$tested_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "TESTED_DIGEST '${tested_digest}' is not an OCI index digest"
  if [[ "$hub_enabled" == "true" ]]; then
    [[ "$hub_digest" == "$tested_digest" ]] \
      || fail "Docker Hub staging digest '${hub_digest}' is not the tested digest '${tested_digest}'; refusing to promote an untested artifact"
  fi

  store_init
  require_not_frozen
  [[ -n "$identity" ]] || fail "IDENTITY is required for promotion"
  [[ -f "$(intent_path "$identity")" ]] \
    || fail "no accepted intent for ${identity}; the release workflow must reserve an identity before building (run 'promote-release.sh reserve')"

  local intent recorded status
  intent=$(intent_path "$identity")
  recorded=$(jq -r '.tested_digest // ""' "$intent")
  if [[ -z "$recorded" ]]; then
    status="promotion recorded the tested digest; no rebuild has happened"
  elif [[ "$recorded" != "$tested_digest" ]]; then
    fail "intent ${identity} recorded tested digest ${recorded}, this run tested ${tested_digest}; an existing identity is never rebuilt into. Allocate a new dated identity"
  else
    status="resuming from the retained tested digest"
  fi

  build_targets
  journal_init

  local alias_ghcr alias_hub dated_ghcr dated_hub vpointer_ghcr vpointer_hub sha_ghcr sha_hub

  # Preflight every target in both registries before any consumer write.
  dated_ghcr=$(inspect_outcome "${ghcr_repo}:${identity}")
  check_identity_target ghcr_dated "$ghcr_repo" "$dated_ghcr"
  dated_hub="ABSENT"
  if [[ "$hub_enabled" == "true" ]]; then
    dated_hub=$(inspect_outcome "${hub_repo}:${identity}")
    check_identity_target dockerhub_dated "$hub_repo" "$dated_hub"
  fi

  alias_ghcr=$(inspect_outcome "${ghcr_repo}:${version}")
  check_alias_target ghcr_alias "$ghcr_repo" "$alias_ghcr"
  alias_hub="ABSENT"
  if [[ "$hub_enabled" == "true" ]]; then
    alias_hub=$(inspect_outcome "${hub_repo}:${version}")
    check_alias_target dockerhub_alias "$hub_repo" "$alias_hub"
  fi

  vpointer_ghcr="ABSENT"
  vpointer_hub="ABSENT"
  sha_ghcr="ABSENT"
  sha_hub="ABSENT"
  if [[ "$route" == "numeric" ]]; then
    vpointer_ghcr=$(inspect_outcome "${ghcr_repo}:v${version}")
    [[ "$vpointer_ghcr" == "ERROR" ]] && fail "registry inspection failed for ${ghcr_repo}:v${version}; promotion stops"
    vpointer_hub="ABSENT"
    sha_ghcr=$(inspect_outcome "${ghcr_repo}:sha-${sha_short}")
    [[ "$sha_ghcr" == "ERROR" ]] && fail "registry inspection failed for ${ghcr_repo}:sha-${sha_short}; promotion stops"
    if [[ "$hub_enabled" == "true" ]]; then
      vpointer_hub=$(inspect_outcome "${hub_repo}:v${version}")
      [[ "$vpointer_hub" == "ERROR" ]] && fail "registry inspection failed for ${hub_repo}:v${version}; promotion stops"
      sha_hub=$(inspect_outcome "${hub_repo}:sha-${sha_short}")
      [[ "$sha_hub" == "ERROR" ]] && fail "registry inspection failed for ${hub_repo}:sha-${sha_short}; promotion stops"
    fi
  fi

  compute_pointer_policy
  journal_init

  # Persist the accepted intent, including the pointer values this promotion is
  # allowed to move, before the first write. A retry then has to find exactly
  # these values (or the tested digest) and fails closed otherwise.
  local expected_prev
  expected_prev=$(jq -n \
    --arg gd "$dated_ghcr" --arg hd "$dated_hub" \
    --arg ga "$alias_ghcr" --arg ha "$alias_hub" \
    --arg gv "$vpointer_ghcr" --arg hv "$vpointer_hub" \
    --arg gs "$sha_ghcr" --arg hs "$sha_hub" \
    '{ghcr_dated: $gd, dockerhub_dated: $hd, ghcr_alias: $ga, dockerhub_alias: $ha, ghcr_vpointer: $gv, dockerhub_vpointer: $hv, ghcr_sha: $gs, dockerhub_sha: $hs}')
  jq \
    --arg digest "$tested_digest" \
    --arg commit "$commit_sha" \
    --arg run "$run_url" \
    --arg at "$(utc_now)" \
    --argjson prev "$expected_prev" \
    '.tested_digest = $digest
     | .status = "promoting"
     | .expected_previous = $prev
     | .commit = $commit
     | .run = $run
     | .updated_at = $at' "$intent" > "${intent}.tmp"
  mv "${intent}.tmp" "$intent"
  store_commit_push "intent: accept ${identity} at ${tested_digest} (${status})"

  # Ordered writes: every immutable dated tag first, then the mutable alias,
  # then the numeric-only pointers. Each write is read back before the next.
  local entry class label repo tag
  for entry in "${targets[@]}"; do
    IFS='|' read -r class label repo tag <<< "$entry"
    assert_target_class "$class" "$label" "$repo" "$tag"
    write_target "$class" "$label" "$repo" "$tag"
  done

  # The alias invariant from PERS-99: in each registry the mutable alias and
  # the dated identity must both report the tested index.
  local ghcr_alias_after hub_alias_after
  ghcr_alias_after=$(inspect_outcome "${ghcr_repo}:${version}")
  [[ "$ghcr_alias_after" == "$tested_digest" ]] \
    || freeze_and_fail "alias invariant failed in GHCR: ${ghcr_repo}:${version} reports ${ghcr_alias_after}, expected ${tested_digest} (and ${identity})"
  hub_alias_after="skipped"
  if [[ "$hub_enabled" == "true" ]]; then
    hub_alias_after=$(inspect_outcome "${hub_repo}:${version}")
    [[ "$hub_alias_after" == "$tested_digest" ]] \
      || freeze_and_fail "alias invariant failed on Docker Hub: ${hub_repo}:${version} reports ${hub_alias_after}, expected ${tested_digest} (and ${identity})"
  fi

  jq \
    --arg digest "$tested_digest" \
    --arg ghcr "$ghcr_alias_after" \
    --arg hub "$hub_alias_after" \
    --arg at "$(utc_now)" \
    '.status = "promoted"
     | .promoted_at = $at
     | .alias_digest = {ghcr: $ghcr, dockerhub: $hub}
     | .updated_at = $at' "$intent" > "${intent}.tmp"
  mv "${intent}.tmp" "$intent"
  store_commit_push "intent: promoted ${identity} (${tested_digest})"

  {
    echo "- pointer decisions: latest=$([[ "$move_latest" == "true" ]] && echo move || echo skip) (route ${route})"
    echo "- v${version} pointer: $([[ "$route" == "numeric" ]] && echo moved || echo skipped)"
    echo "- sha-${sha_short:-none}: $([[ "$route" == "numeric" ]] && echo moved || echo skipped)"
    echo "- edge: skipped (release and rebuild routes never write it)"
    echo "- GitHub release: $([[ "$route" == "numeric" ]] && echo created-after-promotion || echo none-for-rebuild)"
    echo "- alias invariant: ${version} == ${identity} == ${tested_digest} in GHCR$([[ "$hub_enabled" == "true" ]] && echo " and Docker Hub")"
  } >> "$journal"

  emit_output identity "$identity"
  emit_output move_latest "$move_latest"
  emit_output ghcr_dated "$tested_digest"
  emit_output hub_dated "$([[ "$hub_enabled" == "true" ]] && echo "$tested_digest" || echo "")"
  emit_output ghcr_alias "$ghcr_alias_after"
  emit_output hub_alias "$hub_alias_after"
  printf 'promotion complete: identity=%s digest=%s move_latest=%s\n' "$identity" "$tested_digest" "$move_latest"
}

case "$mode" in
  reserve) reserve ;;
  promote) promote ;;
  *)
    fail "usage: promote-release.sh reserve|promote"
    ;;
esac
