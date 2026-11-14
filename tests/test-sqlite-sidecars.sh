#!/usr/bin/env bash
set -eu
: "${FIXTURE_DIR:?Set FIXTURE_DIR to disposable fixture data}"
: "${IMAGE:?Set IMAGE to exact candidate image}"
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'chmod -R u+w "$tmp_dir"; rm -rf "$tmp_dir"' EXIT
chmod 777 "$tmp_dir"
docker run --rm --network none --user 0:0 -e "COPY_UID=$(id -u)" -e "COPY_GID=$(id -g)" \
    -v "$FIXTURE_DIR:/fixture:ro" -v "$tmp_dir:/copy" --entrypoint /bin/sh "$IMAGE" \
    -c 'cp -a /fixture/. /copy/; chown -R "$COPY_UID:$COPY_GID" /copy; chmod -R a+rX /copy; chmod 777 /copy; chmod 666 /copy/privacyidea.db'
printf 'touch /data/privacyidea/hook-ran\n' > "$tmp_dir/hook.sh"
printf '#!/bin/sh\ntouch /data/privacyidea/server-ran\n' > "$tmp_dir/server.sh"
chmod 755 "$tmp_dir/server.sh"
docker run --rm -i --network none --user "$(id -u):$(id -g)" -e PI_SKIP_BOOTSTRAP=false \
    -v "$tmp_dir:/data/privacyidea" \
    -v "$tmp_dir/hook.sh:/usr/local/privacyidea/scripts/pre-configure/test.sh:ro" \
    -v "$tmp_dir/server.sh:/opt/privacyidea/bin/gunicorn:ro" \
    -v "$repo_dir/rootfs/usr/local/bin/configure_privacyidea.sh:/usr/local/bin/configure_privacyidea.sh:ro" \
    --entrypoint /opt/privacyidea/bin/python "$IMAGE" - <<'PY'
import hashlib, os, pathlib, sqlite3, subprocess

data = pathlib.Path('/data/privacyidea')
path = data / 'privacyidea.db'
def snapshot():
    result = {}
    directory = os.open(data, os.O_RDONLY | os.O_DIRECTORY | os.O_NOATIME)
    try:
        stat = os.fstat(directory)
        result['<directory>'] = (stat.st_mode, stat.st_uid, stat.st_gid, stat.st_size,
                                 stat.st_nlink, stat.st_atime_ns, stat.st_mtime_ns, stat.st_ctime_ns)
        names = os.listdir(directory)
    finally:
        os.close(directory)
    for name in names:
        p = data / name
        if p.is_file():
            try:
                fd = os.open(p, os.O_RDONLY | os.O_NOATIME)
                with os.fdopen(fd, 'rb') as f:
                    stat = os.fstat(f.fileno())
                    digest = hashlib.sha256(f.read()).hexdigest()
            except PermissionError:
                stat = p.stat()
                digest = None
            result[p.name] = (stat.st_mode, stat.st_uid, stat.st_gid, stat.st_size,
                              stat.st_nlink, stat.st_atime_ns, stat.st_mtime_ns, stat.st_ctime_ns, digest)
    return result
def check(label, expected):
    before = snapshot()
    result = subprocess.run(['/usr/local/bin/configure_privacyidea.sh', '--check-initialized'],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    after = snapshot()
    if (result.returncode == 0) != expected or before != after:
        changed = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
        raise SystemExit('FAIL: ' + label + ' return=' + str(result.returncode) + ' changed=' + str(changed))
def check_entrypoint(label):
    before = snapshot()
    result = subprocess.run(['/usr/local/bin/privacyidea_entrypoint.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode == 0 or before != snapshot() or (data / 'hook-ran').exists() or (data / 'server-ran').exists():
        raise SystemExit('FAIL: ' + label + ' reached hook/server or changed persistent state')

check('rollback', True)
alias = data / 'privacyidea-alias.db'
os.link(path, alias)
check('hard-linked database alias', False)
alias.unlink()
os.chmod(data, 0o555)
check('rollback unwritable directory', False)
os.chmod(data, 0o777)
original = path.read_bytes()
os.chmod(path, 0o000)
check('unreadable database', False)
os.chmod(path, 0o666)
path.write_bytes(bytes(100))
check('corrupt database', False)
path.write_bytes(original)
with path.open('r+b') as f:
    f.truncate(64 * 1024 * 1024 + 1)
check('oversized database', False)
path.write_bytes(original)
for suffix in ('-wal', '-shm', '-journal'):
    sidecar = pathlib.Path(str(path) + suffix)
    sidecar.write_bytes(b'unqualified')
    check('orphan ' + suffix, False)
    sidecar.unlink()
with sqlite3.connect(path) as db:
    db.execute('PRAGMA journal_mode=WAL')
check('WAL without sidecars', False)
check_entrypoint('WAL without sidecars')
db = sqlite3.connect(path)
db.execute('CREATE TABLE wal_test (id INTEGER)')
db.commit()
assert (data / 'privacyidea.db-wal').exists() and (data / 'privacyidea.db-shm').exists()
check('WAL with sidecars', False)
check_entrypoint('WAL with sidecars')
db.close()
os.chmod(data, 0o555)
check('WAL unwritable directory', False)
os.chmod(data, 0o777)
print('PASS: rollback probe and WAL sidecar rejection preserve file metadata and hashes')
PY
