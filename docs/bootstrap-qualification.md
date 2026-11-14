## Bootstrap and Image Qualification

No automatic-bootstrap database and storage topology is qualified. The CI fixture is designed to exercise startup against intentionally provisioned disposable SQLite state with `PI_SKIP_BOOTSTRAP=true`; it does not qualify automatic bootstrap, locking, an external database, production storage, or recovery.

Guarded initialized startup requires the installed image's exact migration heads. Automatic migration is disabled; at verified head `PI_AUTO_UPDATE=true` is a no-op, while combining it with `PI_SKIP_BOOTSTRAP=true` is rejected. The CI fixture uses the explicit skip bypass with auto-update off and does not test guarded startup. See `docs/bootstrap-state.md` for restrictions and compatibility limits.

### Local artifact exercised

| Item | Evidence |
| --- | --- |
| Repository base | `4f951cb96afe5af7e1856ac623ea70fb87eec0be` |
| privacyIDEA | `3.14` for the local amd64 build only |
| Base image | `python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f` |
| SQLite library | SQLite 3.46.1; SQLAlchemy 2.0.53 |
| Database drivers | PyMySQL 1.2.0; psycopg2 2.9.13 |
| Database server / topology | No DB server version tested. Successful smoke used one disposable SQLite file on a Docker named volume; MariaDB/PostgreSQL server versions, shared storage, and automatic bootstrap remain untested. |
| Reference server examples | MariaDB 10.4 and PostgreSQL 14 are Compose examples only; neither was run or qualified |
| Image identity | `sha256:5a2d634de3393dedfcfb3d1c6d43b01b1832d48d0935d98ea163f1cf9e6d7dda` (`linux/amd64`); local only, unpublished |
| OS packages | Exact resolved names/versions recorded in attached inventory. APT uses the moving Debian suite, so later builds can differ |

The CI Compose fixture provisions disposable SQLite schema, encryption/audit keys, an admin, and an initialized marker with explicit test-only values. App startup uses `PI_SKIP_BOOTSTRAP=true`; the workflow waits for readiness before running the UI smoke. The one-shot provisioner validates and preserves an existing fixture on rerun. Local validation of `COMPOSE_PROJECT_NAME=pers113-new PI_IMAGE=privacyidea:pers113-review SOURCE_BRANCH=review bash tests/run-provisioned-compose-smoke.sh` passed for fresh state and after restarting the app. Before/after DB integrity, admin count, admin password fingerprint, encryption key hash, and audit private-key hash matched. `.env` hash also remained unchanged across `make credentials` after restart. No GitHub Actions run was dispatched. These checks do not execute automatic bootstrap and must not be described as a supported installation procedure.

### Python and release inputs

Supported privacyIDEA scope starts at 3.14; no upper bound is declared. Numeric release builds install the exact version selected by the numeric release ref. Edge builds resolve the current PyPI privacyIDEA version at build time. The release validator records the upstream requirements tag, peeled commit SHA, and SHA-256; the build verifies the checksum before using that file. The upstream requirements file is pinned to the peeled v3.14 commit `31db0ecd87bbbb00b7ca43bd70d4a7f4fb846842` with SHA-256 `66210b8b2ae2b20afe980976a29ee51d8896c78ddfcd7d95ae762fbf36bfc5c8`; the fetched lock pins and hashes its package set. The build removes upstream entries superseded by local dependency overrides, adds the exact hash-verified privacyIDEA artifact and hash-verified local requirements, then installs the combined lock with `--require-hashes --no-deps`. Pinned, hash-verified pip, wheel, and setuptools are in a separate lock. Both locks and source metadata are retained under `/usr/share/privacyidea/`.

The scheduled upstream-tag feeder runs daily. Dependabot updates Python, Docker, Compose, and GitHub Actions dependencies weekly. Python version resolution and Debian package resolution can change between builds; byte-for-byte image reproducibility is not claimed.

### Unqualified combinations

Fresh automatic bootstrap is disabled pending database-wide exclusion, crash/loss handling, and exact image/server/storage evidence. This includes fresh SQLite, MariaDB, MySQL, PostgreSQL, explicit SQLAlchemy URIs, SQLite aliases, bind mounts, network filesystems, and shared or clustered databases. The Compose files are opt-in reference examples; their database services start empty. They do not create a qualified server by setting `PI_SKIP_BOOTSTRAP=true`.
