# PrivacyIDEA Docker Image

![main workflow](https://github.com/Khalibre/privacyidea-docker/actions/workflows/release.yml/badge.svg) ![GitHub](https://img.shields.io/github/license/Khalibre/privacyidea-docker) ![Docker Pulls](https://img.shields.io/docker/pulls/khalibre/privacyidea) ![GitHub Repo stars](https://img.shields.io/github/stars/Khalibre/privacyidea-docker)

This is a build environment to build a docker image for privacyIDEA based on [official Python image](https://hub.docker.com/_/python) and [PrivacyIDEA](https://github.com/privacyidea/privacyidea)

> [!TIP]
> If you like this project and find it useful, please consider starring :star: it on GitHub to help it reach more people and get more feedback.

## The image

The docker image is a self-contained Debian with privacyIDEA installed, which will run on every distribution.

> [!NOTE]
> **Disclaimer**: The respective trademarks mentioned in the offering are owned by the respective companies. We do not provide a commercial license for any of these products. This listing has an open-source license. privacyIDEA is run and maintained by NetKnights, which is a complete and separate project from Khalibre.

### Registry

The image is stored in bellow registries:

- [Docker Hub](https://hub.docker.com/r/khalibre/privacyidea)
- [GitHub Container Registry](https://github.com/Khalibre/privacyidea-docker/pkgs/container/privacyidea)

### Tags

The image tags are following privacyIDEA version e.g. `3.9.1` and `latest`. The default tag is `latest` is not suitable for production environments as it might not test all use cases.

| Tag | Description |
| :-- | :---------- |
| `latest` | The latest image build from main branch |
| `3.9.2` `3.9.2-python-3.8.18-slim-bookworm`   | The image build from base image python 3.8.18-slim-bookworm |
| `3.9.2-python-3.9.18-slim-bookworm`   | The image build from base image python 3.9.18-slim-bookworm |
| `3.9.2-python-3.10.13-slim-bookworm`  | The image build from base image python 3.10.13-slim-bookworm |
| `3.9.2-python-3.8.18-slim-bullseye`   | The image build from base image python 3.8.18-slim-bullseye |
| `3.9.2-python-3.9.18-slim-bullseye`   | The latest image from base image python 3.9.18-slim-bullseye |
| `3.9.2-python-3.10.13-slim-bullseye`  | The latest image build from base image python 3.10.13-slim-bullseye |

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

Login to <http://localhost> with **admin/privacyidea**

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

The Khalibre privacyIDEA container can create a default admin user by setting the following environment variables:

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
| `PI_DB_PASSWORD` | Database password | |
| `PI_DB_NAME` | Database name | |
| `PI_DB_HOST` | Database host. For on postgres use it support multiple hosts with comma separated | |
| `PI_DB_PORT` | Database port. For on postgres use it support multiple hosts with comma separated | depnds on PI_DB_VENDOR default for each type |
| `PI_DB_ARGS` | Addiitional DB attributes | |
| `PI_DB_UPGRADE` | Automatic DB Migration after versiion upgrade. **Experimental** not for production use. To enable se to TRUE vale(case sensetive) | |
| `PI_BACKUP_DIR` | For use together with PI_DB_UPGRADE -- backup directory path, don't forget to mount persistant volume | /mnt/files/backups |
| `SQLALCHEMY_DATABASE_URI` | Full SQL connection string. If set it will override all PI_DB_* settings | |
| `PI_CACHE_TYPE` | privacyIDEA cache type | simple |
| `PI_PEPPER` | This is used to encrypt the admin passwords | |
| `PI_AUDIT_NO_SIGN` | If you by any reason want to avoid signing audit entries set it true | false |
| `PI_AUDIT_KEY_PRIVATE_PATH` | This is used to sign the audit log | |
| `PI_AUDIT_KEY_PUBLIC_PATH` | This is used to sign the audit log | |
| `PI_ENCFILE` | This is used to encrypt the token data and token passwords | |
| `PI_HSM` | privacyIDEA HSM | default |
| `PI_LOGFILE` | privacyIDEA log file location | /var/log/privacyidea/privacyidea.log |
| `PI_LOGLEVEL` | privacyIDEA log level | INFO |
| `PI_SECRET_KEY` | This is used to encrypt the auth_token | |
| `PI_SUPERUSER_REALM` | The realm, where users are allowed to login as administrators in comma separated value | administrator |
| `PI_SKIP_BOOTSTRAP` | Set this to true to prevent the container to run setup again | false |

> [!WARNING]
> Be careful and setting `PI_SKIP_BOOTSTRAP` to **true** after first initialization. This will prevent the container to run setup again or your data such as admin credentials, secret keys, etc will be overwritten.

### gunicorn environment variables

| Environment Variable | Description | Default |
| :------------------- | :---------- | :------ |
| `GUNICORN_ACCESS_LOGFILE` | Gunicorn access log file location | stdout |
| `GUNICORN_ERROR_LOGFILE` | Gunicorn error log file location | stderr |
| `GUNICORN_WORKER_CLASS` | Gunicorn worker class | sync |
| `GUNICORN_WORKERS` | Gunicorn workers | 1 |
| `GUNICORN_BIND` | Gunicorn bind address if not set `GUNICORN_HOST` and `GUNICORN_PORT` will be used | None |
| `GUNICORN_HOST` | Gunicorn host will be ingored if `GUNICORN_BIND` is set | 0.0.0.0 |
| `GUNICORN_PORT` | Gunicorn port will be ingored if `GUNICORN_BIND` is set | 8080 |
| `GUNICORN_LOGLEVEL` | Gunicorn log level | INFO |
| `GUNICORN_TIMEOUT` | Gunicorn timeout | 60 |

## Providing Files to the Container

The privacyIDEA container uses the files you provide to execute the following use cases:

- Configure PrivacyIDEA with configuration files
- Run scripts

All of the use cases can be triggered on container creation when the container finds files in specific folders within key container folders.

### Key Container Folders

- /mnt/privacyidea
- /user/local/privacyidea/scripts

The Container Lifecycle and API specifies the scanned subfolders, the phases in which the container scans them, and the actions taken on their files.

You can provide files to the container in several ways.

### Ways to Provide Files

- [Bind mounts](https://docs.docker.com/storage/bind-mounts/)
- [Volumes](https://docs.docker.com/storage/volumes/)
- [Using docker cp](https://docs.docker.com/engine/reference/commandline/cp/)

All of the use cases require making files available on container creation. Bind mounts and volumes accomplish this. Applying config files can be accomplished on container creation using bind mounts and volumes, or at run time using docker cp.

Bind mounts are used in the examples here as they are simpler than volumes for providing files. As you prepare files for mounting to a container, it’s helpful to organize them in a way that’s easiest for you to manage. Bind mounting to privacyIDEA containers, organizing files, and using docker cp are covered here.

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
- /usr/local/privacyidea/scripts/post-shutdown
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
  5. Post-shutdown: Runs user-provided scripts after privacyIDEA stops.

### API

The container entry point scans the following container folders for files and uses those files to configure the container and privacyIDEA and to act on privacyIDEA.

- /mnt/privacyidea
- /user/local/privacyidea/scripts

The key folders above have subfolders that are designated for specific actions. The subfolders, the actions taken on their files, and associated use cases are listed in lifecycle phase order in the following sections.

## Contributing

We'd love for you to contribute to this container. You can request new features by creating an issue, or submitting a pull request with your contribution.

## Star History

<a href="https://star-history.com/#Khalibre/privacyidea-docker&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Khalibre/privacyidea-docker&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Khalibre/privacyidea-docker&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Khalibre/privacyidea-docker&type=Date" />
  </picture>
</a>
