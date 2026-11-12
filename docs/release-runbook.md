# Release runbook

Operational procedure for `.github/workflows/release.yml`. Written for the approval and recovery path; it does not authorise any registry action by itself.

## Preconditions

- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` are configured (release-channel runs fail closed without them). `DOCKERHUB_NAMESPACE` is optional and defaults to the repository owner.
- `ubuntu-24.04-arm` hosted runners are available to the repository.
- The `release` environment exists. Decide whether it needs required reviewers; without reviewers the publish job runs unattended.
- A GitHub release exists for every version already published (`v3.14`, ...). The release list is the ordering ledger. If the registry has a `latest` tag but no release exists, the publish job stops and asks for the baseline below.

## Normal release

Automated: the daily `Sync PI Tags` workflow creates a `vX.Y` tag above the 3.14 floor and dispatches `release.yml` for it.

Manual:

```console
gh workflow run release.yml --ref v3.14.1 -f pi_version=3.14.1
```

The workflow validates the ref and version before any credential is used, builds one multi-platform index under a run-scoped staging tag (`stg-<run-id>-<attempt>-<version>`), tests that digest natively on amd64 and arm64, then promotes it in a serialized publish job. Version tags are refused if a different digest already exists.

## Manual dispatch targets

`workflow_dispatch` takes two inputs: `channel` (`release` or `edge`, default `release`) and `pi_version` (release only). GitHub does not let a workflow restrict the branch/tag dropdown, so the supported combinations are enforced by `Validate release input` (`.github/scripts/resolve-release-input.sh`) before any credential is used.

| Ref selected in "Use workflow from" | `channel` | `pi_version` | Outcome |
| :-- | :-- | :-- | :-- |
| Release tag `v<version>` | `release` (default) | Required, must equal the tag version | Release: GHCR and Docker Hub version tags, GitHub release, `latest` when it is the highest version |
| `main` | `edge` | Must be omitted | Edge: GHCR `edge` and `sha-<12>` only |
| Any other branch | either | — | Rejected with the commands below |
| Release tag `v<version>` | `edge` | — | Rejected: edge builds come from `main` |
| `main` | `release` (default) | — | Rejected: a release needs a tag ref |

```console
# Release v3.14.1 (tag must already exist; the feeder creates tags)
gh workflow run release.yml --ref v3.14.1 -f pi_version=3.14.1

# Rebuild the edge channel from the current main HEAD
gh workflow run release.yml --ref main -f channel=edge
```

An edge dispatch resolves the version from PyPI, runs the same build, native tests and CRITICAL Trivy gate, and writes only the mutable `edge` and `sha-<12>` GHCR tags. It never creates a GitHub release, never logs in to Docker Hub, and never moves `latest`.

### A rejected dispatch

A rejected dispatch fails in `Validate release input` and does nothing else: no build, no test, no registry write, no release. The annotation names the fix.

| Message | Fix |
| :-- | :-- |
| `release dispatch must target a release tag` | Select the `v<version>` tag as the ref, or dispatch `--ref main -f channel=edge` for an edge build |
| `pi_version input is required for release dispatch` | Add `-f pi_version=<version>` matching the tag |
| `pi_version <x> does not match ref v<y>` | Correct `pi_version` or select the matching tag |
| `edge dispatch must target the main branch` | Use `--ref main` for `channel=edge` |
| `pi_version must be omitted for channel=edge` | Drop the `pi_version` input; edge installs the current PyPI release |
| `unsupported channel input` | Use `release` or `edge` |

## Failure handling

### Promotion failed after some tags were written

The publish job fails closed and never overwrites a version tag whose digest differs. Recovery is manual:

1. Open the failed run and download the `release-promotion-<version>-<run>-<attempt>` artefact. It lists the tested index digest and every registry/tag already written.
2. Freeze further publication: do not re-dispatch the same version and do not run another release until this is closed.
3. Inspect both registries for the version tags and compare them with the tested digest in the journal.
4. Decide with the maintainer whether to complete the promotion by re-running the release (safe only if every written tag already matches the tested digest) or to repair tags. Repairing or deleting registry tags needs separate explicit approval.
5. If repair is approved, write the new digests and the decision into the issue record.

Staging tags (`stg-*`) are the evidence for this window. They are never deleted by a workflow or by a release. Keep them for at least 90 days; the promotion-journal artefact is retained for 90 days by `actions/upload-artifact`.

### `latest` did not move but the release exists

The GitHub release is created before the `latest` pointer moves. A failure in between leaves `latest` behind the ledger, never ahead.

1. Confirm the release `v<version>` exists and is the highest stable release.
2. If approved, move `latest` in each registry to the release's tested digest:

   ```console
   docker buildx imagetools create --tag ghcr.io/kheeklab/privacyidea:latest \
     ghcr.io/kheeklab/privacyidea:v<version>
   docker buildx imagetools create --tag kheeklab/privacyidea:latest \
     kheeklab/privacyidea:v<version>
   ```

   The release is already recorded, so a later run will skip this version; there is no automatic retry.
3. Record the digests before and after the change.

### Ledger baseline is missing

If `latest` exists in GHCR but no GitHub release does, publication stops rather than guessing the current version. Restore the ledger (restore the deleted releases, or recreate them from the known published tags), or obtain explicit approval for a one-off baseline decision. Do not move `latest` by hand without recording the version it points to.

### Re-dispatch fairness

The feeder re-dispatches every tag above the floor that has no GitHub release, on each daily run, with no fixed cap. A version that keeps failing fails visibly each day without starving later versions. A canceled pending publish run is re-dispatched on the next sync.

## Evidence and retention

- Promotion journal: one artifact per publish attempt, retained 90 days. Contains version, run URL, tested digest and each registry/tag write.
- Staging tags: keep 90 days minimum, then delete manually after confirming no open recovery.
- Workflow logs: GitHub default retention; do not rely on logs alone for a failed promotion.

## Attestations and signing

`provenance: mode=max` and `sbom: true` are attached to the GHCR index. Whether Docker Hub exposes the same referrers after the same-registry copy is not verified; treat GHCR as the authoritative attestation store. Image signing is not implemented (separate decision).

## Rollback

Reverting the workflow changes stops new releases from using this pipeline. It does not undo registry tags, `latest`, or GitHub releases already written; those are separate approved actions. Restore the previous workflow files and record which versions were published under which pipeline.

## Out of scope here

Registry tag restoration or deletion, retention/immutability policy, signing, and changing repository settings or the `release` environment protection are maintainer decisions, not runbook steps.
