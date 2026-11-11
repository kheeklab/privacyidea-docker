# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds a Docker image for [privacyIDEA](https://github.com/privacyidea/privacyidea), an open-source authentication and authorization solution. The image is based on Python and installs privacyIDEA with gunicorn as the WSGI server.

## Build Commands

```bash
make build       # Build Docker image locally (tag: mr-ssd/privacyidea:dev)
make run         # Build, create volumes, generate secrets, and run container
make test        # Run container-structure-test against the dev image
make push        # Push dev image to registry
make cleanup     # Remove container, volumes, and secret files
```

Build with specific privacyIDEA version:
```bash
docker build --build-arg PI_VERSION=3.14 -t privacyidea:test .
```

## Architecture

### Multi-stage Dockerfile
- **Builder stage**: Creates a Python virtual environment at `/opt/privacyidea`, installs privacyIDEA and dependencies
- **Runtime stage**: Copies the venv from builder, sets up runtime user (`nobody`), exposes port 8080

### Container Lifecycle Phases
1. **pre-configure** (`/usr/local/privacyidea/scripts/pre-configure`): Scripts run before configuration
2. **configure**: Generates `pi.cfg` from template using environment variables
3. **pre-startup** (`/usr/local/privacyidea/scripts/pre-startup`): Scripts run before privacyIDEA starts
4. **privacyIDEA startup**: Launches gunicorn with privacyIDEA

### Key Directories (in container)
- `/opt/privacyidea` - Python virtual environment and application code
- `/etc/privacyidea` - Runtime configuration
- `/data/privacyidea` - Data directory (SQLite DB, keys)
- `/var/log/privacyidea` - Log files
- `/mnt/privacyidea` or `/etc/privacyidea/mount` - Mount point for user-provided files and scripts

### Entry Point Scripts
- `rootfs/usr/local/bin/privacyidea_entrypoint.sh` - Main entry point, orchestrates lifecycle
- `rootfs/usr/local/bin/configure_privacyidea.sh` - Generates config, creates DB tables, admin user, encryption keys
- `rootfs/usr/local/bin/_privacyidea_common.sh` - Shared functions for script execution

### Configuration Template
`rootfs/opt/templates/pi-config.template` is processed by envsubst to generate `/etc/privacyidea/pi.cfg`. Uses `$SQLALCHEMY_DATABASE_URI` which is constructed from `PI_DB_*` environment variables.

### Database Support
Supports SQLite (default), MariaDB/MySQL, and PostgreSQL. The `SQLALCHEMY_DATABASE_URI` is constructed in `configure_privacyidea.sh` from `PI_DB_VENDOR`, `PI_DB_HOST`, `PI_DB_PORT`, `PI_DB_USER`, `PI_DB_PASSWORD`, `PI_DB_NAME`.

## Testing

### Container Structure Tests
Defined in `structure-tests.yaml`, validates:
- Environment variables
- User (nobody) and workdir (/opt/privacyidea)
- Required files and directories exist
- Scripts have valid bash syntax
- Binary permissions

Run with: `container-structure-test test --image mr-ssd/privacyidea:dev --config structure-tests.yaml`

### Integration Tests
`docker-compose-test.yml` spins up the container and a test script (`run-tests.sh`) that waits for privacyIDEA to be ready and verifies the page title.

### CI/CD Workflow
`.github/workflows/ci.yml` runs on pull requests only: hadolint, shellcheck, actionlint, then builds and tests amd64 and arm64 natively with no secrets or write token.

`.github/workflows/release.yml` runs on pushes to `main`, `v*` tags, and validated manual dispatches:
1. Validates the ref/version and supported floor before any credential exists
2. Builds one multi-platform index (amd64, arm64) and pushes it to a `sha-<12>` staging tag with SBOM and max provenance
3. Tests the staging digest natively on amd64 and arm64: structure tests, compose integration test, installed-version assertion, Trivy CRITICAL gate
4. Promotes the tested digest to version tags, `latest` (forward-only), or `edge` in a serialized publish job
5. Records published digests in the GitHub release

Tag semantics: version tags come only from release refs and are never overwritten; `main` writes `edge` and `sha-<12>`. See `README.md` for the consumer-facing table.

`.github/workflows/check-pi-version.yml` runs daily, creates missing `v*` tags for privacyIDEA releases at or above the support floor, dispatches `release.yml` explicitly (GITHUB_TOKEN tag pushes do not trigger workflows), verifies the queued run, and re-dispatches tags that have no GitHub release.

## Version Resolution
When `PI_VERSION=main` or empty, the builder stage fetches the latest version from PyPI using `curl` and `jq`.

## Gunicorn Configuration
`rootfs/opt/privacyidea/gunicorn_conf.py` is the gunicorn config file. Workers scale based on CPU cores (web_concurrency). Uses environment variables prefixed with `GUNICORN_`.
