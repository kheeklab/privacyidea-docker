# AGENTS.md — project guide for coding agents

Commands and facts in this file were verified against the files named here; when code and README disagree, the code is the source of truth.

## What this repo is

A Docker image that packages privacyIDEA (installed from PyPI) on `python:3.12-slim`, targeting privacyIDEA 3.14 and newer (upstream removed the separate kerberos requirements file in 3.14, so none are installed). The Dockerfile (build) creates a Python virtualenv at `/opt/privacyidea` in a builder stage, then the runtime stage copies it, adds `tini`, and runs as the non-root user `nobody` with gunicorn as the WSGI server (Dockerfile:28–50). Configuration is env-var-only: `configure_privacyidea.sh` builds `pi.cfg` from `rootfs/opt/templates/pi-config.template` via `envsubst`, then gunicorn is `exec`'d as a direct child of tini so it receives Docker's SIGTERM for graceful shutdown.

## Commands that matter

From `Makefile` (default target is `help`, Makefile:40):

```bash
make build    # docker build -t $(IMAGE):$(IMAGE_TAG) .  (Makefile:12)
make run      # cleanup + create_volume + secretkey + pipepper, then docker run -p 8080:8080 with --env-file=secretkey --env-file=pipepper (Makefile:18)
make test     # container-structure-test test --image $(IMAGE):$(IMAGE_TAG) --config structure-tests.yaml (Makefile:38)
make push     # docker push $(IMAGE):$(IMAGE_TAG) (Makefile:16)
make cleanup  # stop/remove privacyidea-dev container, sudo rm -rf /tmp/privacyidea-data (Makefile:32)
```

`make run` requires the generated files `secretkey` (PI_SECRET_KEY) and `pipepper` (PI_PEPPER) in the repo root; `make` creates them. Requires container-structure-test on PATH.

CI pipeline in `.github/workflows/release.yml` (triggers: push to `main`, `v*` tags, PRs, manual dispatch with `pi_version`):

```bash
docker build --build-arg PI_VERSION=${PI_VERSION} -t privacyidea:test .        # release.yml:143
container-structure-test test --image privacyidea:test --config structure-tests.yaml   # release.yml:157, CST v1.22.1 installed in CI
docker compose --file docker-compose-test.yml build --build-arg PI_VERSION=${PI_VERSION}  # release.yml:175
docker compose --file docker-compose-test.yml up --exit-code-from sut --timeout 120       # release.yml:176
docker compose --file docker-compose-test.yml down -v                                     # release.yml:178
```

Dockerfile lint is hadolint with `no-fail: true` (release.yml:121–126); CI builds/pushes amd64+arm64 to Docker Hub and GHCR on non-PR runs, then Trivy (CRITICAL,HIGH, report-only). `.github/workflows/check-pi-version.yml` runs daily, creates missing `v*` tags for privacyIDEA releases available on PyPI, and pushes them, which retriggers release.yml.

## Repository map

```text
Dockerfile                 multi-stage build; venv at /opt/privacyidea, nobody, tini, VOLUME /data/privacyidea (Dockerfile:1–50)
docker-compose.yml         demo stack: pi + mariadb (pi-db), wordpress + mariadb (wp-db); publishes 8080, 3306, 3307, 8081
docker-compose-test.yml    test stack: pi-app (build with PI_VERSION=main) + sut running ./run-tests.sh (docker-compose-test.yml:1–19)
Makefile                   build/push/run/test/cleanup/help targets
requirements.txt           psycopg2==2.9.10, gunicorn==23.0.0 (added to the venv)
structure-tests.yaml       schemaVersion 2.0.0 (CI runs container-structure-test v1.22.1): metadata (env defaults, user nobody, workdir, entrypoint, port 8080, volume), file existence/permissions, bash -n syntax checks, logging/audit template assertions
run-tests.sh               integration check: waits for pi-app:8080, asserts page title 'pivacyIDEA'
tests/                     test-db-uri-encoding.sh: PI_DB_PASSWORD round-trips through one jq @uri encoding
README.md                  user-facing docs (partially drifted — see below)
CLAUDE.md                  Claude-Code-specific guide (partially drifted — see below)
prebuildfs/                /usr/sbin/install_packages helper sourced at Dockerfile:39/41
rootfs/usr/local/bin/      privacyidea_entrypoint.sh, configure_privacyidea.sh, _privacyidea_common.sh
rootfs/opt/privacyidea/    gunicorn_conf.py, pi-logging.yml
rootfs/opt/templates/      pi-config.template
example/                   docker-compose-posgresql.yml
.github/workflows/         release.yml (buildx CI), check-pi-version.yml (daily tag sync)
```

## Runtime contract

Startup chain, in order, all inside the container (files under `rootfs/`, copied to their container paths by Dockerfile:47):

```text
tini (Dockerfile:50 ENTRYPOINT)
  └─ /usr/local/bin/privacyidea_entrypoint.sh        rootfs/usr/local/bin/privacyidea_entrypoint.sh
      ├─ execute_scripts /usr/local/privacyidea/scripts/pre-configure    (line 24; helper: _privacyidea_common.sh:3)
      ├─ execute_scripts /usr/local/privacyidea/scripts/pre-startup      (line 27)
      ├─ source configure_privacyidea.sh                                  (line 31)
      │    ├─ generate_pi_config: build SQLALCHEMY_DATABASE_URI from PI_DB_*, envsubst template → /etc/privacyidea/pi.cfg, rewrite log level/file in pi-logging.yml
      │    └─ prestart_privacyidea: copy ${PI_MOUNT_DIR}/files into PI_HOME, run ${PI_MOUNT_DIR}/scripts, then unless PI_SKIP_BOOTSTRAP: pi-manage setup create_tables / create_enckey / create_audit_keys / admin add
      └─ exec gunicorn -c /opt/privacyidea/gunicorn_conf.py "privacyidea.app:create_app(...)"    (lines 39–50; with --certfile/--keyfile if /etc/privacyidea/server.{key,crt} exist)
```

The `exec` (privacyidea_entrypoint.sh:39–50) replaces the shell, making gunicorn a direct child of tini (PID 1), so Docker's SIGTERM reaches gunicorn and shuts it down gracefully. Do not replace this handoff with a foreground child shell.

## Configuration surface

Only environment variables; there is no dotenv loader in the image. Families:

| Family | Variables | Where they act |
| :-- | :-- | :-- |
| Bootstrap | `PI_SKIP_BOOTSTRAP`, `PI_AUTO_UPDATE` | configure_privacyidea.sh:170 (`=false` runs pi-manage setup), :232–238 (schema upgrade only when skip=true and auto-update=true); Dockerfile ENV defaults |
| Database | `PI_DB_VENDOR`, `PI_DB_NAME`, `PI_DB_HOST`, `PI_DB_USER`, `PI_DB_PASSWORD`, `PI_DB_ARGS` (+ `PI_DB_PORT`, `SQLALCHEMY_DATABASE_URI` override) | configure_privacyidea.sh:53–97 builds SQLAlchemy URI; `PI_DB_PASSWORD` is the plain password, percent-encoded exactly once with jq at :32; template renders URI at pi-config.template:18 |
| Secrets | `PI_SECRET_KEY`, `PI_PEPPER` | read at runtime by pi-config.template:5,10; refuses to start if unset; created by Makefile `secretkey`/`pipepper` |
| Admin | `PI_ADMIN_USER`, `PI_ADMIN_PASSWORD` | configure_privacyidea.sh:208–225; required for non-SQLite, defaults admin/privacyidea for SQLite |
| Paths | `PI_DATA_DIR`, `PI_CFG_DIR`, `PI_CFG_FILE`, `PI_HOME`, `PI_MOUNT_DIR` | Dockerfile ENV (31–37); PI_MOUNT_DIR set to /etc/privacyidea/mount or /mnt/privacyidea at privacyidea_entrypoint.sh:15–21; used for file copy/script hooks (configure_privacyidea.sh:145–167) |
| Logging | `PI_LOGLEVEL`, `PI_LOGFILE`, `PI_LOGCONFIG` | app logs go to stdout via the `console` handler by default; `PI_LOGFILE` set to a real path switches the logger to the rotating `file` handler (configure_privacyidea.sh:113–150); template reads the values at pi-config.template:31–33 |
| TLS | `PI_SSLPORT` + mounted `/etc/privacyidea/server.key` / `server.crt` | gunicorn bind at privacyidea_entrypoint.sh:39–50 (default 8443; only bound when both files exist) |

gunicorn tuning uses the `GUNICORN_*` variables that `rootfs/opt/privacyidea/gunicorn_conf.py` actually reads (see drift section before trusting README).

## Persistence

- `/data/privacyidea` — declared VOLUME (Dockerfile:49); holds `privacyidea.db` for SQLite (configure_privacyidea.sh:95) and `/data/privacyidea/keys/` (encfile, private.pem/public.pem; :179–205).
- `/etc/privacyidea` — runtime config `pi.cfg` and TLS material; chowned to nobody (Dockerfile:42–43) but not a declared volume.
- External DB — MariaDB/PostgreSQL via `PI_DB_VENDOR` + the `PI_DB_*` variables; demo stack uses bitnami images with their default env vars (docker-compose.yml:4–30).
- There is no backup or restore tooling anywhere in the repo; volume deletion destroys the database and keys with no recovery path in-repo.

## Conventions in force

- Shell: `set -e` only, no `pipefail`/`-u` (privacyidea_entrypoint.sh:2, configure_privacyidea.sh:2); mixed `function name {}` and `name() {}` styles in the same file (e.g. configure_privacyidea.sh:20 vs _privacyidea_common.sh:3). Keep new code consistent with whichever form sits nearest.
- Dockerfile: global ARGs declared before the first FROM, re-declared inside each stage (Dockerfile:1–7, 28–29); defaults in one multi-key ENV block (31–37); layer ordering installs runtime packages and chowns before `USER nobody`.
- Docs: user-facing docs live as tables in README.md (Environment variables, gunicorn variables); CLAUDE.md carries architecture and testing notes for Claude sessions.
- Commits: recent history uses gitmoji + imperative subject; no format is enforced by CI or hooks.

## Known verified drift (documented; do not fix silently)

None currently. The former `PI_DB_PASSWORD` double-encoding note was a contract, not a defect: input is the plain password, percent-encoded exactly once at configure_privacyidea.sh:32 (see the Database row above and tests/test-db-uri-encoding.sh).

## Working rules for agents

- Read the code, not the README, to determine behaviour; treat README/CLAUDE.md claims as needing verification (see drift above).
- Configuration/data-plane changes go through environment variables and `pi-config.template` (or new `PI_*` keys read there) — not edits to generated runtime files.
- Do not add a HEALTHCHECK-motivated change alone: `curl` was installed into the image (Dockerfile:41) for a healthcheck that does not exist; if you introduce one, wire it in the same change and update structure-tests.yaml.
- There is no unit-test framework. Regression gates are container-structure-test (`make test`, structure-tests.yaml), the integration test via docker-compose-test.yml + run-tests.sh, and `bash tests/test-db-uri-encoding.sh` (needs a built image, `IMAGE` env selects it); run or extend those for any behaviour change.
- Keep the image non-root (`USER nobody`, Dockerfile:44) and keep the `exec`-based handoff to gunicorn (privacyidea_entrypoint.sh:40,47) so SIGTERM shuts down gunicorn, not a shell wrapper.

## Pointers

- `.opencode/context/project-intelligence/` — detailed code patterns, naming table, and security requirements (owns the excerpt-level detail; this file stays high-level).
- `README.md` — user-facing build/run/config documentation.
- `CLAUDE.md` — Claude-specific guide; useful entry points but partially drifted (listed above).
