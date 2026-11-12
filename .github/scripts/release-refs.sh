#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared release ref and identity rules. Sourced by:
#   .github/scripts/resolve-release-input.sh   routing and input validation
#   .github/scripts/promote-release.sh         identity and tag class rules
#   .github/workflows/check-pi-version.yml     feeder discovery and reconciliation
#   tests/test-release-refs.sh                 unit cases for the rules below
#
# Keep this file free of network, registry and git access: every rule here has
# to be testable offline, and the workflows read them from one place so the
# resolver and the feeder cannot drift apart again.
# shellcheck disable=SC2034 # parse_* functions expose PARSED_* globals to callers.

# A real upstream privacyIDEA version: major.minor[.patch]. Anything else
# (pre-releases, dev tags, dated rebuild refs) is not a numeric release.
NUMERIC_VERSION_RE='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
NUMERIC_TAG_RE='^v[0-9]+\.[0-9]+(\.[0-9]+)?$'

# Rebuild ref: v<V>-<YYYYMMDD> or v<V>-<YYYYMMDD>-<NNN>. The optional sequence
# is three digits, 001-999; 000 is reserved and rejected by callers.
REBUILD_TAG_RE='^v([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]{8})(-([0-9]{3}))?$'

# Immutable image release identity: <V>-<YYYYMMDD>[-NNN].
DATED_IDENTITY_RE='^([0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]{8})(-([0-9]{3}))?$'

is_numeric_version() {
  [[ "${1:-}" =~ $NUMERIC_VERSION_RE ]]
}

is_numeric_tag() {
  [[ "${1:-}" =~ $NUMERIC_TAG_RE ]]
}

is_rebuild_tag() {
  [[ "${1:-}" =~ $REBUILD_TAG_RE ]]
}

is_dated_identity() {
  [[ "${1:-}" =~ $DATED_IDENTITY_RE ]]
}

# Version components used to resolve the upstream requirements ref.
version_major_minor() {
  local version="${1:-}"
  is_numeric_version "$version" || return 1
  printf '%s.%s\n' "${version%%.*}" "$(printf '%s' "$version" | cut -d. -f2)"
}

# parse_rebuild_ref <ref>
#
# Sets PARSED_VERSION, PARSED_DATE and PARSED_SEQUENCE (empty for a bare date).
# Returns non-zero for a non-rebuild ref or the ambiguous sequence 000.
parse_rebuild_ref() {
  local ref="${1:-}"
  [[ "$ref" =~ $REBUILD_TAG_RE ]] || return 1
  # These globals are the documented result values consumed by callers.
  # shellcheck disable=SC2034
  PARSED_VERSION="${BASH_REMATCH[1]}"
  PARSED_DATE="${BASH_REMATCH[3]}"
  PARSED_SEQUENCE="${BASH_REMATCH[5]:-}"
  [[ "$PARSED_SEQUENCE" != "000" ]] || return 1
  return 0
}

# parse_dated_identity <identity>
#
# Sets PARSED_VERSION, PARSED_DATE and PARSED_SEQUENCE.
parse_dated_identity() {
  local identity="${1:-}"
  [[ "$identity" =~ $DATED_IDENTITY_RE ]] || return 1
  PARSED_VERSION="${BASH_REMATCH[1]}"
  PARSED_DATE="${BASH_REMATCH[3]}"
  PARSED_SEQUENCE="${BASH_REMATCH[4]:-}"
  PARSED_SEQUENCE="${PARSED_SEQUENCE#-}"
  [[ "$PARSED_SEQUENCE" != "000" ]] || return 1
  return 0
}

# route_identity <version> <YYYYMMDD> [sequence]
route_identity() {
  local version="$1" date="$2" sequence="${3:-}"
  if [[ -n "$sequence" ]]; then
    printf '%s-%s-%s\n' "$version" "$date" "$sequence"
  else
    printf '%s-%s\n' "$version" "$date"
  fi
}

utc_today() {
  date -u +%Y%m%d
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# A real calendar date in YYYYMMDD form. Rejects 20260231, 20261301, etc.
is_calendar_date() {
  local ymd="${1:-}" rendered
  [[ "$ymd" =~ ^[0-9]{8}$ ]] || return 1
  rendered=$(date -u -d "${ymd:0:4}-${ymd:4:2}-${ymd:6:2}" +%Y%m%d 2>/dev/null) || return 1
  [[ "$rendered" == "$ymd" ]]
}

# True when <YYYYMMDD> is after the UTC date of the caller.
is_future_date() {
  local ymd="${1:-}" today
  today="${TODAY_UTC:-$(utc_today)}"
  [[ "$ymd" > "$today" ]]
}

# Whole days between <YYYYMMDD> and the UTC date of the caller (positive: past).
date_age_days() {
  local ymd="${1:-}" then_epoch today_epoch today
  today="${TODAY_UTC:-$(utc_today)}"
  then_epoch=$(date -u -d "${ymd:0:4}-${ymd:4:2}-${ymd:6:2} 00:00:00" +%s)
  today_epoch=$(date -u -d "${today:0:4}-${today:4:2}-${today:6:2} 00:00:00" +%s)
  echo $(( (today_epoch - then_epoch) / 86400 ))
}

# Compare two numeric versions; true when $1 is strictly greater than $2.
version_gt() {
  local left="${1:-}" right="${2:-}" highest
  highest=$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -1)
  [[ "$highest" == "$left" && "$left" != "$right" ]]
}

# classify_target_tag <route> <tag>
#
# The explicit write allowlist from PERS-99, scoped per route. Prints
# immutable|mutable|forbidden. A route may write its own dated identity and
# only the mutable names listed for that route; everything else is refused.
#
#   rebuild (v<V>-<date>): <V>-<date>[-NNN] immutable, <V> mutable.
#   numeric (v<V>):        <V>-<date>[-NNN] immutable, <V>, v<V>, sha-<12> mutable.
#   edge:                  edge, sha-<12> mutable; no dated identity.
classify_target_tag() {
  local route="$1" tag="$2" version="${VERSION:-}"
  case "$route" in
    rebuild)
      if is_dated_identity "$tag" && [[ "$tag" == "${version}-"* ]]; then
        echo immutable
      elif [[ "$tag" == "$version" ]]; then
        echo mutable
      else
        echo forbidden
      fi
      ;;
    numeric)
      if is_dated_identity "$tag" && [[ "$tag" == "${version}-"* ]]; then
        echo immutable
      else
        case "$tag" in
          "$version"|"v$version"|sha-*) echo mutable ;;
          *) echo forbidden ;;
        esac
      fi
      ;;
    edge)
      case "$tag" in
        edge|sha-*) echo mutable ;;
        *) echo forbidden ;;
      esac
      ;;
    *)
      echo forbidden
      ;;
  esac
}
