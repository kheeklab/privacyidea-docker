# PrivacyIDEA Docker Image

![main workflow](https://github.com/Khalibre/privacyidea-docker/actions/workflows/main.yml/badge.svg) ![GitHub](https://img.shields.io/github/license/Khalibre/privacyidea-docker) ![Docker Pulls](https://img.shields.io/docker/pulls/khalibre/privacyidea) ![GitHub Repo stars](https://img.shields.io/github/stars/Khalibre/privacyidea-docker)

This is a build environment to build a docker image for privacyIDEA based on [official Python image](https://hub.docker.com/_/python) and [PrivacyIDEA](https://github.com/privacyidea/privacyidea)

> [!TIP]
> If you like this project and find it useful, please consider starring :star: it on GitHub to help it reach more people and get more feedback.

> [!NOTE]
> **Disclaimer**: The respective trademarks mentioned in the offering are owned by the respective companies. We do not provide a commercial license for any of these products. This listing has an open-source license. privacyIDEA is run and maintained by NetKnights, which is a complete and separate project from Khalibre.

## The image
The docker image is a self-contained Debian with privacyIDEA and NGINX installed, which will run on every distribution.

## Building

To build the image

```bash
make build
```

## Running

Run it with

```bash
make run
```

Login to http://localhost with **admin/privacyidea**

> [!CAUTION]
> :unlock: You must not use this in a production environment, since it contains fixed credentials and encryption keys!

## Configuration

### Admin credentials

The Khalibre privacyIDEA container can create a default admin user by setting the following environment variables:

  - `PI_ADMIN_USER`: Administrator default user. Default: **admin**.
  - `PI_ADMIN_PASSWORD`:  Administrator default password. Default: **privacyidea**

### Connecting to database

The Khalibre privacyIDEA requires a database to work. This is configured with the following environment variables:

  - `DB_VENDOR`: Database vendor (support mysql, mariadb or posgresql) Default **sqlite**.
  - `DB_USER`: Database user. No defaults.
  - `DB_PASSWORD`: Database. No defaults.
  - `DB_NAME`: Database name. No defaults.
  - `DB_HOST`: Database host. No defaults.

### NGINX configuration

  - `NGINX_LISTEN_PORT`: Get the listen port for Nginx, default to **80**
  - `NGINX_LISTEN_SSL_PORT`: Get the secured listen port for Nginx, default to **443**
  - `NGINX_MAX_UPLOAD`: Get the maximum upload file size for Nginx, default to **100Mb**
  - `NGINX_SERVER_TOKENS`: Hide Nginx server version on error pages and in the “Server HTTP” response header field. Default **off**
  - `NGINX_SSL_CERT`: Path to SSL certificate. Default to **/etc/nginx/certs/pi-server-cert.pem**
  - `NGINX_SSL_ENABLED`: Set to true to enable SSL, Default **false**
  - `NGINX_SSL_KEY`: Path to SSL key, default **/etc/nginx/certs/pi-server-key.pem**
  - `NGINX_WORKER_CONNECTIONS`: Set the max number of connections per worker for Nginx, if requested.
  - `NGINX_WORKER_PROCESSES`: Get the number of workers for Nginx, default to 1

### privacyIDEA configuration

  - `CACHE_TYPE`: privacyIDEA cache type. Default simple.
  - `PI_PEPPER`: This is used to encrypt the admin passwords. No defaults.
  - `PI_AUDIT_NO_SIGN`: If you by any reason want to avoid signing audit entries set it **true**.
  - `PI_AUDIT_KEY_PRIVATE_PATH`: This is used to sign the audit log
  - `PI_AUDIT_KEY_PUBLIC_PATH`: This is used to sign the audit log
  - `PI_ENCFILE`: This is used to encrypt the token data and token passwords. No defaults.
  - `PI_HSM`: privacyIDEA HSM. Default **default**
  - `PI_LOGFILE`: privacyIDEA log file location. Default **/var/log/privacyidea/privacyidea.log**
  - `PI_LOGLEVEL`: privacyIDEA log level. Default **INFO**
  - `SECRET_KEY`: This is used to encrypt the auth_token. No defaults.
  - `SUPERUSER_REALM`: The realm, where users are allowed to login as administrators. Default **administrator**
  - `PI_SKIP_BOOTSTRAP`: Set this to **true** to prevent the container to run setup again. Default **false**

## Providing Files to the Container

The privacyIDEA container uses the files you provide to execute the following use cases:

  - Configure PrivacyIDEA with configuration files
  - Configure NGINX with configuration files
  - Run scripts

All of the use cases can be triggered on container creation when the container finds files in specific folders within key container folders.

### Key Container Folders:

  - /mnt/privacyidea
  - /user/local/privacyidea/scripts

The Container Lifecycle and API specifies the scanned subfolders, the phases in which the container scans them, and the actions taken on their files.

You can provide files to the container in several ways.

### Ways to Provide Files:

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

At a high level, the container starts supervisord with privacyIDEA deployed on it. Additionally, however, the container entry point provides an API for executing these use cases:

  - Invoking scripts
  - Configuring NGINX and privacyIDEA

The container provides an API for triggering and configuring these use cases. It executes the use cases in different phases of its lifecycle.

### Lifecycle

After you create a container in an environment, the container entry point executes the following lifecycle phases in that environment:

  1. Pre-configure: Runs user-provided scripts before configuring NGINX and privacyIDEA.
  2. Configure: Prepares for running NGINX and privacyIDEA.
      1. Set Python's runtime environment.
      2. Run user-provided scripts.
  3. Pre-startup: Runs user-provided scripts before starting supervisd.
  4. NGINX and privacyIDEA startup: Launches privacyIDEA and NGINX using the supervisd script.
  5. Post-shutdown: Runs user-provided scripts after supervisd stops.

### API

The container entry point scans the following container folders for files and uses those files to configure the container, NGINX, and privacyIDEA and to act on privacyIDEA.

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
