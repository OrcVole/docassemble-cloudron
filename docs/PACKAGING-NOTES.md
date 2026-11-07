# Packaging notes (verified-versus-assumed log, newest first)

Anonymised. Box-specific detail lives in the maintainer's local notes, not here.

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
