# 0001. Rebuild on `cloudron/base` instead of adapting upstream's all-in-one image

- **Status:** accepted, 2026-11-07
- **Supersedes:** the v0.1 package (`OrcVole/docassemble-cloudron`, to be renamed
  `docassemble-cloudron-v0.1`), which used a different app id

## Context

Docassemble's official image is built to be a whole server: PostgreSQL, Redis, RabbitMQ, nginx or
Apache, uWSGI, Celery, exim4, cron, syslog-ng and Let's Encrypt in one container, set up by a
1,868-line `initialize.sh` that writes into the image's own filesystem. Cloudron expects nearly the
opposite. The image is read-only, the platform supplies the database, cache, mail, sign-in, TLS and
scheduling, writable state lives only in `/app/data`, and the app is restarted, backed up, restored
and cloned by the platform.

v0.1 bridged the gap by starting from upstream's image (`jhpyle/docassemble:latest`) and redirecting
its writes. That worked well enough to run, but every redirect became something to maintain, and
each one fought the platform somewhere:

| v0.1 | Effect |
|---|---|
| `FROM jhpyle/docassemble:latest`, unpinned | every rebuild could pull a different docassemble and a different operating system |
| 28 symlinks from the image into `/app/data` and `/run` | upstream's own scripts write through them; each new upstream path is a new symlink to find |
| the whole Python environment (about 2 GB) copied into `/app/data` on first boot | the program lives in the backup, an image update does not update it, and every backup carries 2 GB that the image already contains |
| a bundled message broker (LavinMQ) with its store in `/app/data` | a live store copied file by file during backup, with no consistent snapshot |
| `config.yml` rewritten from a template on every boot | settings changed in docassemble's own configuration editor are lost at the next restart |
| health check on `/` | anonymous `/` answers 501, so the dashboard marks the app down after every restart |
| `memoryLimit: 6144` | read as bytes, not megabytes |
| exim4 started for outbound mail | fails on the read-only filesystem, so the app cannot send mail |
| logs in `/app/data` | a single log reached 233 MB inside the backup |
| installed from a local image with no versions feed | it can never receive an update |

timconsidine's community alpha (appx.uk, 0.0.2) showed a better direction: platform addons for every
service, Redis as the Celery broker, `gosu`, and secrets generated per install. It is credited in the
README and CHANGELOG. We borrowed those ideas, not its code.

## Decision

Build a new package from `cloudron/base`, installing docassemble from its published Python packages
and running its programs directly, and fork neither predecessor. Five principles follow.

1. **The platform provides; the package does not bundle.** PostgreSQL, Redis (also the Celery
   broker, ADR 0005), mail (`sendmail`), sign-in (`ldap`), TLS and scheduling (`scheduler`) all come
   from Cloudron addons. Nothing in the container keeps a database of its own, so Cloudron's own
   backup is consistent and complete with no `backupCommand`.

2. **Configure, don't redirect.** Every writable location docassemble uses is a configuration key
   (`uploads`, `packages`, `log`, `webapp`, `ready file`, the config file itself through
   `DA_CONFIG_FILE`). Each one is pointed at `/app/data` or `/run` by configuration. The target is
   zero symlinks; any that remain are justified in a comment beside them.

3. **The image owns the program; `/app/data` owns only the data.** The Python environment, the
   interpreter and the OS packages live in the read-only image. `/app/data` holds the configuration,
   the secret key, uploaded files and add-on packages (ADR 0004). An update replaces the program
   completely, and backups contain only what cannot be rebuilt.

4. **The operator's settings survive.** `config.yml` is written once, on first boot, and never again.
   Values that come from the platform and can change (database, Redis, mail, hostname) reach
   docassemble through environment variables on every boot, which docassemble's
   `ENVIRONMENT_TAKES_PRECEDENCE` honours. A few safety settings are enforced every boot and listed
   in the README.

5. **Pinned, current and provable.** The base image and every build input are pinned by digest or
   exact version. The package follows every upstream release on the newest base and Python (ADR
   0002). Each release passes the same scripted gates, which test real work: a PDF assembled, an OCR
   page read, a background task run, live help connected, a restore that really rolls back. A
   process showing as running is not enough.

## Consequences

- **Smaller, cleaner backups**: no Python environment, broker store or logs in `/app/data`.
- **Updates actually update**: docassemble moves when the image moves, through a versions feed.
- **Settings stick**, and sign-in uses Cloudron accounts through LDAP.
- **One small code change is unavoidable**: docassemble's websocket server does not pass the Redis
  password, so live help would fail against the addon (ADR 0003). The change is three lines, checked
  at build time, and offered upstream.
- **We own a start script** in place of upstream's `initialize.sh`. It is shorter because the platform
  does most of what `initialize.sh` sets up, but it must track upstream's start-up order on each
  release. The gates exist to catch drift.
- **Fresh installs only.** Moving data from a v0.1 install is not supported. An existing install's
  stored answers are encrypted with its secret key, and a migration tool is out of scope.
