# Project Profile

## Purpose and verified source

`privacyidea-docker` builds a container image that installs privacyIDEA from PyPI on the official Python image (`README.md:5`, `Dockerfile:10,48`). This profile describes tracked `main` at `f3c01c28cefd6f3df6ea2fe95c4653088ee4024e` (2026-11-26). All file references below refer to that commit except the dated dependency-pin update below, verified against `main` at `259f8de086a251e9185f333e6df53acb67d26d8c` (2026-11-26). Workflow definitions and scripts were inspected; workflow runs, published registry state, and deployment-specific behavior were not independently exercised.

## Languages and versions

- Python application/dependencies, based on `python:3.14-slim`, pinned by image index digest (`Dockerfile:1,10,48`). The project installs privacyIDEA from PyPI; the image targets 3.14 and newer (`Dockerfile:17-29,44`; `README.md:30`).
- Shell scripts run with Bash (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:1-2`; `.github/workflows/ci.yml:59-69`). Workflow tools include actionlint 1.7.12 and container-structure-test 1.22.1 (`.github/workflows/ci.yml:55-69,127-145`).
- Locally pinned Python overrides are `psycopg2==2.9.13`, `gunicorn==27.0.1`, and `certifi==2026.10.23` (`requirements.txt:1-2,19` at `259f8de086a251e9185f333e6df53acb67d26d8c`, 2026-11-26). The psycopg2 pin is unchanged from the profile's recorded commit.

## Frameworks and image build

The builder creates `/opt/privacyidea`, installs privacyIDEA’s upstream requirements first, the exact privacyIDEA package next, and local `requirements.txt` overrides last (`Dockerfile:14-45`). `PI_VERSION` defaults to `main` and empty/`main` resolves to the current PyPI privacyIDEA release. The upstream requirements ref defaults to `v<version>`; Dockerfile falls back to `v<major.minor>` if the first ref has no requirements file (`Dockerfile:2-7,17-38`). The runtime image copies the virtual environment and `rootfs`, installs `tini`, runs as `nobody`, declares port `8080/tcp` and volume `/data/privacyidea`, and starts `tini` with the entrypoint (`Dockerfile:48-70`). The application is served by Gunicorn using `privacyidea.app:create_app(...)` (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:39-50`).

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

There is no unit-test framework declared by these tracked gates. `IMAGE=privacyidea:test bash tests/test-db-uri-encoding.sh` is a manual regression check, not invoked by tracked workflows; it checks SQLAlchemy password round-trip after the script’s URI encoding and assembly (`tests/test-db-uri-encoding.sh:10-42`; `.github/workflows/ci.yml:1-171`). The Compose suite uses SQLite, so it does not exercise a live PostgreSQL service (`docker-compose-test.yml:8-18`). Open questions: the manual DB URI check does not establish a live external-database integration gate, and TLS binding plus mounts/permissions still need deployment-specific verification; existing CI does not cover those paths (`.github/workflows/ci.yml:86-171`; `docker-compose-test.yml:8-18`).

## Runtime and configuration

The startup sequence selects the mount root, sources pre-configuration and pre-startup hooks, then sources `configure_privacyidea.sh` before launching Gunicorn (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:14-31`). Hook scripts are sourced in sorted glob order (`rootfs/usr/local/bin/_privacyidea_common.sh:3-24`). Configure owns generated `pi.cfg`, database URI assembly, file/script handling, bootstrap, keys/admin, and optional schema upgrade (`rootfs/usr/local/bin/configure_privacyidea.sh:19-103,120-196,205-309`). The entrypoint uses `exec` for Gunicorn, making it a direct child of `tini` for signal delivery (`rootfs/usr/local/bin/privacyidea_entrypoint.sh:33-50`).

| Main inputs and defaults | Source owner and evidence |
| --- | --- |
| `PI_DATA_DIR=/data/privacyidea` (persistent data and SQLite DB); `PI_CFG_DIR=/etc/privacyidea`; `PI_CFG_FILE=pi.cfg`; image volume is `/data/privacyidea` | Docker defaults and volume: `Dockerfile:51-69`; SQLite URI: `rootfs/usr/local/bin/configure_privacyidea.sh:79-95`; generated config path: `rootfs/usr/local/bin/configure_privacyidea.sh:106-117` |
| `PI_DB_VENDOR=sqlite`; empty `SQLALCHEMY_DATABASE_URI` selects `PI_DB_*` construction, while a supplied URI overrides those fields. SQLite stores `privacyidea.db` under `PI_DATA_DIR`; non-SQLite vendor inputs and DB password are required when constructing that URI. | Image default: `Dockerfile:51-55`; selection, URI override, and vendor-specific URI: `rootfs/usr/local/bin/configure_privacyidea.sh:19-103` |
| `PI_SECRET_KEY` and `PI_PEPPER` are required; there is no source default. | Template exits if either is missing: `rootfs/opt/templates/pi-config.template:5-13` |
| `PI_SKIP_BOOTSTRAP=false`; `PI_AUTO_UPDATE=false`. Bootstrap marker is `${PI_DATA_DIR}/.privacyidea_initialized`; update runs the schema upgrade when enabled. | Image defaults: `Dockerfile:51-55`; bootstrap and marker: `rootfs/usr/local/bin/configure_privacyidea.sh:198-220,248-295`; schema upgrade: `rootfs/usr/local/bin/configure_privacyidea.sh:297-304` |
| `PI_LOGLEVEL=INFO`; `PI_LOGFILE` unset uses stdout, a real path selects rotating-file logging; logging config defaults to `/opt/privacyidea/pi-logging.yml`. | Template defaults: `rootfs/opt/templates/pi-config.template:31-33`; log level and destination: `rootfs/usr/local/bin/configure_privacyidea.sh:120-164`; handlers: `rootfs/opt/privacyidea/pi-logging.yml:7-25` |
| Plain HTTP Gunicorn bind defaults to `0.0.0.0:8080`; `GUNICORN_BIND` overrides `GUNICORN_HOST` and `GUNICORN_PORT`. | `rootfs/opt/privacyidea/gunicorn_conf.py:12-19` |
| TLS activates only if both `/etc/privacyidea/server.key` and `/etc/privacyidea/server.crt` exist; bind is `GUNICORN_BIND` if set, otherwise `0.0.0.0:${PI_SSLPORT:-8443}`. Port 8443 is not declared by the image. | `rootfs/usr/local/bin/privacyidea_entrypoint.sh:39-50`; declared port and volume: `Dockerfile:68-70` |

The image declares only `8080/tcp` and `/data/privacyidea` (`Dockerfile:64-70`). Gunicorn environment settings should be read from its tracked config (`rootfs/opt/privacyidea/gunicorn_conf.py:5-48`), not inferred from README’s table.

## Release and CI/CD

Pull requests run lint, release-input tests, and amd64/arm64 image tests in `.github/workflows/ci.yml:3-5,13-171`. Release has three publication routes (`.github/workflows/release.yml:37-50`): **edge** publishes GHCR `edge` and `sha-<12>` only; **numeric** publishes the dated identity, plain version alias, `v<V>`, and `sha-<12>`, creates a GitHub Release and may move `latest`; **rebuild** publishes only its dated tag and plain version alias in both registries. The workflow’s Trivy SARIF scan reports OS and library vulnerabilities to code scanning and is non-blocking (`.github/workflows/release.yml:387-400,414-419`). The table-format Trivy scan blocks promotion on fixable CRITICAL OS/library findings; `.trivyignore` exceptions are applied (`.github/workflows/release.yml:402-412`).

The version-check workflow runs on a daily schedule or manual dispatch, discovers upstream versions, and dispatches/reconciles releases (`.github/workflows/check-pi-version.yml:3-30,90-130,153-180,205-230`). `FEEDER_APPROVED_VERSIONS` is the member-approved numeric-version allowlist for creating upstream refs and dispatching releases (`docs/release-runbook.md:18-20,52-54`). Release input validation is implemented in `.github/scripts/resolve-release-input.sh:1-252`; promotion in `.github/scripts/promote-release.sh:1-731`; release ref helpers in `.github/scripts/release-refs.sh:1-170`. Operational tag mutability, approval boundaries, and recovery are described in `docs/release-runbook.md:5-22,24-50,52-60`.

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

Verification date: **2026-11-26**, against `main` SHA `f3c01c28cefd6f3df6ea2fe95c4653088ee4024e`.
