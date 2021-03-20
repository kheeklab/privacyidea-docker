# PrivacyIdea Docker Image

This is a build environment to build a docker image for privacyIDEA.

## The image
The docker image is a self contained Ubuntu 20.04 with privacyIDEA installed, which will run on every distribution.

## Building

To build the image

```bash
make build
```

## Running

Run it with

```bash
make runserver
```

This will download the existing privacyIDEA container from the Docker hub https://registry.hub.docker.com/u/khalibre/pricvacy/ and run it.

Login to http://localhost:5000 with "admin"/"privacyidea".

> You must not use this in productive environment, since it contains fixed credentail, encryption keys!

## Advanced usage
This image extended from [meinheld-gunicorn-docker](https://github.com/tiangolo/meinheld-gunicorn-docker). Some enviromment variables are inherited from parent image. Pease refer to above link for more infomation.

### PrivacyIdea Environment variables

CACHE_TYPE
PI_PEPPER
PI_AUDIT_KEY_PRIVATE
PI_AUDIT_KEY_PUBLIC
PI_AUDIT_MODULE
PI_ENCFILE
PI_EXTERNAL_LINKS
PI_HSM
PI_LOGFILE
PI_LOGLEVEL
SECRET_KEY
SQLALCHEMY_DATABASE_URI
