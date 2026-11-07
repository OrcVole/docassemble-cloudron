# Notes for docassemble upstream

Offered gratefully, with evidence. Each item is something that would make docassemble easier to run
under a platform that supplies its own database, cache and mail, and keeps the image read-only.
Paths and line numbers are from v1.10.15.

## 1. Live help does not send the Redis password (bug)

`docassemble/webapp/socketserver.py` lines 102, 460 and 905 create
`redis.StrictRedis(host=redis_host, port=redis_port, db=redis_offset)` with no `password`,
`username` or TLS options, and line 28 imports only the host, port and offset. Every other connection
(`daredis.py:6-8`, `restart.py:20`) passes all of them. With a password-protected Redis, live help's
publish/subscribe channels fail with `NOAUTH`. Suggested fix: import `redis_password`,
`redis_username` and `ssl_opts` from `daredis` and pass them in the three calls. This package carries
that change as a patch (ADR 0003) until a release includes it.

## 2. A `packages` prefix outside the virtual environment is never importable

`update.py` installs add-ons with `pip install --prefix=<packages>`, but nothing adds
`<packages>/lib/pythonX.Y/site-packages` to `sys.path`. It works today only because `packages`
defaults to the environment itself. Adding the prefix to `sys.path` (or documenting a `.pth` file)
would let installations keep the environment read-only while still allowing add-ons and the
Playground.

## 3. Small documentation gaps met while packaging

- The Python code reads `DA_CONFIG_FILE`; `DA_CONFIG` is translated by the shell scripts only.
- Without the version file, `system version` falls back to 0.1.12, which silently disables the
  `single` Celery queue and changes the default ready-file path.
- `/health_check?ready=1` answers 400 before start-up completes. Platforms that treat only 5xx as
  unhealthy read that as healthy; a 503 would be understood everywhere.
