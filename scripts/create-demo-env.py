#!/usr/bin/env python3
"""Create example credentials; this does not provision a usable service."""

from pathlib import Path
import os
import secrets
import stat


env_file = Path(".env")
required_keys = {
    "PI_ADMIN_USER", "PI_ADMIN_PASSWORD", "PI_DB_NAME", "PI_DB_HOST", "PI_DB_USER",
    "PI_DB_PASSWORD", "PI_DB_ROOT_PASSWORD", "PG_ROOT_PASSWORD", "PI_SECRET_KEY", "PI_PEPPER",
    "WP_DB_PASSWORD", "WP_DB_ROOT_PASSWORD",
}
try:
    existing = env_file.lstat()
except FileNotFoundError:
    existing = None
if existing is not None:
    if not stat.S_ISREG(existing.st_mode) or existing.st_uid != os.geteuid():
        raise SystemExit(".env must be a regular file owned by the current user; move unsafe path and review manually")
    if stat.S_IMODE(existing.st_mode) != 0o600:
        raise SystemExit(".env permissions must be 0600; run chmod 600 .env after reviewing its owner")
    parsed = {}
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not key or not value or key in parsed:
            raise SystemExit(".env is incomplete or malformed; preserve it and repair it manually")
        parsed[key] = value
    if not required_keys.issubset(parsed):
        raise SystemExit(".env lacks required values; preserve it and complete it manually")
    print("Existing private .env preserved; credentials were not changed.")
    raise SystemExit(0)

values = {
    "PI_ADMIN_USER": "pi-admin",
    "PI_ADMIN_PASSWORD": secrets.token_urlsafe(32),
    "PI_DB_NAME": "privacyidea",
    "PI_DB_HOST": "pi-db",
    "PI_DB_USER": "privacyidea",
    "PI_DB_PASSWORD": secrets.token_urlsafe(32),
    "PI_DB_ROOT_PASSWORD": secrets.token_urlsafe(32),
    "PI_SECRET_KEY": secrets.token_urlsafe(48),
    "PI_PEPPER": secrets.token_urlsafe(48),
    "PG_ROOT_PASSWORD": secrets.token_urlsafe(32),
    "WP_DB_PASSWORD": secrets.token_urlsafe(32),
    "WP_DB_ROOT_PASSWORD": secrets.token_urlsafe(32),
}
temporary = env_file.with_name(f".env.{os.getpid()}.{secrets.token_hex(8)}.tmp")
flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
old_umask = os.umask(0)
try:
    descriptor = os.open(temporary, flags, 0o600)
finally:
    os.umask(old_umask)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")
        output.flush()
        os.fsync(output.fileno())
    os.link(temporary, env_file, follow_symlinks=False)
finally:
    try:
        temporary.unlink()
    except FileNotFoundError:
        pass
print("Created .env with fresh local demo credentials (values hidden).")
