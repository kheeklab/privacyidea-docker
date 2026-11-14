# PrivacyIDEA Docker Image

![main workflow](https://github.com/kheeklab/privacyidea-docker/actions/workflows/release.yml/badge.svg) ![GitHub](https://img.shields.io/github/license/kheeklab/privacyidea-docker) ![Docker Pulls](https://img.shields.io/docker/pulls/kheeklab/privacyidea) ![GitHub Repo stars](https://img.shields.io/github/stars/kheeklab/privacyidea-docker)

This is a build environment to build a docker image for privacyIDEA based on [official Python image](https://hub.docker.com/_/python) and [PrivacyIDEA](https://github.com/privacyidea/privacyidea)

> [!TIP]
> If you like this project and find it useful, please consider starring :star: it on GitHub to help it reach more people and get more feedback.

## The image

The docker image is a self-contained Debian with privacyIDEA installed, which will run on every distribution.

> [!NOTE]
> **Disclaimer**: The respective trademarks mentioned in the offering are owned by the respective companies. We do not provide a commercial license for any of these products. This listing has an open-source license. privacyIDEA is run and maintained by NetKnights, which is a complete and separate project from kheeklab.

### Registry

The image is stored in below registries:

- [Docker Hub](https://hub.docker.com/r/kheeklab/privacyidea) — stable release tags only.
- [GitHub Container Registry](https://github.com/kheeklab/privacyidea-docker/pkgs/container/privacyidea) — all channels, including `edge`.

### Tags

Version tags identify a released privacyIDEA version and are never rewritten by later builds. `main` publishes only the moving `edge` channel, so use `edge` if you want the newest unreleased code; `edge` is GHCR-only.

Pin production deployments by digest. `latest`, `edge` and `sha-<12>` are mutable tags and can be republished by a later build.

This image targets privacyIDEA 3.14 and newer. Kerberos extras are not installed: upstream dropped the separate `requirements-kerberos.txt` in 3.14.

| Tag | Written from | Description |
| :-- | :-- | :---------- |
| `latest` | Newest stable release | Highest released version. Moves forward only while the GitHub Releases ledger is intact; an older release never moves it back. |
| `X.Y` | Release `vX.Y` | Version alias, e.g. `3.14`. Rewritten only by a release of the same version. |
| `X.Y.Z` | Release `vX.Y.Z` | Patch alias when upstream publishes a patch release. |
| `vX.Y` `vX.Y.Z` | Release tag | Same image as `X.Y` / `X.Y.Z`. |
| `X.Y-YYYYMMDD` | Release build date | Dated snapshot of that release, created once. |
| `edge` | Every push to `main` | Moving GHCR-only development channel for the newest `main` build. Not a release; may be unstable. |
| `sha-<12>` | Every build | Mutable build alias: the first 12 characters of the commit SHA. A re-run republishes the same name with a new digest. Pin by digest, not by this tag. |


## Building

To build the image

```console
make build
```

## Running

Run it with

```console

make run
```

Login to <http://localhost:8080> with **admin/privacyidea**

> [!CAUTION]
> The default configuration provide in this reposotory contains fixed credentials and encryption keys for testing and demo purposes. It should not be used in a production environment.Please refer to the [configuration](#configuration) section below for more details.
>
> **Additional notes:**
>
> - Production environments should use environment variables or other secure methods to store sensitive information.
> - Fixed credentials and encryption keys can be easily compromised if exposed, leading to security breaches.
> - It is important to take all necessary precautions to protect sensitive data in production environments.

## Configuration

### Admin credentials

The kheeklab privacyIDEA container can create a default admin user by setting the following environment variables:

- `PI_ADMIN_USER`: Administrator default user. Default: **admin**.
- `PI_ADMIN_PASSWORD`:  Administrator default password. Default: **privacyidea**

## Environment variables

### PrivacyIDEA Environment Variables

| Environment Variable | Description | Default |
| :------------------- | :---------- | :------ |
| `PI_ADMIN_USER` | Initial admin user for privacyIDEA login | admin |
| `PI_ADMIN_PASSWORD` | Initial admin password | privacyidea |
| `PI_DB_VENDOR` | Database vendor | sqlite |
| `PI_DB_USER` | Database user | |
| `PI_DB_PASSWORD` | Database password (plain text; must not be URL-encoded) | |
| `PI_DB_NAME` | Database name | |
| `PI_DB_HOST` | Database host. For on postgres use it support multiple hosts with comma separated | |
| `PI_DB_PORT` | Database port. For on postgres use it support multiple hosts with comma separated | depnds on PI_DB_VENDOR default for each type |
| `PI_DB_ARGS` | Additional DB attributes as comma-separated `key=value` pairs; commas become `&`, and values are inserted verbatim without URL-encoding. Avoid `&`, `=`, `%`, `,`, and spaces inside values | |
| `SQLALCHEMY_DATABASE_URI` | Full SQL connection string. If set it will override all PI_DB_* settings | |
| `PI_CACHE_TYPE` | privacyIDEA cache type | simple |
| `PI_PEPPER` | This is used to encrypt the admin passwords | |
| `PI_AUDIT_NO_SIGN` | If you by any reason want to avoid signing audit entries set it true | false |
| `PI_AUDIT_KEY_PRIVATE_PATH` | This is used to sign the audit log | |
| `PI_AUDIT_KEY_PUBLIC_PATH` | This is used to sign the audit log | |
| `PI_ENCFILE` | This is used to encrypt the token data and token passwords | |
| `PI_HSM` | privacyIDEA HSM | default |
| `PI_LOGFILE` | App log destination. Unset: app logs go to stdout. Set to a real file path: switches to rotating file logging | (unset — stdout) |
| `PI_LOGLEVEL` | privacyIDEA log level | INFO |
| `PI_LOGCONFIG` | privacyIDEA logging configuration file (YAML, loaded via `logging.config.dictConfig`) | /opt/privacyidea/pi-logging.yml |
| `PI_SECRET_KEY` | This is used to encrypt the auth_token | |
| `PI_SUPERUSER_REALM` | The realm, where users are allowed to login as administrators in comma separated value | administrator |
| `PI_SKIP_BOOTSTRAP` | Set this to true to force skipping bootstrap. Bootstrap runs only on first start, tracked by a marker file in `PI_DATA_DIR` | false |
| `PI_AUTO_UPDATE` | Set this to true to upgrade the privacyIDEA schema when the system is initialized (including when `PI_SKIP_BOOTSTRAP` is true) | false |
| `PI_SSLPORT` | Use https instead of http and listen on this port. To make this work bind mount or copy the private key and the certificate into /etc/privacyidea/server.{key,crt} | 8443 |

> [!WARNING]
> Bootstrap runs only once, on first start, and records initialization in `PI_DATA_DIR`. Setting `PI_SKIP_BOOTSTRAP` to **true** forces bootstrap to be skipped; it does not overwrite admin credentials or keys. For non-SQLite databases, startup refuses to generate new keys if privacyIDEA data exists but key files are missing.
> `PI_AUTO_UPDATE` set to **true** will update privacyIDEA to the latest version. Make sure you have backup your data before setting `PI_AUTO_UPDATE` to **true**.

### gunicorn environment variables

| Environment Variable | Description | Default |
| :------------------- | :---------- | :------ |
| `GUNICORN_WORKERS_PER_CORE` | Gunicorn workers per CPU core | 1 |
| `GUNICORN_MAX_WORKERS` | Maximum number of workers (cap). If unset, no cap is applied | (unset) |
| `GUNICORN_WEB_CONCURRENCY` | Explicit worker count; overrides the per-core calculation (must be > 0) | (unset) |
| `GUNICORN_HOST` | Gunicorn host, ignored if `GUNICORN_BIND` is set | 0.0.0.0 |
| `GUNICORN_PORT` | Gunicorn port, ignored if `GUNICORN_BIND` is set | 8080 |
| `GUNICORN_BIND` | Gunicorn bind address; overrides `GUNICORN_HOST` and `GUNICORN_PORT` | (unset) |
| `GUNICORN_LOG_LEVEL` | Gunicorn log level | info |
| `GUNICORN_ACCESS_LOG` | Gunicorn access log file (`-` = stdout) | - |
| `GUNICORN_ERROR_LOG` | Gunicorn error log file (`-` = stderr) | - |
| `GUNICORN_GRACEFUL_TIMEOUT` | Gunicorn graceful timeout (seconds) | 120 |
| `GUNICORN_TIMEOUT` | Gunicorn worker timeout (seconds) | 120 |
| `GUNICORN_KEEP_ALIVE` | Gunicorn keep-alive (seconds) | 5 |

The number of workers is calculated as `GUNICORN_WORKERS_PER_CORE` × CPU cores, with a minimum of 2. If `GUNICORN_MAX_WORKERS` is set, the count is capped at that value. `GUNICORN_WEB_CONCURRENCY` overrides the whole calculation and must be greater than 0.

## Providing Files to the Container

The privacyIDEA container uses the files you provide to execute the following use cases:

- Configure PrivacyIDEA with configuration files
- Run scripts

All of the use cases can be triggered on container creation when the container finds files in specific folders within key container folders.

### Key Container Folders

- /mnt/privacyidea
- /usr/local/privacyidea/scripts

The Container Lifecycle and API specifies the scanned subfolders, the phases in which the container scans them, and the actions taken on their files.

You can provide files to the container in several ways.

### Ways to Provide Files

- [Bind mounts](https://docs.docker.com/storage/bind-mounts/)
- [Volumes](https://docs.docker.com/storage/volumes/)
- [Using docker cp](https://docs.docker.com/engine/reference/commandline/cp/)

All of the use cases require making files available on container creation. Bind mounts and volumes accomplish this. Applying config files can be accomplished on container creation using bind mounts and volumes, or at run time using docker cp.

Bind mounts are used in the examples here as they are simpler than volumes for providing files. As you prepare files for mounting to a container, it’s helpful to organize them in a way that’s easiest for you to manage. Bind mounting to privacyIDEA containers, organizing files, and using docker cp are covered here.

Scripts under `/mnt/privacyidea/scripts/*.sh` are sourced into the entrypoint shell, not run in a subshell. A script that calls `exit` terminates container startup; a failing command aborts startup because the shell uses `set -e`; exported variables are available to later stages.

### Bind Mount Format

You can specify any number of bind mounts to a docker run command. Each bind mount follows this format:

```bash
-v [source path in host]:[destination path in container]
```

The bind mount source can be any folder path or file path in the host. The bind mount destination can be any folder path or file path in the container.

### Scanned Container Folders

The container scans these folders.

- /mnt/privacyidea/files (all files and subfolders are scanned)
- /mnt/privacyidea/scripts
- /usr/local/privacyidea/scripts/pre-configure
- /usr/local/privacyidea/scripts/pre-startup

## Container Lifecycle and API

At a high level, the container starts gunicorn with privacyIDEA deployed on it. Additionally, however, the container entry point provides an API for executing these use cases:

- Invoking scripts

The container provides an API for triggering and configuring these use cases. It executes the use cases in different phases of its lifecycle.

### Lifecycle

After you create a container in an environment, the container entry point executes the following lifecycle phases in that environment:

  1. Pre-configure: Runs user-provided scripts before configuring privacyIDEA.
  2. Configure: Prepares for running privacyIDEA.
      1. Set Python's runtime environment.
      2. Run user-provided scripts.
  3. Pre-startup: Runs user-provided scripts before starting privacyIDEA.
  4. PrivacyIDEA startup: Launches privacyIDEA.

### API

The container entry point scans the following container folders for files and uses those files to configure the container and privacyIDEA and to act on privacyIDEA.

- /mnt/privacyidea
- /usr/local/privacyidea/scripts

The key folders above have subfolders that are designated for specific actions. The subfolders, the actions taken on their files, and associated use cases are listed in lifecycle phase order in the following sections.

## Contributing

We'd love for you to contribute to this container. You can request new features by creating an issue, or submitting a pull request with your contribution.

## Persistence

The image chowns `/data/privacyidea` and `/etc/privacyidea` to `nobody` at build time. Bind mounts and reused named volumes do not inherit this ownership. If a mount is owned by another UID, `nobody` cannot write: SQLite startup fails with `PI_DATA_DIR ... is not writable`, and external-DB key/config writes fail. Use a fresh named volume, which copies ownership on first use, or pre-chown a bind mount to the `nobody` UID.

## Star History

<a href="https://star-history.com/#kheeklab/privacyidea-docker&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=kheeklab/privacyidea-docker&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=kheeklab/privacyidea-docker&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=kheeklab/privacyidea-docker&type=Date" />
  </picture>
</a>
