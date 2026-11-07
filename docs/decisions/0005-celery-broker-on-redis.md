# 0005. The Redis addon as Celery's broker; no RabbitMQ

- **Status:** accepted, 2026-11-07. Proof 1 passed on the local stack, before and after a restart: a
  background PDF (19,240 bytes) on the `celery` queue and its OCR on the `single` queue, through a
  password-protected Redis on database 3.

## Context

Upstream runs RabbitMQ as Celery's broker and Redis as its result store and cache. Docassemble passes
the `rabbitmq` configuration value straight to `Celery(broker=...)`, so any broker URL Celery
understands works. Despite its name, the key accepts a Redis URL. timconsidine's community alpha used
Redis as the broker first; credit to him.

## Decision

- `RABBITMQ=redis://default:<password>@<host>:<port>/3`, built every boot from the addon's
  variables. Database 3 keeps the broker clear of docassemble's own databases 0 to 2 (`daredis.py`).
- `REDIS` from the addon, also every boot.
- No message broker in the container, so nothing to back up beyond what Cloudron already does.

## Proof 1: pass criteria

A PDF assembly task and an OCR task complete, the OCR task on the `single` queue (check which queue
served it; the queue exists only if the version file reads 1.2.50 or later). Both still complete after
a restart of the app.

## Fallback

LavinMQ bound to localhost, its store in a `persistentDirs` path outside `/app/data`, with a
`restoreCommand` and an in-place restore at gate 3 (field guide #327).

## Note

Celery here serialises tasks with `pickle` (upstream's `config_worker.py`). Anyone able to write to
the broker could run code in the worker. The broker is this app's own password-protected Redis,
reachable only inside the server, so this is acceptable. It is stated in the README.
