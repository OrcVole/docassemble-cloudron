# Packaging notes (verified-versus-assumed log, newest first)

Anonymised. Box-specific detail lives in the maintainer's local notes, not here.

---

## 2026-11-07 (evening): gate ladder 0 to 4 on a test Cloudron 10.1.6

Four candidates of 0.1.0; every finding below landed before the final one
(`sha256:2a10dc4b...`). Evidence tables: `docs/DEBUGGING.md`.

**Surfaced and fixed:**

- Anonymous `/` answered 501: with demos off, docassemble refuses its built-in default interview to
  anonymous visitors. Fresh installs now redirect `/` to sign-in (`root redirect url`).
- No Cloudron user could sign in: Cloudron's LDAP server lacks WhoAmI (ADR 0008). The fix also refuses
  anonymous binds, which Cloudron's server accepts.
- Two background tasks in 602 failed under load: Celery's forked workers shared the parent's database
  connection (ADR 0009). 0 of 1,210 after the fix.
- The scanner template still pinned base 5.0.0's SSH host keys; NLTK's dictionary data matched two
  short denylist patterns (scoped allowlist).
- The workstation does not trust the test box's new Let's Encrypt intermediate (YE2): gate scripts
  take `INSECURE=1` for that box only.

**Validated:** see DEBUGGING.md. `memoryLimit` 4.5 GiB from a measured 3.1 GiB peak.

**Still open:** gate 5 (stranger path) after publication; clone leg not run.

---

## 2026-11-07 (afternoon): first image; both day-one proofs pass on the local stack

Image built from `cloudron/base:6.0.1` (6.1 GB), run under `test/local-stack.sh`: read-only root
filesystem, `/app/data` volume, PostgreSQL 18 and a password-protected Redis standing in for the addons.

**Validated:**

- **First boot is healthy in 20 s** (tables, migrations, package check, seven programs); a restart takes
  about 40 s including the stop, and leaves `config.yml` untouched ("refreshed nothing").
- **Proof 1 (ADR 0005):** background PDF on the `celery` queue (19,240 bytes, set in Tinos), then OCR of
  it on the `single` queue, both through Redis database 3; the same after a restart.
- **Proof 2 (ADR 0004):** a fixture add-on installed through `POST /api/package` lands in
  `/app/data/packages` and is imported from there by the restarted web app, with no manual restart; it
  survives an app restart. Shadowing a pinned library fails cleanly on the read-only image.

**Surfaced and fixed:**

- supervisord as the app user cannot create its socket in root-owned `/run`: it runs as root, every
  program as `cloudron` (the fleet's pattern); `reset.sh` uses the authenticated localhost port.
- nginx as `cloudron` cannot reopen root's stdout pipe: `access_log off` (Cloudron's proxy logs requests);
  `error_log stderr` works.
- The NLTK daemon reads only `NLTKSOCKET`, not the config key.
- Times New Roman required by the default LaTeX template (ADR 0006: Tinos).
- Two upstream OCR bugs (ADR 0007).
- fontconfig wrote its build-time cache to the runtime cache directory; the operator-fonts config is
  now installed after the build's `fc-cache`.
- A proof can pass vacuously: `docassemble.demo` is already in the image. Proof 2 uses a fixture that
  exists nowhere else.

**Still open:** the Proving Ground gates (0 to 4), LDAP sign-in (the WhoAmI check), mail through the
sendmail addon, live help across two browsers, memory (gate 4), and the stranger path (gate 5).

---

## 2026-11-07: repository started; Python 3.15 probe; upstream source read

Desk research against docassemble v1.10.15's source, then a probe build on `cloudron/base:6.0.1`. No
box involved yet, so nothing below is proven on Cloudron.

**Validated:**

- **CPython 3.15.2 can carry docassemble 1.10.15.** uv 0.13.7 installed the interpreter and a
  pip-seeded venv. The full pinned set (plus `uWSGI==2.0.31`) installed, exit 0. Locally compiled:
  PyYAML, ruamel.yaml.clib, netifaces, python-ldap, uWSGI. Everything else used published cp315 wheels.
- **No executable-stack libraries:** 485 shared objects scanned with `readelf -lW`, zero `RWE`.
- **Imports:** the base, parser, socket server, celery, ldap, psycopg2, lxml, PIL, numpy, pandas,
  redis, pyzbar and cairosvg all import. The web server and worker get through start-up and stop at
  their first Redis connection, which they make while loading.
- **The WSGI-file trap is real:** with no WSGI file, start-up exits with "Unable to modify the
  timestamp of the WSGI file". Pointing `webapp` at a writable path clears it.

**Surfaced (from source, to fix in the build):**

- Live help's three Redis connections omit the password (ADR 0003).
- The `packages` prefix is never put on `sys.path` (ADR 0004).
- The config file variable the Python reads is `DA_CONFIG_FILE`.
- Without the version file, the `single` OCR queue is silently disabled.
- `/health_check?ready=1` answers 400 before ready, which Cloudron reads as healthy.

**Still open:**

- Proof 1 (ADR 0005) and proof 2 (ADR 0004): need the image and live services.
- Whether the health check should prove the database is reachable.
