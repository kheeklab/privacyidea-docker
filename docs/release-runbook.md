# Release runbook

Operational rules for `.github/workflows/release.yml` and `.github/workflows/check-pi-version.yml`. This runbook does not grant approval to publish.

## Tag classes and write rules

| Ref or image tag | Meaning | Writer and mutability |
| :-- | :-- | :-- |
| `vV` | Upstream numeric privacyIDEA release | Feeder may create only after the approval gate; never overwrite |
| `V` | Mutable image alias for installed version `V` | Numeric release or rebuild may move it to its tested digest |
| `V-YYYYMMDD[-NNN]` | Immutable image release identity | Release workflow only; a different digest is always refused |
| `vV-YYYYMMDD[-NNN]` | Explicit image rebuild trigger, not an upstream version | Member/maintainer creates; feeder never creates or dispatches it |
| `vV` image tag, `latest` | Numeric release pointers | Numeric route only; `latest` follows the highest numeric GitHub release |
| `edge`, `sha-<12>` | Edge or numeric commit pointers | Edge route writes GHCR only; numeric route may write both registries |

Rebuild route uses option A: it writes only `V-YYYYMMDD[-NNN]` and `V` in both registries. It does not move `vV`, `latest`, `edge`, or `sha-<12>`, create a GitHub Release, or edit the numeric release ledger. A real upstream patch such as `v3.14.1` uses the numeric route, installs exactly `3.14.1`, and gets its own dated identity and alias.

## Approval boundaries

Repository variable `FEEDER_APPROVED_VERSIONS` is the feeder allowlist. Add an exact numeric version only after member approval to create its upstream ref and dispatch its numeric release. Scheduled execution alone grants no approval. The workflow then runs with the repository's configured release environment and credentials.

Every outward action still needs explicit member approval: merge; git tag push; workflow dispatch; staging writes; dated tag creation in GHCR and Docker Hub; alias move in each registry; any `vV` or `latest` move; GitHub Release creation or edit; registry repair. A successful CI run or `in_review` status authorizes none of these actions.

## Dispatch and identity reservation

Numeric releases are dispatched against the upstream tag:

```console
gh workflow run release.yml --ref v3.14.1 -f channel=release -f pi_version=3.14.1
```

Rebuilds use an annotated ref at the implementation commit. Choose the current UTC date when reserving a new intent. Use bare date if unused; otherwise use the next unused sequence greater than every accepted sequence for that version and day (`001`–`999`). `000` is invalid. Dispatch with the matching installed version:

```console
gh workflow run release.yml --ref v3.14-YYYYMMDD -f channel=release -f pi_version=3.14
```

The durable intent is stored as `intents/<version>/<identity>.json` on the repository's `release-intents` orphan branch. The workflow reads and writes it under the shared `release-publish` concurrency group. A failed concurrent push stops the run. The record fixes the identity, ref, commit, date, tested digest and expected prior registry values. A retry resumes that intent and digest. It must not rebuild into a recorded identity. New intents cannot be backdated beyond seven days or use future/impossible dates.

The resolver requires upstream `vV` and exact PyPI package `V` for rebuilds. Dockerfile gets its requirements ref explicitly; it installs exactly `privacyidea==V`. For supported upstream forms, versions follow `major.minor[.patch]`.

## Promotion and recovery

The workflow builds staging tags, tests the same multi-arch index on native amd64 and arm64, verifies installed package version, and runs the blocking CRITICAL Trivy gate. Under the publication lock it reads the full numeric GitHub Releases ledger immediately before deciding `latest`.

Before any consumer write, promotion inspects every target in both registries. Only a confirmed manifest absence counts as absent; authorization, network, and other inspection errors stop promotion. It writes dated immutable tags first, reads each back, then writes the mutable version alias and reads it back. Registry index digests must equal the tested digest. A mismatch freezes further promotion for that version; retain evidence and investigate. Registry repair requires separate approval.

The promotion journal records version, identity, ref, commit, tested digest, expected previous alias values, per-registry before/after values, ledger ordering evidence, and skipped pointer decisions. Workflow artifacts and staging evidence are retained at least 90 days. A partial two-registry write can resume only from the same recorded intent and digest when every existing target matches; no alternate identity or digest retry is allowed.

For numeric releases, `latest` moves only if that version is the highest actual numeric release in the freshly read ledger. If a newer numeric release arrives before promotion, the dated identity and version alias may publish, while `latest` stays unchanged. Rebuilds never move `latest`.

## Feeder contract

`check-pi-version.yml` discovers only numeric upstream refs at or above the support floor with an exact PyPI package. It creates missing numeric refs at HEAD only when `FEEDER_APPROVED_VERSIONS` contains the version, then dispatches `release.yml` with matching `pi_version`. Reconciliation dispatches only approved numeric refs without a GitHub Release. Dated identities, rebuild refs, and other suffixed refs are excluded from discovery and retry.

## Rollback

Revert the workflow/script/docs commit to stop using this release path. A revert does not retract published identities, aliases, pointers, GitHub Releases, or ledger entries. Restoring or deleting published state requires a separately approved repair with before/after digests recorded in the issue.

Known historical drift remains out of scope: Docker Hub `3.13` differs from GHCR `3.13`; the existing `3.14` and `v3.14` image tags also differ. Do not repair either as part of this runbook.
