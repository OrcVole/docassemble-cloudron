# AGENTS.md: Docassemble Cloudron package working contract

The settled-decisions record for packaging **Docassemble** (`docassemble`, MIT) as a Cloudron
community app. Read this before changing anything. Do not relitigate these decisions without a
concrete reason found on a running box. **The box is the authority, not the docs.**

## What this package is

Docassemble's web application, background workers and helper daemons, installed from PyPI into a
uv-managed CPython 3.15 environment on `cloudron/base:6.0.1`, with every stateful service supplied by
Cloudron addons. ADR 0001 explains why this replaces the v0.1 package.

Topology (planned; each row is proven at the gates before it is called done), all logging to stdout:

| Process | Role | Port (localhost unless noted) |
|---|---|---|
| nginx | front door on `httpPort`; health shim; websocket routing | 8000 (published) |
| uwsgi | the Flask web application | unix socket |
| celery | background tasks | none |
| celerysingle | the `single` queue (OCR) | none |
| websockets | live help | 5000 |
| nltk | language daemon | unix socket |
| unoserver | document conversion, system Python | 2003 |

State: PostgreSQL, Redis (also the broker, ADR 0005), LDAP, sendmail and scheduler are addons.
Not included: RabbitMQ, exim4, syslog-ng, Apache, certbot, upstream's cron and watchdog.

## Golden rules

1. **Conformance to the Cloudron contract first.** Adapt the runtime environment, not the application.
   **Recorded exceptions, each guarded at build time and reported upstream:** ADR 0003 (websocket
   Redis authentication), ADR 0006 (default PDF font), ADR 0007 (two OCR bugs). Any further patch
   needs its own ADR, a build-time guard, and an upstream report.
2. **Pin everything** by digest or exact version: base, uv, the interpreter, docassemble, uWSGI,
   unoserver. One build argument for the docassemble version, mirrored as `upstreamVersion`.
3. **Persisted state only in `/app/data`.** Re-assert ownership and mode on every boot.
4. **Fail loud.** Never regenerate the secret key (it decrypts stored answers), and never rewrite
   `config.yml` after first boot.
5. **Configure, don't redirect.** Every writable path is a docassemble configuration key. No symlinks
   unless one is justified in a comment beside it.
6. **Code and docs ship together.** ADRs in `docs/decisions/`; `docs/PACKAGING-NOTES.md`, newest
   first. Box-specific notes stay in the gitignored `phase-notes/`.
7. **`CMD`, never `ENTRYPOINT`.** Maintain `.dockerignore` as carefully as `.gitignore`.
8. **Anonymise before every push.** `test/secret-scan.sh` is the release gate; `example.com` is the
   placeholder.
9. **Git hygiene.** No AI co-authorship or tool-attribution trailers. Commit as the maintainer
   identity, set repo-local.

## Locked decisions (operator-confirmed 2026-09-25 and 2026-11-07)

- **Manifest id:** `io.github.orcvole.docassemble`. `packagerName` `OrcVole`.
- **Registry:** `ghcr.io/orcvole/docassemble-cloudron`, public, tag `<upstream>-<pkg-rev>`, pinned in
  the manifest by the digest `podman push --digestfile` writes (field guide #323).
- **Repos:** GitHub `OrcVole/docassemble-cloudron` is canonical, with a private mirror.
- **Cadence:** follow every upstream release. Gates 0, 2 and 3 are scripted so each update is cheap.
- **Python:** CPython 3.15.2 via pinned uv (ADR 0002). Fallback: newest 3.14.
- **Fresh installs only;** no migration from v0.1.
- **Playground on**, with the trust wording in README, DESCRIPTION and POSTINSTALL.
- **memoryLimit:** 8 GiB placeholder until gate 4 measures it. Gate 4 reads all of `memory.events`
  and `memory.swap.peak`, not only OOM kills.
- **Health:** `/healthz` from the internal nginx: 503 until docassemble's ready file exists, then a
  proxy to `/health_check`. Never `/`, which answers anonymous visitors with an error page.
- **Sign-in:** the `ldap` addon (docassemble has no generic OIDC provider). The first administrator
  is a local account created per install.

## Configuration mapping

| docassemble | Source | When |
|---|---|---|
| config file | `DA_CONFIG_FILE=/app/data/config/config.yml` (the Python reads this name, not `DA_CONFIG`) | every boot |
| `uploads`, `packages`, `log` | `/app/data/files`, `/app/data/packages`, `/run/docassemble/log` | first boot, in `config.yml` |
| `webapp`, `ready file` | `/run/docassemble/docassemble.wsgi` (must be writable or the app exits), `/run/docassemble/ready` | first boot |
| `version file` | upstream's `VERSION`, shipped in the image (without it OCR silently leaves the `single` queue) | first boot |
| `DBHOST`, `DBNAME`, `DBUSER`, `DBPASSWORD`, `DBPORT` | postgresql addon | every boot |
| `REDIS`, `RABBITMQ` | redis addon; broker on database 3 | every boot |
| `DAHOSTNAME`, `URLROOT` | `CLOUDRON_APP_DOMAIN`, `CLOUDRON_APP_ORIGIN` | every boot |
| mail | sendmail addon, STARTTLS port 2587 | every boot |
| `ENVIRONMENT_TAKES_PRECEDENCE` | `true` | every boot |
| `DASUPERVISORUSERNAME`, `DASUPERVISORPASSWORD` | generated once into `/app/data` | every boot |
| `DAREADONLYFILESYSTEM` | **never set**: it makes upstream's reset script exit early | — |

## Secrets

| Secret | Criticality | Notes |
|---|---|---|
| `secretkey` | data-loss-critical | decrypts stored answers; generated once, sha256 proven identical across update and restore |
| supervisor credentials | seed-once | local only, for docassemble's self-restart |
| first admin password | seed-once | shown once in the post-install checklist; never a fixed default |

## Backup and restore

Everything stateful is an addon or `/app/data`. No `persistentDirs`, no `backupCommand`. Gate 3 proves
an **in-place** restore rolls back: count interviews and sessions, add some, restore, count back.

## Future compatibility

The single bump point is the docassemble build argument. Database migrations run through Alembic on
every start. The ADR 0003 patch is re-checked automatically by its build guard.
