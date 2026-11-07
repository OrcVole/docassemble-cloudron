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

## 3. Background OCR to text recurses until the database pool is exhausted (bug, since 1.10.0)

`webapp/tasks/tasks.py`, task `ocr_finalize`, final return: `content=ocr_finalize(*pargs, **kwargs)`
calls the task itself. 1.9.0 had `worker_controller.util.ocr_finalize(...)`; the file imports that helper
as `do_ocr_finalize`. Symptom: `ocr_file_in_background()` returns `QueuePool limit of size 5 overflow 10
reached`. Fix: `content=do_ocr_finalize(*pargs, **kwargs)`.

## 4. `ocr_page` passes a pixel size to `pdftoppm -r` (bug, 1.9.0 or earlier)

`ocr_page_tasks` sets `ocr_resolution = str(int(float(ocr_resolution)*11.0))`, a `-scale-to` value
(`ocr_file` uses it that way). `ocr_page`, when a page has no pre-rendered image, passes it to
`pdftoppm -r`, so 300 becomes 3300 dpi; poppler refuses the allocation, exits 0 and writes a 1x1 PNG, and
OCR returns nothing. Fix: `-scale-to` in that call. Visible with PDFs an interview assembles (no
pre-rendered pages), not usually with uploads.

## 5. The default LaTeX template requires Times New Roman by name

`Legal-Template.tex` has `\setmainfont{Times New Roman}` when `fontfamily` is unset, so any image
without Microsoft's fonts cannot make PDFs. A configuration directive for the default font family (or a
fallback such as `\IfFontExistsTF`) would let packagers ship an openly licensed metric-compatible face
(Tinos, Liberation Serif) without patching the template.

## 6. LDAP sign-in requires the WhoAmI extended operation

`MySignInForm.validate` calls `connect.whoami_s()` after a successful bind. Some LDAP servers (Cloudron's
among them) do not implement WhoAmI (RFC 4532), so LDAP sign-in always falls back to local passwords.
A related point about how a bind result is interpreted is being reported privately, as SECURITY.md asks.
This package's change is in ADR 0008.

## 7. Celery workers share database connections inherited from the parent (bug)

The Celery parent opens a PostgreSQL connection while importing `docassemble.webapp.worker`, and the
prefork pool's children inherit the socket. Under concurrent background tasks two processes use one
connection and the stream breaks: `error with status PGRES_TUPLES_OK and no message from the libpq`,
`ResourceClosedError`, `StaleDataError`. Measured: 2 failed tasks in 602 sessions (8 clients, 6
minutes); 0 in 598 after the fix. Suggested fix, SQLAlchemy's documented pattern for forked processes:

    @worker_process_init.connect
    def _fresh_connections(**_):
        for engine in (all SQLAlchemy engines): engine.dispose(close=False)

This package does it from outside (ADR 0009).

## 8. Small documentation gaps met while packaging

- The Python code reads `DA_CONFIG_FILE`; `DA_CONFIG` is translated by the shell scripts only.
- Without the version file, `system version` falls back to 0.1.12, which silently disables the
  `single` Celery queue and changes the default ready-file path.
- `/health_check?ready=1` answers 400 before start-up completes. Platforms that treat only 5xx as
  unhealthy read that as healthy; a 503 would be understood everywhere.
