# Project Profile

## Purpose and verified source

`privacyidea-docker` builds a container image that installs privacyIDEA from PyPI on the official Python image (`README.md:5`, `Dockerfile:10,48`). This profile describes tracked `main` at `f3c01c28cefd6f3df6ea2fe95c4653088ee4024e` (2026-11-26). All file references below refer to that commit. Workflow definitions and scripts were inspected; workflow runs, published registry state, and deployment-specific behavior were not independently exercised.

## Languages and versions

- Python application/dependencies, based on `python:3.14-slim`, pinned by image index digest (`Dockerfile:1,10,48`). The project installs privacyIDEA from PyPI; the image targets 3.14 and newer (`Dockerfile:17-29,44`; `README.md:30`).
- Shell scripts run with Bash (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:1-2`; `.github/workflows/ci.yml:59-69`). Workflow tools include actionlint 1.7.12 and container-structure-test 1.22.1 (`.github/workflows/ci.yml:55-69,127-145`).
- Locally pinned Python overrides are `psycopg2==2.9.13`, `gunicorn==26.2.0`, and `certifi==2026.10.19` (`requirements.txt:1-11`). These are the pins at the recorded commit, not proposed Dependabot versions.

## Frameworks and image build

The builder creates `/opt/privacyidea`, installs privacyIDEA’s upstream requirements first, the exact privacyIDEA package next, and local `requirements.txt` overrides last (`Dockerfile:14-45`). The runtime image copies the virtual environment and `rootfs`, installs `tini`, runs as `nobody`, declares port `8080/tcp` and volume `/data/privacyidea`, and starts `tini` with the entrypoint (`Dockerfile:48-70`). The application is served by Gunicorn using `privacyidea.app:create_app(...)` (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:39-50`).

## Build, test, lint, and run commands

Run commands from the repository root. The Makefile defines these targets (`Makefile:6-38`):

```sh
make build   # docker build -t $(IMAGE):$(IMAGE_TAG) .
make test    # container-structure-test against the already built image
make run     # cleanup, create_volume, generate secretkey/pipepper, then docker run
make push    # docker push $(IMAGE):$(IMAGE_TAG)
make cleanup # stop/remove privacyidea-dev and remove /tmp/privacyidea-data
```

`IMAGE` defaults to the repository owner’s `privacyidea` image (or `privacyidea` if no owner is detected), and `IMAGE_TAG` defaults to `dev` (`Makefile:2-4`). `make run` uses the existing image; it does not build it. Although its prerequisites create `/tmp/privacyidea-data`, its `docker run` command does not mount that directory. `cleanup` removes the data directory but leaves generated `secretkey` and `pipepper` files in the repository root (`Makefile:18-35`). These details differ from the simplified usage description in `CLAUDE.md:12-16`.

The tracked CI gates and their evidence are:

| Command or gate | What it checks | Source |
| --- | --- | --- |
| Hadolint, `failure-threshold: error` | Dockerfile errors | `.github/workflows/ci.yml:27-33` |
| ShellCheck, `severity: error` | Shell errors; warnings do not fail this gate | `.github/workflows/ci.yml:44-53` |
| `actionlint -color` | Workflow syntax and semantics | `.github/workflows/ci.yml:55-69` |
| `bash tests/test-release-input.sh` | Release input accept/reject cases and workflow wiring; it also invokes `tests/test-release-promotion.sh` | `.github/workflows/ci.yml:71-84`; `tests/test-release-input.sh:276-333` |
| `docker build --build-arg "PI_VERSION=${PI_VERSION}" -t privacyidea:test .` | Builds the image on amd64 and arm64 runners | `.github/workflows/ci.yml:86-125` |
| `container-structure-test test --image privacyidea:test --config structure-tests.yaml` | Image metadata, user, files, permissions, syntax, and selected runtime configuration assertions | `.github/workflows/ci.yml:127-148`; `structure-tests.yaml:3-96` |
| `docker compose --file docker-compose-test.yml up --no-build --exit-code-from sut --timeout 120` | Compose integration startup/readiness and provisioned API scenarios; test services use SQLite | `.github/workflows/ci.yml:150-155`; `docker-compose-test.yml:8-18`; `run-tests.sh:9-41`; `tests/integration-provisioned-api.sh:13-115` |
| Installed-version assertion | Compares the image’s installed privacyIDEA package version with the requested version | `.github/workflows/ci.yml:156-167` |

There is no unit-test framework declared by these tracked gates. `IMAGE=privacyidea:test bash tests/test-db-uri-encoding.sh` is a manual regression check, not invoked by tracked workflows; it checks SQLAlchemy password round-trip after the script’s URI encoding and assembly (`tests/test-db-uri-encoding.sh:10-42`; `.github/workflows/ci.yml:1-171`). The Compose suite uses SQLite, so it does not exercise a live PostgreSQL service (`docker-compose-test.yml:8-18`).

## Runtime and configuration

The startup sequence selects the mount root, sources pre-configuration and pre-startup hooks, then sources `configure_privacyidea.sh` before launching Gunicorn (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:14-31`). Hook scripts are sourced in sorted glob order (`rootfs/usr/local/bin/_privacyidea_common.sh:3-24`). Configure owns generated `pi.cfg`, database URI assembly, file/script handling, bootstrap, keys/admin, and optional schema upgrade (`rootfs/usr/local/bin/configure_privacyidea.sh:19-103,120-196,205-309`). The entrypoint uses `exec` for Gunicorn, making it a direct child of `tini` for signal delivery (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:33-50`).

| Configuration area | Source of truth |
| --- | --- |
| Image defaults, runtime user, data/config paths, declared port/volume, entrypoint | `Dockerfile:48-70` |
| Database selection/URI, bootstrap, admin and key lifecycle, schema upgrade | `rootfs/usr/local/bin/configure_privacyidea.sh:19-103,205-309` |
| Rendered privacyIDEA application settings | `rootfs/opt/templates/pi-config.template:5-42` |
| Application logging configuration | `rootfs/opt/privacyidea/pi-logging.yml:7-25`; selection and file/stdout setup in `rootfs/usr/local/bin/configure_privacyidea.sh:51-103` |
| Gunicorn worker count, bind, logs, timeouts, keepalive | `rootfs/opt/privacyidea/gunicorn_conf.py:5-48` |
| TLS activation and bind precedence | `rootfs/usr/local/bin/privacyidea_entrypoint.sh:39-50` |

The image declares only `8080/tcp` and `/data/privacyidea` (`Dockerfile:64-70`). TLS starts only when both `/etc/privacyidea/server.key` and `/etc/privacyidea/server.crt` exist. In that mode `GUNICORN_BIND` takes precedence; otherwise the bind defaults to `0.0.0.0:${PI_SSLPORT:-8443}` (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:39-50`). The image does not declare port 8443 (`Dockerfile:68-70`). Gunicorn environment settings should be read from its tracked config (`rootfs/opt/privacyidea/gunicorn_conf.py:5-48`), not inferred from README’s table.

## Release and CI/CD

Pull requests run lint, release-input tests, and amd64/arm64 image tests in `.github/workflows/ci.yml:3-5,13-171`. The release workflow routes `main` to the edge channel and release refs through validation, multi-architecture build/test, scanning, and promotion (`.github/workflows/release.yml:33-50,290-423,435-535,690-749`). The version-check workflow runs on a daily schedule or manual dispatch, discovers upstream versions, applies an approval allowlist, and dispatches/reconciles releases (`.github/workflows/check-pi-version.yml:3-30,90-130,153-180,205-230`). Release input validation is implemented in `.github/scripts/resolve-release-input.sh`; operational tag mutability, rebuild behavior, approval boundaries, and recovery are described in `docs/release-runbook.md:5-22,24-50,52-60`.

README summarizes registries and tag channels (`README.md:17-40`): stable releases are described for Docker Hub, while GHCR carries all channels, including `edge`. It describes version tags as immutable, while `edge` and `sha-<12>` are moving aliases; use the runbook for the precise writer and rebuild rules (`README.md:24-40`; `docs/release-runbook.md:5-16`). Registry contents and workflow execution were not independently verified for this profile.

## Environments

- Local build/run uses Docker and Docker Compose; the Makefile and compose files are the command definitions (`Makefile:12-38`; `docker-compose.yml:1-57`; `docker-compose-test.yml:1-34`).
- CI uses GitHub-hosted `ubuntu-24.04` and `ubuntu-24.04-arm` runners (`.github/workflows/ci.yml:13-17,71-97`).
- The container defaults to SQLite and `/data/privacyidea`; mounts must be writable by the runtime user. Fresh named volumes inherit image ownership on first use, while bind mounts may need pre-chowning (`Dockerfile:51-63`; `README.md:216-218`).

## Conventions

- Keep the runtime non-root and use the `tini` entrypoint/`exec` startup contract (`Dockerfile:61-70`; `rootfs/usr/local/bin/privacyidea_entrypoint.sh:33-50`).
- The Docker base image is digest-pinned (`Dockerfile:10,48`); GitHub Actions are pinned by full commit SHA with version comments (example: `.github/workflows/ci.yml:22-28`). Dependabot is configured for dependency updates (`.github/dependabot.yml:1-41`).
- Release writes and tag meanings follow the approval boundaries in `docs/release-runbook.md:5-22`; CI success alone does not authorize publication (`docs/release-runbook.md:22`).

## Repository layout

- Root: Dockerfile, requirements, Makefile, README, and demo/test Compose files (`Dockerfile:1-70`; `requirements.txt:1-11`; `Makefile:1-40`; `docker-compose.yml:1-57`; `docker-compose-test.yml:1-34`).
- `rootfs/`: entrypoint/configuration scripts, templates, and Gunicorn/logging configuration (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:1-55`; `rootfs/usr/local/bin/configure_privacyidea.sh:1-309`; `rootfs/opt/templates/pi-config.template:1-42`; `rootfs/opt/privacyidea/gunicorn_conf.py:1-67`).
- `.github/workflows/`: CI, release, and upstream version-check workflows (`.github/workflows/ci.yml:1-171`; `.github/workflows/release.yml:1-749`; `.github/workflows/check-pi-version.yml:1-230`).
- `.github/scripts/`: release input resolution and promotion helpers (`.github/scripts/resolve-release-input.sh:1-252`; `.github/scripts/promote-release.sh`; `.github/scripts/release-refs.sh`).
- `tests/`: release input/promotion scripts, DB URI regression script, and provisioned API integration script (`tests/test-release-input.sh:1-333`; `tests/test-release-promotion.sh`; `tests/test-db-uri-encoding.sh:1-43`; `tests/integration-provisioned-api.sh:1-115`).
- `docs/`: release runbook (`docs/release-runbook.md:1-60`).

## Known drift and verification limits

- `AGENTS.md` is tracked, but its ShellCheck severity, dependency pins, and test descriptions are stale (`AGENTS.md:32,41-44`; current pins: `requirements.txt:1-11`; actual ShellCheck gate: `.github/workflows/ci.yml:44-53`).
- `CLAUDE.md` places `pre-startup` after configuration; the entrypoint runs both hook directories before sourcing configure (`CLAUDE.md:30-34`; `rootfs/usr/local/bin/privacyidea_entrypoint.sh:23-31`).
- README says `PI_AUTO_UPDATE` updates privacyIDEA to the latest version; source runs a schema upgrade (`README.md:114`; `rootfs/usr/local/bin/configure_privacyidea.sh:297-303`).
- README’s TLS description does not fully express that both files are required or that `GUNICORN_BIND` overrides `PI_SSLPORT` (`README.md:110`; `rootfs/usr/local/bin/privacyidea_entrypoint.sh:39-50`).
- `tests/test-db-uri-encoding.sh` is not a CI workflow invocation at this commit; Compose uses SQLite (`.github/workflows/ci.yml:1-171`; `docker-compose-test.yml:8-18`).
- README and runbook together describe tag behavior; consult both because mutable aliases and rebuild routes have distinct rules (`README.md:24-40`; `docs/release-runbook.md:5-16`).
- No claim is made here about successful execution of CI or release workflows, remote registry contents, real deployment mounts/proxies, or whether user-provided environment values work in every deployment. Those require environment-specific verification.

## Key directories

`rootfs/` contains runtime behavior; `.github/workflows/` and `.github/scripts/` contain automation; `tests/` contains checks; `docs/` contains operational documentation. See the cited inventory under [Repository layout](#repository-layout).

## Last verified date

2026-11-26 against `main` SHA `f3c01c28cefd6f3df6ea2fe95c4653088ee4024e`.
