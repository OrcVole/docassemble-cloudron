# 0003. Patch the websocket server to authenticate to Redis

- **Status:** accepted, 2026-11-07. The one deliberate exception to "never patch the application"
  (AGENTS.md, golden rule 1).

## Context

`docassemble/webapp/socketserver.py` (1.10.15) opens three Redis connections for live help's
publish/subscribe channels with host, port and database only:

    r = redis.StrictRedis(host=redis_host, port=redis_port, db=redis_offset)

Every other Redis connection in docassemble (`daredis.py`, `restart.py`) also passes the password,
username and TLS options parsed from the `redis` URL. Cloudron's Redis addon always requires a
password, so live help's channels would fail with `NOAUTH`. Nothing in configuration can change it.

## Decision

At build time, rewrite those three calls to pass `password=redis_password, username=redis_username,
**ssl_opts`, and import those names from `docassemble.webapp.daredis`. The build **fails** unless
exactly three original lines are found and replaced, so a changed upstream file stops the build
instead of being patched blindly. Offer the same change upstream (`docs/FOR-UPSTREAM.md`). Remove the
patch once a release carries the fix.

## Consequences

- Live help works against a password-protected Redis. Gate 2 proves it with two browser sessions
  exchanging a message, not by the websocket process appearing as running.
- Each upstream bump re-checks the patch automatically through the build's line count.
