# 0009. Each forked Celery worker gets its own database connections

- **Status:** accepted, 2026-11-07. Not a patch to docassemble: a small module of the package's own,
  loaded with Celery's `--include`.

## Context

Gate 4's first load (8 clients for 6 minutes, 602 sessions) finished with 2 failed background tasks:
`error with status PGRES_TUPLES_OK and no message from the libpq`, `ResourceClosedError` and a
`StaleDataError` on the `user` table. These are the symptoms of two processes using one PostgreSQL
connection at the same time.

On the running container, `ss -tnp` showed one PostgreSQL socket owned by the Celery parent and both
of its forked children at once (and the same for `celerysingle`). docassemble builds its SQLAlchemy
engines when the Celery parent imports the worker module, the parent opens a connection, and the
prefork pool's children inherit it. docassemble has no `worker_process_init` handler, so upstream's
image has the same exposure (it runs more Celery processes, so likely more of it).

## Decision

`image/cloudron_celery_fork.py`, installed beside the venv's packages and loaded by both Celery
programs with `--include cloudron_celery_fork`, connects to Celery's `worker_process_init` signal and
calls `dispose(close=False)` on every SQLAlchemy engine in the new child. That is SQLAlchemy's
documented pattern for forked processes: the child drops its references to the inherited pool and opens
its own connections, while the parent's sockets are left untouched. The build's import gate includes the
module.

## Evidence (lab, Cloudron 10.1.6)

| Run | Image | Sessions completed | Failed | libpq corruption errors in log |
|---|---|---|---|---|
| before | candidate 3 | 300 PDF+OCR, 302 DOCX | 2 | 3 lines |
| after | candidate 4 | 299 PDF+OCR, 299 DOCX | 0 | see DEBUGGING.md |

`ss` still lists the inherited descriptor under the children after the fix: `close=False` leaves it
open so the parent's connection is not broken. The proof is behavioural (no failures, no corruption
errors), not the descriptor listing.

## Consequences

- Reported upstream (`docs/FOR-UPSTREAM.md`), with the same three-line handler as the suggested fix.
- uWSGI runs a single worker under its master; the master does not query after forking, so it is left
  as upstream configures it.
